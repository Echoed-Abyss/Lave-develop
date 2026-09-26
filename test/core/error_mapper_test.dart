import 'package:flutter_test/flutter_test.dart';
import 'package:lavedevelop/core/error/app_error.dart';
import 'package:lavedevelop/core/error/error_mapper.dart';
import 'package:lavedevelop/core/error/qq_error_codes.dart';

/// 错误码映射的回归用例。
///
/// 依据：`docs/qq-bot/knowledge-base.html` 第 10 章（HTTP 状态码 / 公共错误码 /
/// WebSocket 错误码）与架构文档第 8 章异常处理矩阵。
/// 每个官方码都必须落到一个明确的语义类别，并决定「是否值得自动重试」。
void main() {
  group('ErrorMapper.fromHttp —— 鉴权与凭证', () {
    test('HTTP 401 认证失败 → AuthError，不可重试且需要用户处理', () {
      final error = ErrorMapper.fromHttp(statusCode: 401);

      expect(error, isA<AuthError>());
      expect(error.retryable, isFalse);
      expect(error.needsUserAction, isTrue);
    });

    test('官方 token 校验失败码 11242 / 11243 → AuthError', () {
      expect(ErrorMapper.fromHttp(errCode: 11242), isA<AuthError>());
      expect(ErrorMapper.fromHttp(errCode: 11243), isA<AuthError>());
    });

    test('取 token 接口失败时 HTTP 仍为 200，必须依据 body 的 code 判定', () {
      final error = ErrorMapper.fromHttp(statusCode: 200, errCode: 100016);

      expect(error, isA<AuthError>());
      expect(error.officialCode, 100016);
    });

    test('appid / secret 类错误码全部归为凭证问题', () {
      for (final code in <int>[11241, 11251, 11261, 11275, 100007, 10004]) {
        expect(
          ErrorMapper.fromHttp(errCode: code),
          isA<AuthError>(),
          reason: '$code 应判定为凭证问题',
        );
      }
    });
  });

  group('ErrorMapper.fromHttp —— 频率限制', () {
    test('HTTP 429 → RateLimitedError，可重试', () {
      final error = ErrorMapper.fromHttp(statusCode: 429);

      expect(error, isA<RateLimitedError>());
      expect(error.retryable, isTrue);
    });

    test('官方超频码 22009 / 40034100 / 50002 / 20028 / 1100100', () {
      for (final code in <int>[22009, 40034100, 50002, 20028, 1100100]) {
        expect(
          ErrorMapper.fromHttp(errCode: code),
          isA<RateLimitedError>(),
          reason: '$code 应判定为限流',
        );
      }
    });
  });

  group('ErrorMapper.fromHttp —— 被动回复窗口与主动消息', () {
    test('40034128 被动回复时间或次数超限 → ReplyWindowExpiredError', () {
      final error = ErrorMapper.fromHttp(errCode: 40034128);

      expect(error, isA<ReplyWindowExpiredError>());
      expect(error.retryable, isFalse);
    });

    test('304103 / 40034005 / 40034026 消息或事件已过期 → ReplyWindowExpiredError', () {
      for (final code in <int>[304103, 40034005, 40034026]) {
        expect(ErrorMapper.fromHttp(errCode: code), isA<ReplyWindowExpiredError>());
      }
    });

    test('40034105 / 40034122 / 40034123 主动消息与召回被拒 → ActiveMessageDeniedError', () {
      for (final code in <int>[40034105, 40034122, 40034123]) {
        expect(
          ErrorMapper.fromHttp(errCode: code),
          isA<ActiveMessageDeniedError>(),
          reason: '$code 应判定为主动消息被拒',
        );
      }
    });
  });

  group('ErrorMapper.fromHttp —— 去重与请求合法性', () {
    test('40054005 消息被去重 → DuplicateMessageError，重试无用（应递增 msg_seq）', () {
      final error = ErrorMapper.fromHttp(errCode: 40054005);

      expect(error, isA<DuplicateMessageError>());
      expect(error.retryable, isFalse);
    });

    test('22006 消息类型与内容不匹配 → InvalidRequestError', () {
      final error = ErrorMapper.fromHttp(errCode: 22006);

      expect(error, isA<InvalidRequestError>());
      expect(error.retryable, isFalse);
    });

    test('官方其它请求合法性错误码', () {
      for (final code in <int>[304061, 340069, 40034029, 40034008, 40034011]) {
        expect(
          ErrorMapper.fromHttp(errCode: code),
          isA<InvalidRequestError>(),
          reason: '$code 应判定为请求参数非法',
        );
      }
    });
  });

  group('ErrorMapper.fromHttp —— 内容与 URL', () {
    test('40034006 / 1100101 内容违规 → ContentRejectedError，不可重试', () {
      for (final code in <int>[40034006, 1100101]) {
        final error = ErrorMapper.fromHttp(errCode: code);

        expect(error, isA<ContentRejectedError>());
        expect(error.retryable, isFalse);
      }
    });

    test('304003 / 40054010 URL 未报备 → UrlNotRegisteredError，不可重试', () {
      for (final code in <int>[304003, 40054010]) {
        final error = ErrorMapper.fromHttp(errCode: code);

        expect(error, isA<UrlNotRegisteredError>());
        expect(error.retryable, isFalse);
      }
    });
  });

  group('ErrorMapper.fromHttp —— 富媒体', () {
    test('可重试的转存类失败 → MediaTransferError', () {
      for (final code in <int>[40034004, 304082, 304083, 850026, 850027, 40093001, 304080]) {
        final error = ErrorMapper.fromHttp(errCode: code);

        expect(error, isA<MediaTransferError>(), reason: '$code 官方建议重试');
        expect(error.retryable, isTrue);
      }
    });

    test('不合规类失败 → MediaRejectedError，不可重试', () {
      for (final code in <int>[850019, 850031, 40093002]) {
        final error = ErrorMapper.fromHttp(errCode: code);

        expect(error, isA<MediaRejectedError>(), reason: '$code 属于不合规');
        expect(error.retryable, isFalse);
      }
    });
  });

  group('ErrorMapper.fromHttp —— 禁言 / 群成员 / 下线 / 封禁', () {
    test('40054002 / 850018 禁言 → MutedError', () {
      expect(ErrorMapper.fromHttp(errCode: 40054002), isA<MutedError>());
      expect(ErrorMapper.fromHttp(errCode: 850018), isA<MutedError>());
    });

    test('40034101 / 40054003 非群成员 → NotInGroupError', () {
      expect(ErrorMapper.fromHttp(errCode: 40034101), isA<NotInGroupError>());
      expect(ErrorMapper.fromHttp(errCode: 40054003), isA<NotInGroupError>());
    });

    test('40054016 机器人已下线 → BotOfflineError', () {
      final error = ErrorMapper.fromHttp(errCode: 40054016);

      expect(error, isA<BotOfflineError>());
      expect(error.needsUserAction, isTrue);
    });

    test('11265 机器人被封禁 → BotBannedError，属于终态', () {
      final error = ErrorMapper.fromHttp(errCode: 11265);

      expect(error, isA<BotBannedError>());
      expect(error.retryable, isFalse);
      expect(error.isTerminalForBot, isTrue);
    });

    test('11253 / 11254 接口未授权或接口被封 → PermissionDeniedError，不是凭证问题', () {
      for (final code in <int>[11253, 11254]) {
        final error = ErrorMapper.fromHttp(errCode: code);

        expect(
          error,
          isA<PermissionDeniedError>(),
          reason: '官方把「接口权限」与「机器人封禁」列为不同的码，不能混为一类',
        );
        expect(error.retryable, isFalse);
        expect(error.needsUserAction, isTrue);
        // 关键：不能被误判为凭证问题，否则会引导用户去重填本来就正确的密钥。
        expect(error.isCredentialIssue, isFalse);
      }
    });
  });

  group('ErrorMapper.fromHttp —— 网络与服务端瞬时故障', () {
    test('statusCode 为 null 表示请求未到达服务端 → NetworkError，可重试', () {
      final error = ErrorMapper.fromHttp(cause: Exception('dns'));

      expect(error, isA<NetworkError>());
      expect(error.retryable, isTrue);
    });

    test('HTTP 500 / 504 → TransientServerError，可重试', () {
      expect(ErrorMapper.fromHttp(statusCode: 500), isA<TransientServerError>());
      expect(ErrorMapper.fromHttp(statusCode: 504), isA<TransientServerError>());
    });
  });

  group('ErrorMapper.fromHttp —— 未知码必须保留原始信息', () {
    test('未收录的错误码落到 UnknownApiError 且保留官方码与文案', () {
      final error = ErrorMapper.fromHttp(
        statusCode: 400,
        errCode: 999999,
        message: '自定义错误文案',
        traceId: 'trace-abc',
      );

      expect(error, isA<UnknownApiError>());
      expect(error.officialCode, 999999);
      expect(error.officialMessage, '自定义错误文案');
      expect(error.traceId, 'trace-abc');
    });

    test('traceId 会被带到具体类别上，便于排查', () {
      final error = ErrorMapper.fromHttp(errCode: 40034128, traceId: 't-1');

      expect(error.traceId, 't-1');
    });
  });

  group('ErrorMapper.fromWsClose —— WSS 关闭码', () {
    test('4006 / 4007 会话失效 → SessionInvalidError，可自动恢复', () {
      for (final code in <int>[4006, 4007]) {
        final error = ErrorMapper.fromWsClose(code);

        expect(error, isA<SessionInvalidError>());
        expect(error.retryable, isTrue);
      }
    });

    test('4008 / 4009 可重试 Resume → TransientServerError', () {
      for (final code in <int>[4008, 4009]) {
        final error = ErrorMapper.fromWsClose(code);

        expect(error, isA<TransientServerError>());
        expect(error.retryable, isTrue);
      }
    });

    test('4900~4913 内部错误 → TransientServerError，可重连', () {
      for (final code in <int>[4900, 4901, 4913]) {
        expect(ErrorMapper.fromWsClose(code), isA<TransientServerError>());
      }
    });

    test('4001 / 4002 / 4010~4014 协议与权限错误 → ProtocolRejectedError，不可重试', () {
      for (final code in <int>[4001, 4002, 4010, 4011, 4012, 4013, 4014]) {
        final error = ErrorMapper.fromWsClose(code);

        expect(error, isA<ProtocolRejectedError>(), reason: '$code 两个都不可重试');
        expect(error.retryable, isFalse);
      }
    });

    test('4014 的提示必须指向事件订阅权限（官方：intent 无权限）', () {
      final error = ErrorMapper.fromWsClose(4014);

      expect(error.userMessage, contains('权限'));
    });

    test('4915 机器人已封禁 → BotBannedError，终态', () {
      final error = ErrorMapper.fromWsClose(4915);

      expect(error, isA<BotBannedError>());
      expect(error.retryable, isFalse);
      expect(error.isTerminalForBot, isTrue);
    });

    test('4914 机器人已下架 → BotOfflineError', () {
      final error = ErrorMapper.fromWsClose(4914);

      expect(error, isA<BotOfflineError>());
      expect(error.needsUserAction, isTrue);
    });

    test('未收录的关闭码（含标准码 1000）按网络断开处理，可重试', () {
      final error = ErrorMapper.fromWsClose(1000, reason: 'going away');

      expect(error, isA<TransientServerError>());
      expect(error.retryable, isTrue);
      expect(error.officialCode, 1000);
    });

    test('官方表中不存在的 4003 / 4004 / 4005 也按网络类处理', () {
      for (final code in <int>[4003, 4004, 4005]) {
        expect(ErrorMapper.fromWsClose(code), isA<TransientServerError>());
      }
    });
  });

  group('错误分类集合自身的一致性', () {
    test('限流码与凭证码不重叠，避免分类歧义', () {
      expect(
        QqErrorCodes.authCodes.intersection(QqErrorCodes.rateLimitCodes),
        isEmpty,
      );
    });

    test('媒体「可重试」与「不合规」两个集合不重叠', () {
      expect(
        QqErrorCodes.mediaTransferCodes
            .intersection(QqErrorCodes.mediaRejectedCodes),
        isEmpty,
      );
    });

    test('封禁码集合只含「机器人被封禁」，与接口权限码互不混淆', () {
      expect(QqErrorCodes.bannedCodes, contains(11265));
      expect(QqErrorCodes.bannedCodes, isNot(contains(11254)));
      expect(QqErrorCodes.permissionDeniedCodes, contains(11254));
      expect(QqErrorCodes.permissionDeniedCodes, contains(11253));
    });

    test('凭证码与接口权限码不重叠（两者的用户处理动作不同）', () {
      expect(
        QqErrorCodes.authCodes.intersection(QqErrorCodes.permissionDeniedCodes),
        isEmpty,
      );
    });
  });
}
