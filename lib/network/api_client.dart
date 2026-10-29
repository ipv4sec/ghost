import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';

/// API 业务异常
class ApiException implements Exception {
  ApiException(this.code, this.message);

  final int code;
  final String message;

  /// token 失效需要刷新（40140125 / 40140126）
  bool get needRefresh =>
      code == 40140125 || code == 40140126;

  /// refresh_token 终态失效，必须重新授权
  /// 40140116/40140119/40140120/40140137
  bool get needReauth =>
      code == 40140116 ||
      code == 40140119 ||
      code == 40140120 ||
      code == 40140137;

  @override
  String toString() => 'ApiException($code): $message';
}

/// 轮询原始状态（client 层，session 层映射为 QrPhase）
enum QrPhaseRaw { scanned, success, expired }

/// 授权凭证
class TokenBundle {
  TokenBundle({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt, // 毫秒时间戳
  });

  final String accessToken;
  final String refreshToken;
  final int expiresAt;

  bool get expired => DateTime.now().millisecondsSinceEpoch >= expiresAt - 60000;

  Map<String, dynamic> toJson() => {
        'access_token': accessToken,
        'refresh_token': refreshToken,
        'expires_at': expiresAt,
      };

  factory TokenBundle.fromJson(Map<String, dynamic> j) => TokenBundle(
        accessToken: '${j['access_token'] ?? ''}',
        refreshToken: '${j['refresh_token'] ?? ''}',
        expiresAt: (j['expires_at'] as num?)?.toInt() ?? 0,
      );
}

/// 115 开放平台 API 客户端
///
/// 职责：
/// - 携带 Bearer token 请求业务接口
/// - 业务接口全局限速（串行 + 最小间隔 500ms，即每秒最多 2 次），
///   无论界面如何连点都不会突破该频率，避免触发平台频率控制（HTTP 405）
/// - 读接口（GET）2 秒结果缓存 + 在途去重：同一接口短时间重复触发
///   （如连点刷新）只发一次真实请求
/// - 写操作成功后失效读缓存，保证后续读取看到最新数据
/// - 405 限流自动退避重试一次
/// - 40140125/40140126 自动单飞刷新并重放请求
/// - refresh_token 终态失效时抛出 [ApiException.needReauth]
class Open115Client {
  Open115Client({
    http.Client? httpClient,
    TokenBundle? Function()? tokenLoader,
    Future<void> Function(TokenBundle)? tokenSaver,
    Future<void> Function()? onReauthRequired,
  })  : _http = httpClient ?? http.Client(),
        _loadToken = tokenLoader,
        _saveToken = tokenSaver,
        _onReauth = onReauthRequired;

  final http.Client _http;
  final TokenBundle? Function()? _loadToken;
  final Future<void> Function(TokenBundle)? _saveToken;
  final Future<void> Function()? _onReauth;

  /// 单飞刷新锁
  Future<TokenBundle?>? _refreshing;

  // ---------------- 授权流程（无需 token） ----------------

  /// 第一步：获取设备码与二维码内容
  Future<Map<String, dynamic>> authDeviceCode(
      String clientId, String codeChallenge) async {
    return _postForm(
      Uri.parse('${AppConfig.passportApi}/open/authDeviceCode'),
      {
        'client_id': clientId,
        'code_challenge': codeChallenge,
        'code_challenge_method': 'sha256',
      },
    );
  }

  /// 第三步：设备码 + code_verifier 换 token
  Future<TokenBundle> deviceCodeToToken(
      String uid, String codeVerifier) async {
    final j = await _postForm(
      Uri.parse('${AppConfig.passportApi}/open/deviceCodeToToken'),
      {'uid': uid, 'code_verifier': codeVerifier},
    );
    _ensureOk(j);
    return TokenBundle(
      accessToken: '${j['data']['access_token']}',
      refreshToken: '${j['data']['refresh_token']}',
      expiresAt: DateTime.now().millisecondsSinceEpoch +
          ((j['data']['expires_in'] as num?)?.toInt() ?? 7200) * 1000,
    );
  }

  /// 刷新 token（60 秒内勿重复调用，由单飞锁保证）
  Future<TokenBundle> refreshToken(String rt) async {
    final j = await _postForm(
      Uri.parse('${AppConfig.passportApi}/open/refreshToken'),
      {'refresh_token': rt},
    );
    _ensureOk(j);
    return TokenBundle(
      accessToken: '${j['data']['access_token']}',
      refreshToken: '${j['data']['refresh_token']}',
      expiresAt: DateTime.now().millisecondsSinceEpoch +
          ((j['data']['expires_in'] as num?)?.toInt() ?? 7200) * 1000,
    );
  }

  // ---------------- 业务接口（需 token） ----------------

  /// 获取文件列表
  Future<Map<String, dynamic>> listFiles({
    required String cid,
    int limit = 50,
    int offset = 0,
    String order = 'user_ptime',
    bool asc = false,
  }) async {
    final q = {
      'cid': cid,
      'limit': '$limit',
      'offset': '$offset',
      'o': order,
      'asc': asc ? '1' : '0',
      'custom_order': '2',
      'show_dir': '1',
      'cur': '1',
    };
    return _cachedGetJson(
      Uri.parse('${AppConfig.proApi}/open/ufile/files')
          .replace(queryParameters: q),
    );
  }

  /// 用户信息
  Future<Map<String, dynamic>> userInfo() =>
      _cachedGetJson(Uri.parse('${AppConfig.proApi}/open/user/info'));

  /// 文件/文件夹详情（按 ID）
  Future<Map<String, dynamic>> fileInfo(String fileId) => _cachedGetJson(
      Uri.parse('${AppConfig.proApi}/open/folder/get_info')
          .replace(queryParameters: {'file_id': fileId}));

  /// 新建文件夹
  Future<void> addFolder({required String pid, required String name}) async {
    await _postMultipart(
      Uri.parse('${AppConfig.proApi}/open/folder/add'),
      {'pid': pid, 'file_name': name},
    );
  }

  /// 视频播放信息
  Future<Map<String, dynamic>> videoPlay(String pickCode) => _cachedGetJson(
      Uri.parse('${AppConfig.proApi}/open/video/play')
          .replace(queryParameters: {'pick_code': pickCode}));

  /// 读取播放进度，返回秒（无记录 0）
  Future<int> videoHistory(String pickCode) async {
    try {
      final j = await _cachedGetJson(
        Uri.parse('${AppConfig.proApi}/open/video/history')
            .replace(queryParameters: {'pick_code': pickCode}),
      );
      final d = j['data'];
      if (d is Map) return (d['time'] as num?)?.toInt() ?? 0;
      return 0;
    } on ApiException {
      return 0; // 无记录视为 0
    }
  }

  /// 上报播放进度
  Future<void> reportVideoHistory(String pickCode, int sec,
      {bool watchEnd = false}) async {
    await _postMultipart(
      Uri.parse('${AppConfig.proApi}/open/video/history'),
      {
        'pick_code': pickCode,
        'time': '$sec',
        'watch_end': watchEnd ? '1' : '0',
      },
    );
  }

  // ---------------- 内部请求与刷新逻辑 ----------------

  /// proapi 全局串行队列：115 对所有 API 实施频率控制，
  /// 突发请求会被网关限流（表现为 HTTP 405），故所有业务请求
  /// 排队串行执行并保持最小间隔（500ms = 每秒最多 2 次）
  static const Duration _minInterval = Duration(milliseconds: 500);
  Future<void> _gate = Future.value();
  int _lastSentAt = 0;

  // ---------------- 读缓存（2 秒） ----------------

  /// GET 响应缓存有效期
  static const Duration _cacheTtl = Duration(seconds: 2);

  /// key = 请求 URL；value = 结果 Future（含在途请求）。
  /// 存 Future 而非结果：连点刷新时第一次请求尚未返回，后续触发
  /// 直接共享同一 Future，真正做到只发一次请求
  final Map<String, Future<Map<String, dynamic>>> _getCache = {};

  /// 带缓存的 GET：同一 URL 在有效期内（含在途）直接复用；
  /// 失败立即失效以便重试，成功保留 [_cacheTtl] 后清除。
  /// 写操作成功后会整体失效（见 [_postMultipart]）
  Future<Map<String, dynamic>> _cachedGetJson(Uri uri) {
    final key = '$uri';
    final hit = _getCache[key];
    if (hit != null) return hit;
    final fut = _getJson(uri);
    _getCache[key] = fut;
    void evict() {
      // 仅当条目仍是自己时才移除，避免误删后来放入的新请求
      if (identical(_getCache[key], fut)) _getCache.remove(key);
    }

    fut.then(
      (_) => Future.delayed(_cacheTtl, evict),
      onError: (_) => evict(), // 失败不缓存，允许立刻重试
    );
    return fut;
  }

  /// 排队并限速执行一次业务请求；405（限流）退避后原地重试一次
  Future<http.Response> _sendPro(Future<http.Response> Function() send) {
    return _enqueue(() async {
      final res = await send();
      if (res.statusCode != 405) return res;
      // 限流是瞬态的：冷却 1.5s 再试一次（冷却期间也压住队列后续请求）
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      return send();
    });
  }

  Future<T> _enqueue<T>(Future<T> Function() task) {
    final run = _gate.then((_) async {
      final wait = _lastSentAt +
          _minInterval.inMilliseconds -
          DateTime.now().millisecondsSinceEpoch;
      if (wait > 0) await Future<void>.delayed(Duration(milliseconds: wait));
      _lastSentAt = DateTime.now().millisecondsSinceEpoch;
      return task();
    });
    // 失败不断链：后续请求继续排队
    _gate = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  Future<Map<String, dynamic>> _getJson(Uri uri, {bool retried = false}) async {
    final token = await _ensureToken();
    final res = await _sendPro(() => _http.get(
          uri,
          headers: {
            'Authorization': 'Bearer ${token.accessToken}',
            'User-Agent': ua,
          },
        ));
    final j = _decode(res);
    if (_stateOk(j)) return j;
    final ex = _toException(j);
    if (ex.needRefresh && !retried) {
      await _refreshSingleton();
      return _getJson(uri, retried: true);
    }
    throw ex;
  }

  Future<Map<String, dynamic>> _postMultipart(Uri uri, Map<String, String> form,
      {bool retried = false}) async {
    final token = await _ensureToken();
    // 每次发送重建请求（MultipartRequest 消费后不可复用，重试需重建）
    Future<http.Response> send() async {
      final req = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer ${token.accessToken}'
        ..headers['User-Agent'] = ua;
      form.forEach((k, v) => req.fields[k] = v);
      return http.Response.fromStream(await _http.send(req));
    }

    final res = await _sendPro(send);
    final j = _decode(res);
    if (_stateOk(j)) {
      // 写操作改变了服务端状态：整体失效读缓存，保证随后的读取
      // （如新建文件夹后刷新列表）拿到最新数据
      _getCache.clear();
      return j;
    }
    final ex = _toException(j);
    if (ex.needRefresh && !retried) {
      await _refreshSingleton();
      return _postMultipart(uri, form, retried: true);
    }
    throw ex;
  }

  Future<Map<String, dynamic>> _postForm(
      Uri uri, Map<String, String> form) async {
    final res = await _http.post(
      uri,
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'User-Agent': ua,
      },
      body: form,
    );
    return _decode(res);
  }

  /// 取有效 token；过期则先刷新
  Future<TokenBundle> _ensureToken() async {
    final t = _loadToken?.call();
    if (t == null) {
      throw ApiException(-2, '未登录');
    }
    if (!t.expired) return t;
    return (await _refreshSingleton()) ?? t;
  }

  /// 单飞刷新：并发请求只触发一次网络刷新
  Future<TokenBundle?> _refreshSingleton() {
    return _refreshing ??= _doRefresh().whenComplete(() {
      // 保留结果 2 秒，避免 60 秒频率限制内被并发再次触发
      Future.delayed(const Duration(seconds: 2), () => _refreshing = null);
    });
  }

  Future<TokenBundle?> _doRefresh() async {
    final t = _loadToken?.call();
    if (t == null) return null;
    try {
      final nt = await refreshToken(t.refreshToken);
      await _saveToken?.call(nt);
      return nt;
    } on ApiException catch (e) {
      if (e.needReauth) {
        await _onReauth?.call();
        rethrow;
      }
      rethrow;
    }
  }

  // ---------------- 响应解析 ----------------

  /// 统一 UA：API 与视频流（m3u8/播放器）保持一致，
  /// 避免 WAF 因请求特征不一致而拦截
  static const String ua = 'Mozilla/5.0 (Linux; Android 14) ghost/0.1';

  /// 无鉴权原始 GET（扫码轮询用），带 35s 超时（服务端长轮询约 30s）
  Future<String> httpGetRaw(Uri uri) async {
    final res = await _http.get(uri).timeout(const Duration(seconds: 35));
    return utf8.decode(res.bodyBytes);
  }

  /// 第二步：长轮询二维码状态
  /// 返回 null = 继续轮询；expired = 二维码失效；scanned = 已扫码待确认；success = 已确认
  Future<QrPhaseRaw?> pollQrStatus({
    required String uid,
    required int time,
    required String sign,
  }) async {
    try {
      final raw = await httpGetRaw(
        Uri.parse('${AppConfig.qrcodeApi}/get/status/').replace(
          queryParameters: {
            'uid': uid,
            'time': '$time',
            'sign': sign,
          },
        ),
      );
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final state = (j['state'] as num?)?.toInt() ?? 0;
      if (state == 0) return QrPhaseRaw.expired;
      final d = j['data'];
      if (d is Map) {
        final status = (d['status'] as num?)?.toInt() ?? 0;
        if (status == 1) return QrPhaseRaw.scanned;
        if (status == 2) return QrPhaseRaw.success;
      }
      return null;
    } catch (_) {
      return null; // 长轮询超时 ≠ 失败，继续
    }
  }

  Map<String, dynamic> _decode(http.Response res) {
    if (res.statusCode != 200) {
      // 405 是平台限流的表现，给出可操作的提示
      final msg = res.statusCode == 405
          ? '操作太频繁，被 115 限流了，请稍候再试'
          : 'HTTP ${res.statusCode}';
      throw ApiException(res.statusCode, msg);
    }
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return decoded.cast<String, dynamic>();
      // 顶层不是对象（如数组）：包一层保留原始内容
      return {'state': false, 'code': -3, 'message': '响应格式异常'};
    } catch (_) {
      throw ApiException(-3, '响应解析失败');
    }
  }

  bool _stateOk(Map<String, dynamic> j) {
    final s = j['state'];
    if (s is bool) return s;
    if (s is num) return s == 1;
    return false;
  }

  ApiException _toException(Map<String, dynamic> j) => ApiException(
        (j['code'] as num?)?.toInt() ?? -1,
        '${j['message'] ?? '请求失败'}',
      );

  void _ensureOk(Map<String, dynamic> j) {
    if (!_stateOk(j)) throw _toException(j);
  }
}
