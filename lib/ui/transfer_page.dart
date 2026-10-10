import 'dart:async';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../network/api_client.dart';
import '../session.dart';
import '../ui/theme.dart';
import '../util/formatters.dart';
import 'files_page.dart';

/// 云下载任务页：115 /open/offline/get_task_list。
/// 磁力链接经 magnet_page 添加后可在此查看进度。
///
/// - 默认显示 5 条任务，「加载更多」每次多显示 5 条（已加载数据不够时
///   才请求下一页）
/// - 存在分配中/下载中任务时每 1 秒轮询刷新（页面不在最前时不轮询，
///   避免挤占全局串行请求队列），全部结束后自动停止
/// - 下载中不带进度条：状态文字直接带百分比（下载中 42%）
/// - 副标题与文件页一致：日期之后是大小
/// - 下载中卡住不动（含 0%）超过 1 分钟的任务按失败态展示（云下载通常
///   很快完成，长挂多为无种子的死任务；仅影响展示，任务恢复前进后
///   自动翻回下载中，服务端完成后翻回完成态）
/// - autoOpen（设置「云下载后自动打开」）：从磁力页提交进来时盯住
///   列表最新一条任务，轮询发现完成即自动打开其保存位置；任务失败
///   或被删则不再等待。仅此入口生效，平时从主页进的列表不自动打开
class TransferPage extends StatefulWidget {
  const TransferPage({super.key, this.autoOpen = false});

  /// 提交云下载后跳进来时为 true：等待任务完成自动打开
  final bool autoOpen;

  @override
  State<TransferPage> createState() => _TransferPageState();
}

class _TransferPageState extends State<TransferPage> {
  final List<OfflineTask> _tasks = [];
  int _page = 1;
  int _pageCount = 1;
  int _count = 0;
  bool _loading = true;
  String? _error;

  /// 当前显示条数（默认 5；加载更多 +5）
  int _visibleCount = 5;

  Timer? _pollTimer;
  bool _refreshing = false; // 一轮轮询在途时跳过下一个 tick

  /// 下载中超过该时长按失败态展示（本地判定，服务端状态不变）
  static const _transferTimeout = Duration(minutes: 1);

  /// infoHash → (最近一次进度变化时的百分比, 时间)。百分比一前进就重置，
  /// 超时判定只针对「卡住不动」（含一直 0%）的任务
  final Map<String, (int, DateTime)> _transferSince = {};

  /// autoOpen 模式下待自动打开的任务（进页后列表最新一条的 infoHash；
  /// 清空 = 不再盯：已打开/失败/被删/未开启）
  String? _watchHash;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) setState(() => _loading = true);
    try {
      final page = reset ? 1 : _page + 1;
      final j = await Session.instance.client.offlineTaskList(page: page);
      final d = (j['data'] as Map?)?.cast<String, dynamic>() ?? {};
      final raw = (d['tasks'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => OfflineTask.fromJson(e.cast<String, dynamic>()))
          .toList();
      if (!mounted) return;
      setState(() {
        if (reset) {
          _tasks.clear();
          _visibleCount = 5;
        } else {
          // 新页到达后先多显示 5 条
          _visibleCount += 5;
        }
        _tasks.addAll(raw);
        _page = (d['page'] as num?)?.toInt() ?? page;
        _pageCount = (d['page_count'] as num?)?.toInt() ?? 1;
        _count = (d['count'] as num?)?.toInt() ?? _tasks.length;
        _loading = false;
        _error = null;
      });
      _trackTransfers();
      _syncPollTimer();
      _pickWatchTarget();
      _maybeAutoOpen();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '网络异常，请稍后重试';
      });
    }
  }

  /// 有分配中(0)/下载中(1)任务 → 保证轮询在跑；否则停
  void _syncPollTimer() {
    final active = _tasks.any((t) => t.status == 0 || t.status == 1);
    if (active && _pollTimer == null) {
      _pollTimer =
          Timer.periodic(const Duration(milliseconds: 500), (_) => _pollTick());
    } else if (!active && _pollTimer != null) {
      _pollTimer!.cancel();
      _pollTimer = null;
    }
  }

  /// 维护超时计时起点：下载中任务首次出现或百分比前进时重置时间戳，
  /// 任务完成/失败/移出列表后清掉
  void _trackTransfers() {
    final active =
        _tasks.where((t) => t.status == 1).map((t) => t.infoHash).toSet();
    _transferSince.removeWhere((k, _) => !active.contains(k));
    final now = DateTime.now();
    for (final t in _tasks.where((t) => t.status == 1)) {
      final prev = _transferSince[t.infoHash];
      if (prev == null || prev.$1 != t.percentDone) {
        _transferSince[t.infoHash] = (t.percentDone, now);
      }
    }
  }

  /// 是否按失败态展示：服务端已失败，或下载中卡住不动（含 0%）超 1 分钟
  /// （超时只改展示，轮询继续，任务恢复前进/真实完成后翻回原状态）
  bool _shownFailed(OfflineTask t) {
    if (t.failed) return true;
    if (t.status != 1) return false;
    final s = _transferSince[t.infoHash];
    return s != null && DateTime.now().difference(s.$2) > _transferTimeout;
  }

  /// autoOpen：首次见到任务列表时把最新一条定为盯梢目标
  /// （新提交的任务排在最前）；目标已定/未开启则不动
  void _pickWatchTarget() {
    if (!widget.autoOpen || _watchHash != null || _tasks.isEmpty) return;
    _watchHash = _tasks.first.infoHash;
  }

  /// autoOpen：盯住的任务完成即自动打开其保存位置（只开一次）；
  /// 失败或已从列表消失（被删）则停止等待
  void _maybeAutoOpen() {
    final hash = _watchHash;
    if (!widget.autoOpen || hash == null) return;
    OfflineTask? t;
    for (final x in _tasks) {
      if (x.infoHash == hash) {
        t = x;
        break;
      }
    }
    if (t == null) {
      _watchHash = null; // 已不在列表（被删）
      return;
    }
    if (t.done) {
      _watchHash = null;
      _openTask(t);
    } else if (t.failed || _shownFailed(t)) {
      _watchHash = null; // 失败不再等待
    }
  }

  void _pollTick() {
    // 页面被压在下面（如点开任务进了文件页）时不轮询：全局请求队列
    // 串行限流，后台轮询会拖慢前台页面的接口
    if (!mounted || _loading || _refreshing) return;
    if (ModalRoute.of(context)?.isCurrent != true) return;
    _pollRefresh();
  }

  /// 轮询：重拉已加载的页（1.._page，force 绕过 2s 缓存），整表替换；
  /// 静默失败等下一轮
  Future<void> _pollRefresh() async {
    _refreshing = true;
    try {
      final pages = <List<OfflineTask>>[];
      for (var p = 1; p <= _page; p++) {
        final j =
            await Session.instance.client.offlineTaskList(page: p, force: true);
        final d = (j['data'] as Map?)?.cast<String, dynamic>() ?? {};
        pages.add((d['tasks'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => OfflineTask.fromJson(e.cast<String, dynamic>()))
            .toList());
        if (d['count'] != null) _count = (d['count'] as num).toInt();
        if (d['page_count'] != null) {
          _pageCount = (d['page_count'] as num).toInt();
        }
      }
      if (!mounted) return;
      setState(() {
        _tasks
          ..clear()
          ..addAll(pages.expand((x) => x));
      });
      _trackTransfers();
      _syncPollTimer();
      _pickWatchTarget();
      _maybeAutoOpen();
    } catch (_) {
      // 轮询失败静默：保留现有数据，下一轮再试
    } finally {
      _refreshing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('云下载'),
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading && _tasks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!,
                style:
                    TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: () => _load(reset: true), child: const Text('重试')),
          ],
        ),
      );
    }
    if (_tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off_outlined, size: 64, color: AppTheme.textSecondary),
            const SizedBox(height: 12),
            Text('暂无云下载任务',
                style: TextStyle(fontSize: 16, color: AppTheme.textSecondary)),
            const SizedBox(height: 8),
            Text('点击磁力链接即可添加到云下载',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: 1 + _shown.length + (_hasMore ? 1 : 0),
        itemBuilder: (_, i) {
          // 第 0 项：任务总数摘要；其后为任务；最后一项为"加载更多"
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                  '共 $_count 个任务 · 第 $_page/$_pageCount 页',
                  style: TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary)),
            );
          }
          if (i <= _shown.length) return _tile(_shown[i - 1]);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: TextButton(
                onPressed: _loading ? null : _revealMore,
                child: Text(_loading ? '加载中…' : '加载更多'),
              ),
            ),
          );
        },
      ),
    );
  }

  /// 当前显示的窗口（默认 5 条）
  List<OfflineTask> get _shown => _tasks.take(_visibleCount).toList();

  /// 已加载数据未显示完，或服务端还有下一页
  bool get _hasMore => _visibleCount < _tasks.length || _page < _pageCount;

  /// 加载更多：先显示内存里后续 5 条；用尽后才请求下一页
  void _revealMore() {
    if (_visibleCount < _tasks.length) {
      setState(() => _visibleCount += 5);
    } else {
      _load();
    }
  }

  /// 磁链展示：只保留 btih（magnet:?xt=urn:btih:…），dn/tr 等其余
  /// 参数不展示；非磁链或无 btih 原样返回
  static String _shortMagnet(String url) {
    if (!url.startsWith('magnet:')) return url;
    final m = RegExp(r'[?&]xt=urn:btih:([0-9A-Za-z]+)').firstMatch(url);
    if (m == null) return url;
    return 'magnet:?xt=urn:btih:${m.group(1)}';
  }

  Widget _tile(OfflineTask t) {
    final failed = _shownFailed(t);
    // 与主页列表行（FileLeadingIcon）同款圆底图标风格：
    // 圆底色区分状态（绿=完成 / 深金=失败 / 主题色=下载中），
    // 图案色与文件页统一按底色亮度自动取黑/白
    final icon = t.done
        ? Icons.cloud_done_outlined
        : failed
            ? Icons.error_outline
            : Icons.cloud_download_outlined;
    final circleColor = t.done
        ? Colors.green
        : failed
            ? AppTheme.accentDeep // 深金：金黄在白底上对比不足
            : AppTheme.primary;
    final time =
        t.addTime > 0 ? fmtDate(DateTime.fromMillisecondsSinceEpoch(t.addTime * 1000)) : '';
    return Dismissible(
      key: ValueKey('task-${t.infoHash}'),
      direction: DismissDirection.endToStart, // 仅左滑删除
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      confirmDismiss: (_) => _deleteTask(t),
      onDismissed: (_) {
        setState(() {
          _tasks.remove(t);
          _count = _count > 0 ? _count - 1 : 0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  '已删除"${t.name.isEmpty ? _shortMagnet(t.url) : t.name}"')),
        );
      },
      child: ListTile(
        onTap: () => _openTask(t),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: circleColor, shape: BoxShape.circle),
          child: Icon(icon, color: AppTheme.onColor(circleColor), size: 20),
        ),
        title: Text(
          // 无名任务展示磁链摘要（仅 btih，见 _shortMagnet）
          t.name.isEmpty ? _shortMagnet(t.url) : t.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          // 与文件页/搜索页列表行标题同字号
          style: TextStyle(fontSize: 16, color: AppTheme.textPrimary),
        ),
        // 副标题与文件页一致：日期之后是大小；下载中不带进度条，
        // 状态文字直接带百分比
        subtitle: Text(
          [
            failed
                ? '下载失败'
                : t.status == 1
                    ? '下载中 ${t.percentDone}%'
                    : t.statusText,
            if (time.isNotEmpty) time,
            if (t.size > 0) formatBytes(t.size),
          ].join(' · '),
          style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
        ),
      ),
    );
  }

  /// 点击任务：已完成的跳转到其保存位置，未完成提示
  void _openTask(OfflineTask t) {
    if (!t.done) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('任务尚未完成')));
      return;
    }
    final id = t.fileId;
    if (id.isEmpty || id == '0') {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('未找到保存位置')));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FilesPage(
        initialDir: DirEntry(
            cid: id, name: t.name.isEmpty ? '云下载' : t.name),
      ),
    ));
  }

  /// 左滑删除：先请求接口，成功才允许收起；失败弹回并提示
  Future<bool> _deleteTask(OfflineTask t) async {
    try {
      await Session.instance.client.offlineDelTask(t.infoHash);
      return true;
    } on ApiException catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('删除失败：${e.message}')));
      return false;
    } catch (_) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('删除失败，请稍后重试')));
      return false;
    }
  }
}
