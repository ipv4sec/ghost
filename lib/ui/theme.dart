import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// 主题色快捷入口：页面直接 AppTheme.xxx 取当前 flex 配色方案派生的
/// 语义角色。应用整体保持浅色设计（白底深字），配色方案与派生规则
/// 参考 varus（flex_color_scheme 内置方案表）。主题切换后
/// MaterialApp 重挂载 home 子树（见 main.dart 的 KeyedSubtree），
/// 各页重建时重新取色。
class AppTheme {
  AppTheme._();

  /// 当前配色方案（[FlexColor.schemesList] 内置方案）；
  /// main() 里从 SharedPreferences 恢复
  static FlexSchemeData current = FlexColor.schemesList.first;

  /// 当前方案的浅色色板
  static FlexSchemeColor get _c => current.light;

  /// 主交互色：按钮/进度/选中态底色
  static Color get primary => _c.primary;

  /// 文件夹圆形图标底色，onAccent 为圆内图案色
  static Color get accent => _c.secondary;
  static Color get onAccent => _onColor(_c.secondary);

  /// 浅底上的强调文字/图标（错误提示、下载失败状态）
  static Color get accentDeep => _c.error ?? const Color(0xFFB3261E);

  /// 顶栏底色（方案的 appBarColor，缺省回退 primary），
  /// onHeader 为顶栏图标/文字色；lightHeader = 顶栏是否浅色
  /// （决定状态栏图标深浅）
  static Color get header => _c.appBarColor ?? _c.primary;
  static Color get onHeader => _onColor(header);
  static bool get lightHeader =>
      ThemeData.estimateBrightnessForColor(header) == Brightness.light;

  /// 浅底色（登录卡片/粘贴栏/磁链框/启动页），配深色文字
  static Color get scaffold => Colors.white;

  /// 分隔线
  static Color get divider => const Color(0x1F000000);

  /// 主文字 / 次文字（浅底上的近黑两级灰）
  static Color get textPrimary => Colors.black87;
  static Color get textSecondary => Colors.black54;

  /// VIP 卡渐变两端（配深色文字）
  static Color get vipStart => _c.primaryContainer;
  static Color get vipEnd => _c.secondaryContainer;

  /// 深底配浅字、浅底配深字（FlexSchemeColor 不含 onX，
  /// 按背景亮度估算）
  static Color _onColor(Color bg) =>
      ThemeData.estimateBrightnessForColor(bg) == Brightness.dark
          ? Colors.white
          : Colors.black87;

  static ThemeData light() {
    // 参考 varus：flex_color_scheme + Material 2 + Montserrat 字体
    // （中文回退微软正黑体），配色取当前内置方案；
    // 顶栏 elevation 20 投影同 varus
    return FlexThemeData.light(
      fontFamily: 'Montserrat',
      fontFamilyFallback: const ['微软正黑体'],
      useMaterial3: false,
      colors: _c,
    ).copyWith(
      scaffoldBackgroundColor: Colors.white,
      appBarTheme: AppBarTheme(
        backgroundColor: header,
        foregroundColor: onHeader,
        // 顶栏深浅决定状态栏图标深浅（AppBar 页随主题自动生效）
        systemOverlayStyle:
            lightHeader ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
        // varus 风格：顶栏带投影
        elevation: 20,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: onHeader,
          fontSize: 20, // varus 顶栏字号
          fontWeight: FontWeight.w500,
        ),
      ),
      dividerColor: divider,
      progressIndicatorTheme: ProgressIndicatorThemeData(color: primary),
      snackBarTheme:
          const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
      ),
    );
  }
}

/// 主题选择管理：切换后通知 MaterialApp 重建，并持久化到
/// SharedPreferences（ghost.scheme，存方案名）
class ThemeManager extends ChangeNotifier {
  ThemeManager._();
  static final ThemeManager instance = ThemeManager._();

  static const _kScheme = 'ghost.scheme';

  /// 旧版 12 套色卡主题遗留的 key（存主题 id int），加载时顺手清掉
  static const _kLegacyTheme = 'ghost.theme';

  /// 所有可选配色方案（flex_color_scheme 内置方案表）
  List<FlexSchemeData> get schemes => FlexColor.schemesList;

  /// 启动时恢复上次选择（main() 里 await，避免首帧闪默认主题）
  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kLegacyTheme); // 旧版主题 id 已无对应方案
    final name = sp.getString(_kScheme);
    if (name == null) return;
    for (final s in FlexColor.schemesList) {
      if (s.name == name) {
        AppTheme.current = s;
        return;
      }
    }
  }

  /// 切换配色：改 current → 通知重建 → 持久化
  Future<void> select(FlexSchemeData s) async {
    if (s == AppTheme.current) return;
    AppTheme.current = s;
    notifyListeners();
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kScheme, s.name);
  }
}

/// 文件类型中文名 + 类型图案（列表行圆形图标，见 [FileLeadingIcon]）
class KindStyle {
  KindStyle._();

  /// 圆形底色：文件夹用主题 accent，文件用主题 primary
  /// （与交互色同色）——两类行图标深浅区分
  static Color color(FileKind k) =>
      k == FileKind.folder ? AppTheme.accent : AppTheme.primary;

  /// 圆内图案色：文件夹 accent 底配 onAccent，文件 primary 底配白
  static Color iconColor(FileKind k) =>
      k == FileKind.folder ? AppTheme.onAccent : Colors.white;

  /// 类型中文名
  static String label(FileKind k) => switch (k) {
        FileKind.folder => '文件夹',
        FileKind.doc => '文档',
        FileKind.image => '图片',
        FileKind.audio => '音频',
        FileKind.video => '视频',
        FileKind.archive => '压缩包',
        FileKind.app => '应用',
        FileKind.book => '书籍',
        FileKind.other => '文件',
      };

  /// 行图标：Material outlined 家族，按类型区分（文件夹=文件夹图案，
  /// 视频=胶片、图片=相片…），与主题色圆底组成统一风格
  static IconData icon(FileKind k) => switch (k) {
        FileKind.folder => Icons.folder_outlined,
        FileKind.doc => Icons.description_outlined,
        FileKind.image => Icons.image_outlined,
        FileKind.audio => Icons.music_note_outlined,
        FileKind.video => Icons.movie_outlined,
        FileKind.archive => Icons.archive_outlined,
        FileKind.app => Icons.android_outlined,
        FileKind.book => Icons.book_outlined,
        FileKind.other => Icons.insert_drive_file_outlined,
      };
}

/// 圆形行图标：类型色圆底 + Material 类型图案（文件夹 accent 底
/// onAccent 图案、文件 primary 底白图案；列表观感统一）
class FileLeadingIcon extends StatelessWidget {
  const FileLeadingIcon({super.key, required this.item, this.size = 40});

  final FileItem item;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: KindStyle.color(item.kind),
        shape: BoxShape.circle,
      ),
      child: Icon(KindStyle.icon(item.kind),
          color: KindStyle.iconColor(item.kind), size: size * 0.5),
    );
  }
}

/// 自绘顶栏的投影（varus AppBar elevation 20 的观感）：渐变阴影压在
/// 内容区最上层，滚动内容从投影下方穿过。须放在 Stack 的 children 里
/// （内部是 Positioned），如 `Stack(children: [body, HeaderShadow()])`
class HeaderShadow extends StatelessWidget {
  const HeaderShadow({super.key, this.height = 16});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Container(
          height: height,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black26, Colors.transparent],
            ),
          ),
        ),
      ),
    );
  }
}
