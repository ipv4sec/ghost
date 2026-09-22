import 'package:flutter_test/flutter_test.dart';

import 'package:ghost/models/models.dart';
import 'package:ghost/network/pkce.dart';

void main() {
  test('FileItem 从列表 JSON 解析', () {
    final f = FileItem.fromListJson({
      'fid': '123',
      'pid': '0',
      'fn': '电影.mkv',
      'fc': '1',
      'fs': 1024,
      'upt': 1715496600,
      'pc': 'abc',
      'ism': '1',
    });
    expect(f.isDir, false);
    expect(f.isVideo, true);
    expect(f.starred, true);
    expect(f.kind, FileKind.video);
    expect(f.size, 1024);
  });

  test('FileItem 文件夹判定', () {
    final d = FileItem.fromListJson({'fid': '9', 'fn': '资料', 'fc': '0'});
    expect(d.isDir, true);
    expect(d.kind, FileKind.folder);
  });

  test('formatBytes', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(1024), '1.0 KB');
    expect(formatBytes(1536), '1.5 KB');
    expect(formatBytes(1024 * 1024 * 1024), '1.0 GB');
  });

  test('formatDuration', () {
    expect(formatDuration(0), '00:00');
    expect(formatDuration(65), '01:05');
    expect(formatDuration(3671), '1:01:11');
  });

  test('PKCE challenge 为 url-safe base64 无填充', () {
    final digest = [
      159, 134, 208, 155, 19, 81, 6, 85, 174, 92, 62, 100, 239, 144, 129, 38,
      206, 9, 122, 44, 87, 222, 79, 214, 188, 199, 67, 33, 136, 203, 130, 205
    ];
    final c = Pkce.challengeFrom(digest);
    expect(c.endsWith('='), isFalse);
    expect(RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(c), isTrue);
  });
  test('parsePlayInfo 防御性解析：multitrack_list 为数组不崩溃', () {
    final info = parsePlayInfo({
      'state': true,
      'data': {
        'file_id': '1',
        'file_name': 'x.mkv',
        'user_def': 100,
        'multitrack_list': [],
        'definition_list': [],
        'video_url': [
          {'url': 'http://cdnfhnfile.115.com/a', 'definition': 100, 'title': '原画'},
          {'url': 'https://xx.115.com/720.m3u8', 'definition': 2, 'title': '高清'},
        ],
      },
    });
    expect(info.audioTracks, isEmpty);
    expect(info.definitions, isEmpty);
    expect(info.videoUrl.length, 2);
    expect(info.defaultItem.url, contains('.m3u8'));
  });

  test('parsePlayInfo data 为数组时返回空 PlayInfo 不崩溃', () {
    final info = parsePlayInfo({'state': false, 'data': []});
    expect(info.videoUrl, isEmpty);
  });
}
