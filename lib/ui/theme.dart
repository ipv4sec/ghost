import 'package:flutter/material.dart';

import '../models/models.dart';

/// 蓝色文件管理器风格主题（按参考图 752845 取色）
class AppTheme {
  AppTheme._();

  /// 顶栏深蓝紫（参考图估值 #4153B8）
  static const primary = Color(0xFF4153B8);
  /// 强调玫红（圆形图标底 / FAB）
  static const accent = Color(0xFFE91E63);
  static const scaffold = Color(0xFFF7F8FA);
  static const textPrimary = Color(0xFF1F2329);
  static const textSecondary = Color(0xFF9E9E9E);
  static const divider = Color(0xFFE0E0E0);

  static ThemeData light() {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        primary: primary,
        secondary: accent,
      ),
      scaffoldBackgroundColor: Colors.white,
      appBarTheme: const AppBarTheme(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w500,
        ),
      ),
      dividerColor: divider,
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: primary),
      snackBarTheme:
          const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: Colors.white,
      ),
    );
  }
}

/// 文件类型中文名 + 类型图案（列表行圆形图标，见 [FileLeadingIcon]）
class KindStyle {
  KindStyle._();

  /// 圆形底色：文件夹玫红（accent，参考图），文件深蓝紫（primary，
  /// 与顶栏同色）——两类行图标颜色区分
  static Color color(FileKind k) =>
      k == FileKind.folder ? AppTheme.accent : AppTheme.primary;

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
  /// 视频=胶片、图片=相片…），与玫红圆形底组成统一风格
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

/// 圆形行图标：类型色圆底 + 白色 Material 类型图案（文件夹玫红、文件
/// 深蓝紫；不再用网络缩略图，列表观感统一）
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
          color: Colors.white, size: size * 0.5),
    );
  }
}
