import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 授权模式：runtime = API<=29 普通运行时权限弹窗；manage = API 30+ 「所有文件访问」设置页
enum BackupPermMode { runtime, manage }

class BackupPerm {
  const BackupPerm(this.mode, this.granted, this.sdk);

  final BackupPermMode mode;
  final bool granted;
  final int sdk;
}

/// 设置页状态行数据
class BackupStatus {
  const BackupStatus({
    required this.path,
    required this.exists,
    required this.lastSavedAt,
    required this.perm,
    required this.lastError,
  });

  final String path;
  final bool exists;
  final int? lastSavedAt;
  final BackupPerm perm;
  final String? lastError;
}

/// 备份文件解析结果（[decode] 的返回值）
class BackupData {
  const BackupData(this.token, this.prefs, this.savedAt);

  /// token 对象（access_token/refresh_token/expires_at），回写 prefs 时 jsonEncode
  final Map<String, dynamic> token;

  /// 白名单内的设置键值
  final Map<String, Object?> prefs;

  final int? savedAt;
}

/// 凭证与本地设置的「卸载不丢」备份服务：
/// 明文 JSON 写到外部存储根目录隐藏文件（<外部存储根>/.ghost.json），
/// 该位置不随应用卸载清除；重装后启动时静默恢复到 SharedPreferences。
///
/// 设计约束：
/// - 115 refresh_token 是轮换制（每次刷新换新），所以每次 token 写入
///   （登录 saveToken / 刷新 tokenSaver）都必须 scheduleSave 同步重写备份，
///   否则恢复出来的 refresh_token 已作废；
/// - 未登录不写文件（退出登录 forceLogout 会 clear，防止作废凭证被误恢复）；
/// - 所有公开方法吞异常（debugPrint + lastError），绝不影响登录/播放主流程；
/// - 非 Android 平台全部短路（host 单测零副作用）。
///
/// 权限经 MethodChannel 'ghost/backup'（MainActivity.kt 原生实现，零新依赖）：
/// API 24-29 用 READ/WRITE_EXTERNAL_STORAGE（manifest requestLegacyExternalStorage）；
/// API 30+ 用 MANAGE_EXTERNAL_STORAGE（设置页授权）。
class BackupService extends ChangeNotifier {
  BackupService._();

  static final BackupService instance = BackupService._();

  static const _ch = MethodChannel('ghost/backup');
  static const _fileName = '.ghost.json';
  static const _fallbackRoot = '/storage/emulated/0';

  /// 与 Session._kToken 保持一致（session.dart 的 token prefs 键）
  static const kTokenKey = 'ghost.token';

  /// 设置备份白名单（token 单独存对象；ghost.backup.* 辅助键不入文件）
  static const settingKeys = [
    'ghost.blocklist',
    'ghost.sort',
    'ghost.scheme',
    'ghost.font',
    'ghost.grid',
  ];

  /// 最近一次成功备份时间（ms，设置页展示用，不入备份文件）
  static const kLastAt = 'ghost.backup.last';

  /// API<=29 启动时权限弹窗是否已请求过（每 install 至多弹一次，不打扰）
  static const kAsked = 'ghost.backup.asked';

  /// API 30+ 登录页晚授权提示是否已弹过（每 install 一次）
  static const kPrompted = 'ghost.backup.prompted';

  /// 备份文件格式版本（decode 不认识的版本直接忽略，前向兼容）
  static const fileVersion = 1;

  Timer? _debounce;

  /// 写串行化链：save/clear 不交错
  Future<void> _tail = Future.value();
  String? _dirCache;
  String? lastError;

  /// 是否有防抖中的待写备份（main 的生命周期 observer 在 paused 时据此立即落盘）
  bool get hasPendingSave => _debounce?.isActive ?? false;

  // ---------- 纯函数（可单测，不碰 channel/文件） ----------

  /// 组装备份文件 payload（白名单过滤，token 必须非空对象）
  static Map<String, dynamic> encode({
    required int savedAt,
    required Map<String, dynamic> token,
    required Map<String, Object?> prefs,
  }) {
    return {
      'version': fileVersion,
      'saved_at': savedAt,
      'token': token,
      'prefs': {
        for (final k in settingKeys)
          if (prefs[k] != null) k: prefs[k],
      },
    };
  }

  /// 解析并校验备份文件内容：版本不识别 / 结构非法 / token 缺失 → null（忽略该文件）
  static BackupData? decode(String raw) {
    try {
      final j = jsonDecode(raw);
      if (j is! Map || j['version'] != fileVersion) return null;
      final token = j['token'];
      if (token is! Map) return null;
      final tokenMap = token.cast<String, dynamic>();
      if ('${tokenMap['access_token'] ?? ''}'.isEmpty ||
          '${tokenMap['refresh_token'] ?? ''}'.isEmpty) {
        return null;
      }
      final prefsRaw = j['prefs'];
      final prefs = <String, Object?>{};
      if (prefsRaw is Map) {
        final m = prefsRaw.cast<String, dynamic>();
        for (final k in settingKeys) {
          if (m.containsKey(k)) prefs[k] = m[k];
        }
      }
      return BackupData(tokenMap, prefs, (j['saved_at'] as num?)?.toInt());
    } catch (_) {
      return null;
    }
  }

  /// 把解析结果回写 prefs 的键值对（严格白名单 + 类型规整，供 restore 与单测共用）
  static Map<String, Object> toPrefsEntries(BackupData data) {
    final entries = <String, Object>{kTokenKey: jsonEncode(data.token)};
    for (final e in data.prefs.entries) {
      final v = e.value;
      if (v is String) {
        entries[e.key] = v;
      } else if (v is bool) {
        entries[e.key] = v;
      } else if (v is int) {
        entries[e.key] = v;
      } else if (v is List) {
        entries[e.key] = v.map((e2) => '$e2').toList();
      }
      // 其他类型（不应出现）忽略
    }
    return entries;
  }

  // ---------- 路径与权限 ----------

  Future<String> _root() async {
    if (_dirCache != null) return _dirCache!;
    var root = _fallbackRoot;
    try {
      final v = await _ch.invokeMethod<String>('externalDir');
      if (v != null && v.isNotEmpty) root = v;
    } catch (_) {
      // 通道失败用常量兜底
    }
    return _dirCache = root;
  }

  Future<File?> _file() async =>
      Platform.isAndroid ? File('${await _root()}/$_fileName') : null;

  /// 权限现状（每次实时问原生；从设置页授权返回后应重查）
  Future<BackupPerm> permissionStatus() async {
    if (!Platform.isAndroid) {
      return const BackupPerm(BackupPermMode.manage, false, 0);
    }
    try {
      final m = (await _ch.invokeMethod<Map>('storageStatus'))!.cast<String, dynamic>();
      return BackupPerm(
        m['mode'] == 'manage' ? BackupPermMode.manage : BackupPermMode.runtime,
        m['granted'] == true,
        (m['sdk'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      // 通道失败按不可用处理
      return const BackupPerm(BackupPermMode.manage, false, 0);
    }
  }

  /// API<=29：弹系统运行时权限框；API 30+ 恒 false（须走设置页）
  Future<bool> requestRuntimePermission() async {
    try {
      return await _ch.invokeMethod<bool>('requestStorage') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// API 30+：跳「所有文件访问」设置页；返回是否成功打开（授予态需 resumed 后重查）
  Future<bool> openAllFilesAccessSettings() async {
    try {
      return await _ch.invokeMethod<bool>('openAllFilesAccess') ?? false;
    } catch (_) {
      return false;
    }
  }

  // ---------- 恢复 ----------

  /// 启动入口（main() 里 await，必须先于 ThemeManager.load / Session.init）：
  /// 本地无 token 且备份文件存在 → 直接写回 prefs，下游读到的就是恢复值。
  /// 唯一交互：API<=29 且从未请求过 → 一次系统权限弹窗（重装后权限被重置，
  /// 无法避免；每 install 至多一次，拒绝则记 kAsked 不再打扰）。
  /// API 30+ 未授权不弹窗，交给登录页一次性提示（login_page.dart）。
  Future<void> restoreOnStartup() async {
    if (!Platform.isAndroid) return;
    try {
      final p = await SharedPreferences.getInstance();
      if ((p.getString(kTokenKey) ?? '').isNotEmpty) return; // 已登录：零文件 IO
      var perm = await permissionStatus();
      if (!perm.granted &&
          perm.mode == BackupPermMode.runtime &&
          !(p.getBool(kAsked) ?? false)) {
        await p.setBool(kAsked, true);
        await requestRuntimePermission();
        perm = await permissionStatus();
      }
      if (!perm.granted) return;
      await restoreIntoPrefs();
    } catch (e) {
      debugPrint('备份恢复失败（忽略）: $e');
    }
  }

  /// 备份文件 → prefs（严格白名单回写）。返回是否恢复。永不抛。
  /// 运行中晚授权（登录页 API 30+ 路径）也走这里，随后调用方 live-apply。
  Future<bool> restoreIntoPrefs() async {
    if (!Platform.isAndroid) return false;
    try {
      final p = await SharedPreferences.getInstance();
      if ((p.getString(kTokenKey) ?? '').isNotEmpty) return false; // 本地已有，不覆盖
      if (!(await permissionStatus()).granted) return false;
      final f = await _file();
      if (f == null || !await f.exists()) return false;
      final data = decode(await f.readAsString());
      if (data == null) return false;
      for (final e in toPrefsEntries(data).entries) {
        final v = e.value;
        if (v is String) {
          await p.setString(e.key, v);
        } else if (v is bool) {
          await p.setBool(e.key, v);
        } else if (v is int) {
          await p.setInt(e.key, v);
        } else if (v is List<String>) {
          await p.setStringList(e.key, v);
        }
      }
      debugPrint('已从备份恢复登录凭证与设置: ${f.path}');
      return true;
    } catch (e) {
      debugPrint('备份文件读取失败（忽略）: $e');
      return false;
    }
  }

  // ---------- 保存 ----------

  /// 设置/token 变化 → 800ms 防抖重写（合并连改；token 刷新频率远低于此）
  void scheduleSave() {
    if (!Platform.isAndroid) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), () => unawaited(saveNow()));
  }

  /// 立即写（设置页「立即备份」/ paused flush）。失败返回 false（原因见 lastError），永不抛。
  Future<bool> saveNow() async {
    _debounce?.cancel();
    if (!Platform.isAndroid) return false;
    final r = _tail.then((_) => _saveImpl());
    _tail = r.then<void>((_) {}, onError: (_) {});
    return r;
  }

  Future<bool> _saveImpl() async {
    try {
      final p = await SharedPreferences.getInstance();
      final tokenRaw = p.getString(kTokenKey);
      if (tokenRaw == null || tokenRaw.isEmpty) {
        lastError = '未登录';
        return false;
      }
      if (!(await permissionStatus()).granted) {
        lastError = '未授予存储权限';
        notifyListeners();
        return false;
      }
      final f = await _file();
      if (f == null) return false;
      final token = jsonDecode(tokenRaw);
      if (token is! Map) {
        lastError = '本地 token 数据损坏';
        return false;
      }
      final savedAt = DateTime.now().millisecondsSinceEpoch;
      final payload = encode(
        savedAt: savedAt,
        token: token.cast<String, dynamic>(),
        prefs: {for (final k in settingKeys) k: p.get(k)},
      );
      await f.parent.create(recursive: true);
      // 原子写：同目录 tmp + rename，避免半截文件
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode(payload), flush: true);
      await tmp.rename(f.path);
      await p.setInt(kLastAt, savedAt);
      lastError = null;
      notifyListeners();
      return true;
    } catch (e) {
      lastError = '$e';
      debugPrint('备份写入失败（忽略）: $e');
      notifyListeners();
      return false;
    }
  }

  // ---------- 删除 ----------

  /// 删备份文件（forceLogout 用 unawaited 调，不阻塞退出）。永不抛。
  Future<void> clear() {
    _debounce?.cancel(); // 先取消防抖，避免残留 timer 重建文件
    final r = _tail.then((_) => _clearImpl());
    _tail = r.then<void>((_) {}, onError: (_) {});
    return r;
  }

  Future<void> _clearImpl() async {
    try {
      final f = await _file();
      if (f != null && await f.exists()) await f.delete();
      final p = await SharedPreferences.getInstance();
      await p.remove(kLastAt);
      lastError = null;
    } catch (e) {
      lastError = '$e';
      debugPrint('删除备份失败（忽略）: $e');
    }
    notifyListeners();
  }

  // ---------- 状态 ----------

  Future<BackupStatus> status() async {
    final f = await _file();
    final perm = await permissionStatus();
    int? last;
    var exists = false;
    try {
      final p = await SharedPreferences.getInstance();
      last = p.getInt(kLastAt);
      exists = f != null && await f.exists();
    } catch (_) {
      // 状态查询失败按无备份展示
    }
    return BackupStatus(
      path: f?.path ?? '-',
      exists: exists,
      lastSavedAt: last,
      perm: perm,
      lastError: lastError,
    );
  }
}
