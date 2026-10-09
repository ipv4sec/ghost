import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// 一套主题配色：对应桌面 配色.png 中的一张色卡（5 色从浅到深），
/// 派生少量补充角色（次文字 = 主文字向白提亮、分隔线 = 浅色均值、
/// 对比度不足时加深的交互色、深色卡的浅底替身），保证各角色可用。
class GhostPalette {
  const GhostPalette({
    required this.id,
    required this.name,
    required this.swatches,
    required this.primary,
    required this.accent,
    required this.onAccent,
    required this.accentDeep,
    required this.header,
    required this.onHeader,
    required this.lightHeader,
    required this.scaffold,
    required this.divider,
    required this.textPrimary,
    required this.textSecondary,
    required this.vipStart,
    required this.vipEnd,
  });

  final int id;

  /// 主题名（设置页选择列表展示）
  final String name;

  /// 色卡原始 5 色，从浅到深（选择列表预览圆点）
  final List<Color> swatches;

  /// 主交互色：按钮/进度/选中态底色（白前景，对比 ≥3:1）
  final Color primary;

  /// 文件夹圆形图标底色，onAccent 为圆内图案色
  final Color accent;
  final Color onAccent;

  /// 浅底上的强调文字/图标（错误提示、下载失败状态）
  final Color accentDeep;

  /// 顶栏底色，onHeader 为顶栏图标/文字色；
  /// lightHeader = 顶栏是否浅色（决定状态栏图标深浅）
  final Color header;
  final Color onHeader;
  final bool lightHeader;

  /// 浅底色（登录卡片/粘贴栏/磁链框/启动页），配深色文字，
  /// 因此深色卡也用浅色替身
  final Color scaffold;

  /// 分隔线
  final Color divider;

  /// 主文字 / 次文字
  final Color textPrimary;
  final Color textSecondary;

  /// VIP 卡渐变两端（配 textPrimary 深字）
  final Color vipStart;
  final Color vipEnd;
}

/// 12 套主题：前 9 套取自桌面 配色.png 的 9 张色卡（3×3，从左到右、
/// 从上到下），第 10 套取自桌面 配色1.png 的 5 色色卡，第 11、12 套
/// 为直接给出的 4 色配色
const List<GhostPalette> ghostPalettes = [
  // 1 苔原：灰绿 + 棕
  GhostPalette(
    id: 1,
    name: '苔原',
    swatches: [
      Color(0xFFD7DEDE),
      Color(0xFFAEC7B8),
      Color(0xFF85AA99),
      Color(0xFF9E6A3C),
      Color(0xFF592D25),
    ],
    primary: Color(0xFF9E6A3C),
    accent: Color(0xFF85AA99),
    onAccent: Color(0xFF592D25),
    accentDeep: Color(0xFF9E6A3C),
    header: Color(0xFFAEC7B8),
    onHeader: Color(0xFF592D25),
    lightHeader: true,
    scaffold: Color(0xFFD7DEDE),
    divider: Color(0xFFC2D2CB),
    textPrimary: Color(0xFF592D25),
    textSecondary: Color(0xFFA48C88),
    vipStart: Color(0xFFD7DEDE),
    vipEnd: Color(0xFFAEC7B8),
  ),
  // 2 鸢尾：薰衣草灰 + 金 + 砖
  GhostPalette(
    id: 2,
    name: '鸢尾',
    swatches: [
      Color(0xFFD7D7E3),
      Color(0xFFDAC880),
      Color(0xFFF4CA60),
      Color(0xFFA593A0),
      Color(0xFF743A32),
    ],
    primary: Color(0xFF743A32),
    accent: Color(0xFFF4CA60),
    onAccent: Color(0xFF743A32),
    accentDeep: Color(0xFF743A32),
    header: Color(0xFFDAC880),
    onHeader: Color(0xFF743A32),
    lightHeader: true,
    scaffold: Color(0xFFD7D7E3),
    divider: Color(0xFFD8D0B2),
    textPrimary: Color(0xFF743A32),
    textSecondary: Color(0xFFB3938F),
    vipStart: Color(0xFFD7D7E3),
    vipEnd: Color(0xFFDAC880),
  ),
  // 3 珊瑚：天蓝 + 珊瑚红 + 石板灰
  GhostPalette(
    id: 3,
    name: '珊瑚',
    swatches: [
      Color(0xFFD2D5D2),
      Color(0xFFA79F97),
      Color(0xFF69AACF),
      Color(0xFFDB5E4F),
      Color(0xFF625766),
    ],
    primary: Color(0xFFDB5E4F),
    accent: Color(0xFF625766),
    onAccent: Colors.white,
    accentDeep: Color(0xFFDB5E4F),
    header: Color(0xFFDB5E4F),
    onHeader: Colors.white,
    lightHeader: false, // 珊瑚顶栏配浅色状态栏图标
    scaffold: Color(0xFFD2D5D2),
    divider: Color(0xFFBCBAB4),
    textPrimary: Color(0xFF625766),
    textSecondary: Color(0xFFA9A3AB),
    vipStart: Color(0xFFD2D5D2),
    vipEnd: Color(0xFFA79F97),
  ),
  // 4 暖秋：桃 + 金 + 铁锈
  GhostPalette(
    id: 4,
    name: '暖秋',
    swatches: [
      Color(0xFFFCCB9B),
      Color(0xFFEDBC1B),
      Color(0xFFC45622),
      Color(0xFF444119),
      Color(0xFF391C16),
    ],
    primary: Color(0xFFC45622),
    accent: Color(0xFFFCCB9B),
    onAccent: Color(0xFF391C16),
    accentDeep: Color(0xFFC45622),
    header: Color(0xFFEDBC1B),
    onHeader: Color(0xFF391C16),
    lightHeader: true,
    scaffold: Color(0xFFFCCB9B),
    divider: Color(0xFFF4C35B),
    textPrimary: Color(0xFF391C16),
    textSecondary: Color(0xFF92827F),
    vipStart: Color(0xFFFCCB9B),
    vipEnd: Color(0xFFEDBC1B),
  ),
  // 5 薄荷：奶油 + 薄荷绿 + 橙（交互色取橙加深保证白字对比）
  GhostPalette(
    id: 5,
    name: '薄荷',
    swatches: [
      Color(0xFFF6EBD8),
      Color(0xFFD9E9CD),
      Color(0xFFB4E6C1),
      Color(0xFFFDE473),
      Color(0xFFF3912C),
    ],
    primary: Color(0xFFB96E21),
    accent: Color(0xFFB4E6C1),
    onAccent: Color(0xFF55330F),
    accentDeep: Color(0xFFB96E21),
    header: Color(0xFFF3912C),
    onHeader: Color(0xFF55330F),
    lightHeader: true,
    scaffold: Color(0xFFF6EBD8),
    divider: Color(0xFFE7EAD2),
    textPrimary: Color(0xFF55330F),
    textSecondary: Color(0xFFA18F7B),
    vipStart: Color(0xFFF6EBD8),
    vipEnd: Color(0xFFD9E9CD),
  ),
  // 6 橄榄：沙 + 琥珀 + 橄榄绿
  GhostPalette(
    id: 6,
    name: '橄榄',
    swatches: [
      Color(0xFFEFE5DA),
      Color(0xFFF3D9A6),
      Color(0xFFE29F31),
      Color(0xFFB1BA50),
      Color(0xFF6C7C25),
    ],
    primary: Color(0xFF6C7C25),
    accent: Color(0xFFB1BA50),
    onAccent: Color(0xFF474A20),
    accentDeep: Color(0xFF6C7C25),
    header: Color(0xFFF3D9A6),
    onHeader: Color(0xFF6C7C25),
    lightHeader: true,
    scaffold: Color(0xFFEFE5DA),
    divider: Color(0xFFF1DFC0),
    textPrimary: Color(0xFF6C7C25),
    textSecondary: Color(0xFFAEB787),
    vipStart: Color(0xFFEFE5DA),
    vipEnd: Color(0xFFF3D9A6),
  ),
  // 7 紫玫：麦色 + 灰玫 + 梅紫
  GhostPalette(
    id: 7,
    name: '紫玫',
    swatches: [
      Color(0xFFEADFBE),
      Color(0xFFB7968F),
      Color(0xFFAC7885),
      Color(0xFFA45985),
      Color(0xFF833252),
    ],
    primary: Color(0xFFA45985),
    accent: Color(0xFFAC7885),
    onAccent: Colors.white,
    accentDeep: Color(0xFFA45985),
    header: Color(0xFFB7968F),
    onHeader: Color(0xFF833252),
    lightHeader: true,
    scaffold: Color(0xFFEADFBE),
    divider: Color(0xFFD0BAA6),
    textPrimary: Color(0xFF833252),
    textSecondary: Color(0xFFBB8FA0),
    vipStart: Color(0xFFEADFBE),
    vipEnd: Color(0xFFB7968F),
  ),
  // 8 铜绿：灰 + 黄绿 + 铜
  GhostPalette(
    id: 8,
    name: '铜绿',
    swatches: [
      Color(0xFFDAD9D4),
      Color(0xFFB8C787),
      Color(0xFFBD8846),
      Color(0xFF8A807A),
      Color(0xFF675E5D),
    ],
    primary: Color(0xFFBD8846),
    accent: Color(0xFFB8C787),
    onAccent: Color(0xFF675E5D),
    accentDeep: Color(0xFF8A807A),
    header: Color(0xFFB8C787),
    onHeader: Color(0xFF675E5D),
    lightHeader: true,
    scaffold: Color(0xFFDAD9D4),
    divider: Color(0xFFC9D0AE),
    textPrimary: Color(0xFF675E5D),
    textSecondary: Color(0xFFABA7A6),
    vipStart: Color(0xFFDAD9D4),
    vipEnd: Color(0xFFB8C787),
  ),
  // 9 暗夜：深褐 + 藏青 + 绛红（深顶栏浅图标；浅底/分隔线用派生浅灰，
  // 保证粘贴栏、登录卡上的深色文字可读）
  GhostPalette(
    id: 9,
    name: '暗夜',
    swatches: [
      Color(0xFF6C5D54),
      Color(0xFF603A27),
      Color(0xFF0E2B3A),
      Color(0xFF3D1B26),
      Color(0xFF981406),
    ],
    primary: Color(0xFF981406),
    accent: Color(0xFF0E2B3A),
    onAccent: Colors.white,
    accentDeep: Color(0xFF981406),
    header: Color(0xFF603A27),
    onHeader: Colors.white,
    lightHeader: false, // 深褐顶栏配浅色状态栏图标
    scaffold: Color(0xFFE2DEDC),
    divider: Color(0xFFD3CECC),
    textPrimary: Color(0xFF3D1B26),
    textSecondary: Color(0xFF958288),
    vipStart: Color(0xFFD8CFCA),
    vipEnd: Color(0xFFBFB0A9),
  ),
  // 10 粉彩：白 + 薄荷 + 薰衣草 + 金 + 近黑（桌面 配色1.png 的色卡）。
  // 近黑作交互色与正文（白字对比约 16:1），薄荷作顶栏、薰衣草作
  // 文件夹圆底；金较浅不配白字，落在 VIP 卡渐变深端（纯白作渐变
  // 起点会在白底上隐形，故起点改用薄荷）
  GhostPalette(
    id: 10,
    name: '粉彩',
    swatches: [
      Color(0xFFFFFFFF),
      Color(0xFFC7F4C2),
      Color(0xFFBFB5FF),
      Color(0xFFFDDD8D),
      Color(0xFF241F21),
    ],
    primary: Color(0xFF241F21),
    accent: Color(0xFFBFB5FF),
    onAccent: Color(0xFF241F21),
    accentDeep: Color(0xFF241F21),
    header: Color(0xFFC7F4C2),
    onHeader: Color(0xFF241F21),
    lightHeader: true,
    scaffold: Color(0xFFFFFFFF),
    divider: Color(0xFFE3F9E0),
    textPrimary: Color(0xFF241F21),
    textSecondary: Color(0xFF878485),
    vipStart: Color(0xFFC7F4C2),
    vipEnd: Color(0xFFFDDD8D),
  ),
  // 11 暮色：白 + 浅蓝 + 陶土 + 近黑（直接给出的 4 色配色）。近黑作
  // 交互色与正文（白字对比约 18:1），陶土作顶栏（配近黑图标约 7.5:1）、
  // 浅蓝作文件夹圆底；蓝、陶土又作 VIP 卡渐变两端（深字均可读）
  GhostPalette(
    id: 11,
    name: '暮色',
    swatches: [
      Color(0xFFFBFBFB),
      Color(0xFFAEC4E7),
      Color(0xFFD7987D),
      Color(0xFF161615),
    ],
    primary: Color(0xFF161615),
    accent: Color(0xFFAEC4E7),
    onAccent: Color(0xFF161615),
    accentDeep: Color(0xFF161615),
    header: Color(0xFFD7987D),
    onHeader: Color(0xFF161615),
    lightHeader: true,
    scaffold: Color(0xFFFBFBFB),
    divider: Color(0xFFD5C8CA),
    textPrimary: Color(0xFF161615),
    textSecondary: Color(0xFF958682),
    vipStart: Color(0xFFAEC4E7),
    vipEnd: Color(0xFFD7987D),
  ),
  // 12 晨雾：冷白 + 薰衣草 + 薄荷 + 灰黑（直接给出的 4 色配色）。
  // 灰黑作交互色与正文（白字对比约 12:1）；薰衣草/薄荷原色近白，
  // 顶栏与 VIP 卡渐变两端各压深少许避免与底色相融，圆底仍用原薄荷
  GhostPalette(
    id: 12,
    name: '晨雾',
    swatches: [
      Color(0xFFF9F9FB),
      Color(0xFFEFE9FF),
      Color(0xFFE7F6DF),
      Color(0xFF383838),
    ],
    primary: Color(0xFF383838),
    accent: Color(0xFFE7F6DF),
    onAccent: Color(0xFF383838),
    accentDeep: Color(0xFF383838),
    header: Color(0xFFDED9ED),
    onHeader: Color(0xFF383838),
    lightHeader: true,
    scaffold: Color(0xFFF9F9FB),
    divider: Color(0xFFEAE8F2),
    textPrimary: Color(0xFF383838),
    textSecondary: Color(0xFF8B8A94),
    vipStart: Color(0xFFDED9ED),
    vipEnd: Color(0xFFD7E5CF),
  ),
];

/// 主题色快捷入口：页面直接 AppTheme.xxx 取当前主题对应角色。
/// 主题切换后 MaterialApp 重挂载 home 子树（见 main.dart 的
/// KeyedSubtree），各页重建时重新取色。
class AppTheme {
  AppTheme._();

  /// 当前主题，默认第 1 套；main() 里从 SharedPreferences 恢复
  static GhostPalette current = ghostPalettes[0];

  static Color get primary => current.primary;
  static Color get accent => current.accent;
  static Color get onAccent => current.onAccent;
  static Color get accentDeep => current.accentDeep;
  static Color get scaffold => current.scaffold;
  static Color get divider => current.divider;
  static Color get textPrimary => current.textPrimary;
  static Color get textSecondary => current.textSecondary;
  static Color get header => current.header;
  static Color get onHeader => current.onHeader;
  static Color get vipStart => current.vipStart;
  static Color get vipEnd => current.vipEnd;

  static ThemeData light() {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        primary: primary,
        secondary: accent,
      ),
      scaffoldBackgroundColor: Colors.white,
      appBarTheme: AppBarTheme(
        backgroundColor: header,
        foregroundColor: onHeader,
        // 顶栏深浅决定状态栏图标深浅（AppBar 页随主题自动生效）
        systemOverlayStyle: current.lightHeader
            ? SystemUiOverlayStyle.dark
            : SystemUiOverlayStyle.light,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: onHeader,
          fontSize: 18,
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
/// SharedPreferences（ghost.theme，存主题 id）
class ThemeManager extends ChangeNotifier {
  ThemeManager._();
  static final ThemeManager instance = ThemeManager._();

  /// 启动时恢复上次选择（main() 里 await，避免首帧闪默认主题）
  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    final id = sp.getInt('ghost.theme');
    if (id == null) return;
    AppTheme.current = ghostPalettes.firstWhere(
      (p) => p.id == id,
      orElse: () => ghostPalettes.first,
    );
  }

  /// 切换主题：改 current → 通知重建 → 持久化
  Future<void> select(GhostPalette p) async {
    if (p == AppTheme.current) return;
    AppTheme.current = p;
    notifyListeners();
    final sp = await SharedPreferences.getInstance();
    await sp.setInt('ghost.theme', p.id);
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
      k == FileKind.folder ? AppTheme.current.onAccent : Colors.white;

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
        FileKind.video => Icons.movie_outlined,
        FileKind.audio => Icons.music_note_outlined,
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
