import 'package:flutter_test/flutter_test.dart';
import 'package:lavedevelop/core/logging/app_logger.dart';

/// 日志脱敏的回归用例。
///
/// 存在的理由：官方接入票据（access_token / clientSecret）一旦进入日志，
/// 就等于凭据泄露。调试环境的网络日志是最容易出问题的地方，因此脱敏必须是
/// 所有日志输出的必经之路，而不是「注意一下别打出来」。
void main() {
  group('AppLogger.redact', () {
    test('抹掉 Authorization 请求头的整个值（含 QQBot 前缀与 token）', () {
      final redacted = AppLogger.redact('Authorization: QQBot abc123def456');

      expect(redacted, contains('Authorization'));
      expect(redacted, contains('***'));
      expect(redacted, isNot(contains('abc123def456')));
      expect(redacted, isNot(contains('QQBot')));
    });

    test('Authorization 脱敏在遇到换行时停止，不吞掉后续内容', () {
      final redacted = AppLogger.redact(
        'Authorization: QQBot abc123\nbody={"content":"hi"}',
      );

      expect(redacted, isNot(contains('abc123')));
      expect(redacted, contains('"content":"hi"'));
    });

    test('抹掉 JSON 中引号包裹的 access_token 值但保留其他字段', () {
      final redacted = AppLogger.redact(
        '{"access_token":"secret-token-value","expires_in":"7200"}',
      );

      expect(redacted, isNot(contains('secret-token-value')));
      expect(redacted, contains('"access_token":"***"'));
      expect(redacted, contains('7200'));
    });

    test('抹掉 clientSecret / client_secret（取 token 请求体）', () {
      expect(
        AppLogger.redact('{"appId":"1020","clientSecret":"s3cr3t"}'),
        isNot(contains('s3cr3t')),
      );
      expect(
        AppLogger.redact('{"appId":"1020","client_secret":"s3cr3t"}'),
        isNot(contains('s3cr3t')),
      );
    });

    test('抹掉 appSecret / app_secret（本项目由用户输入并本地保存的密钥）', () {
      expect(
        AppLogger.redact('{"appSecret":"my-app-secret"}'),
        isNot(contains('my-app-secret')),
      );
      expect(
        AppLogger.redact('{"app_secret":"my-app-secret"}'),
        isNot(contains('my-app-secret')),
      );
    });

    test('抹掉未加引号的键值形式（如 query string）', () {
      final redacted = AppLogger.redact('token=abc123');

      expect(redacted, contains('token='));
      expect(redacted, isNot(contains('abc123')));
    });

    test('抹掉 Identify 报文里的 token（WSS 帧日志场景）', () {
      final redacted = AppLogger.redact(
        'Op2 Identify d={"token":"abc123","intents":33554432}',
      );

      expect(redacted, isNot(contains('abc123')));
      expect(redacted, contains('33554432'));
    });

    test('普通文本原样返回，不误伤内容', () {
      expect(AppLogger.redact('已保存到本地'), '已保存到本地');
      expect(
        AppLogger.redact('{"content":"你好世界"}'),
        '{"content":"你好世界"}',
      );
    });

    test('自然语言中出现的「token / secret」字样不会被误判为键', () {
      const text = '本次 token 已刷新，secret 无需处理';

      expect(AppLogger.redact(text), text);
    });

    test('密码类字段同样脱敏', () {
      expect(
        AppLogger.redact('{"password":"p@ssw0rd"}'),
        isNot(contains('p@ssw0rd')),
      );
    });
  });
}
