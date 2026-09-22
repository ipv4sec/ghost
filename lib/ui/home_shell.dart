import 'package:flutter/material.dart';

import '../magnet_channel.dart';
import '../ui/files_page.dart';
import '../ui/magnet_page.dart';
import '../ui/profile_page.dart';

/// 主页壳：文件页全屏（Amaze 布局，无底部导航），
/// 汉堡按钮侧滑打开"我的"抽屉；授权失效时 Session 通知自动回登录页。
/// 另监听磁力链接信箱：系统点击 magnet: 链接时整页推入磁链落地页
/// [MagnetPage]（处理完返回主页，不再弹底部面板）。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _magnetPageOpen = false;

  @override
  void initState() {
    super.initState();
    MagnetInbox.instance.addListener(_onMagnet);
    // 登录后冷启动带入的磁链（HomeShell 构建时已就绪）
    WidgetsBinding.instance.addPostFrameCallback((_) => _onMagnet());
  }

  @override
  void dispose() {
    MagnetInbox.instance.removeListener(_onMagnet);
    super.dispose();
  }

  void _onMagnet() {
    final link = MagnetInbox.instance.pending;
    if (link == null || _magnetPageOpen || !mounted) return;
    _scaffoldKey.currentState?.closeDrawer();
    _magnetPageOpen = true;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => MagnetPage(link: link)))
        .whenComplete(() {
      _magnetPageOpen = false;
      // 页面关闭即视为已处理（提交成功/取消/失败重试由用户主动再来）
      if (MagnetInbox.instance.pending == link) {
        MagnetInbox.instance.consume();
      }
      // 落地页开着时又来了新链接：接着处理，不丢弃
      if (MagnetInbox.instance.pending != null) _onMagnet();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.white,
      body: FilesPage(
        onOpenProfile: () => _scaffoldKey.currentState?.openDrawer(),
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
