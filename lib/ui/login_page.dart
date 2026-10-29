import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../network/api_client.dart';
import '../session.dart';
import '../ui/theme.dart';
import '../util/backup_service.dart';
import 'tv.dart';

/// 扫码授权登录页
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with WidgetsBindingObserver {
  final AuthFlow _flow = AuthFlow(client: Session.instance.client, session: Session.instance);

  QrPhase _phase = QrPhase.loading;
  String? _qrcode;
  String _error = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restart();
    _maybePromptRestore();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flow.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从「所有文件访问」设置页返回时重查权限，已授予则恢复备份
    if (state == AppLifecycleState.resumed) _tryLateRestore();
  }

  /// API 30+ 一次性晚授权提示（kPrompted 每 install 一次）：授予
  /// 「所有文件访问」后可自动恢复卸载前的登录与设置。API<=29 不提示
  /// （启动时已弹过一次系统权限框，被拒的登录后走设置页「去授权」）
  Future<void> _maybePromptRestore() async {
    final b = BackupService.instance;
    final perm = await b.permissionStatus();
    if (perm.mode != BackupPermMode.manage || perm.granted) return;
    final p = await SharedPreferences.getInstance();
    if (p.getBool(BackupService.kPrompted) ?? false) return;
    await p.setBool(BackupService.kPrompted, true);
    if (!mounted) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复登录'),
        content: const Text('曾备份过登录凭证？授予「所有文件访问」权限后，'
            '可自动恢复登录与本地设置，免扫码。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('以后再说'),
          ),
          FilledButton(
            autofocus: Tv.isTv,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('去授权'),
          ),
        ],
      ),
    );
    if (go == true) await b.openAllFilesAccessSettings();
  }

  /// 授权返回后：已授予且本地无 token → 恢复备份并 live-apply，
  /// _Bootstrap 监听 Session 通知自动切主页（免重启应用）
  Future<void> _tryLateRestore() async {
    if (Session.instance.loggedIn) return;
    final b = BackupService.instance;
    if (!(await b.permissionStatus()).granted) return;
    if (!await b.restoreIntoPrefs()) return;
    await ThemeManager.instance.reload();
    await Session.instance.reloadFromPrefs();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('已从备份恢复登录')));
  }

  Future<void> _restart() async {
    setState(() {
      _phase = QrPhase.loading;
      _error = '';
    });
    try {
      final r = await _flow.start();
      if (!mounted) return;
      setState(() {
        _qrcode = r.qrcode;
        _phase = r.phase;
      });
      _pollLoop();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = QrPhase.error;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _phase = QrPhase.error;
        _error = '网络异常';
      });
    }
  }

  Future<void> _pollLoop() async {
    while (mounted && !_flow.cancelled) {
      final phase = await _flow.pollOnce();
      if (!mounted || _flow.cancelled) return;
      if (phase == null) continue; // 长轮询超时，继续
      setState(() => _phase = phase);
      if (phase == QrPhase.success) {
        try {
          await _flow.complete();
          if (mounted) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(const SnackBar(content: Text('授权成功')));
          }
          return;
        } on ApiException catch (e) {
          setState(() {
            _phase = QrPhase.error;
            _error = e.message;
          });
          return;
        }
      }
      if (phase == QrPhase.expired) return; // 停止，等用户点刷新
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _qrView(),
                const SizedBox(height: 24),
                _statusText(),
                const SizedBox(height: 24),
                if (_phase == QrPhase.expired || _phase == QrPhase.error)
                  FilledButton.icon(
                    onPressed: _restart,
                    // 电视：重试按钮出现即聚焦，遥控器 OK 直接重试
                    autofocus: Tv.isTv,
                    icon: const Icon(Icons.refresh),
                    label: Text(
                      _phase == QrPhase.error ? '重试' : '刷新二维码',
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _qrView() {
    // 二维码统一 200（与手机端同尺寸），不再电视端放大
    const qrSize = 200.0;
    Widget body;
    if (_phase == QrPhase.loading) {
      body = const SizedBox(
        width: qrSize,
        height: qrSize,
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (_qrcode != null &&
        (_phase == QrPhase.waitingScan || _phase == QrPhase.scanned)) {
      body = Stack(
        alignment: Alignment.center,
        children: [
          QrImageView(
            data: _qrcode!,
            size: qrSize,
            backgroundColor: Colors.white,
          ),
          if (_phase == QrPhase.scanned)
            Container(
              width: qrSize,
              height: qrSize,
              color: Colors.white.withValues(alpha: 0.8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle, color: AppTheme.primary, size: 48),
                  const SizedBox(height: 8),
                  const Text('扫码成功',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
        ],
      );
    } else {
      body = SizedBox(
        width: qrSize,
        height: qrSize,
        child: Center(
          child: Icon(
            _phase == QrPhase.success ? Icons.check_circle : Icons.qr_code_2,
            size: 64,
            color: _phase == QrPhase.success
                ? AppTheme.primary
                : AppTheme.textSecondary,
          ),
        ),
      );
    }
    // 二维码直接裸显示，不再套卡片容器（边框/圆角/阴影）
    return body;
  }

  Widget _statusText() {
    final (text, color) = switch (_phase) {
      QrPhase.loading => ('正在获取二维码…', AppTheme.textSecondary),
      QrPhase.waitingScan => ('请使用 115 App 扫码授权', AppTheme.textPrimary),
      QrPhase.scanned => ('请在手机上确认授权', AppTheme.primary),
      QrPhase.success => ('授权成功，正在进入…', AppTheme.primary),
      QrPhase.expired => ('二维码已失效', AppTheme.textSecondary),
      QrPhase.error => (_error.isEmpty ? '出错了' : _error, AppTheme.textSecondary),
    };
    return Text(text, style: TextStyle(color: color, fontSize: 16));
  }
}
