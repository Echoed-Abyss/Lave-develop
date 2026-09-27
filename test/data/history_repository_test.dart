import 'package:flutter_test/flutter_test.dart';
import 'package:lavedevelop/data/local/json_doc_store.dart';
import 'package:lavedevelop/data/repository/history_repository.dart';
import 'package:lavedevelop/domain/models/qq_enums.dart';
import 'package:lavedevelop/domain/models/qq_message.dart';

/// 历史消息落盘 → 恢复的往返测试。
///
/// 重点锁住三件事，都是「重启后消息看起来变样了」这一类问题：
/// 1. 群聊里**每个发言者都要被区分开**。恢复时如果拿会话标识
///    （`group_openid`）去顶替发送者标识，一屏消息会全部显示成同一个人；
/// 2. @ 到的昵称要跟着正文一起回来，否则正文里的 `<@openid>` 会退化成 `@某人`；
/// 3. 引用块不能一重启就消失。
class _MemoryStore implements ListStoreLike {
  final Map<String, List<Map<String, dynamic>>> lists = {};

  @override
  Future<List<Map<String, dynamic>>> readList(String key) async =>
      lists[key] ?? const [];

  @override
  Future<void> writeList(String key, List<Map<String, dynamic>> items) async {
    // 存深拷贝：真实实现是序列化后写入，共享引用会掩盖掉持久化本身的问题。
    lists[key] = items
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }
}

QqMessage _message({
  required String conversationId,
  required String senderId,
  String? senderName,
  String? content,
  ConversationScope scope = ConversationScope.group,
  Map<String, String> mentions = const {},
  QqMessage? quote,
  int? messageType,
}) =>
    QqMessage(
      localId: 1,
      botId: '102810595',
      scope: scope,
      conversationId: conversationId,
      sender: ActorRef(
        scopeId: senderId,
        displayName: senderName,
        avatarUrl: 'https://q.qlogo.cn/qqapp/102810595/$senderId/100',
      ),
      direction: MessageDirection.incoming,
      at: DateTime(2026, 9, 27, 10),
      wireId: 'msg-$senderId',
      content: content,
      mentions: mentions,
      quote: quote,
      messageType: messageType,
    );

/// 写盘 → 换一个仓库实例读回来。
Future<HistoryRepository> _roundTrip(
  _MemoryStore store,
  List<QqMessage> messages,
) async {
  final writer = HistoryRepository(store: store);
  for (final message in messages) {
    writer.addMessage(message);
  }
  // addMessage 是 3 秒防抖落盘，这里直接触发一次立即写：
  // 走的是应用退出时用的同一个入口，测试因此不依赖真实时间。
  await writer.flush();

  final reader = HistoryRepository(store: store);
  await reader.restore();
  return reader;
}

void main() {
  group('发送者标识的往返', () {
    test('群聊里两个不同的发言者，恢复后仍然是两个人', () async {
      final store = _MemoryStore();
      final reader = await _roundTrip(store, [
        _message(
          conversationId: 'GROUP_OPENID',
          senderId: 'MEMBER_A',
          senderName: '白轩',
        ),
        _message(
          conversationId: 'GROUP_OPENID',
          senderId: 'MEMBER_B',
          senderName: '在下百香果',
        ),
      ]);

      final messages = reader.messagesOf('102810595', 'GROUP_OPENID');

      expect(messages, hasLength(2));
      expect(messages[0].sender.scopeId, 'MEMBER_A');
      expect(messages[1].sender.scopeId, 'MEMBER_B');
      // 关键：绝不能退化成会话标识，否则两个人都变成同一个「群」
      expect(
        messages.every((m) => m.sender.scopeId != 'GROUP_OPENID'),
        isTrue,
      );
    });

    test('恢复后的发送者仍然带得出头像地址', () async {
      final store = _MemoryStore();
      final reader = await _roundTrip(store, [
        _message(
          conversationId: 'GROUP_OPENID',
          senderId: 'MEMBER_A',
          senderName: '白轩',
        ),
      ]);

      final sender =
          reader.messagesOf('102810595', 'GROUP_OPENID').single.sender;

      expect(sender.avatarUrl, contains('MEMBER_A'));
      expect(sender.label, '白轩');
    });

    test('机器人自己发出的消息不会被当成用户', () async {
      final store = _MemoryStore();
      final writer = HistoryRepository(store: store);
      writer.addMessage(
        QqMessage(
          localId: 1,
          botId: '102810595',
          scope: ConversationScope.group,
          conversationId: 'GROUP_OPENID',
          sender: const ActorRef(
            scopeId: 'robot',
            displayName: '落日余晖',
            isBot: true,
          ),
          direction: MessageDirection.outgoing,
          at: DateTime(2026, 9, 27, 10),
          content: '收到',
        ),
      );
      await writer.flush();

      final reader = HistoryRepository(store: store);
      await reader.restore();

      final message =
          reader.messagesOf('102810595', 'GROUP_OPENID').single;
      expect(message.isIncoming, isFalse);
      expect(message.sender.scopeId, 'robot');
      // 机器人头像来自账号资料，不能按 openid 拼
      expect(message.sender.avatarUrl, isNull);
    });
  });

  group('@ 与引用的往返', () {
    test('mentions 落盘后恢复，正文里的 @ 仍然显示昵称', () async {
      final store = _MemoryStore();
      const openid = 'CA87605D7C22D7BA4863B86754D1876D';
      final reader = await _roundTrip(store, [
        _message(
          conversationId: 'GROUP_OPENID',
          senderId: 'MEMBER_A',
          senderName: '白轩',
          content: '<@$openid> 你看这个',
          mentions: {openid.toLowerCase(): '在下百香果'},
        ),
      ]);

      final message =
          reader.messagesOf('102810595', 'GROUP_OPENID').single;

      expect(message.mentions, isNotEmpty);
      expect(message.mentions[openid.toLowerCase()], '在下百香果');
      // 渲染出来的正文里不该再有十六进制 openid
      expect(
        message.segments.map((e) => e.text).join(),
        '@在下百香果 你看这个',
      );
      expect(message.preview.contains(openid), isFalse);
    });

    test('引用块能跨重启保留', () async {
      final store = _MemoryStore();
      final reader = await _roundTrip(store, [
        _message(
          conversationId: 'GROUP_OPENID',
          senderId: 'MEMBER_A',
          senderName: '白轩',
          content: '同意',
          messageType: 103,
          quote: _message(
            conversationId: 'GROUP_OPENID',
            senderId: 'MEMBER_B',
            senderName: '在下百香果',
            content: '每天坚持阅读半小时',
          ),
        ),
      ]);

      final message =
          reader.messagesOf('102810595', 'GROUP_OPENID').single;

      expect(message.quote, isNotNull);
      expect(message.quote!.content, '每天坚持阅读半小时');
      expect(message.quote!.sender.displayName, '在下百香果');
      expect(message.messageType, 103);
      expect(message.isQuote, isTrue);
    });

    test('空内容的引用块不会被恢复成空壳', () async {
      final store = _MemoryStore();
      final reader = await _roundTrip(store, [
        _message(
          conversationId: 'GROUP_OPENID',
          senderId: 'MEMBER_A',
          content: '正文',
          quote: _message(
            conversationId: 'GROUP_OPENID',
            senderId: 'MEMBER_B',
            // 既没有 content 也没有卡片：恢复时应当整块丢弃
          ),
        ),
      ]);

      final message =
          reader.messagesOf('102810595', 'GROUP_OPENID').single;
      expect(message.quote, isNull);
    });
  });
}
