import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lavedevelop/domain/models/bot_profile.dart';
import 'package:lavedevelop/gateway/protocol/events/qq_event.dart';
import 'package:lavedevelop/gateway/protocol/gateway_frame.dart';
import 'package:lavedevelop/gateway/protocol/qq_opcode.dart';

/// 事件与帧解析的回归用例。
///
/// **测试输入全部是官方文档中的原始 JSON 样例**（`docs/qq-bot/knowledge-base.html`
/// 第 5 章逐字收录）。这样做的价值：官方任何一次字段调整只要反映到文档上，
/// 这里就会红——它同时是「解析是否正确」与「文档是否变化」的双重哨兵。
void main() {
  group('GatewayFrame', () {
    test('Op10 Hello 解析出心跳周期', () {
      final frame = GatewayFrame.fromJson(
        jsonDecode('{"op": 10, "d": {"heartbeat_interval": 45000}}')
            as Map<String, dynamic>,
      );

      expect(frame.op, QqOpCode.hello);
      expect(frame.rawOp, 10);
      expect(frame.isDispatch, isFalse);
      expect(HelloData.fromJson(frame.data as Map<String, dynamic>)
          .heartbeatIntervalMs, 45000);
    });

    test('Hello 缺心跳周期时按官方示例值兜底，避免上层拿到 0 而疯狂发包', () {
      final hello = HelloData.fromJson(const <String, dynamic>{});

      expect(hello.heartbeatIntervalMs, 45000);
    });

    test('Op0 READY 解析出 session_id 与 shard', () {
      const raw = '''
{
  "op": 0,
  "s": 1,
  "t": "READY",
  "d": {
    "version": 1,
    "session_id": "082ee18c-0be3-491b-9d8b-fbd95c51673a",
    "user": {"id": "6158788878435714165", "username": "群pro测试机器人", "bot": true},
    "shard": [0, 0]
  }
}''';
      final frame =
          GatewayFrame.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      final ready = ReadyData.fromJson(frame.data as Map<String, dynamic>);

      expect(frame.isDispatch, isTrue);
      expect(frame.type, 'READY');
      expect(frame.seq, 1);
      expect(ready.sessionId, '082ee18c-0be3-491b-9d8b-fbd95c51673a');
      expect(ready.isUsable, isTrue);
      expect(ready.user?.username, '群pro测试机器人');
      expect(ready.user?.bot, isTrue);
      // 官方示例中 READY 的 shard 为 [0, 0]，与 Identify 请求的 [0, 1] 形态不同。
      expect(ready.shard, <int>[0, 0]);
    });

    test('官方未定义的 op 不抛异常，而是标记为未知', () {
      final frame = GatewayFrame.fromJson(
        jsonDecode('{"op": 3, "d": {}}') as Map<String, dynamic>,
      );

      expect(frame.op, isNull);
      expect(frame.rawOp, 3);
      expect(frame.isUnknownOp, isTrue);
    });

    test('id 字段可缺失（官方两份 payload 示例不一致）', () {
      final withId = GatewayFrame.fromJson(
        jsonDecode('{"id":"event_id","op":0,"d":{},"s":42,"t":"X"}')
            as Map<String, dynamic>,
      );
      final withoutId = GatewayFrame.fromJson(
        jsonDecode('{"op":0,"d":{},"s":42,"t":"X"}') as Map<String, dynamic>,
      );

      expect(withId.id, 'event_id');
      expect(withoutId.id, isNull);
      expect(withoutId.seq, 42);
      expect(withoutId.type, 'X');
    });
  });

  group('IdentifyPayload / ResumePayload', () {
    test('Identify 序列化包含官方四个字段', () {
      final payload = IdentifyPayload.withPlatformProperties(
        token: 'QQBot ACCESS_TOKEN',
        intents: QqIntents.defaultMask,
        os: 'android',
      );
      final json = payload.toJson();

      expect(json['token'], 'QQBot ACCESS_TOKEN');
      expect(json['intents'], QqIntents.defaultMask);
      expect(json['shard'], <int>[0, 1]);
      // 官方示例的 properties 键名带 $ 前缀，必须原样保留。
      expect((json['properties'] as Map).keys,
          containsAll(<String>[r'$os', r'$browser', r'$device']));
    });

    test('Resume 序列化使用官方字段名 session_id 与 seq', () {
      final payload = ResumePayload(
        token: 'my_token',
        sessionId: 'session_id_i_stored',
        seq: 1337,
      );

      expect(payload.toJson(), <String, dynamic>{
        'token': 'my_token',
        'session_id': 'session_id_i_stored',
        'seq': 1337,
      });
    });

    test('心跳载荷 d 为裸值而非对象，首次连接为 null', () {
      expect(const HeartbeatPayload(null).toData(), isNull);
      expect(const HeartbeatPayload(251).toData(), 251);
    });
  });

  group('C2C_MESSAGE_CREATE（官方三例）', () {
    test('示例1：纯文本', () {
      const raw = '''
{
  "id": "ROBOT1.0_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
  "author": {
    "id": "A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4",
    "user_openid": "A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4",
    "union_openid": "",
    "username": "",
    "bot": false
  },
  "content": "你好，今天有什么推荐的活动吗？",
  "message_type": 0,
  "message_scene": {
    "source": "default",
    "ext": ["msg_idx=REFIDX_xxxxxxxxxxxxxxx=="]
  },
  "timestamp": "2026-07-21T10:00:00+08:00"
}''';
      final event = QqEvent.decode(
        'C2C_MESSAGE_CREATE',
        jsonDecode(raw),
        id: 'outer-id',
        seq: 7,
      );

      expect(event, isA<C2cMessageCreate>());
      final message = event as C2cMessageCreate;
      expect(message.content, '你好，今天有什么推荐的活动吗？');
      expect(message.messageType, 0);
      expect(message.author?.userOpenid, 'A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4');
      expect(message.author?.bot, isFalse);
      // 官方时间带东八区偏移，等价于 UTC 02:00。
      expect(message.timestamp?.toUtc(), DateTime.utc(2026, 7, 21, 2));
      // ext 是 "key=value" 字符串数组，必须解析出来才可用。
      expect(message.messageScene?.msgIdx, 'REFIDX_xxxxxxxxxxxxxxx==');
      expect(message.messageScene?.source, 'default');
      // 被动回复的 msg_id 取 d.id，而 event_id 取外层 id。
      expect(message.id, startsWith('ROBOT1.0_'));
      expect(message.eventId, 'outer-id');
      expect(message.seq, 7);
      expect(message.conversationId, 'A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4');
    });

    test('示例2：结构化卡片（message_type=3）', () {
      const raw = '''
{
  "id": "ROBOT1.0_yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy",
  "author": {"id": "B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4E5", "user_openid": "B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4E5", "bot": false},
  "content": "[卡片消息] 小程序\\n摘要: [每日打卡]快来完成今日学习打卡",
  "message_type": 3,
  "ark_data": {
    "ark_type": "miniapp",
    "ark_name": "小程序",
    "prompt": "[每日打卡]快来完成今日学习打卡",
    "fields": {
      "title": "快来完成今日学习打卡",
      "source": "学习助手",
      "tag": "微信小程序",
      "jump_url": "https://example.com/x"
    }
  },
  "timestamp": "2026-07-21T10:01:00+08:00"
}''';
      final message = QqEvent.decode('C2C_MESSAGE_CREATE', jsonDecode(raw))
          as C2cMessageCreate;

      expect(message.messageType, 3);
      expect(message.arkData?.arkType, 'miniapp');
      expect(message.arkData?.arkName, '小程序');
      expect(message.arkData?.title, '快来完成今日学习打卡');
      expect(message.arkData?.field('source'), '学习助手');
      expect(message.arkData?.jumpUrl, 'https://example.com/x');
      expect(message.arkData?.hasJumpUrl, isTrue);
      // 展示名优先中文类型名。
      expect(message.arkData?.displayName, '小程序');
    });

    test('示例3：引用消息（message_type=103），msg_elements 带被引用内容', () {
      const raw = '''
{
  "id": "ROBOT1.0_zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz",
  "author": {"id": "C3D4E5F6A1B2C3D4E5F6A1B2C3D4E5F6", "user_openid": "C3D4E5F6A1B2C3D4E5F6A1B2C3D4E5F6", "bot": false},
  "content": "这个建议很有帮助，谢谢你！",
  "message_type": 103,
  "msg_elements": [
    {
      "msg_idx": "REFIDX_aaaaaaaaaaaaaaa==",
      "message_type": 103,
      "content": "每天坚持阅读半小时，一个月后你会发现自己的变化"
    }
  ],
  "message_scene": {
    "source": "default",
    "ext": ["ref_msg_idx=REFIDX_aaaaaaaaaaaaaaa==", "msg_idx=REFIDX_zzzzzzzzzzzzzzz=="]
  },
  "timestamp": "2026-07-21T10:02:00+08:00"
}''';
      final message = QqEvent.decode('C2C_MESSAGE_CREATE', jsonDecode(raw))
          as C2cMessageCreate;

      expect(message.messageType, 103);
      expect(message.msgElements, hasLength(1));
      expect(message.msgElements!.first.content,
          '每天坚持阅读半小时，一个月后你会发现自己的变化');
      expect(message.messageScene?.isQuote, isTrue);
      // 两个 ext key 都要解析到，且值里的 '=' 不能被截断。
      expect(message.messageScene?.refMsgIdx, 'REFIDX_aaaaaaaaaaaaaaa==');
      expect(message.messageScene?.msgIdx, 'REFIDX_zzzzzzzzzzzzzzz==');
      expect(message.dedupKey, 'REFIDX_zzzzzzzzzzzzzzz==');
    });
  });

  group('GROUP_AT_MESSAGE_CREATE（官方两例）', () {
    test('示例1：纯文本，群聊额外携带 auth_token', () {
      const raw = '''
{
  "id": "ROBOT1.0_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
  "author": {
    "id": "A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4",
    "member_openid": "A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4",
    "member_role": "member",
    "username": "小明",
    "bot": false
  },
  "content": " /今日天气 ",
  "group_openid": "B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4E5",
  "message_type": 0,
  "timestamp": "2026-07-21T10:00:00+08:00",
  "message_scene": {
    "source": "default",
    "ext": ["msg_idx=REFIDX_xxxxxxxxxxxxxxx==", "auth_token=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"]
  }
}''';
      final message = QqEvent.decode('GROUP_AT_MESSAGE_CREATE', jsonDecode(raw))
          as GroupAtMessageCreate;

      // 官方已自动去除 @机器人 前缀，这里验证保留了原始前后空格（内容不被再次处理）。
      expect(message.content, ' /今日天气 ');
      expect(message.groupOpenid, 'B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4E5');
      expect(message.senderRole, 'member');
      expect(message.author?.memberOpenid,
          'A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4');
      expect(message.messageScene?.authToken,
          'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx');
    });

    test('示例2：图片附件（8 个官方字段逐一核对）', () {
      const raw = '''
{
  "id": "ROBOT1.0_yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy",
  "author": {"member_openid": "C3D4E5F6A1B2C3D4E5F6A1B2C3D4E5F6", "member_role": "member", "username": "小红", "bot": false},
  "content": " 看看这张风景照 ",
  "group_openid": "B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4E5",
  "message_type": 0,
  "timestamp": "2026-07-21T10:05:00+08:00",
  "attachments": [
    {
      "content_type": "image/jpeg",
      "filename": "photo.jpg",
      "url": "https://multimedia.nt.qq.com.cn/download?appid=xxx&fileid=xxx&rkey=xxx&spec=0",
      "width": 1920,
      "height": 1080,
      "size": 256000
    }
  ]
}''';
      final message = QqEvent.decode('GROUP_AT_MESSAGE_CREATE', jsonDecode(raw))
          as GroupAtMessageCreate;

      expect(message.attachments, hasLength(1));
      final attachment = message.attachments!.first;
      expect(attachment.contentType, 'image/jpeg');
      expect(attachment.filename, 'photo.jpg');
      expect(attachment.width, 1920);
      expect(attachment.height, 1080);
      expect(attachment.size, 256000);
      expect(attachment.isImage, isTrue);
      expect(attachment.isKnownType, isTrue);
    });

    test('示例3：引用消息且发送者是群主', () {
      const raw = '''
{
  "id": "ROBOT1.0_zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz",
  "author": {"member_openid": "D4E5F6A1B2C3D4E5F6A1B2C3D4E5F6A1", "member_role": "owner", "username": "小华", "bot": false},
  "content": " ",
  "group_openid": "B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4E5",
  "message_type": 103,
  "timestamp": "2026-07-21T10:10:00+08:00",
  "msg_elements": [
    {"content": "=== 消息 1 ===\\n[消息内容] 今天的学习计划已完成"}
  ],
  "message_scene": {
    "source": "default",
    "ext": ["msg_idx=REFIDX_zzzzzzzzzzzzzzz==", "auth_token=zz", "ref_msg_idx=TMP_xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"]
  }
}''';
      final message = QqEvent.decode('GROUP_AT_MESSAGE_CREATE', jsonDecode(raw))
          as GroupAtMessageCreate;

      expect(message.senderRole, 'owner');
      expect(message.messageScene?.refMsgIdx,
          'TMP_xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx');
      expect(message.msgElements!.first.content, contains('消息 1'));
    });
  });

  group('群生命周期与好友事件', () {
    test('GROUP_ADD_ROBOT：Unix 秒时间戳能解析', () {
      const raw = '''
{"group_openid": "A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4",
 "op_member_openid": "A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4",
 "timestamp": 1784570534}''';
      final event = QqEvent.decode('GROUP_ADD_ROBOT', jsonDecode(raw));

      expect(event, isA<GroupAddRobot>());
      final added = event as GroupAddRobot;
      expect(added.isLifecycleEvent, isTrue);
      expect(added.groupOpenid, 'A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4');
      expect(added.opMemberOpenid, 'A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4');
      expect(
        added.timestamp?.millisecondsSinceEpoch,
        DateTime.fromMillisecondsSinceEpoch(1784570534 * 1000)
            .millisecondsSinceEpoch,
      );
    });

    test('GROUP_MEMBER_ADD：member_openid 与 user_openid 并存', () {
      const raw = '''
{"timestamp": 1784276757,
 "group_openid": "B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4E5",
 "member_openid": "C3D4E5F6A1B2C3D4E5F6A1B2C3D4E5F6",
 "user_openid": "C3D4E5F6A1B2C3D4E5F6A1B2C3D4E5F6"}''';
      final event =
          QqEvent.decode('GROUP_MEMBER_ADD', jsonDecode(raw)) as GroupMemberAdd;

      expect(event.memberOpenid, 'C3D4E5F6A1B2C3D4E5F6A1B2C3D4E5F6');
      expect(event.userOpenid, 'C3D4E5F6A1B2C3D4E5F6A1B2C3D4E5F6');
      expect(event.isLifecycleEvent, isTrue);
    });

    test('FRIEND_ADD：scene_param 用于区分来源', () {
      const raw = '''
{"openid": "A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4",
 "timestamp": 1784570600,
 "scene": 2003,
 "scene_param": "callback_abc123",
 "author": {"union_openid": "DB85A74E07BA08B5B44CD9ED332FCBD2"}}''';
      final event = QqEvent.decode('FRIEND_ADD', jsonDecode(raw)) as FriendAdd;

      expect(event.scene, 2003);
      expect(event.sceneParam, 'callback_abc123');
      expect(event.hasSceneParam, isTrue);
      expect(event.isFromDeveloperShareLink, isTrue);
      expect(event.author?.unionOpenid, 'DB85A74E07BA08B5B44CD9ED332FCBD2');
      expect(event.isLifecycleEvent, isTrue);
    });

    test('FRIEND_DEL 不需要 author 也能解析', () {
      final event = QqEvent.decode('FRIEND_DEL', jsonDecode(
        '{"openid": "A1", "timestamp": 1784570524}',
      )) as FriendDel;

      expect(event.openid, 'A1');
      expect(event.author, isNull);
      expect(event.timestamp, isNotNull);
    });

    test('GROUP_JOIN_REQUEST：解析验证方式与自动审批信息', () {
      const raw = '''
{
  "group_openid": "30584554AA2BF4E72BD3B8F27A70339D",
  "join_request_id": "AVKiFWpdy0",
  "risk_tips": "warning_tips",
  "member_openid": "FE003FAF76C4817251FDC128A16753BB",
  "username": "申请人",
  "apply_at": "2026-07-21T10:00:00+08:00",
  "apply_source": "invited",
  "invited_by": "AAAA",
  "bot": false,
  "verify_info": {"method": "admin_review_qa", "review_qa_list": [{"question": "你是谁", "answer": "朋友"}]},
  "auto_approved": {"strategy_id": "st-1"}
}''';
      final event = QqEvent.decode('GROUP_JOIN_REQUEST', jsonDecode(raw))
          as GroupJoinRequest;

      expect(event.joinRequestId, 'AVKiFWpdy0');
      expect(event.hasRiskTip, isTrue);
      expect(event.isInvited, isTrue);
      expect(event.invitedBy, 'AAAA');
      expect(event.verifyInfo?.isQaReview, isTrue);
      expect(event.verifyInfo?.isMessageVerify, isFalse);
      expect(event.verifyInfo?.reviewQaList?.first.question, '你是谁');
      expect(event.verifyInfo?.reviewQaList?.first.answer, '朋友');
      expect(event.autoApproved?.strategyId, 'st-1');
      expect(event.applyAt?.toUtc(), DateTime.utc(2026, 7, 21, 2));
    });
  });

  group('INTERACTION_CREATE（官方三例）', () {
    test('示例1：单聊消息按钮，需要回应', () {
      const raw = '''
{
  "application_id": "1904842048",
  "chat_type": 2,
  "data": {"resolved": {"button_data": "confirm:once", "button_id": "allow-once"}, "type": 11},
  "id": "1b13d569-4610-4ab9-bc51-feecc5def6d4",
  "scene": "c2c",
  "timestamp": "2026-07-20T21:53:54+08:00",
  "type": 11,
  "user_openid": "A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4",
  "version": 1
}''';
      final event = QqEvent.decode('INTERACTION_CREATE', jsonDecode(raw))
          as InteractionCreate;

      expect(event.type, 11);
      expect(event.interactionType, InteractionType.inlineKeyboard);
      expect(event.requiresAck, isTrue);
      expect(event.chatScene, InteractionChatType.c2c);
      expect(event.data?.resolved?.buttonData, 'confirm:once');
      expect(event.data?.resolved?.buttonId, 'allow-once');
      expect(event.conversationId, 'A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4');
    });

    test('示例2：群聊消息按钮，会话标识取 group_openid', () {
      const raw = '''
{
  "application_id": "101984245",
  "chat_type": 1,
  "data": {"resolved": {"button_data": "eyJjb21tYW5kIjogInNhbXBsZSJ9"}, "type": 11},
  "group_member_openid": "A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4",
  "group_openid": "B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4E5",
  "id": "06915133-7aef-46ed-94f7-c50939e285ae",
  "scene": "group",
  "timestamp": "2026-07-20T21:53:54+08:00",
  "type": 11,
  "version": 1
}''';
      final event = QqEvent.decode('INTERACTION_CREATE', jsonDecode(raw))
          as InteractionCreate;

      expect(event.chatScene, InteractionChatType.group);
      expect(event.requiresAck, isTrue);
      expect(event.data?.resolved?.buttonData, 'eyJjb21tYW5kIjogInNhbXBsZSJ9');
      expect(event.conversationId, 'B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4E5');
    });

    test('示例3：用户授权事件不需要回应', () {
      const raw = '''
{
  "application_id": "102057050",
  "data": {"resolved": {"authorize_data": {"opt_scene": "setting", "scope": "c2c_push"}}},
  "id": "c30c003e-9454-4450-8e5e-665267c088c4",
  "scene": "c2c",
  "timestamp": "2026-07-20T21:54:38+08:00",
  "type": 18,
  "user_openid": "A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4",
  "version": 1
}''';
      final event = QqEvent.decode('INTERACTION_CREATE', jsonDecode(raw))
          as InteractionCreate;

      expect(event.interactionType, InteractionType.userAuthorize);
      // 官方明确只有 type=11/12 需要回应，其他无需回应。
      expect(event.requiresAck, isFalse);
      expect(event.data?.resolved?.authorizeData?.isC2cPush, isTrue);
      expect(event.data?.resolved?.authorizeData?.scopeLabel, '单聊主动消息推送');
    });
  });

  group('SUBSCRIBE_MESSAGE_STATUS', () {
    test('区分已授权与已拒绝的模板', () {
      const raw = '''
{
  "openid": "A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4",
  "result": [
    {"template_id": 10001, "custom_template_id": "tpl_abc123", "op": 1,
     "subscribe_id": "sub_def456", "subscribe_ts": 1784276820, "update_ts": 1784276820},
    {"template_id": 10002, "custom_template_id": "tpl_xyz789", "op": 2,
     "subscribe_id": "sub_ghi012", "subscribe_ts": 1784276815, "update_ts": 1784276820}
  ]
}''';
      final event = QqEvent.decode('SUBSCRIBE_MESSAGE_STATUS', jsonDecode(raw))
          as SubscribeMessageStatus;

      expect(event.result, hasLength(2));
      expect(event.granted, hasLength(1));
      expect(event.rejected, hasLength(1));
      expect(event.granted.first.subscribeId, 'sub_def456');
      expect(event.rejected.first.templateId, 10002);
      expect(event.isGroupSubscription, isFalse);
      expect(event.granted.first.subscribeAt?.millisecondsSinceEpoch,
          DateTime.fromMillisecondsSinceEpoch(1784276820 * 1000)
              .millisecondsSinceEpoch);
    });
  });

  group('消息推送开关事件', () {
    test('C2C_MSG_REJECT 解析为「已关闭」并保留原始载荷', () {
      final event = QqEvent.decode(
        'C2C_MSG_REJECT',
        jsonDecode('{"openid":"A1","timestamp":1784570524}'),
      );

      expect(event, isA<MessageSwitchEvent>());
      final switchEvent = event as MessageSwitchEvent;
      expect(switchEvent.target, MessageSwitchTarget.c2c);
      expect(switchEvent.enabled, isFalse);
      expect(switchEvent.isDisabled, isTrue);
      expect(switchEvent.openid, 'A1');
      // 官方未给该事件的完整字段表，原始载荷必须保留以便补建模。
      expect(switchEvent.payload.raw['timestamp'], 1784570524);
    });

    test('GROUP_MSG_RECEIVE 解析为「已开启」', () {
      final event = QqEvent.decode(
        'GROUP_MSG_RECEIVE',
        jsonDecode('{"group_openid":"G1","timestamp":1784570524}'),
      ) as MessageSwitchEvent;

      expect(event.target, MessageSwitchTarget.group);
      expect(event.enabled, isTrue);
      expect(event.groupOpenid, 'G1');
    });
  });

  group('未知事件降级', () {
    test('未建模的 t 返回 UnknownEvent 且保留原始载荷', () {
      final event = QqEvent.decode(
        'SOME_FUTURE_EVENT',
        jsonDecode('{"foo":"bar","n":1}'),
        id: 'e-1',
        seq: 9,
      );

      expect(event, isA<UnknownEvent>());
      final unknown = event as UnknownEvent;
      expect(unknown.type, 'SOME_FUTURE_EVENT');
      expect(unknown.needsModeling, isTrue);
      expect(unknown.hasNoType, isFalse);
      expect(unknown.raw['foo'], 'bar');
      expect(unknown.raw['n'], 1);
      expect(unknown.eventId, 'e-1');
      expect(unknown.seq, 9);
      // 未知事件也进事件日志，保证「有事件发生」不会丢失。
      expect(unknown.isLifecycleEvent, isTrue);
    });

    test('t 缺失时也能兜住', () {
      final event = QqEvent.decode(null, jsonDecode('{}'));

      expect(event, isA<UnknownEvent>());
      expect((event as UnknownEvent).hasNoType, isTrue);
    });

    test('d 为空字符串（官方 RESUMED 的形态）不导致解析失败', () {
      final event = QqEvent.decode('RESUMED', '');

      expect(event, isA<UnknownEvent>());
      expect((event as UnknownEvent).raw, isEmpty);
    });
  });

  group('TokenScheme（官方 token 拼接口径冲突）', () {
    test('两种拼法都能生成符合官方描述的形式', () {
      expect(
        TokenScheme.qqBotAccessToken.build(appId: '1020', token: 'AT'),
        'QQBot AT',
      );
      expect(
        TokenScheme.botAppToken.build(appId: '1020', token: 'BT'),
        'Bot 1020.BT',
      );
    });

    test('未知名称回退到字段表口径', () {
      expect(TokenScheme.fromName('unknown'), TokenScheme.qqBotAccessToken);
      expect(TokenScheme.fromName(null), TokenScheme.qqBotAccessToken);
      expect(TokenScheme.fromName('botAppToken'), TokenScheme.botAppToken);
    });
  });
}
