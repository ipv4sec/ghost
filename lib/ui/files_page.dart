import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../models/models.dart';
import '../network/api_client.dart';
import '../session.dart';
import '../ui/theme.dart';
import '../util/formatters.dart';
import 'search_page.dart';
import 'transfer_page.dart';
import 'video_player_page.dart';

/// 目录栈中的一层
class DirEntry {
  DirEntry({required this.cid, required this.name});

  final String cid;
  final String name;
}

/// 文件浏览页（100% 参照 Amaze 截图布局）
///
/// - 整块深蓝顶栏：app 名（路径行 + 统计行暂时隐藏，恢复见 _header 内注释）
/// - 列表行：玫红圆图标 + 名称/灰色时间副标题 + 行尾 ⋮
/// - 全宽细分隔线；右下玫红 FAB 新建文件夹
class FilesPage extends StatefulWidget {
  const FilesPage(
      {super.key, this.onOpenProfile, this.initialDir, this.isHome = false});

  /// 顶栏汉堡按钮回调（打开"我的"）
  final VoidCallback? onOpenProfile;

  /// 初始目录（如云下载任务的保存位置）；不传则从根目录开始
  final DirEntry? initialDir;

  /// 是否为主页实例：主页根目录的返回手势走"再划一次退出"；
  /// 推入的实例（如云下载任务位置页）在栈底直接 pop 回上一页
  final bool isHome;

  @override
  State<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends State<FilesPage>
    with AutomaticKeepAliveClientMixin {
  final _client = Session.instance.client;

  /// initState 里按 widget.initialDir 初始化（字段初始化器访问不了 widget）
  late final List<DirEntry> _stack;
  final List<FileItem> _items = [];

  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  int _count = 0;
  int _offset = 0;
  static const _limit = 50;

  // ---- 刷新防叠加 ----
  // 同一目录/排序的刷新进行中则合并触发（连点刷新只发一轮请求）；
  // 目录/排序变化时新一轮刷新递增 _reloadGen，取代所有过期异步结果
  bool _reloading = false;
  String _loadingKey = '';
  int _reloadGen = 0;

  /// fid → 是否空文件夹（会话级缓存：重复刷新不再逐个重查详情）
  final Map<String, bool> _emptyDirCache = {};

  /// 正在播放"移除动画"的文件夹 fid：动画结束后才真正从列表剔除
  final Set<String> _removingIds = {};

  bool _gridView = false;
  String _order = 'user_ptime';
  bool _asc = false;

  // 剪贴板：剪切中的文件（fid + 名字），非空时列表上方显示粘贴栏
  String? _cutFid;
  String? _cutName;

  // 根目录"再划一次退出"：上次返回手势时间 + 居中提示的自动清理
  DateTime? _lastBackAt;
  Timer? _exitHintTimer;
  OverlayEntry? _exitHint;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _stack = [
      widget.initialDir ?? DirEntry(cid: '0', name: '全部文件')
    ];
    _restorePrefs();
    _reload();
  }

  @override
  void dispose() {
    _exitHintTimer?.cancel();
    _exitHint?.remove();
    super.dispose();
  }

  Future<void> _restorePrefs() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _gridView = p.getBool('ghost.grid') ?? false);
  }

  /// 网格/列表视图切换（菜单入口已隐藏，恢复时在菜单里加回"网格视图"项即可）
  // ignore: unused_element
  Future<void> _toggleView() async {
    setState(() => _gridView = !_gridView);
    final p = await SharedPreferences.getInstance();
    await p.setBool('ghost.grid', _gridView);
  }

  /// 屏幕正中"再划一次退出此应用"提示：不拦截点击，2 秒后自动消失
  void _showExitHint() {
    _exitHintTimer?.cancel();
    _exitHint?.remove();
    _exitHint = OverlayEntry(
      builder: (_) => IgnorePointer(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              '再划一次退出此应用',
              style: TextStyle(color: Colors.white, fontSize: 15),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_exitHint!);
    _exitHintTimer = Timer(const Duration(seconds: 2), () {
      _exitHint?.remove();
      _exitHint = null;
    });
  }

  DirEntry get _dir => _stack.last;

  /// 面包屑式路径文本：/ 子目录 / 孙目录（不显示根级"全部文件"）。
  /// 以本地导航栈为准——服务端 path 数组可能包含与实际导航无关的
  /// 系统目录段（如在"文件"文件夹里返回 /全部文件/小视频/文件），
  /// 直接拼接会多显示目录名
  ///
  /// 顶栏路径行暂时隐藏，此 getter 一并注释（恢复路径行时取消注释）
  // String get _pathText {
  //   final names = [for (final d in _stack.skip(1)) d.name];
  //   return names.isEmpty ? '/' : '/ ${names.join(' /')}';
  // }

  Future<void> _reload() async {
    // 同一目录/排序的刷新进行中：合并本次触发，避免叠加请求触发限流（405）
    final key = '${_dir.cid}|$_order|$_asc';
    if (_reloading && key == _loadingKey) return;
    _reloading = true;
    _loadingKey = key;
    final gen = ++_reloadGen;
    setState(() {
      _loading = _items.isEmpty;
      _error = null;
      _loadingMore = false; // 在途的分页请求一并作废
      _removingIds.clear(); // 过期轮次的移除动画一并作废
    });
    _offset = 0;
    try {
      final j = await _client.listFiles(
        cid: _dir.cid,
        limit: _limit,
        offset: 0,
        order: _order,
        asc: _asc,
      );
      if (!mounted || gen != _reloadGen) return;
      final raw = (j['data'] as List)
          .map((e) => FileItem.fromListJson((e as Map).cast<String, dynamic>()))
          .toList();
      final list = _filterBySize(raw);
      setState(() {
        _items
          ..clear()
          ..addAll(list);
        _count = (j['count'] as num?)?.toInt() ?? raw.length;
        _loading = false;
        // 按服务端原始返回条数推进（与本地过滤无关），服务端未回显则用请求值
        _offset = (j['offset'] as num?)?.toInt() ?? 0;
        if (_offset == 0) _offset = raw.length;
      });
      // 大小过滤后再剔除空文件夹（异步，不阻塞首屏）。
      // 先标记播放淡出折叠动画，动画走完再真正移除，避免瞬间消失晃眼
      final visible = await _hideEmptyDirs(_items.toList(), gen);
      if (!mounted || gen != _reloadGen) return;
      final visibleIds = visible.map((v) => v.fid).toSet();
      final removedIds = _items
          .where((f) => f.isDir && !visibleIds.contains(f.fid))
          .map((f) => f.fid)
          .toSet();
      if (removedIds.isEmpty) return;
      setState(() => _removingIds.addAll(removedIds));
      await Future<void>.delayed(const Duration(milliseconds: 320));
      if (!mounted || gen != _reloadGen) return;
      setState(() {
        _removingIds.removeAll(removedIds);
        _items.removeWhere((f) => f.isDir && removedIds.contains(f.fid));
      });
    } on ApiException catch (e) {
      if (!mounted || gen != _reloadGen) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted || gen != _reloadGen) return;
      setState(() {
        _loading = false;
        _error = '网络异常';
      });
    } finally {
      // 只有最新一轮负责解锁（过期轮次解锁会覆盖新一轮的状态）
      if (gen == _reloadGen) _reloading = false;
    }
  }

  /// 大小过滤：仅显示 >= AppConfig.minFileSize 的文件；文件夹不受限
  List<FileItem> _filterBySize(List<FileItem> src) {
    if (AppConfig.minFileSize <= 0) return src;
    return src
        .where((f) => f.isDir || f.size >= AppConfig.minFileSize)
        .toList();
  }

  /// 剔除空文件夹：逐个串行查详情，count+folder_count 均 0 视为空，直接隐藏。
  /// 结果按 fid 缓存（重复刷新零请求）；被新一轮刷新取代（gen 过期）立即中止。
  Future<List<FileItem>> _hideEmptyDirs(List<FileItem> src, int gen) async {
    final emptyIds = <String>{};
    for (final d in src.where((f) => f.isDir)) {
      if (!mounted || gen != _reloadGen) return src;
      final cached = _emptyDirCache[d.fid];
      if (cached != null) {
        if (cached) emptyIds.add(d.fid);
        continue;
      }
      try {
        final j = await _client.fileInfo(d.fid);
        final dd = j['data'];
        final empty = dd is Map &&
            (dd['count'] ?? -1) == 0 &&
            (dd['folder_count'] ?? -1) == 0;
        _emptyDirCache[d.fid] = empty;
        if (empty) emptyIds.add(d.fid);
      } catch (_) {/* 失败保留 */}
    }
    if (emptyIds.isEmpty) return src;
    return src.where((f) => !f.isDir || !emptyIds.contains(f.fid)).toList();
  }

  void _maybeLoadMore() {
    // 刷新在途不分页：_reload 会把 _offset 重置为 0，此时触发分页
    // 会用 offset=0 再拉一次第一页，并与刷新结果叠加造成重复
    if (!_reloading && !_loadingMore && _offset < _count) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadMore());
    }
  }

  Future<void> _loadMore() async {
    if (_reloading || _loadingMore || _offset >= _count) return;
    final lastOffset = _offset;
    final gen = _reloadGen;
    setState(() => _loadingMore = true);
    try {
      final j = await _client.listFiles(
        cid: _dir.cid,
        limit: _limit,
        offset: _offset,
        order: _order,
        asc: _asc,
      );
      final raw = (j['data'] as List)
          .map((e) => FileItem.fromListJson((e as Map).cast<String, dynamic>()))
          .toList();
      final list = _filterBySize(raw);
      // 刷新已重置列表：丢弃过期分页结果
      if (!mounted || gen != _reloadGen) return;
      // 按 fid 去重：别处删除文件会使页边界位移，下一页可能重复上一页尾部
      final known = _items.map((e) => e.fid).toSet();
      final fresh = list.where((f) => !known.contains(f.fid)).toList();
      setState(() {
        _items.addAll(fresh);
        // 服务端原始条数推进；返回空页说明到底了
        final base = (j['offset'] as num?)?.toInt() ?? _offset;
        _offset = raw.isEmpty ? _count : base + raw.length;
      });
    } catch (_) {/* 静默 */} finally {
      // 仅最新一轮负责收尾；过期轮次的状态已由 _reload 重置
      if (gen == _reloadGen) {
        // 保险丝：offset 未推进（异常响应）时标到底，避免无限重拉
        if (_offset <= lastOffset) _offset = _count;
        if (mounted) setState(() => _loadingMore = false);
      }
    }
  }

  void _openDir(FileItem f) {
    if (f.encrypted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('加密文件夹，请使用 115 官方 App 查看')),
      );
      return;
    }
    setState(() {
      _stack.add(DirEntry(cid: f.fid, name: f.name));
      _items.clear();
    });
    _reload();
  }

  /// 返回上级目录
  void _goUp() {
    if (_stack.length <= 1) return;
    setState(() {
      _stack.removeLast();
      _items.clear();
    });
    _reload();
  }

  void _onItemTap(FileItem f) {
    if (f.isDir) {
      _openDir(f);
    } else if (f.isVideo) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => VideoPlayerPage(item: f),
      ));
    } else {
      _showInfoSheet(f);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // 顶栏浅色 → 深色状态栏图标；珊瑚/暗夜主题顶栏深，用浅色图标
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.current.lightHeader
          ? SystemUiOverlayStyle.dark
          : SystemUiOverlayStyle.light,
      child: PopScope(
      // 主页实例拦截所有返回手势（子目录返回上级、根目录"再划一次退出"）；
      // 推入的实例在栈底直接 pop 回上一页
      canPop: !widget.isHome && _stack.length <= 1,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_stack.length > 1) {
          _goUp();
          return;
        }
        // 主页根目录：第一次返回手势只提示，2 秒内第二次才退出
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
        backgroundColor: Colors.white,
        body: Column(
          children: [
            _header(), // 整块顶栏：app名 + 路径 + 统计
            if (_cutFid != null) _pasteBar(),
            Expanded(child: _buildBody()),
          ],
        ),
        // 右下角新建文件夹 FAB（暂时隐藏，恢复时取消注释即可）
        // floatingActionButton: FloatingActionButton(
        //   onPressed: _showAddFolderDialog,
        //   tooltip: '新建文件夹',
        //   shape: const CircleBorder(),
        //   child: const Icon(Icons.add),
        // ),
      ),
      ),
    );
  }

  /// 整块象牙顶栏（app 名行；路径行 + 统计行暂时隐藏，恢复时取消注释）
  Widget _header() {
    // final folders = _items.where((e) => e.isDir).length;
    // final files = _items.length - folders;
    // final stat = _count > _items.length
    //     ? '$folders+个文件夹，$files+个文件'
    //     : '$folders个文件夹，$files个文件';
    return Material(
      color: AppTheme.header,
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 第一行：汉堡 + 标题 + 右侧图标组（路径/统计行隐藏后行高
            // 52→64：48 的图标按钮留出上下各 8 的余量，单独成行不显挤）
            SizedBox(
              height: 64,
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.menu, color: AppTheme.textPrimary),
                    tooltip: '菜单',
                    onPressed: widget.onOpenProfile,
                  ),
                  const Expanded(child: SizedBox()),
                  IconButton(
                    icon: Icon(Icons.search, color: AppTheme.textPrimary),
                    tooltip: '搜索',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SearchPage()),
                    ),
                  ),
                  // 下载入口（原个人信息抽屉菜单项，改为顶栏图标）
                  IconButton(
                    icon: Icon(Icons.cloud_download_outlined,
                        color: AppTheme.textPrimary),
                    tooltip: '下载',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const TransferPage()),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: '更多',
                    icon: Icon(Icons.more_vert,
                        color: AppTheme.textPrimary),
                    color: Colors.white,
                    shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.zero),
                    onSelected: (v) {
                      if (v.startsWith('order:')) {
                        final parts = v.split(':');
                        setState(() {
                          _order = parts[1];
                          _asc = parts[2] == '1';
                        });
                        _reload();
                      }
                    },
                    itemBuilder: (_) => [
                      _orderItem('file_name', '按名称'),
                      _orderItem('file_size', '按大小'),
                      _orderItem('user_ptime', '按上传时间'),
                      _orderItem('user_utime', '按修改时间'),
                    ],
                  ),
                ],
              ),
            ),
            // 第二行：路径（无水波纹点击效果；点按仍返回上级）——暂时隐藏
            // GestureDetector(
            //   behavior: HitTestBehavior.opaque,
            //   onTap: _goUp,
            //   child: Padding(
            //     padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
            //     child: Text(
            //       _pathText,
            //       maxLines: 1,
            //       overflow: TextOverflow.ellipsis,
            //       style: const TextStyle(color: Colors.white, fontSize: 14),
            //     ),
            //   ),
            // ),
            // // 第三行：统计（"X个文件夹，X个文件"）——暂时隐藏
            // Padding(
            //   padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            //   child: Text(
            //     stat,
            //     style: const TextStyle(color: Colors.white70, fontSize: 12),
            //   ),
            // ),
            // 不再额外垫底部间距：图标行在 64 高度内居中，
            // 搜索图标上方/下方的留白保持一致
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _orderItem(String field, String label) {
    final selected = _order == field;
    return PopupMenuItem(
      value: 'order:$field:${_asc ? '0' : '1'}',
      child: Row(
        // 菜单宽度被 SDK 固定为 56 的倍数(此菜单=168lp)，行内容整体居中：
        // 内容自身左右对称(前导 18+8=26，尾随 26)，居中后文字两侧留白相等
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (selected)
            Icon(Icons.check, size: 18, color: AppTheme.primary)
          else
            const SizedBox(width: 18),
          const SizedBox(width: 8),
          Text(label),
          const SizedBox(width: 26),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _ErrorView(message: _error!, onRetry: _reload);
    }
    if (_items.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          Icon(Icons.folder_open, size: 64, color: AppTheme.textSecondary),
          const SizedBox(height: 12),
          Center(
              child: Text('这个文件夹空空如也',
                  style: TextStyle(color: AppTheme.textSecondary))),
        ],
      );
    }
    return RefreshIndicator(
      onRefresh: _reload,
      child: _gridView ? _buildGrid() : _buildList(),
    );
  }

  /// 列表视图：行 = 圆图标 | 名称+时间副标题 | ⋮（行间分隔线暂时隐藏）
  Widget _buildList() {
    return ListView.separated(
      // 显式传 padding：ScrollView 在 padding 为 null 时会把 MediaQuery 的
      // 状态栏 inset 自动垫到列表顶部（无 AppBar 的自定义头部场景下必然
      // 多出一条状态栏高度的白边）。顶部归零，底部保留系统导航条 inset。
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
      itemCount: _items.length + 1,
      // separatorBuilder: (_, __) =>
      //     Divider(height: 1, color: AppTheme.divider),
      separatorBuilder: (_, __) => const SizedBox.shrink(),
      itemBuilder: (ctx, i) {
        if (i == _items.length) {
          _maybeLoadMore();
          return _loadMoreFooter();
        }
        final f = _items[i];
        return _FadeCollapse(
          key: ValueKey('row-${f.fid}'),
          removing: _removingIds.contains(f.fid),
          // Builder：拿到行自身的 RenderBox，作为弹出菜单的锚定区域
          child: Builder(
            builder: (rowCtx) => InkWell(
            onTap: () => _onItemTap(f),
            // 长按 = 原 ⋮ 菜单（剪切/删除/重命名）；详情改由点按非视频文件进入
            onLongPress: () => _showRowMenu(rowCtx, f),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  FileLeadingIcon(item: f, size: 40),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(f.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 15, color: AppTheme.textPrimary)),
                        const SizedBox(height: 2),
                        // 副标题：时间（文件夹/文件都有），文件多一项大小
                        Text(
                          [
                            if (f.mtime != null) fmtDate(f.mtime!),
                            if (!f.isDir) formatBytes(f.size),
                          ].join(' | '),
                          style: TextStyle(
                              fontSize: 12, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  // 行尾 ⋮：剪切/删除/重命名 操作菜单——暂时隐藏，
                  // 功能迁至长按（_showRowMenu），恢复时取消注释
                  // SizedBox(
                  //   width: 36,
                  //   height: 40,
                  //   child: PopupMenuButton<String>(
                  //     padding: EdgeInsets.zero,
                  //     tooltip: '操作',
                  //     icon: Icon(Icons.more_vert,
                  //         size: 20, color: AppTheme.textSecondary),
                  //     color: Colors.white,
                  //     shape: const RoundedRectangleBorder(
                  //         borderRadius: BorderRadius.zero),
                  //     onSelected: (v) => _onRowMenu(v, f),
                  //     itemBuilder: (_) => const [
                  //       PopupMenuItem(value: 'cut', child: Text('剪切')),
                  //       PopupMenuItem(value: 'delete', child: Text('删除')),
                  //       PopupMenuItem(value: 'rename', child: Text('重命名')),
                  //     ],
                  //   ),
                  // ),
                ],
              ),
            ),
          ),
          ),
        );
      },
    );
  }

  /// 网格视图（保留双视图能力）
  Widget _buildGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.95,
      ),
      itemCount: _items.length + 1,
      itemBuilder: (ctx, i) {
        if (i == _items.length) {
          _maybeLoadMore();
          return _loadMoreFooter();
        }
        final f = _items[i];
        // 网格单元格尺寸固定，无法收起高度，只做淡出
        return _FadeCollapse(
          key: ValueKey('grid-${f.fid}'),
          removing: _removingIds.contains(f.fid),
          collapse: false,
          child: Card(
            color: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: AppTheme.divider),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _onItemTap(f),
              onLongPress: () => _showInfoSheet(f),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FileLeadingIcon(item: f, size: 56),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(f.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _loadMoreFooter() {
    if (!_loadingMore && _offset >= _count) {
      return const SizedBox(height: 24);
    }
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
    );
  }

  /// FAB：新建文件夹对话框（FAB 已隐藏，恢复时取消注释 FAB 即可）
  // ignore: unused_element
  Future<void> _showAddFolderDialog() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建文件夹'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '文件夹名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    final name = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true || name.isEmpty) return;
    try {
      await _client.addFolder(pid: _dir.cid, name: name);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('已创建"$name"')));
      }
      _reload();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('创建失败：${e.message}')));
      }
    }
  }

  // ---------------- 行菜单操作：剪切 / 删除 / 重命名 ----------------

  /// 长按操作菜单：原行尾 ⋮ 的 PopupMenu 样式（白底直角），
  /// 锚定在行右端（原 ⋮ 一侧）向下弹出，而非底部面板
  Future<void> _showRowMenu(BuildContext rowCtx, FileItem f) async {
    final rowBox = rowCtx.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (rowBox == null || overlay == null) return;
    final anchor = RelativeRect.fromRect(
      Rect.fromLTWH(rowBox.size.width - 48, 0, 48, rowBox.size.height)
          .shift(rowBox.localToGlobal(Offset.zero, ancestor: overlay)),
      Offset.zero & overlay.size,
    );
    final v = await showMenu<String>(
      context: context,
      position: anchor,
      color: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      items: const [
        PopupMenuItem(value: 'cut', child: Text('剪切')),
        PopupMenuItem(value: 'delete', child: Text('删除')),
        PopupMenuItem(value: 'rename', child: Text('重命名')),
      ],
    );
    if (v != null) _onRowMenu(v, f);
  }

  void _onRowMenu(String v, FileItem f) {
    switch (v) {
      case 'cut':
        _cutItem(f);
      case 'delete':
        _deleteItem(f);
      case 'rename':
        _renameItem(f);
    }
  }

  /// 剪切：记入剪贴板，到目标目录后点粘贴栏完成移动
  void _cutItem(FileItem f) {
    setState(() {
      _cutFid = f.fid;
      _cutName = f.name;
    });
  }

  /// 粘贴栏：剪切中的提示 + 粘贴到当前目录 / 取消
  Widget _pasteBar() {
    return Container(
      width: double.infinity,
      color: AppTheme.scaffold,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Icon(Icons.content_cut,
              size: 16, color: AppTheme.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '已剪切「$_cutName」',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12, color: AppTheme.textPrimary),
            ),
          ),
          TextButton(
            onPressed: _pasteItem,
            child: const Text('粘贴到当前目录',
                style: TextStyle(fontSize: 12)),
          ),
          TextButton(
            onPressed: () =>
                setState(() {
                  _cutFid = null;
                  _cutName = null;
                }),
            child: const Text('取消', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Future<void> _pasteItem() async {
    final fid = _cutFid;
    if (fid == null) return;
    try {
      await _client.ufileMove(fid, _dir.cid);
      if (!mounted) return;
      setState(() {
        _cutFid = null;
        _cutName = null;
      });
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      _toast('粘贴失败：${e.message}');
    } catch (_) {
      if (!mounted) return;
      _toast('粘贴失败，请稍后重试');
    }
  }

  /// 删除：确认后调接口，成功走收起动画并从列表移除
  Future<void> _deleteItem(FileItem f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除'),
        content: Text('确定删除「${f.name}」？可到 115 回收站还原。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFF53F3F)),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _client.ufileDelete(f.fid);
      if (!mounted) return;
      // 复用空文件夹剔除的淡出折叠动画时序
      setState(() => _removingIds.add(f.fid));
      await Future<void>.delayed(const Duration(milliseconds: 320));
      if (!mounted) return;
      setState(() {
        _removingIds.remove(f.fid);
        _items.removeWhere((e) => e.fid == f.fid);
        if (_count > 0) _count--;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      _toast('删除失败：${e.message}');
    } catch (_) {
      if (!mounted) return;
      _toast('删除失败，请稍后重试');
    }
  }

  /// 重命名：弹输入框，成功后整页刷新（排序/统计一并更新）
  Future<void> _renameItem(FileItem f) async {
    final ctrl = TextEditingController(text: f.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(isDense: true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    final name = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true || name.isEmpty || name == f.name) return;
    try {
      await _client.ufileRename(f.fid, name);
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      _toast('重命名失败：${e.message}');
    } catch (_) {
      if (!mounted) return;
      _toast('重命名失败，请稍后重试');
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  void _showInfoSheet(FileItem f) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  FileLeadingIcon(item: f),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(f.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _infoRow('类型', f.isDir ? '文件夹' : KindStyle.label(f.kind)),
              if (!f.isDir) _infoRow('大小', formatBytes(f.size)),
              if (f.mtime != null) _infoRow('时间', fmtDate(f.mtime!)),
              if (f.isVideo) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primary),
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => VideoPlayerPage(item: f),
                      ));
                    },
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('播放'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(k,
                style: TextStyle(
                    fontSize: 13, color: AppTheme.textSecondary)),
          ),
          Expanded(
            child: Text(v,
                style: TextStyle(
                    fontSize: 13, color: AppTheme.textPrimary)),
          ),
        ],
      ),
    );
  }
}

/// 条目移除动画：[removing] 置 true 后 300ms 内淡出并收起高度
/// （网格等定高场景传 [collapse] 为 false 仅淡出）；
/// 动画由父层在延时移除条目前驱动
class _FadeCollapse extends StatefulWidget {
  const _FadeCollapse({
    super.key,
    required this.removing,
    this.collapse = true,
    required this.child,
  });

  final bool removing;
  final bool collapse;
  final Widget child;

  @override
  State<_FadeCollapse> createState() => _FadeCollapseState();
}

class _FadeCollapseState extends State<_FadeCollapse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );

  @override
  void initState() {
    super.initState();
    if (widget.removing) _ctrl.value = 1; // 极端时序：直接处于移除态
  }

  @override
  void didUpdateWidget(covariant _FadeCollapse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.removing && !oldWidget.removing) _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) {
        final t = _ctrl.value;
        if (t == 0) return child!; // 常规状态零包装开销
        return IgnorePointer(
          child: Opacity(
            opacity: 1 - t,
            child: widget.collapse
                ? ClipRect(
                    child: Align(
                      heightFactor: 1 - t,
                      child: child,
                    ),
                  )
                : child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off, size: 64, color: AppTheme.textSecondary),
          const SizedBox(height: 12),
          Text(message, style: TextStyle(color: AppTheme.textSecondary)),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}
