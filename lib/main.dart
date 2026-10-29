import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'magnet_channel.dart';
import 'session.dart';
import 'ui/home_shell.dart';
import 'ui/login_page.dart';
import 'ui/theme.dart';
import 'ui/tv.dart';
import 'ui/tv_cards.dart' show kTvScale;
import 'ui/tv_home_page.dart';
import 'util/backup_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 电视判定先于一切：首帧就是电视版文字缩放（备份恢复的授权 UI 也读 Tv.isTv）
  await Tv.init();
  // 备份静默恢复必须先于 ThemeManager.load 与 Session.init：恢复直接写
  // SharedPreferences（进程内单例），下游全部读到恢复值，无需二次触发
  await BackupService.instance.restoreOnStartup();
  // 先恢复上次选择的主题再 runApp，避免首帧闪默认主题
  await ThemeManager.instance.load();
  // 退后台/被杀前把防抖中的备份立即落盘，压缩 refresh_token 陈旧窗口
  WidgetsBinding.instance.addObserver(_BackupFlushObserver());
  runApp(const GhostApp());
}

/// App 进入后台时 flush 待写备份（paused 后进程随时可能被杀）
class _BackupFlushObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused &&
        BackupService.instance.hasPendingSave) {
      unawaited(BackupService.instance.saveNow());
    }
  }
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
        builder: (context, child) {
          // 电视：文字整体放大（3 米观看距离），布局不变
          if (Tv.isTv && child != null) {
            // 路由转场容器底色跟随深色页面底：默认白底（浅色主题）在
            // 页面切换瞬间会闪白（用户反馈进文件夹闪白屏）；转场动画
            // 换成黑底淡入淡出（系统默认动画中间帧露浅色路由底，用户
            // 反馈进文件夹/打开文件有"白色空白感"）
            return Theme(
              data: Theme.of(context).copyWith(
                scaffoldBackgroundColor: TvHomePage.backgroundColor,
                pageTransitionsTheme: const PageTransitionsTheme(
                  builders: {
                    TargetPlatform.android: _DarkFadeTransitionsBuilder(),
                  },
                ),
              ),
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(Tv.textScale),
                ),
                child: child,
              ),
            );
          }
          return child ?? const SizedBox.shrink();
        },
        theme: AppTheme.light(),
        home: KeyedSubtree(
          key: ValueKey('theme-${AppTheme.current.name}'),
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

  /// 启动页最少停留时长：Session 就绪过快时启动页（图标+文字+点点点）
  /// 会一闪而过，用户只看到 Android 静态屏（无文字无动画），感知上"启动
  /// 提示没生效"——补足到可感知的时长
  static const _minSplash = Duration(milliseconds: 1200);
  bool _splashDone = false;

  /// 「loading」后的动态点：1→2→3→1 循环，每 300ms 一步
  int _dots = 1;
  Timer? _dotsTimer;

  @override
  void initState() {
    super.initState();
    if (!_inited) {
      _inited = true;
      Session.instance.init();
      MagnetInbox.instance.init(); // 冷启动带入的磁力链接
    }
    // 首帧渲染后才起算最少停留：引擎初始化慢时（debug 包冷启动首帧可晚
    // 于 initState 数秒），initState 起算会让计时在首帧前就走完，启动页
    // 从未显示就直接进首页（实测复现过）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(_minSplash, () {
        if (mounted) setState(() => _splashDone = true);
      });
    });
    _dotsTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      if (mounted) setState(() => _dots = _dots % 3 + 1);
    });
  }

  @override
  void dispose() {
    _dotsTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Session.instance,
      builder: (context, _) {
        final s = Session.instance;
        if (!s.ready || !_splashDone) {
          // 电视：深底 + 图标 + 「loading…」点点点（Android 静态启动屏同
          // 深色同图标，衔接无断裂；文字/动画由本页接棒）；手机端保持
          // 浅底（浅色主题），同样加图标与文案
          final dark = Tv.isTv;
          final bg = dark ? TvHomePage.backgroundColor : AppTheme.scaffold;
          final fg = dark ? Colors.white : Colors.black87;
          // 文字与首页文件夹名同款（15 号 w500，用户要求）
          final textStyle = TextStyle(
            color: fg,
            fontSize: 15 * kTvScale,
            fontWeight: FontWeight.w500,
          );
          return Scaffold(
            backgroundColor: bg,
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 与桌面/系统启动动画里的图标观感一致（96 偏大，用户反馈）
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child:
                        Image.asset('assets/icon.png', width: 64, height: 64),
                  ),
                  const SizedBox(height: 20),
                  // 垂直结构与静态启动窗口逐像素对齐（组合图 192x204@2x，
                  // 密度 2.0）：图标64 + 间距20 + 文字行18 → 图标中心在屏心
                  // 上方19、文字中心在下方42，两页一致，过渡时位置零跳动。
                  // 文字用 Stack 恒定居中，点点点绝对定位在右缘外（2~20），
                  // 不占居中宽度——点数变化时 loading 位置不动，静态屏同款
                  SizedBox(
                    height: 18,
                    child: Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        Text('loading', style: textStyle),
                        Positioned(
                          right: -20,
                          child: SizedBox(
                            width: 18,
                            child: Text(
                              '.' * _dots,
                              style: textStyle,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return s.loggedIn ? const HomeShell() : const LoginPage();
      },
    );
  }
}

/// 电视端路由转场：整页黑底淡入淡出。系统默认转场（Material 2 的
/// FadeUpwards）动画中间帧会露出浅色路由底，深色页面间切换时感知为
/// "白色空白感"（进文件夹/打开文件时）；整页（含黑底）随动画渐显，
/// 全程深色，无白帧。pop 时旧页渐隐透出下层深色页面，同理无白
class _DarkFadeTransitionsBuilder extends PageTransitionsBuilder {
  const _DarkFadeTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
      PageRoute<T> route,
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      Widget child) {
    return FadeTransition(
      opacity: animation,
      child: ColoredBox(color: Colors.black, child: child),
    );
  }
}
