import 'package:flutter_test/flutter_test.dart';
import 'package:lavedevelop/core/utils/qq_time.dart';

/// 时间解析的回归用例。
///
/// 依据：官方时间字段格式不统一——消息类事件用 RFC3339 字符串，
/// 状态类事件（FRIEND_ADD / GROUP_ADD_ROBOT / GROUP_MEMBER_ADD 等）用 Unix 秒整数。
/// 见 `docs/qq-bot/knowledge-base.html` 5.1 / 5.4 节。
void main() {
  group('QqTime.tryParse 同时接受 RFC3339 字符串与 Unix 秒', () {
    test('RFC3339 带东八区偏移（官方消息事件样例格式）', () {
      // 官方样例："timestamp": "2026-07-21T10:00:00+08:00"
      final parsed = QqTime.tryParse('2026-07-21T10:00:00+08:00');

      expect(parsed, isNotNull);
      // 东八区 10:00 等价于 UTC 02:00
      expect(parsed!.toUtc(), DateTime.utc(2026, 7, 21, 2, 0, 0));
    });

    test('RFC3339 带 Z 后缀', () {
      final parsed = QqTime.tryParse('2026-07-21T02:00:00Z');

      expect(parsed, isNotNull);
      expect(parsed!.toUtc(), DateTime.utc(2026, 7, 21, 2, 0, 0));
    });

    test('Unix 秒整数（官方状态类事件样例格式）', () {
      // 官方样例："timestamp": 1784570534
      final parsed = QqTime.tryParse(1784570534);

      expect(parsed, isNotNull);
      expect(
        parsed!.millisecondsSinceEpoch,
        DateTime.fromMillisecondsSinceEpoch(1784570534 * 1000)
            .millisecondsSinceEpoch,
      );
    });

    test('Unix 秒以 double 形式出现也能解析', () {
      final parsed = QqTime.tryParse(1784570534.0);

      expect(parsed, isNotNull);
      expect(
        parsed!.millisecondsSinceEpoch,
        DateTime.fromMillisecondsSinceEpoch(1784570534 * 1000)
            .millisecondsSinceEpoch,
      );
    });

    test('null 与缺失字段返回 null，而不是抛异常', () {
      expect(QqTime.tryParse(null), isNull);
    });

    test('无法识别的字符串返回 null，而不是抛异常', () {
      expect(QqTime.tryParse('garbage'), isNull);
      expect(QqTime.tryParse(''), isNull);
    });

    test('不把纯数字字符串当作 Unix 秒（官方标注该字段为 integer 类型）', () {
      // 有意不支持：Dart 的 DateTime.tryParse 会把 "1784570534" 静默解析成
      // 178457-06-03（实测行为），因此必须用格式守门拦掉，否则会变成
      // 一个公元 18 万年的日期且不报任何错。
      expect(QqTime.tryParse('1784570534'), isNull);
    });

    test('不接收不带分隔符的紧凑日期写法', () {
      // 官方一律使用带分隔符的 RFC3339，紧凑写法来源不明，拒绝。
      expect(QqTime.tryParse('20260721'), isNull);
    });

    test('不支持的输入类型返回 null', () {
      expect(QqTime.tryParse(const <String, dynamic>{}), isNull);
      expect(QqTime.tryParse(const <int>[]), isNull);
    });
  });

  group('QqTime.toRfc3339', () {
    test('输出 UTC ISO8601，带毫秒与 Z 后缀（合法 RFC3339）', () {
      expect(
        QqTime.toRfc3339(DateTime.utc(2026, 7, 21, 2, 0, 0)),
        '2026-07-21T02:00:00.000Z',
      );
    });

    test('本地时间会先转成 UTC 再输出', () {
      final local = DateTime.utc(2026, 7, 21, 2, 0, 0).toLocal();

      expect(QqTime.toRfc3339(local), '2026-07-21T02:00:00.000Z');
    });
  });
}
