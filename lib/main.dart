import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'magnet_channel.dart';
import 'session.dart';
import 'ui/home_shell.dart';
import 'ui/login_page.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 先恢复上次选择的主题再 runApp，避免首帧闪默认主题
  await ThemeManager.instance.load();
  runApp(const GhostApp());
}

class GhostApp extends StatelessWidget {
  const GhostApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 主题切换时整体重建：MaterialApp 换 ThemeData（AppBar 页即时变色），
    // home 子树按主题 id 换 key 重挂载（直接取 AppTheme 色的页面全部重建）
    return AnimatedBuilder(
      animation: ThemeManager.instance,
      builder: (context, _) => MaterialApp(
        title: ' ',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: KeyedSubtree(
          key: ValueKey('theme-${AppTheme.current.id}'),
          child: const AnnotatedRegion<SystemUiOverlayStyle>(
            // 启动页为浅底，状态栏图标用深色；深色页（播放页）自行标注覆盖
            value: SystemUiOverlayStyle.dark,
            child: _Bootstrap(),
          ),
        ),
      ),
    );
  }
}

/// 启动页：初始化会话后按登录态分流
class _Bootstrap extends StatefulWidget {
  const _Bootstrap();

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  /// 主题切换会重挂载 home 子树，初始化只做一次
  static bool _inited = false;

  @override
  void initState() {
    super.initState();
    if (_inited) return;
    _inited = true;
    Session.instance.init();
    MagnetInbox.instance.init(); // 冷启动带入的磁力链接
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Session.instance,
      builder: (context, _) {
        final s = Session.instance;
        if (!s.ready) {
          return Scaffold(
            backgroundColor: AppTheme.scaffold,
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        return s.loggedIn ? const HomeShell() : const LoginPage();
      },
    );
  }
}
