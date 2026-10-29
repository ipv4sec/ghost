import 'package:flutter/material.dart';

import '../models/models.dart';
import 'theme.dart';

/// 电视端深色网格共享组件与配色：电视主页（tv_home_page.dart）与
/// 电视文件夹页（files_page.dart 的 Tv.isTv 分支）共用

/// 整页缩放系数：电视端所有元素（卡片/顶栏/图标/文字/间距）等比缩小，
/// 调大调小只改这一处
const double kTvScale = 0.85;

// ---- 深色配色（页面自包含，不动全局 AppTheme）----
const Color tvBg = Color(0xFF101014); // 近黑页面底
const Color tvSurface = Color(0xFF1A1A20); // 卡片底
const Color tvSkeleton = Color(0xFF24242C); // 骨架占位
const Color tvAccent = Color(0xFF00A4DC); // 焦点描边（Jellyfin 蓝，不随配色方案变）
const Color tvTextDim = Colors.white70;

/// 路径面包屑（参照设计图）：祖先段灰色可点跳回、「›」分隔、
/// 当前段白色加粗。不进遥控器焦点遍历（回上级用返回键），触摸/点击可直跳
class TvBreadcrumb extends StatelessWidget {
  const TvBreadcrumb({
    super.key,
    required this.segments,
    this.onJump,
  });

  /// 从根到当前目录的各级名字；末项 = 当前（不可点）
  final List<String> segments;

  /// 点祖先段（下标）跳转；当前段不触发
  final ValueChanged<int>? onJump;

  @override
  Widget build(BuildContext context) {
    // Align 吃满父级宽度并左对齐：父 Column 默认居中交叉轴，
    // 不包一层面包屑会跑到中间
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < segments.length; i++) ...[
                if (i > 0)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6 * kTvScale),
                    child: Icon(Icons.chevron_right,
                        size: 18 * kTvScale, color: tvTextDim),
                  ),
                if (i == segments.length - 1)
                  Text(
                    segments[i],
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15 * kTvScale,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                else
                  InkWell(
                    onTap: onJump == null ? null : () => onJump!(i),
                    borderRadius: BorderRadius.circular(6 * kTvScale),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4 * kTvScale, vertical: 2 * kTvScale),
                      // 祖先段与当前段字体/大小/颜色完全一致（用户要求统一）
                      child: Text(
                        segments[i],
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15 * kTvScale,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 文件图标：视频用视频图标，其余用类型图标（本地字形，不走网络）
IconData tvFileIconOf(FileItem item) =>
    item.isVideo ? Icons.video_file : KindStyle.icon(item.kind);

/// 文件夹卡：圆角深卡 + 左上文件夹图标 + 左下名称；聚焦蓝描边 + 光晕
/// （描边卡内绘制、四边统一、不缩放溢出不被邻卡遮挡）
class TvFolderCard extends StatefulWidget {
  const TvFolderCard({
    super.key,
    required this.item,
    required this.onTap,
    this.onLongPress,
    this.autofocus = false,
  });

  final FileItem item;
  final ValueChanged<FileItem> onTap;
  final VoidCallback? onLongPress;
  final bool autofocus;

  @override
  State<TvFolderCard> createState() => _TvFolderCardState();
}

class _TvFolderCardState extends State<TvFolderCard> {
  final _node = FocusNode(debugLabel: 'tv-folder');
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _node.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _node.removeListener(_onFocusChanged);
    _node.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    final f = _node.hasFocus;
    if (f != _focused) setState(() => _focused = f);
    if (f) {
      Scrollable.ensureVisible(
        context,
        alignment: 0.5,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      focusNode: _node,
      autofocus: widget.autofocus,
      onTap: () => widget.onTap(widget.item),
      onLongPress: widget.onLongPress,
      // 焦点高亮用自绘描边，InkWell 自身高亮透明避免叠加
      focusColor: Colors.transparent,
      borderRadius: BorderRadius.circular(12 * kTvScale),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: tvSurface,
          borderRadius: BorderRadius.circular(12 * kTvScale),
          // 描边常驻 2.5 宽（透明↔蓝切换），避免聚焦时边框挤动布局
          border: Border.all(
            color: _focused ? tvAccent : Colors.transparent,
            width: 2.5,
          ),
          boxShadow: _focused
              ? [
                  BoxShadow(
                    color: tvAccent.withValues(alpha: 0.35),
                    blurRadius: 14,
                  ),
                ]
              : null,
        ),
        padding: const EdgeInsets.all(18 * kTvScale),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.folder_rounded,
                color: Colors.white38, size: 38 * kTvScale),
            const Spacer(),
            Text(
              widget.item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                // 字号与面包屑「首页」一致（15）；w600 显粗，降为 w500（用户反馈）
                fontSize: 15 * kTvScale,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 文件卡：布局与文件夹卡（TvFolderCard）完全同款——左上类型图标 +
/// 底部名称行，仅两处不同：图标用文件类型图标（tvFileIconOf，不走网络）、
/// 名称末尾附文件大小；网格参数（4 列横向卡）也与文件夹卡一致。
/// 聚焦蓝描边 + 光晕（卡内绘制，四边统一）
class TvFileCard extends StatefulWidget {
  const TvFileCard({
    super.key,
    required this.item,
    required this.onTap,
    this.onLongPress,
    this.autofocus = false,
  });

  final FileItem item;
  final ValueChanged<FileItem> onTap;
  final VoidCallback? onLongPress;
  final bool autofocus;

  @override
  State<TvFileCard> createState() => _TvFileCardState();
}

class _TvFileCardState extends State<TvFileCard> {
  final _node = FocusNode(debugLabel: 'tv-file');
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _node.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _node.removeListener(_onFocusChanged);
    _node.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    final f = _node.hasFocus;
    if (f != _focused) setState(() => _focused = f);
    if (f) {
      Scrollable.ensureVisible(
        context,
        alignment: 0.5,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return InkWell(
      focusNode: _node,
      autofocus: widget.autofocus,
      onTap: () => widget.onTap(item),
      onLongPress: widget.onLongPress,
      focusColor: Colors.transparent,
      borderRadius: BorderRadius.circular(12 * kTvScale),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: tvSurface,
          borderRadius: BorderRadius.circular(12 * kTvScale),
          border: Border.all(
            color: _focused ? tvAccent : Colors.transparent,
            width: 2.5,
          ),
          boxShadow: _focused
              ? [
                  BoxShadow(
                    color: tvAccent.withValues(alpha: 0.35),
                    blurRadius: 14,
                  ),
                ]
              : null,
        ),
        padding: const EdgeInsets.all(18 * kTvScale),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 类型图标（同文件夹卡的尺寸与配色，仅图标字形不同）
            Icon(tvFileIconOf(item),
                color: Colors.white38, size: 38 * kTvScale),
            const Spacer(),
            // 名称行：名称 + 末尾文件大小（用户要求，大小不省略、名称溢出省略）
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      // 与文件夹卡同款：15 号 w500
                      fontSize: 15 * kTvScale,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 8 * kTvScale),
                Text(
                  formatBytes(item.size),
                  style: const TextStyle(
                      color: tvTextDim, fontSize: 12 * kTvScale),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
