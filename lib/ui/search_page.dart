import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../network/api_client.dart';
import '../session.dart';
import '../ui/theme.dart';
import '../util/formatters.dart';
import 'video_player_page.dart';

/// 筛选类型（对应 chips 行）
enum _SearchFilter { all, file, folder, audio, image, video }

/// 全盘文件搜索页（参照 Material Files 截图布局）
///
/// - 白色工具栏：返回箭头 + 无边框输入框（清除 X）
/// - 筛选 chips 行：全部 | 文件 | 文件夹 | 音频 | 图片 | 视频（选中主蓝底白字）
/// - 无关键词时展示「最近搜索」：时钟图标 + 关键词，右侧清空入口
/// - 结果列表行与文件页同款，按 chip 客户端过滤
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  static const _kHistory = 'ghost.searchHistory';
  static const _kHistoryMax = 10;

  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;

  List<FileItem> _results = [];
  bool _loading = false;
  String? _error;
  bool _searched = false;

  _SearchFilter _filter = _SearchFilter.all;
  List<String> _history = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
    // 进入即聚焦弹出键盘（参考图状态）
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _history = p.getStringList(_kHistory) ?? []);
  }

  Future<void> _saveHistory(String kw) async {
    final list = [kw, ..._history.where((e) => e != kw)]
        .take(_kHistoryMax)
        .toList();
    setState(() => _history = list);
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kHistory, list);
  }

  Future<void> _clearHistory() async {
    setState(() => _history = []);
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kHistory, []);
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    setState(() {}); // 刷新清除按钮
    if (v.trim().isEmpty) {
      setState(() {
        _results.clear();
        _searched = false;
        _error = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 500), _search);
  }

  Future<void> _search() async {
    final kw = _controller.text.trim();
    if (kw.isEmpty) return;
    _focus.unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final j = await Session.instance.client.search(kw, limit: 100);
      if (!mounted) return;
      setState(() {
        _results = (j['data'] as List)
            .map((e) =>
                FileItem.fromSearchJson((e as Map).cast<String, dynamic>()))
            .toList();
        _loading = false;
        _searched = true;
      });
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
        _error = '网络异常';
      });
    }
  }

  /// 显式提交（回车）：搜索并记入历史
  void _submit() {
    final kw = _controller.text.trim();
    if (kw.isEmpty) return;
    _saveHistory(kw);
    _search();
  }

  /// 点击历史词：填入并立即搜索
  void _applyHistory(String kw) {
    _controller.text = kw;
    setState(() {}); // 刷新清除按钮
    _search();
  }

  /// 当前筛选下的结果
  List<FileItem> get _filtered => switch (_filter) {
        _SearchFilter.all => _results,
        _SearchFilter.file => _results.where((f) => !f.isDir).toList(),
        _SearchFilter.folder => _results.where((f) => f.isDir).toList(),
        _SearchFilter.audio =>
          _results.where((f) => f.kind == FileKind.audio).toList(),
        _SearchFilter.image =>
          _results.where((f) => f.kind == FileKind.image).toList(),
        _SearchFilter.video =>
          _results.where((f) => f.kind == FileKind.video).toList(),
      };

  void _onItemTap(FileItem f) {
    if (f.isVideo) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => VideoPlayerPage(item: f),
      ));
    } else {
      _showInfoSheet(f);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          _toolbar(),
          _chips(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  /// 白色工具栏：返回 + 无边框输入框（参考 Material Files）
  Widget _toolbar() {
    return Material(
      color: Colors.white,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
                tooltip: '返回',
                onPressed: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  cursorColor: AppTheme.primary,
                  textInputAction: TextInputAction.search,
                  style: const TextStyle(
                      fontSize: 15, color: AppTheme.textPrimary),
                  onChanged: _onChanged,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    hintText: '搜索',
                    hintStyle: const TextStyle(
                        fontSize: 15, color: AppTheme.textSecondary),
                    suffixIcon: _controller.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close,
                                size: 18, color: AppTheme.textSecondary),
                            onPressed: () {
                              _controller.clear();
                              setState(() {
                                _results.clear();
                                _searched = false;
                                _error = null;
                              });
                              _focus.requestFocus();
                            },
                          )
                        : null,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }

  /// 筛选 chips 行：全部 | 文件 | 文件夹 | 音频 | 图片 | 视频
  Widget _chips() {
    const entries = [
      (_SearchFilter.all, '全部'),
      (_SearchFilter.file, '文件'),
      (_SearchFilter.folder, '文件夹'),
      (_SearchFilter.audio, '音频'),
      (_SearchFilter.image, '图片'),
      (_SearchFilter.video, '视频'),
    ];
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        itemCount: entries.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final (value, label) = entries[i];
          final selected = _filter == value;
          return GestureDetector(
            onTap: () => setState(() => _filter = value),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? AppTheme.primary : const Color(0xFFF1F3F4),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: selected ? Colors.white : AppTheme.textPrimary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody() {
    // 未搜索：最近搜索历史
    if (!_searched && !_loading && _error == null) return _historyView();
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!,
                style: const TextStyle(color: AppTheme.textSecondary)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _search, child: const Text('重试')),
          ],
        ),
      );
    }
    final list = _filtered;
    if (list.isEmpty) {
      final hasRaw = _results.isNotEmpty;
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(hasRaw ? Icons.filter_alt_off : Icons.folder_off,
                size: 64, color: AppTheme.textSecondary),
            const SizedBox(height: 12),
            Text(
              hasRaw
                  ? '当前筛选类型下无结果'
                  : '未找到"${_controller.text.trim()}"相关文件',
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
          ],
        ),
      );
    }
    // 结果列表：与文件页同款行
    return ListView.separated(
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
      itemCount: list.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: AppTheme.divider),
      itemBuilder: (_, i) => _resultRow(list[i]),
    );
  }

  /// 最近搜索：标题行 + 时钟条目（点击回填搜索）
  Widget _historyView() {
    if (_history.isEmpty) {
      return const Center(
        child: Text('输入关键词搜索全盘文件',
            style: TextStyle(color: AppTheme.textSecondary)),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
      itemCount: _history.length + 1,
      itemBuilder: (_, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 4, 4),
            child: Row(
              children: [
                const Text('最近搜索',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textPrimary)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      size: 20, color: AppTheme.textSecondary),
                  tooltip: '清空历史',
                  onPressed: _clearHistory,
                ),
              ],
            ),
          );
        }
        final kw = _history[i - 1];
        return Column(
          children: [
            InkWell(
              onTap: () => _applyHistory(kw),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.access_time,
                        size: 18, color: AppTheme.textSecondary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(kw,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14, color: AppTheme.textPrimary)),
                    ),
                  ],
                ),
              ),
            ),
            if (i < _history.length)
              const Divider(height: 1, indent: 46, color: AppTheme.divider),
          ],
        );
      },
    );
  }

  Widget _resultRow(FileItem f) {
    return InkWell(
      onTap: () => _onItemTap(f),
      onLongPress: () => _showInfoSheet(f),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                      style: const TextStyle(
                          fontSize: 15, color: AppTheme.textPrimary)),
                  const SizedBox(height: 2),
                  // 副标题：时间（文件夹/文件都有），文件多一项大小（与主页一致）
                  Text(
                    [
                      if (f.mtime != null) fmtDate(f.mtime!),
                      if (!f.isDir) formatBytes(f.size),
                    ].join(' | '),
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 36,
              height: 40,
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.more_vert,
                    size: 20, color: AppTheme.textSecondary),
                onPressed: () => _showInfoSheet(f),
              ),
            ),
          ],
        ),
      ),
    );
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
              _row('类型', f.isDir ? '文件夹' : KindStyle.label(f.kind)),
              if (!f.isDir) _row('大小', formatBytes(f.size)),
              if (f.mtime != null) _row('时间', fmtDate(f.mtime!)),
              if (f.isVideo)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.accent),
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
          ),
        ),
      ),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 64,
                child: Text(k,
                    style: const TextStyle(
                        fontSize: 13, color: AppTheme.textSecondary))),
            Expanded(
              child: Text(v,
                  style: const TextStyle(
                      fontSize: 13, color: AppTheme.textPrimary)),
            ),
          ],
        ),
      );
}
