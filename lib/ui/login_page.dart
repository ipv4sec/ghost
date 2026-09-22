import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../network/api_client.dart';
import '../session.dart';
import '../ui/theme.dart';

/// 扫码授权登录页
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final AuthFlow _flow = AuthFlow(client: Session.instance.client, session: Session.instance);

  QrPhase _phase = QrPhase.loading;
  String? _qrcode;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void dispose() {
    _flow.cancel();
    super.dispose();
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
      appBar: AppBar(title: const Text('登录')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    color: AppTheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.cloud_outlined,
                      color: Colors.white, size: 40),
                ),
                const SizedBox(height: 32),
                _qrCard(),
                const SizedBox(height: 24),
                _statusText(),
                const SizedBox(height: 24),
                if (_phase == QrPhase.expired || _phase == QrPhase.error)
                  FilledButton.icon(
                    onPressed: _restart,
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

  Widget _qrCard() {
    Widget body;
    if (_phase == QrPhase.loading) {
      body = const SizedBox(
        width: 200,
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (_qrcode != null &&
        (_phase == QrPhase.waitingScan || _phase == QrPhase.scanned)) {
      body = Stack(
        alignment: Alignment.center,
        children: [
          QrImageView(
            data: _qrcode!,
            size: 200,
            backgroundColor: Colors.white,
          ),
          if (_phase == QrPhase.scanned)
            Container(
              width: 200,
              height: 200,
              color: Colors.white.withOpacity(0.8),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle, color: AppTheme.primary, size: 48),
                  SizedBox(height: 8),
                  Text('扫码成功', style: TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
        ],
      );
    } else {
      body = SizedBox(
        width: 200,
        height: 200,
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.scaffold,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: body,
    );
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
    return Text(text, style: TextStyle(color: color, fontSize: 15));
  }
}
