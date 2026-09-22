import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:ghost/network/api_client.dart';

/// 记录每次请求发出时刻的假 http.Client，统一返回成功 JSON
class _RecordingClient extends http.BaseClient {
  final sentAt = <DateTime>[];
  final requested = <Uri>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sentAt.add(DateTime.now());
    requested.add(request.url);
    final body = utf8.encode(jsonEncode({
      'state': true,
      'code': 0,
      'data': {'count': 0, 'folder_count': 0},
    }));
    return http.StreamedResponse(Stream.value(body), 200);
  }
}

Open115Client _client(_RecordingClient fake) => Open115Client(
      httpClient: fake,
      tokenLoader: () => TokenBundle(
        accessToken: 't',
        refreshToken: 'r',
        // 一小时后才过期，避免测试中触发刷新
        expiresAt:
            DateTime.now().millisecondsSinceEpoch + 60 * 60 * 1000,
      ),
    );

void main() {
  test('同一接口 2 秒内串行重复调用：只发一次真实请求', () async {
    final fake = _RecordingClient();
    final c = _client(fake);
    await c.userInfo();
    await c.userInfo();
    expect(fake.sentAt.length, 1);
  });

  test('同一接口并发触发（模拟连点刷新）：在途去重，只发一次请求', () async {
    final fake = _RecordingClient();
    final c = _client(fake);
    await Future.wait([
      c.userInfo(),
      c.userInfo(),
      c.userInfo(),
      c.userInfo(),
    ]);
    expect(fake.sentAt.length, 1);
  });

  test('缓存过期后（>2s）再次调用会发起新请求', () async {
    final fake = _RecordingClient();
    final c = _client(fake);
    await c.userInfo();
    await Future<void>.delayed(const Duration(milliseconds: 2100));
    await c.userInfo();
    expect(fake.sentAt.length, 2);
  });

  test('写操作成功后读缓存失效', () async {
    final fake = _RecordingClient();
    final c = _client(fake);
    int infoCalls() => fake.requested
        .where((u) => u.path.endsWith('/open/user/info'))
        .length;
    await c.userInfo(); // 进缓存
    expect(infoCalls(), 1);
    await c.addFolder(pid: '0', name: '新建'); // 写操作
    await c.userInfo(); // 应重新请求
    expect(infoCalls(), 2);
  });

  test('不同接口并发：请求间隔不小于 500ms（每秒最多 2 次）', () async {
    final fake = _RecordingClient();
    final c = _client(fake);
    await Future.wait([
      c.userInfo(),
      c.fileInfo('1'),
      c.videoPlay('p1'),
      c.videoPlay('p2'), // 与 p1 不同 URL，不吃同一缓存
    ]);
    expect(fake.sentAt.length, 4);
    for (var i = 1; i < fake.sentAt.length; i++) {
      final gap = fake.sentAt[i].difference(fake.sentAt[i - 1]);
      // 留 10ms 余量吸收毫秒取整误差
      expect(gap.inMilliseconds >= 490, isTrue,
          reason: '第 $i 个请求间隔仅 ${gap.inMilliseconds}ms');
    }
  });
}
