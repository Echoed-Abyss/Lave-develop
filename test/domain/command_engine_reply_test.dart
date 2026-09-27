import 'package:flutter_test/flutter_test.dart';
import 'package:lavedevelop/api/bot_message_service.dart';
import 'package:lavedevelop/api/dto/send_message_request.dart';
import 'package:lavedevelop/api/qq_http_client.dart';
import 'package:lavedevelop/core/logging/log_service.dart';
import 'package:lavedevelop/domain/command/command_engine.dart';
import 'package:lavedevelop/domain/models/qq_enums.dart';
import 'package:lavedevelop/domain/models/qq_message.dart';

/// 记录被动回复凭据的假发送器。
class _RecordingSender implements MessageSender {
  _RecordingSender({this.usedReplies = 0});

  /// 伪造的「本消息已用掉的被动回复次数」。
  int usedReplies;

  final List<PassiveCredential?> credentials = [];
  final List<String> texts = [];

  @override
  Future<ApiResponse> sendText({
    required String conversationId,
    required ConversationScope scope,
    required String text,
    PassiveCredential? credential,
    int? msgSeq,
  }) async {
    credentials.add(credential);
    texts.add(text);
    return ApiResponse.success(statusCode: 200);
  }

  @override
  Future<ApiResponse> sendImage({
    required String conversationId,
    required ConversationScope scope,
    required String filePath,
    PassiveCredential? credential,
    int? msgSeq,
  }) async {
    credentials.add(credential);
    return ApiResponse.success(statusCode: 200);
  }

  @override
  int repliesUsedFor(String? msgId) => usedReplies;
}

QqMessage _groupMessage({
  String? wireId = 'msg-id-from-d',
  String? eventId = 'outer-event-id',
  Duration windowLeft = const Duration(minutes: 5),
}) =>
    QqMessage(
      localId: 1,
      botId: '102810595',
      scope: ConversationScope.group,
      conversationId: 'group-openid',
      sender: const ActorRef(scopeId: 'member-openid', displayName: '白轩'),
      direction: MessageDirection.incoming,
      at: DateTime.now(),
      wireId: wireId,
      eventId: eventId,
      content: '#help',
      replyDeadline: DateTime.now().add(windowLeft),
    );

void main() {
  group('被动回复凭据（msg_id / event_id 二选一）', () {
    test('回复消息只用 msg_id，绝不把 event_id 一起带上', () async {
      // 这条用例锁定的是一个真实发生过的缺陷：
      // 指令引擎曾经同时传 msgId 与 eventId，导致每一次被动回复都被
      // 本地校验拦下（日志：「msg_id 与 event_id 只能二选一」），
      // 用户看到的现象是「机器人完全不回复指令」。
      final engine = CommandEngine(log: LogService());
      final sender = _RecordingSender();

      final handled = await engine.tryHandle(_groupMessage(), sender);

      expect(handled, isTrue);
      expect(sender.credentials, hasLength(1));

      final credential = sender.credentials.single;
      expect(credential, isNotNull);
      expect(credential!.msgId, 'msg-id-from-d');
      expect(credential.eventId, isNull);
      expect(credential.isMessageReply, isTrue);
    });

    test('事件里没有消息 id 时退回主动消息，而不是构造非法请求', () async {
      final engine = CommandEngine(log: LogService());
      final sender = _RecordingSender();

      await engine.tryHandle(_groupMessage(wireId: null), sender);

      expect(sender.credentials.single, isNull);
    });

    test('被动回复窗口已过时改发主动消息', () async {
      final engine = CommandEngine(log: LogService());
      final sender = _RecordingSender();

      await engine.tryHandle(
        _groupMessage(windowLeft: const Duration(seconds: -1)),
        sender,
      );

      expect(sender.credentials.single, isNull);
      expect(sender.texts, hasLength(1), reason: '窗口过期也要把回复发出去');
    });

    test('回复次数用尽时改发主动消息', () async {
      final engine = CommandEngine(log: LogService());
      // 群聊上限 5 次，已用 5 次即耗尽。
      final sender = _RecordingSender(usedReplies: 5);

      await engine.tryHandle(_groupMessage(), sender);

      expect(sender.credentials.single, isNull);
    });

    test('剩余次数按官方上限扣除实时用量', () async {
      final engine = CommandEngine(log: LogService());
      final sender = _RecordingSender(usedReplies: 2);

      await engine.tryHandle(_groupMessage(), sender);

      // #help 的回复本身不体现次数，这里直接验证计数口径：
      // 群聊 5 次上限、已用 2 次，仍应走被动回复。
      expect(sender.credentials.single?.msgId, 'msg-id-from-d');
    });
  });

  group('SendMessageRequest 的被动字段', () {
    test('回复消息：带 msg_id 与 msg_seq，不带 event_id', () {
      final request = SendMessageRequest.text(
        'hi',
        credential: const PassiveCredential.message('m-1'),
        msgSeq: 2,
      );

      final json = request.toJson();
      expect(json['msg_id'], 'm-1');
      expect(json.containsKey('event_id'), isFalse);
      expect(json['msg_seq'], 2);
      expect(request.validate(), isEmpty);
    });

    test('响应事件：带 event_id，不带 msg_id，也不带 msg_seq', () {
      final request = SendMessageRequest.text(
        'hi',
        credential: const PassiveCredential.event('e-1'),
        // 官方参数表里 msg_seq 只与 msg_id 联合使用，因此这里刻意给了值，
        // 期望它**不**被输出。
        msgSeq: 3,
      );

      final json = request.toJson();
      expect(json['event_id'], 'e-1');
      expect(json.containsKey('msg_id'), isFalse);
      expect(json.containsKey('msg_seq'), isFalse);
      expect(request.validate(), isEmpty);
    });

    test('主动消息：两个 id 都不带', () {
      final request = SendMessageRequest.text('hi');
      final json = request.toJson();

      expect(json.containsKey('msg_id'), isFalse);
      expect(json.containsKey('event_id'), isFalse);
      expect(json.containsKey('msg_seq'), isFalse);
      expect(request.validate(), isEmpty);
    });

    test('校验仍能拦住绕过工厂的非法组合（回归护栏）', () {
      final request = SendMessageRequest(
        msgType: 0,
        content: 'hi',
        msgId: 'm-1',
        eventId: 'e-1',
      );

      expect(request.validate(), contains('msg_id 与 event_id 只能二选一'));
    });
  });

  group('QqMessage.replyCredential', () {
    test('取的是消息 id 而不是外层事件 id', () {
      final credential = _groupMessage().replyCredential;
      expect(credential?.msgId, 'msg-id-from-d');
      expect(credential?.eventId, isNull);
    });

    test('没有消息 id 时返回 null', () {
      expect(_groupMessage(wireId: null).replyCredential, isNull);
      expect(_groupMessage(wireId: '').replyCredential, isNull);
    });
  });
}
