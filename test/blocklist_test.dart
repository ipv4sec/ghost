import 'package:flutter_test/flutter_test.dart';

import 'package:ghost/session.dart';

void main() {
  group('parseBlocklistInput', () {
    test('按换行切分', () {
      expect(Session.parseBlocklistInput('a\nb'), ['a', 'b']);
    });

    test('中英文逗号与换行混用、多余空白与空行剔除', () {
      expect(Session.parseBlocklistInput('a，b, c ,\n\n d '), ['a', 'b', 'c', 'd']);
    });

    test('忽略大小写去重，保留首次出现的大小写', () {
      expect(Session.parseBlocklistInput('A\na\nB'), ['A', 'B']);
    });

    test('空输入与纯空白输入', () {
      expect(Session.parseBlocklistInput(''), []);
      expect(Session.parseBlocklistInput('  \n \n'), []);
    });

    test('词内空格保留（不按空格切分）', () {
      expect(Session.parseBlocklistInput('my file\nanother'), ['my file', 'another']);
    });

    test('Windows 换行 \\r\\n', () {
      expect(Session.parseBlocklistInput('a\r\nb'), ['a', 'b']);
    });
  });

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
