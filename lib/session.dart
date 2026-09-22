import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../network/api_client.dart';
import '../network/pkce.dart';

/// 全局会话状态：token / AppID 持久化 + 授权失效通知
class Session extends ChangeNotifier {
  Session._();

  static final Session instance = Session._();

  static const _kToken = 'ghost.token';
  static const _kAppId = 'ghost.app_id';

  SharedPreferences? _prefs;
  Open115Client? _clientImpl;

  Open115Client get client => _clientImpl!;

  TokenBundle? _token;
  bool _ready = false;

  TokenBundle? get token => _token;
  bool get loggedIn => _token != null;
  bool get ready => _ready;

  /// 当前生效 AppID：本地覆盖优先（设置页可改），未设置时用内置
  String get appId {
    final local = _prefs?.getString(_kAppId) ?? '';
    return local.isNotEmpty ? local : AppConfig.appId;
  }

  /// 用户本地覆盖的 AppID
  String get userAppId => _prefs?.getString(_kAppId) ?? '';

  Future<void> init() async {
    if (_ready) return;
    _prefs = await SharedPreferences.getInstance();
    _clientImpl = Open115Client(
      tokenLoader: () => _token,
      tokenSaver: (t) async {
        await _prefs!.setString(_kToken, jsonEncode(t.toJson()));
        _token = t;
        notifyListeners();
      },
      onReauthRequired: () => forceLogout(),
    );
    final raw = _prefs!.getString(_kToken);
    if (raw != null && raw.isNotEmpty) {
      try {
        _token = TokenBundle.fromJson(jsonDecode(raw));
      } catch (_) {
        await _prefs!.remove(_kToken);
      }
    }
    _ready = true;
    notifyListeners();
  }

  /// 设置本地 AppID（清空 = 移除覆盖）
  Future<void> setUserAppId(String v) async {
    await _prefs!.setString(_kAppId, v.trim());
    notifyListeners();
  }

  Future<void> saveToken(TokenBundle t) async {
    await _prefs!.setString(_kToken, jsonEncode(t.toJson()));
    _token = t;
    notifyListeners();
  }

  /// 清 token 回登录页（授权失效 / 退出登录）
  Future<void> forceLogout() async {
    await _prefs?.remove(_kToken);
    _token = null;
    notifyListeners();
  }
}

/// 扫码授权流程状态机（登录页用）
enum QrPhase { loading, waitingScan, scanned, success, expired, error }

class AuthFlow {
  AuthFlow({required this.client, required this.session});

  final Open115Client client;
  final Session session;

  String? _uid;
  int? _time;
  String? _sign;
  String? _verifier;
  bool _cancelled = false;

  /// 生成 code_challenge
  String _challenge(String verifier) =>
      Pkce.challengeFrom(sha256.convert(utf8.encode(verifier)).bytes);

  /// 开启一轮授权：取设备码 + 二维码内容
  Future<({String qrcode, QrPhase phase})> start() async {
    _cancelled = false;
    _verifier = Pkce.generateVerifier();
    final appId = session.appId;
    if (appId.isEmpty) {
      throw ApiException(-1, '未配置 AppID，请到"我的 → AppID 设置"填写');
    }
    final j = await client.authDeviceCode(appId, _challenge(_verifier!));
    final d = j['data'] is Map
        ? (j['data'] as Map).cast<String, dynamic>()
        : null;
    final ok = j['state'] is bool ? j['state'] as bool : j['state'] == 1;
    if (!ok || d == null) {
      throw ApiException(
          (j['code'] as num?)?.toInt() ?? -1, '${j['message'] ?? '获取二维码失败'}');
    }
    _uid = '${d['uid']}';
    _time = (d['time'] as num?)?.toInt() ?? 0;
    _sign = '${d['sign']}';
    return (qrcode: '${d['qrcode']}', phase: QrPhase.waitingScan);
  }

  /// 单次长轮询；超时/无变化返回 null（调用方应继续轮询）
  Future<QrPhase?> pollOnce() async {
    if (_uid == null) return null;
    final raw = await client.pollQrStatus(
      uid: _uid!,
      time: _time ?? 0,
      sign: _sign ?? '',
    );
    if (raw == null) return null;
    switch (raw) {
      case QrPhaseRaw.expired:
        return QrPhase.expired;
      case QrPhaseRaw.scanned:
        return QrPhase.scanned;
      case QrPhaseRaw.success:
        await complete();
        return QrPhase.success;
    }
  }

  /// 授权成功后换 token 并保存
  Future<void> complete() async {
    if (_uid == null || _verifier == null) {
      throw ApiException(-1, '授权流程状态丢失');
    }
    final t = await client.deviceCodeToToken(_uid!, _verifier!);
    await session.saveToken(t);
  }

  void cancel() {
    _cancelled = true;
  }

  bool get cancelled => _cancelled;
}
