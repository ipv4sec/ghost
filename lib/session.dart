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
  static const _kBlocklist = 'ghost.blocklist';
  static const _kSort = 'ghost.sort';

  /// 合法排序字段（设置页排序区块与持久化解析共用）
  static const sortFields = {'file_name', 'file_size', 'user_ptime', 'user_utime'};

  SharedPreferences? _prefs;
  Open115Client? _clientImpl;

  Open115Client get client => _clientImpl!;

  TokenBundle? _token;
  bool _ready = false;

  /// 屏蔽词（展示形式，保留输入大小写）；另存小写副本供匹配
  List<String> _blocklist = const [];
  List<String> _blockLower = const [];

  /// 文件列表排序（原文件页顶栏三个点菜单迁至设置页）：
  /// 全局生效并持久化，文件页监听变化即时重拉
  String _orderField = 'user_ptime';
  bool _orderAsc = false;

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
    _applyBlocklist(_prefs!.getStringList(_kBlocklist) ?? const []);
    _applySort(_prefs!.getString(_kSort));
    _ready = true;
    notifyListeners();
  }

  /// 设置本地 AppID（清空 = 移除覆盖）
  Future<void> setUserAppId(String v) async {
    await _prefs!.setString(_kAppId, v.trim());
    notifyListeners();
  }

  /// 名字屏蔽词（名字包含任一词即不显示，大小写不敏感）
  List<String> get blocklist => List.unmodifiable(_blocklist);

  /// 名字是否命中屏蔽词（包含匹配，大小写不敏感）
  bool isNameBlocked(String name) => nameBlocked(name, _blockLower);

  /// 设置屏蔽词（规范化：trim、去空、忽略大小写去重）
  Future<void> setBlocklist(List<String> words) async {
    _applyBlocklist(words);
    await _prefs!.setStringList(_kBlocklist, _blocklist);
    notifyListeners();
  }

  void _applyBlocklist(List<String> words) {
    _blocklist = _normalize(words);
    _blockLower = [for (final w in _blocklist) w.toLowerCase()];
  }

  static List<String> _normalize(Iterable<String> raw) {
    final seen = <String>{};
    return [
      for (final w in raw)
        if (w.trim().isNotEmpty && seen.add(w.trim().toLowerCase())) w.trim(),
    ];
  }

  /// 解析设置页输入：按换行与逗号（中英文）切分，去空白/空项，忽略大小写去重
  static List<String> parseBlocklistInput(String raw) =>
      _normalize(raw.split(RegExp(r'[\r\n,，]')));

  /// 纯匹配函数（[lowerWords] 须为小写；空列表永不命中）。
  /// w.isNotEmpty 双重防护：空字符串 contains('') 恒真，会屏蔽一切
  static bool nameBlocked(String name, List<String> lowerWords) {
    if (lowerWords.isEmpty) return false;
    final n = name.toLowerCase();
    return lowerWords.any((w) => w.isNotEmpty && n.contains(w));
  }

  String get orderField => _orderField;
  bool get orderAsc => _orderAsc;

  /// 排序快照键（字段|方向），文件页据此判断排序是否变化
  String get sortKey => '$_orderField|$_orderAsc';

  /// 设置列表排序（文件页监听通知即时重拉）
  Future<void> setSort(String field, bool asc) async {
    if (!sortFields.contains(field)) return;
    _orderField = field;
    _orderAsc = asc;
    await _prefs!.setString(_kSort, '$field|${asc ? '1' : '0'}');
    notifyListeners();
  }

  void _applySort(String? raw) {
    // '字段|0/1'；字段非法回默认（按上传时间降序）
    final parts = (raw ?? '').split('|');
    if (parts.length == 2 && sortFields.contains(parts[0])) {
      _orderField = parts[0];
      _orderAsc = parts[1] == '1';
    }
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
