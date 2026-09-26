import 'package:flutter_test/flutter_test.dart';
import 'package:lavedevelop/core/utils/qq_json.dart';

/// JSON 安全取值的回归用例。
///
/// 依据：官方接口存在若干类型不稳定的字段，例如 `expires_in` 文档标为 number
/// 但示例是字符串 `"7200"`；可选字段可能缺失或为显式 null。
/// 见 `docs/qq-bot/knowledge-base.html` 2.2 / 5.1 节。
void main() {
  group('QqJson.str', () {
    test('字符串原样返回（不做 trim，正文空格有意义）', () {
      expect(QqJson.str('  /今日天气 '), '  /今日天气 ');
    });

    test('空字符串返回空字符串而不是 null（官方 union_openid 可能为 ""）', () {
      expect(QqJson.str(''), '');
    });

    test('其他类型返回 null，不做隐式转换', () {
      expect(QqJson.str(123), isNull);
      expect(QqJson.str(true), isNull);
      expect(QqJson.str(null), isNull);
      expect(QqJson.str(const <String, dynamic>{}), isNull);
    });
  });

  group('QqJson.integer', () {
    test('整数原样返回', () {
      expect(QqJson.integer(7200), 7200);
    });

    test('数字字符串可解析（官方 expires_in 示例为 "7200"）', () {
      expect(QqJson.integer('7200'), 7200);
    });

    test('double 截断为整数', () {
      expect(QqJson.integer(7200.9), 7200);
      expect(QqJson.integer(-1.5), -1);
    });

    test('非数字内容返回 null', () {
      expect(QqJson.integer('abc'), isNull);
      expect(QqJson.integer(''), isNull);
      expect(QqJson.integer(null), isNull);
      expect(QqJson.integer(const <int>[]), isNull);
    });
  });

  group('QqJson.boolean', () {
    test('布尔值原样返回', () {
      expect(QqJson.boolean(true), isTrue);
      expect(QqJson.boolean(false), isFalse);
    });

    test('字符串 true / false 可解析', () {
      expect(QqJson.boolean('true'), isTrue);
      expect(QqJson.boolean('false'), isFalse);
    });

    test('数字 1 / 0 可解析', () {
      expect(QqJson.boolean(1), isTrue);
      expect(QqJson.boolean(0), isFalse);
    });

    test('无法识别的内容返回 null', () {
      expect(QqJson.boolean('yes'), isNull);
      expect(QqJson.boolean(2), isNull);
      expect(QqJson.boolean(null), isNull);
    });
  });

  group('QqJson.map', () {
    test('Map 返回同内容的 Map', () {
      final result = QqJson.map(<String, dynamic>{'source': 'default'});

      expect(result, isNotNull);
      expect(result!['source'], 'default');
    });

    test('非 Map 返回 null（数组、字符串、null 都不是对象）', () {
      expect(QqJson.map(const <int>[]), isNull);
      expect(QqJson.map('x'), isNull);
      expect(QqJson.map(null), isNull);
    });
  });

  group('QqJson.list', () {
    test('缺失的列表返回 null，以便区分「未携带」与「空列表」', () {
      expect(QqJson.list(null, _identity), isNull);
    });

    test('空列表返回空列表', () {
      final result = QqJson.list(const <Object>[], _identity);

      expect(result, isNotNull);
      expect(result, isEmpty);
    });

    test('跳过非对象元素，只映射合法项', () {
      final raw = <Object?>[
        <String, dynamic>{'v': 1},
        'not-a-map',
        null,
        <String, dynamic>{'v': 2},
      ];

      final result = QqJson.list(raw, _identity);

      expect(result, hasLength(2));
      expect(result!.map((e) => e['v']), <int>[1, 2]);
    });

    test('输入不是列表时返回 null', () {
      expect(QqJson.list('x', _identity), isNull);
      expect(QqJson.list(<String, dynamic>{}, _identity), isNull);
    });
  });
}

Map<String, dynamic> _identity(Map<String, dynamic> json) => json;
