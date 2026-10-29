import 'package:flutter/material.dart';

import '../ui/files_page.dart';
import '../ui/profile_page.dart';
import '../ui/tv.dart';
import '../ui/tv_home_page.dart';

/// 主页壳：文件页全屏（Amaze 布局，无底部导航），
/// 汉堡按钮侧滑打开"我的"抽屉；授权失效时 Session 通知自动回登录页。
/// 电视端换深色媒体中心首页（TvHomePage），手机端保持文件页不变。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      // 电视端深色底（与 TvHomePage 同色，避免推入浅色页返回时闪白）
      backgroundColor: Tv.isTv ? TvHomePage.backgroundColor : Colors.white,
      body: Tv.isTv
          ? const TvHomePage()
          : FilesPage(
              onOpenProfile: () => _scaffoldKey.currentState?.openDrawer(),
              isHome: true,
            ),
      drawer: Drawer(
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.zero, // 直角，去掉默认圆角
        ),
        width: MediaQuery.of(context).size.width * 0.82,
        child: const ProfilePage(embedded: true),
      ),
    );
  }
}
