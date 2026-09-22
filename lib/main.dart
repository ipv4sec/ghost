import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'magnet_channel.dart';
import 'session.dart';
import 'ui/home_shell.dart';
import 'ui/login_page.dart';
import 'ui/theme.dart';

void main() {
  runApp(const GhostApp());
}

class GhostApp extends StatelessWidget {
  const GhostApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: ' ',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: _Bootstrap(),
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
  @override
  void initState() {
    super.initState();
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
          return const Scaffold(
            backgroundColor: AppTheme.scaffold,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return s.loggedIn ? const HomeShell() : const LoginPage();
      },
    );
  }
}
