import 'package:flutter_test/flutter_test.dart';

import 'package:ghost/session.dart';

void main() {
  group('nameBlocked', () {
    test('大小写不敏感的包含匹配', () {
      expect(Session.nameBlocked('My Movies', ['movie']), isTrue);
      expect(Session.nameBlocked('MY.MOVIE.mkv', ['movie']), isTrue);
    });

    test('不包含则不命中', () {
      expect(Session.nameBlocked('照片合集', ['movie']), isFalse);
    });

    test('中文子串匹配', () {
      expect(Session.nameBlocked('我的电影合集', ['电影']), isTrue);
      expect(Session.nameBlocked('电影.mp4', ['电影']), isTrue);
    });

    test('空屏蔽词列表永不命中', () {
      expect(Session.nameBlocked('任何名字', []), isFalse);
    });

    test('空字符串词防护（contains(\'\') 恒真，不能屏蔽一切）', () {
      expect(Session.nameBlocked('任何名字', ['']), isFalse);
    });
  });
}
