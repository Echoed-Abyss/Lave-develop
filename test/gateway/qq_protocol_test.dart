import 'package:flutter_test/flutter_test.dart';
import 'package:lavedevelop/core/constants/app_config.dart';
import 'package:lavedevelop/domain/models/qq_enums.dart';
import 'package:lavedevelop/gateway/protocol/qq_opcode.dart';

/// 协议枚举、intents 掩码与关闭码恢复动作的回归用例。
///
/// 依据：`docs/qq-bot/knowledge-base.html`
/// - OpCode 全集与「3/4/5/8 官方未定义」见 3.4 节；
/// - intents 位移表达式与权限规则见第 4 章；
/// - 关闭码与「是否可 RESUME / 是否可 IDENTIFY」两列见 10.1 节；
/// - 富媒体软硬限制见 7.4 节。
void main() {
  group('QqOpCode', () {
    test('官方定义的十个取值都能解析', () {
      expect(QqOpCode.fromValue(0), QqOpCode.dispatch);
      expect(QqOpCode.fromValue(1), QqOpCode.heartbeat);
      expect(QqOpCode.fromValue(2), QqOpCode.identify);
      expect(QqOpCode.fromValue(6), QqOpCode.resume);
      expect(QqOpCode.fromValue(7), QqOpCode.reconnect);
      expect(QqOpCode.fromValue(9), QqOpCode.invalidSession);
      expect(QqOpCode.fromValue(10), QqOpCode.hello);
      expect(QqOpCode.fromValue(11), QqOpCode.heartbeatAck);
      expect(QqOpCode.fromValue(12), QqOpCode.httpCallbackAck);
      expect(QqOpCode.fromValue(13), QqOpCode.callbackUrlVerify);
    });

    test('官方未定义的 3/4/5/8 返回 null，不能自行赋义', () {
      expect(QqOpCode.fromValue(3), isNull);
      expect(QqOpCode.fromValue(4), isNull);
      expect(QqOpCode.fromValue(5), isNull);
      expect(QqOpCode.fromValue(8), isNull);
    });

    test('null 与未知值返回 null', () {
      expect(QqOpCode.fromValue(null), isNull);
      expect(QqOpCode.fromValue(99), isNull);
    });

    test('12 / 13 属于 HTTP 回调模式，不属于 WebSocket 接入', () {
      expect(QqOpCode.httpCallbackAck.isWebSocketOp, isFalse);
      expect(QqOpCode.callbackUrlVerify.isWebSocketOp, isFalse);
      expect(QqOpCode.hello.isWebSocketOp, isTrue);
      expect(QqOpCode.dispatch.isWebSocketOp, isTrue);
    });
  });

  group('QqWsCloseInfo.resolve —— 官方错误码表的恢复策略', () {
    test('4006 无效 session id：必须重新 Identify', () {
      final info = QqWsCloseInfo.resolve(4006);

      expect(info.known, isTrue);
      expect(info.action, WsRecoveryAction.identify);
      expect(info.effectiveAction, WsRecoveryAction.identify);
      expect(info.message, contains('identify'));
    });

    test('4007 seq 错误：必须重新 Identify', () {
      expect(QqWsCloseInfo.resolve(4007).action, WsRecoveryAction.identify);
    });

    test('4008 发送过快：可以重试 Resume', () {
      final info = QqWsCloseInfo.resolve(4008);

      expect(info.action, WsRecoveryAction.resume);
      expect(info.message, contains('频控'));
    });

    test('4009 连接过期：可以重试 Resume', () {
      expect(QqWsCloseInfo.resolve(4009).action, WsRecoveryAction.resume);
    });

    test('4001 / 4002 两个都不可重试，属于代码问题', () {
      expect(QqWsCloseInfo.resolve(4001).action, WsRecoveryAction.fatal);
      expect(QqWsCloseInfo.resolve(4002).action, WsRecoveryAction.fatal);
    });

    test('4010~4014 两个都不可重试', () {
      for (final code in <int>[4010, 4011, 4012, 4013, 4014]) {
        expect(
          QqWsCloseInfo.resolve(code).action,
          WsRecoveryAction.fatal,
          reason: '$code 官方两列均为否',
        );
      }
    });

    test('4014 intent 无权限的文案与权限相关', () {
      expect(QqWsCloseInfo.resolve(4014).message, contains('无权限'));
    });

    test('4900~4913 内部错误：可重新 Identify', () {
      for (final code in <int>[4900, 4906, 4913]) {
        expect(
          QqWsCloseInfo.resolve(code).action,
          WsRecoveryAction.identify,
          reason: '$code 属于「内部错误，请重连」段',
        );
      }
    });

    test('4899 不属于内部错误段，也不是官方表中的已知码', () {
      final info = QqWsCloseInfo.resolve(4899);

      expect(info.known, isFalse);
    });

    test('4914 已下架：终态，仅允许沙箱', () {
      final info = QqWsCloseInfo.resolve(4914);

      expect(info.action, WsRecoveryAction.fatal);
      expect(info.isOfflineSandboxOnly, isTrue);
      expect(info.isTerminal, isTrue);
      expect(info.isBanned, isFalse);
    });

    test('4915 已封禁：终态，必须停止重试', () {
      final info = QqWsCloseInfo.resolve(4915);

      expect(info.action, WsRecoveryAction.fatal);
      expect(info.isBanned, isTrue);
      expect(info.isTerminal, isTrue);
      expect(info.message, contains('申请解封'));
    });

    test('官方表中不存在的 4003 / 4004 / 4005 视为未知码', () {
      for (final code in <int>[4003, 4004, 4005]) {
        expect(QqWsCloseInfo.resolve(code).known, isFalse, reason: '$code 官方缺失');
      }
    });

    test('未知码（如标准关闭码 1000）按网络断开处理：退避重连并尝试 Resume', () {
      final info = QqWsCloseInfo.resolve(1000);

      expect(info.known, isFalse);
      expect(info.effectiveAction, WsRecoveryAction.resume);
    });
  });

  group('QqIntents 掩码', () {
    test('默认掩码包含单聊/群聊、互动、群成员三类事件', () {
      expect(
        QqIntents.has(QqIntents.defaultMask, QqIntents.groupAndC2cEvent),
        isTrue,
      );
      expect(QqIntents.has(QqIntents.defaultMask, QqIntents.interaction), isTrue);
      expect(
        QqIntents.has(QqIntents.defaultMask, QqIntents.groupMemberEvent),
        isTrue,
      );
    });

    test('默认掩码不包含未申请权限的位（多放会被网关直接关连接）', () {
      expect(QqIntents.has(QqIntents.defaultMask, QqIntents.guilds), isFalse);
      expect(
        QqIntents.has(QqIntents.defaultMask, QqIntents.guildMessages),
        isFalse,
      );
      expect(QqIntents.has(QqIntents.defaultMask, QqIntents.forumsEvent), isFalse);
      expect(
        QqIntents.has(QqIntents.defaultMask, QqIntents.publicGuildMessages),
        isFalse,
      );
    });

    test('降级掩码去掉归属存疑的群成员位', () {
      expect(
        QqIntents.has(
          QqIntents.defaultMaskWithoutGroupMembers,
          QqIntents.groupMemberEvent,
        ),
        isFalse,
      );
      expect(
        QqIntents.has(
          QqIntents.defaultMaskWithoutGroupMembers,
          QqIntents.groupAndC2cEvent,
        ),
        isTrue,
      );
      expect(
        QqIntents.has(
          QqIntents.defaultMaskWithoutGroupMembers,
          QqIntents.interaction,
        ),
        isTrue,
      );
    });

    test('位值按官方位移表达式计算', () {
      expect(QqIntents.groupAndC2cEvent, 1 << 25);
      expect(QqIntents.interaction, 1 << 26);
      expect(QqIntents.groupMemberEvent, 1 << 24);
      expect(QqIntents.publicGuildMessages, 1 << 30);
    });
  });

  group('QqMediaFileType 官方软硬限制', () {
    test('图片 20MB / 200MB', () {
      expect(QqMediaFileType.image.softLimitMb, 20);
      expect(QqMediaFileType.image.hardLimitMb, 200);
      expect(QqMediaFileType.image.softLimitBytes, 20 * 1024 * 1024);
    });

    test('视频 30MB / 200MB', () {
      expect(QqMediaFileType.video.softLimitMb, 30);
      expect(QqMediaFileType.video.hardLimitMb, 200);
    });

    test('语音 20MB / 200MB', () {
      expect(QqMediaFileType.audio.softLimitMb, 20);
      expect(QqMediaFileType.audio.hardLimitMb, 200);
    });

    test('文件 200MB / 200MB', () {
      expect(QqMediaFileType.file.softLimitMb, 200);
      expect(QqMediaFileType.file.hardLimitMb, 200);
    });

    test('未知 file_type 返回 null', () {
      expect(QqMediaFileType.fromValue(0), isNull);
      expect(QqMediaFileType.fromValue(5), isNull);
      expect(QqMediaFileType.fromValue(null), isNull);
    });
  });

  group('消息类型枚举的文档口径冲突处理', () {
    test('发送侧只认接口页口径 0/2/6/7，ark(3) 与 embed(4) 不在此枚举内', () {
      expect(QqSendMsgType.fromValue(0), QqSendMsgType.text);
      expect(QqSendMsgType.fromValue(2), QqSendMsgType.markdown);
      expect(QqSendMsgType.fromValue(6), QqSendMsgType.inputNotify);
      expect(QqSendMsgType.fromValue(7), QqSendMsgType.media);
      expect(QqSendMsgType.fromValue(3), isNull);
      expect(QqSendMsgType.fromValue(4), isNull);
    });

    test('接收侧 101/102 官方未给结构，需标记为可降级展示', () {
      expect(QqRecvMsgType.fromValue(101), QqRecvMsgType.parallel);
      expect(QqRecvMsgType.fromValue(102), QqRecvMsgType.chatRecord);
      expect(QqRecvMsgType.parallel.isStructureUnknown, isTrue);
      expect(QqRecvMsgType.chatRecord.isStructureUnknown, isTrue);
      expect(QqRecvMsgType.text.isStructureUnknown, isFalse);
      expect(QqRecvMsgType.ark.isStructureUnknown, isFalse);
      expect(QqRecvMsgType.quote.isStructureUnknown, isFalse);
    });

    test('未知 message_type 返回 null，交由上层降级为纯文本摘要', () {
      expect(QqRecvMsgType.fromValue(999), isNull);
      expect(QqRecvMsgType.fromValue(null), isNull);
    });
  });

  group('GroupRole', () {
    test('官方三种角色', () {
      expect(GroupRole.fromValue('owner'), GroupRole.owner);
      expect(GroupRole.fromValue('admin'), GroupRole.admin);
      expect(GroupRole.fromValue('member'), GroupRole.member);
    });

    test('管理员与群主才具备管理权限（官方：仅群管理员能收到加群申请）', () {
      expect(GroupRole.owner.isAdminOrOwner, isTrue);
      expect(GroupRole.admin.isAdminOrOwner, isTrue);
      expect(GroupRole.member.isAdminOrOwner, isFalse);
    });

    test('未知或空值返回 null', () {
      expect(GroupRole.fromValue('superadmin'), isNull);
      expect(GroupRole.fromValue(''), isNull);
      expect(GroupRole.fromValue(null), isNull);
    });
  });

  group('AppConfig 与官方未提供项的取值', () {
    test('心跳超时判据＝心跳周期 × 倍数（官方未提供阈值）', () {
      const config = AppConfig.dev;

      expect(
        config.heartbeatTimeoutFor(const Duration(milliseconds: 45000)),
        const Duration(milliseconds: 90000),
      );
    });

    test('退避按指数增长并在上限处截断', () {
      const config = AppConfig.dev;

      expect(config.backoffFor(0), const Duration(seconds: 1));
      expect(config.backoffFor(1), const Duration(seconds: 2));
      expect(config.backoffFor(3), const Duration(seconds: 8));
      expect(config.backoffFor(30), config.reconnectMaxDelay);
    });

    test('生产环境关闭逐帧与网络明细日志', () {
      expect(AppConfig.prod.enableNetworkLog, isFalse);
      expect(AppConfig.prod.enableFrameLog, isFalse);
      expect(AppConfig.dev.enableNetworkLog, isTrue);
      expect(AppConfig.dev.enableFrameLog, isTrue);
    });

    test('接入点缓存必须为正，用于规避官方 2 QPM 限制', () {
      expect(AppConfig.dev.endpointCacheTtl.inSeconds, greaterThan(0));
      expect(AppConfig.prod.endpointCacheTtl.inSeconds, greaterThan(0));
    });

    test('copyWith 可覆盖单个字段而不影响其他字段', () {
      final overridden = AppConfig.prod.copyWith(
        httpTimeout: const Duration(milliseconds: 1),
      );

      expect(overridden.httpTimeout, const Duration(milliseconds: 1));
      expect(overridden.maxConcurrentConnections,
          AppConfig.prod.maxConcurrentConnections);
    });
  });
}
