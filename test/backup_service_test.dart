import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:ghost/util/backup_service.dart';

/// 备份文件纯函数测试（encode/decode/toPrefsEntries 不碰 channel/文件系统）
void main() {
  final token = {
    'access_token': 'at-123',
    'refresh_token': 'rt-456',
    'expires_at': 1797000000000,
  };

  group('encode/decode round-trip', () {
    test('正常往返', () {
      final raw = jsonEncode(BackupService.encode(
        savedAt: 1796000000000,
        token: token,
        prefs: {
          'ghost.blocklist': ['广告', 'test'],
          'ghost.sort': 'user_ptime|0',
          'ghost.scheme': 'Mandy red',
          'ghost.font': 'app',
          'ghost.grid': false,
        },
      ));
      final d = BackupService.decode(raw);
      expect(d, isNotNull);
      expect(d!.token['access_token'], 'at-123');
      expect(d.token['refresh_token'], 'rt-456');
      expect(d.savedAt, 1796000000000);
      expect(d.prefs['ghost.sort'], 'user_ptime|0');
      expect(d.prefs['ghost.grid'], false);
      expect(d.prefs['ghost.blocklist'], ['广告', 'test']);
    });

    test('prefs 为空也能往返（只有 token）', () {
      final raw = jsonEncode(BackupService.encode(
        savedAt: 1,
        token: token,
        prefs: const {},
      ));
      final d = BackupService.decode(raw);
      expect(d, isNotNull);
      expect(d!.prefs, isEmpty);
    });
  });

  group('decode 容错', () {
    test('损坏 JSON → null', () {
      expect(BackupService.decode('not json {{{'), isNull);
    });

    test('version 不识别 → null', () {
      final j = BackupService.encode(savedAt: 1, token: token, prefs: const {});
      j['version'] = 99;
      expect(BackupService.decode(jsonEncode(j)), isNull);
    });

    test('缺 token → null', () {
      expect(
          BackupService.decode(jsonEncode({'version': 1, 'prefs': {}})), isNull);
    });

    test('access/refresh token 为空 → null', () {
      expect(
        BackupService.decode(jsonEncode(BackupService.encode(
            savedAt: 1,
            token: {'access_token': '', 'refresh_token': 'rt'},
            prefs: const {}))),
        isNull,
      );
      expect(
        BackupService.decode(jsonEncode(BackupService.encode(
            savedAt: 1,
            token: {'access_token': 'at', 'refresh_token': ''},
            prefs: const {}))),
        isNull,
      );
    });

    test('白名单外的键被丢弃', () {
      final j = BackupService.encode(savedAt: 1, token: token, prefs: const {});
      (j['prefs'] as Map)['ghost.evil'] = 'x';
      (j['prefs'] as Map)['ghost.sort'] = 'file_name|1';
      final d = BackupService.decode(jsonEncode(j));
      expect(d, isNotNull);
      expect(d!.prefs.containsKey('ghost.evil'), isFalse);
      expect(d.prefs['ghost.sort'], 'file_name|1');
    });
  });

  group('encode 白名单过滤', () {
    test('非白名单键不写入文件', () {
      final j = BackupService.encode(
        savedAt: 1,
        token: token,
        prefs: {'ghost.evil': 'x', 'ghost.font': 'app', 'other': 1},
      );
      expect((j['prefs'] as Map).keys, ['ghost.font']);
    });

    test('null 值键跳过', () {
      final j = BackupService.encode(
        savedAt: 1,
        token: token,
        prefs: {'ghost.font': null, 'ghost.grid': true},
      );
      expect((j['prefs'] as Map).keys, ['ghost.grid']);
    });
  });

  group('toPrefsEntries', () {
    test('token 重新编码为 JSON 字符串，设置按类型回写', () {
      final raw = jsonEncode(BackupService.encode(
        savedAt: 1,
        token: token,
        prefs: {
          'ghost.blocklist': ['a'],
          'ghost.grid': true,
          'ghost.sort': 'file_name|1',
        },
      ));
      final entries = BackupService.toPrefsEntries(BackupService.decode(raw)!);
      expect(entries[BackupService.kTokenKey], isA<String>());
      expect(jsonDecode(entries[BackupService.kTokenKey] as String), token);
      expect(entries['ghost.blocklist'], ['a']);
      expect(entries['ghost.grid'], true);
      expect(entries['ghost.sort'], 'file_name|1');
    });
  });
}
