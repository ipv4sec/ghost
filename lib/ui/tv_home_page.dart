import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';

import '../config/app_config.dart';
import '../models/models.dart';
import '../network/api_client.dart';
import '../session.dart';
import 'files_page.dart';
import 'settings_page.dart';
import 'tv_cards.dart';
import 'video_player_page.dart';

/// 电视端首页（Jellyfin 风格媒体中心；仅 Tv.isTv 时由 HomeShell 挂载，
/// 手机端主页仍是 FilesPage，一行不改）
///
/// - 顶栏：时钟 + 设置齿轮（右），无搜索框、无头像（电视端不提供抽屉/
///   退出入口；凭证失效自动回登录页）
/// - 内容：单网格流——根目录文件夹与文件合并在同一个 4 列网格中连续
///   排列（文件夹在前、文件在后；同款卡片布局，文件卡名称末尾带大小）
/// - 数据：一次根目录请求即出全部内容
/// - 过滤与 FilesPage 同规则（512MB / .iso / 屏蔽词）；点文件夹进现有
///   FilesPage（浅色列表，本轮不改），点视频进播放页
/// - 焦点：InkWell 卡片 + 默认方向遍历（跨嵌套横竖列表按几何最近取
///   候选，即 Jellyfin 手感）；聚焦卡 ensureVisible 滚动跟随
/// - 深色自包含配色（不动全局主题；子页面/抽屉本轮保持浅色）
class TvHomePage extends StatefulWidget {
  const TvHomePage({super.key});

  /// 页面深色底（HomeShell 的 Scaffold 背景同步用）
  static const Color backgroundColor = _bg;

  /// 卡片宽度：屏宽 / 5.4（1080p ≈ 177dp，一行可见约 5 张）× 整页缩放系数
  static double cardWidthOf(BuildContext context) =>
      (MediaQuery.sizeOf(context).width / 5.4).clamp(150.0, 260.0) * _kScale;

  @override
  State<TvHomePage> createState() => _TvHomePageState();
}

// ---- 深色配色与缩放系数：与文件夹页共享，见 lib/ui/tv_cards.dart ----
const double _kScale = kTvScale;
const Color _bg = tvBg;
const Color _skeleton = tvSkeleton;
const Color _accent = tvAccent;
const Color _textDim = tvTextDim;

class _TvHomePageState extends State<TvHomePage> {
  final _client = Session.instance.client;

  bool _rootLoading = true;
  String? _rootError;
  List<FileItem> _folders = const []; // 「文件夹」区：根目录文件夹
  List<FileItem> _files = const []; // 「文件」区：根目录文件

  /// 世代号：整页重拉时作废所有在途异步结果（同 files_page._reloadGen）
  int _gen = 0;

  /// 屏蔽词/排序快照：仅实际变化才整页重拉（token 刷新等通知忽略）
  List<String> _blockSnapshot = const [];
  String _sortSnapshot = '';

  /// 首张卡 autofocus 一次性标志（仿 files_page 首行聚焦：刷新/重拉重建
  /// 的行不再抢焦点，但整页重拉后焦点需要有处可落，故 _reload 时复位）
  bool _autoFocusFirst = true;

  // 根路由「再按一次返回退出」：上次返回时间 + 提示的自动清理
  DateTime? _lastBackAt;
  Timer? _toastTimer;
  OverlayEntry? _toast;

  @override
  void initState() {
    super.initState();
    _blockSnapshot = Session.instance.blocklist;
    _sortSnapshot = Session.instance.sortKey;
    Session.instance.addListener(_onSessionChanged);
    _reload();
  }

  @override
  void dispose() {
    Session.instance.removeListener(_onSessionChanged);
    _toastTimer?.cancel();
    _toast?.remove();
    super.dispose();
  }

  /// 屏蔽词/排序变化 → 整页重拉（用户在设置页改动，返回主页即生效）
  void _onSessionChanged() {
    if (!mounted) return;
    final s = Session.instance;
    final blockChanged = !listEquals(s.blocklist, _blockSnapshot);
    final sortChanged = s.sortKey != _sortSnapshot;
    if (!blockChanged && !sortChanged) return;
    _blockSnapshot = s.blocklist;
    _sortSnapshot = s.sortKey;
    _reload();
  }

  Future<void> _reload() async {
    final gen = ++_gen;
    _autoFocusFirst = true; // 重拉后焦点回到首卡（遥控器永远有落点）
    setState(() {
      _rootLoading = _folders.isEmpty && _files.isEmpty; // 已有内容时刷新不闪整页骨架
      _rootError = null;
    });
    final rootFuture = _client.listFiles(
      cid: '0',
      limit: 50,
      order: Session.instance.orderField,
      asc: Session.instance.orderAsc,
    );
    try {
      final j = await rootFuture;
      if (!mounted || gen != _gen) return;
      final raw = (j['data'] as List)
          .map((e) => FileItem.fromListJson((e as Map).cast<String, dynamic>()))
          .toList();
      final list = _filterByExt(_filterByName(_filterBySize(raw)));
      setState(() {
        _folders = list.where((f) => f.isDir).toList();
        _files = list.where((f) => !f.isDir).toList();
        _rootLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _rootLoading = false;
        _rootError = e.message;
      });
    } catch (_) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _rootLoading = false;
        _rootError = '网络异常';
      });
    }
  }

  // ---- 可见性过滤（与 files_page.dart 同规则：512MB / .iso / 屏蔽词）----
  // 电视首页与文件页必须看到相同内容，改规则时两处同步

  List<FileItem> _filterBySize(List<FileItem> src) {
    if (AppConfig.minFileSize <= 0) return src;
    return src
        .where((f) => f.isDir || f.size >= AppConfig.minFileSize)
        .toList();
  }

  List<FileItem> _filterByExt(List<FileItem> src) {
    return src
        .where((f) => f.isDir || !f.name.toLowerCase().endsWith('.iso'))
        .toList();
  }

  List<FileItem> _filterByName(List<FileItem> src) {
    final s = Session.instance;
    if (s.blocklist.isEmpty) return src;
    return src.where((f) => !s.isNameBlocked(f.name)).toList();
  }

  // ---- 点击路由（复刻 FilesPage._onItemTap 语义）----

  Future<void> _onItemTap(FileItem f) async {
    if (f.isDir) {
      if (f.encrypted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('加密文件夹，请使用 115 官方 App 查看'),
        ));
        return;
      }
      // 点按先取该目录列表做预检（与 FilesPage._openDir 同款、同参数）：
      // 过滤后为空直接 toast「无文件」，不打开页面——用户反馈空目录
      // 只该有提示，不该有打开转场动画。「空」以过滤后的可见结果为准
      // （纯 .iso/小文件目录在服务端 count 看是非空的）。读接口 2s 结果
      // 缓存：进入后的首屏 _reload 直接复用本次响应，不会重复请求
      List<FileItem>? visible;
      try {
        final j = await _client.listFiles(
          cid: f.fid,
          limit: 50,
          offset: 0,
          order: Session.instance.orderField,
          asc: Session.instance.orderAsc,
        );
        final raw = (j['data'] as List)
            .map((e) =>
                FileItem.fromListJson((e as Map).cast<String, dynamic>()))
            .toList();
        visible = _filterByExt(_filterByName(_filterBySize(raw)));
      } catch (_) {
        // 拉取失败按未知处理：正常进入，页面自己会显示错误与重试
      }
      if (!mounted) return;
      if (visible != null && visible.isEmpty) {
        _showToast('无文件');
        return;
      }
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            FilesPage(initialDir: DirEntry(cid: f.fid, name: f.name)),
      ));
    } else if (f.isVideo) {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => VideoPlayerPage(item: f)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('该类型文件暂不支持在电视上打开'),
      ));
    }
  }

  void _openSettings() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SettingsPage()));
  }

  /// 屏幕正中轻提示 toast（与 files_page 同款，退出提示与「无文件」共用）
  void _showToast(String text) {
    _toastTimer?.cancel();
    _toast?.remove();
    _toast = OverlayEntry(
      builder: (_) => IgnorePointer(
        child: Center(
          // 无 Material 祖先时 Text 继承框架 error 样式（黄色双下划线，
          // 用户看到文字下的"下划线"即此），包透明 Material 恢复正常渲染
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                text,
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_toast!);
    _toastTimer = Timer(const Duration(seconds: 2), () {
      _toast?.remove();
      _toast = null;
    });
  }

  /// 屏幕正中 toast「再按一次返回退出应用」；2 秒内第二次返回才真正退出
  void _showExitHint() => _showToast('再按一次返回退出应用');

  @override
  Widget build(BuildContext context) {
    // 深底配浅色状态栏图标（同播放页）
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: PopScope(
        // 主页根路由拦截返回：第一次只提示，2 秒内第二次才退出
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          final now = DateTime.now();
          if (_lastBackAt != null &&
              now.difference(_lastBackAt!) < const Duration(seconds: 2)) {
            SystemNavigator.pop();
            return;
          }
          _lastBackAt = now;
          _showExitHint();
        },
        child: Scaffold(
          backgroundColor: _bg,
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                // 顶栏（时钟·设置）整体不挂载——暂时隐藏（用户要求去掉空白栏）
                // _TopBar(onSettings: _openSettings),
                Expanded(child: _buildBody()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_rootError != null) {
      return _TvErrorView(message: _rootError!, onRetry: _reload);
    }
    if (_rootLoading) {
      // 根加载中：顶栏可用 + 网格骨架
      return ListView(
        // 四边 20 与网格行距一致（左右原 48 与卡片间距不等，用户要求统一）
        padding: const EdgeInsets.fromLTRB(
            20 * _kScale, 20 * _kScale, 20 * _kScale, 20 * _kScale),
        children: const [
          _GridSection(items: [], onItemTap: _nop, loading: true),
        ],
      );
    }
    if (_folders.isEmpty && _files.isEmpty) {
      final blocked = Session.instance.blocklist.isNotEmpty;
      return Center(
        child: Text(
          blocked ? '没有可显示的内容（部分内容可能被屏蔽词过滤）' : '没有可显示的内容',
          style: const TextStyle(color: Colors.white54),
        ),
      );
    }
    // 首卡 autofocus 一次性标志：首卡始终在视口内会被构建，构建即消费
    final bool af = _autoFocusFirst;
    _autoFocusFirst = false;
    return ListView(
      // 四边 20 与网格行距一致（左右原 48 与卡片间距不等，用户要求统一）
      padding: const EdgeInsets.fromLTRB(
          20 * _kScale, 20 * _kScale, 20 * _kScale, 20 * _kScale),
      // 视口外一~两行已构建：方向键下移时焦点遍历有落点
      scrollCacheExtent: const ScrollCacheExtent.pixels(1000),
      children: [
        // 文件夹与文件合并在同一网格流中连续排列（文件夹在前、文件在后，
        // 不再分区块各自换行，用户要求）
        _GridSection(
          items: [..._folders, ..._files],
          onItemTap: _onItemTap,
          autoFocusFirst: af,
        ),
      ],
    );
  }
}

void _nop(FileItem f) {}

/// 顶栏：时钟 · 设置齿轮（右对齐）
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.onSettings,
  });

  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72 * _kScale,
      child: Padding(
        // 左右 48 与网格卡片左缘对齐（面包屑与卡片同左缘）
        padding: const EdgeInsets.symmetric(horizontal: 48 * _kScale),
        child: Row(
          children: [
            // 路径面包屑：根目录固定「首页」——暂时隐藏（用户要求）
            // const TvBreadcrumb(segments: ['首页']),
            // 右上角时钟 + 设置按钮——暂时隐藏（用户要求）
            // const Spacer(),
            // const _Clock(),
            // const SizedBox(width: 24 * _kScale),
            // IconButton(
            //   icon: const Icon(Icons.settings, color: Colors.white),
            //   iconSize: 24 * _kScale,
            //   tooltip: '设置',
            //   focusColor: Colors.white24,
            //   onPressed: onSettings,
            // ),
          ],
        ),
      ),
    );
  }
}

/// 顶栏时钟：每 30 秒刷新 HH:mm（无 intl 依赖，手写格式）
class _Clock extends StatefulWidget {
  const _Clock();

  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  Timer? _timer;
  String _text = '';

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _tick() {
    final dt = DateTime.now();
    final t =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    if (t != _text) setState(() => _text = t);
  }

  @override
  Widget build(BuildContext context) => Text(
        _text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 22 * _kScale,
          fontWeight: FontWeight.w600,
        ),
      );
}

/// 内容网格：文件夹与文件合并在同一个网格流中连续排列（文件夹在前、
/// 文件在后，用户要求不分区块各自换行）；4 列横向卡，按类型选文件夹卡
/// 或文件卡（同款布局）。网格自身不滚动、随外层页面滚动
class _GridSection extends StatelessWidget {
  const _GridSection({
    required this.items,
    required this.onItemTap,
    this.loading = false,
    this.autoFocusFirst = false,
  });

  final List<FileItem> items;
  final ValueChanged<FileItem> onItemTap;
  final bool loading;
  final bool autoFocusFirst;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 20 * _kScale,
        mainAxisSpacing: 20 * _kScale,
        childAspectRatio: 2.3,
      ),
      padding: EdgeInsets.zero,
      itemCount: loading ? 6 : items.length,
      itemBuilder: (ctx, i) {
        if (loading) {
          return Container(
            decoration: BoxDecoration(
              color: _skeleton,
              borderRadius: BorderRadius.circular(12 * _kScale),
            ),
          );
        }
        final f = items[i];
        return f.isDir
            ? TvFolderCard(
                item: f,
                onTap: onItemTap,
                autofocus: autoFocusFirst && i == 0,
              )
            : TvFileCard(
                item: f,
                onTap: onItemTap,
                autofocus: autoFocusFirst && i == 0,
              );
      },
    );
  }
}

/// 整页错误视图：图标 + 文案 + 重试（autofocus，遥控器直接 OK 重试）
class _TvErrorView extends StatelessWidget {
  const _TvErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off,
              size: 64 * _kScale, color: Colors.white38),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(color: _textDim)),
          const SizedBox(height: 16),
          OutlinedButton(
            autofocus: true,
            onPressed: onRetry,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: _accent),
            ),
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }
}
