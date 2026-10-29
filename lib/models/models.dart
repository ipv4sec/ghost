import 'dart:math';

/// 文件类型分类（对应列表接口 type 枚举）
enum FileKind { folder, doc, image, audio, video, archive, app, book, other }

/// 通用文件项（文件列表用）
class FileItem {
  FileItem({
    required this.fid,
    required this.pid,
    required this.name,
    required this.isDir,
    this.size = 0,
    this.mtime,
    this.ext = '',
    this.pickCode = '',
    this.thumbUrl,
    this.starred = false,
    this.encrypted = false,
    this.sha1 = '',
    this.playLong = 0,
  });

  final String fid;
  final String pid;
  final String name;
  final bool isDir;
  final int size;
  final DateTime? mtime;
  final String ext; // 后缀，小写
  final String pickCode;
  final String? thumbUrl;
  final bool starred;
  final bool encrypted;
  final String sha1;
  final int playLong; // 秒

  FileKind get kind {
    if (isDir) return FileKind.folder;
    switch (ext) {
      case 'txt':
      case 'doc':
      case 'docx':
      case 'pdf':
      case 'ppt':
      case 'pptx':
      case 'xls':
      case 'xlsx':
      case 'md':
        return FileKind.doc;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
      case 'bmp':
      case 'heic':
        return FileKind.image;
      case 'mp3':
      case 'flac':
      case 'ape':
      case 'wav':
      case 'aac':
      case 'm4a':
        return FileKind.audio;
      case 'mp4':
      case 'mkv':
      case 'avi':
      case 'mov':
      case 'wmv':
      case 'flv':
      case 'webm':
      case 'ts':
      case 'm2ts':
        return FileKind.video;
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
      case 'gz':
        return FileKind.archive;
      case 'apk':
        return FileKind.app;
      case 'epub':
      case 'mobi':
        return FileKind.book;
      default:
        return FileKind.other;
    }
  }

  bool get isVideo => kind == FileKind.video;

  /// 从列表接口 data[] 构建
  factory FileItem.fromListJson(Map<String, dynamic> j) {
    return FileItem(
      fid: '${j['fid'] ?? ''}',
      pid: '${j['pid'] ?? ''}',
      name: '${j['fn'] ?? ''}',
      isDir: '${j['fc'] ?? '1'}' == '0',
      size: _toInt(j['fs']),
      mtime: _toDate(j['upt']),
      ext: _extOf('${j['fn'] ?? ''}'),
      pickCode: '${j['pc'] ?? ''}',
      thumbUrl: _thumb(j['v_img'] ?? j['thumb'] ?? j['fco']),
      starred: '${j['ism'] ?? '0'}' == '1',
      encrypted: '${j['isp'] ?? 0}' == '1',
      sha1: '${j['sha1'] ?? ''}',
      playLong: _toInt(j['play_long']),
    );
  }

  /// 缩略图地址：视频 v_img / 图片 thumb / 文件夹封面 fco；
  /// 空串与非字符串值按无缩略图处理
  static String? _thumb(dynamic v) => v is String && v.isNotEmpty ? v : null;

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  static DateTime? _toDate(dynamic v) {
    final sec = _toInt(v);
    if (sec <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(sec * 1000);
  }

  static String _extOf(String name) {
    final i = name.lastIndexOf('.');
    if (i <= 0 || i == name.length - 1) return '';
    return name.substring(i + 1).toLowerCase();
  }
}

/// 格式化字节数
String formatBytes(int bytes) {
  if (bytes < 0) return '';
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB', 'PB'];
  var v = bytes.toDouble();
  var u = -1;
  do {
    v /= 1024;
    u++;
  } while (v >= 1024 && u < units.length - 1);
  final s = v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  return '$s ${units[u]}';
}

/// 格式化时长（秒 → mm:ss / h:mm:ss）
String formatDuration(int sec) {
  if (sec <= 0) return '00:00';
  final h = sec ~/ 3600;
  final m = (sec % 3600) ~/ 60;
  final s = sec % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

/// 用户信息（我的页）
class UserInfo {
  UserInfo({
    required this.userId,
    required this.name,
    required this.avatar,
    required this.usedBytes,
    required this.totalBytes,
    required this.usedText,
    required this.totalText,
    required this.vipName,
    required this.vipExpire,
    required this.tpRights,
  });

  final int userId;
  final String name;
  final String avatar;
  final int usedBytes;
  final int totalBytes;
  final String usedText;
  final String totalText;
  final String vipName;
  final int vipExpire; // 时间戳，0 无 VIP
  final bool tpRights; // 第三方畅用权益

  factory UserInfo.fromJson(Map<String, dynamic> j) {
    // 以下字段防御性解析：服务端空值可能返回 [] 或 null 而非 {}
    Map<String, dynamic> asMap(dynamic v) =>
        v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};

    final d = asMap(j['data']);
    final space = asMap(d['rt_space_info']);
    int sizeOf(String key) {
      final m = asMap(space[key]);
      return (m['size'] as num?)?.toInt() ?? 0;
    }

    String textOf(String key) {
      final m = asMap(space[key]);
      return '${m['size_format'] ?? ''}';
    }

    final vip = asMap(d['vip_info']);
    final rights = asMap(vip['tp_rights']);
    return UserInfo(
      userId: (d['user_id'] as num?)?.toInt() ?? 0,
      name: '${d['user_name'] ?? ''}',
      avatar: '${d['user_face_m'] ?? d['user_face_s'] ?? ''}',
      usedBytes: sizeOf('all_use'),
      totalBytes: sizeOf('all_total'),
      usedText: textOf('all_use'),
      totalText: textOf('all_total'),
      vipName: '${vip['level_name'] ?? ''}',
      vipExpire: (vip['expire'] as num?)?.toInt() ?? 0,
      tpRights: '${rights['is_tp_rights'] ?? 0}' == '1',
    );
  }

  double get usagePercent {
    if (totalBytes <= 0) return 0;
    return min(1.0, usedBytes / totalBytes);
  }
}

/// 视频播放信息
class PlayInfo {
  PlayInfo({
    required this.fileId,
    required this.fileName,
    required this.videoUrl,
    required this.definitions,
    required this.audioTracks,
    required this.userDef,
  });

  final String fileId;
  final String fileName;
  final List<PlayUrlItem> videoUrl; // 各清晰度地址
  final Map<int, String> definitions; // 清晰度值 → 名称
  final Map<String, String> audioTracks; // 音轨键 → 标题
  final int userDef; // 记忆清晰度

  /// 默认选择：m3u8 转码档优先（兼容性好），原画直链仅作备选
  PlayUrlItem get defaultItem {
    if (videoUrl.isEmpty) {
      throw StateError('no play url');
    }
    // 记忆清晰度且是 m3u8 → 直接用
    for (final u in videoUrl) {
      if (u.definition == userDef && u.url.toLowerCase().contains('m3u8')) return u;
    }
    // 任意 m3u8 转码档
    for (final u in videoUrl) {
      if (u.url.toLowerCase().contains('m3u8')) return u;
    }
    return videoUrl.first;
  }
}

class PlayUrlItem {
  PlayUrlItem({
    required this.url,
    required this.definition,
    required this.title,
    required this.width,
    required this.height,
  });

  final String url;
  final int definition;
  final String title;
  final int width;
  final int height;

  factory PlayUrlItem.fromJson(Map<String, dynamic> j) => PlayUrlItem(
        url: '${j['url'] ?? ''}',
        definition: (j['definition'] as num?)?.toInt() ?? 0,
        title: '${j['title'] ?? ''}',
        width: (j['width'] as num?)?.toInt() ?? 0,
        height: (j['height'] as num?)?.toInt() ?? 0,
      );
}

PlayInfo parsePlayInfo(Map<String, dynamic> j) {
  // data 防御：无数据/数组时回退空 Map
  final dynamic rawData = j['data'];
  final d = rawData is Map ? rawData.cast<String, dynamic>() : <String, dynamic>{};

  // video_url 防御：可能为 null/Map/字段缺失
  final dynamic rawUrls = d['video_url'];
  final urls = (rawUrls is List ? rawUrls : const [])
      .map((e) => e is Map
          ? PlayUrlItem.fromJson(e.cast<String, dynamic>())
          : null)
      .whereType<PlayUrlItem>()
      .where((e) => e.url.isNotEmpty)
      .toList()
    ..sort((a, b) => b.definition.compareTo(a.definition));

  // definition_list 文档写 object，实际空时可能返回数组 [] —— 两种都兼容
  final defs = <int, String>{};
  final rawDefs = d['definition_list'];
  if (rawDefs is Map) {
    rawDefs.forEach((k, v) {
      final n = int.tryParse('$k');
      if (n != null) defs[n] = '$v';
    });
  }

  // multitrack_list 同理：空音轨时实际返回 [] 而非 {}
  final tracks = <String, String>{};
  final rawTracks = d['multitrack_list'];
  if (rawTracks is Map) {
    rawTracks.forEach((k, v) {
      if (v is Map) tracks['$k'] = '${v['title'] ?? k}';
    });
  }

  return PlayInfo(
    fileId: '${d['file_id'] ?? ''}',
    fileName: '${d['file_name'] ?? ''}',
    videoUrl: urls,
    definitions: defs,
    audioTracks: tracks,
    userDef: (d['user_def'] as num?)?.toInt() ?? 0,
  );
}
