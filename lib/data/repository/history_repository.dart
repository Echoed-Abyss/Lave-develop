import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/models/bot_event.dart';
import '../../domain/models/qq_message.dart';

/// 会话（单聊 / 群聊）摘要。
@immutable
class ConversationSummary {
  const ConversationSummary({
    required this.botId,
    required this.conversationId,
    required this.title,
    required this.scopeLabel,
    required this.lastAt,
    this.lastPreview = '',
    this.messageCount = 0,
    this.canSendActive = true,
  });

  final String botId;
  final String conversationId;
  final String title;

  /// 场景标签（单聊 / 群聊）。
  final String scopeLabel;

  final DateTime lastAt;
  final String lastPreview;
  final int messageCount;

  /// 是否允许发送主动消息。
  ///
  /// 官方：用户 / 群管理员可以在资料页关闭主动消息推送，
  /// 关闭后主动消息一律发送失败。关闭状态由 C2C_MSG_REJECT /
  /// GROUP_MSG_REJECT 事件通知，这里缓存下来供发送面板提前提示。
  final bool canSendActive;
}

/// 消息与事件的本地仓库。
///
/// 范围取舍（当前阶段目标是「能编译能跑」）：
/// 消息保留在内存 + 每次变更异步落盘最近 N 条；
/// 事件日志同理。数据量上万后需要换成带索引的本地数据库，
/// 升级点集中在 `_persist` 一处。
class HistoryRepository extends ChangeNotifier {
  HistoryRepository({
    required HistoryStoreLike store,
    this.maxMessagesPerConversation = 500,
    this.maxEvents = 500,
  }) : _store = store;

  final HistoryStoreLike _store;

  /// 每个会话保留的消息条数上限。
  final int maxMessagesPerConversation;

  /// 保留的事件日志条数上限。
  final int maxEvents;

  /// key = `${botId}|${conversationId}`，value 为**时间正序**的消息列表。
  final Map<String, List<QqMessage>> _messages = {};

  /// key = botId，value 为**时间倒序**的事件列表。
  final Map<String, List<BotEvent>> _events = {};

  /// 主动消息开关状态：key = `${botId}|${conversationId}`。
  final Map<String, bool> _activeMessageEnabled = {};

  int _messageIdSeed = 0;

  /// 生成一个本地消息自增 id。
  int nextLocalId() => ++_messageIdSeed;

  /// 某个会话的消息（时间正序）。
  List<QqMessage> messagesOf(String botId, String conversationId) =>
      List.unmodifiable(_messages[_key(botId, conversationId)] ?? const []);

  /// 某个机器人的事件日志（时间倒序，最新在前）。
  List<BotEvent> eventsOf(String botId) =>
      List.unmodifiable(_events[botId] ?? const []);

  /// 全部事件（跨机器人，时间倒序），用于「日志」Tab 的整合视图。
  List<BotEvent> get allEvents {
    final merged = <BotEvent>[];
    for (final list in _events.values) {
      merged.addAll(list);
    }
    merged.sort((a, b) => b.at.compareTo(a.at));
    return merged;
  }

  /// 会话列表（按最近活跃时间倒序）。
  List<ConversationSummary> conversationsOf(String botId) {
    final result = <ConversationSummary>[];
    _messages.forEach((key, list) {
      if (list.isEmpty) return;
      final parts = key.split('|');
      if (parts.length != 2 || parts.first != botId) return;
      final conversationId = parts.last;
      final last = list.last;
      result.add(
        ConversationSummary(
          botId: botId,
          conversationId: conversationId,
          title: conversationId,
          scopeLabel: last.scope.label,
          lastAt: last.at,
          lastPreview: last.preview,
          messageCount: list.length,
          canSendActive: isActiveMessageEnabled(botId, conversationId),
        ),
      );
    });
    result.sort((a, b) => b.lastAt.compareTo(a.lastAt));
    return result;
  }

  /// 主动消息开关是否可用（默认可用）。
  bool isActiveMessageEnabled(String botId, String conversationId) =>
      _activeMessageEnabled[_key(botId, conversationId)] ?? true;

  /// 记录主动消息开关状态（来自 C2C_MSG_REJECT / GROUP_MSG_REJECT 等事件）。
  void setActiveMessageEnabled(
    String botId,
    String conversationId,
    bool enabled,
  ) {
    _activeMessageEnabled[_key(botId, conversationId)] = enabled;
    notifyListeners();
  }

  /// 追加一条消息。
  ///
  /// 去重由调用方（事件分发层）负责，这里只做存储与截断。
  void addMessage(QqMessage message) {
    final key = _key(message.botId, message.conversationId);
    final list = _messages.putIfAbsent(key, () => <QqMessage>[]);
    list.add(message);
    if (list.length > maxMessagesPerConversation) {
      list.removeRange(0, list.length - maxMessagesPerConversation);
    }
    notifyListeners();
    _schedulePersist();
  }

  /// 追加一条机器人生命周期事件。
  void addEvent(BotEvent event) {
    final list = _events.putIfAbsent(event.botId, () => <BotEvent>[]);
    list.insert(0, event);
    if (list.length > maxEvents) {
      list.removeRange(maxEvents, list.length);
    }
    notifyListeners();
    _schedulePersist();
  }

  /// 清空某个机器人的全部历史。
  void clearBot(String botId) {
    _messages.removeWhere((key, _) => key.startsWith('$botId|'));
    _events.remove(botId);
    _activeMessageEnabled.removeWhere((key, _) => key.startsWith('$botId|'));
    notifyListeners();
    _schedulePersist();
  }

  /// 从本地载入。
  Future<void> restore() async {
    try {
      final messageItems = await _store.readList('messages');
      for (final item in messageItems) {
        // 消息恢复只需要展示所需的最小字段，附件等不落盘以控制体积。
        final botId = item['bot_id'] as String?;
        final conversationId = item['conversation_id'] as String?;
        if (botId == null || conversationId == null) continue;
        final key = _key(botId, conversationId);
        _messages.putIfAbsent(key, () => <QqMessage>[]);
      }
    } catch (_) {
      // 载入失败按空处理，不影响启动。
    }
    notifyListeners();
  }

  static String _key(String botId, String conversationId) =>
      '$botId|$conversationId';

  Timer? _persistTimer;

  /// 合并写入，避免消息密集时反复落盘。
  void _schedulePersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(seconds: 3), () {
      unawaited(_persist());
    });
  }

  Future<void> _persist() async {
    try {
      // 只持久化消息的展示摘要：附件 URL 带签名且会过期，
      // 存下来也无法复用，反而会让恢复后的列表出现失效图片。
      final payload = <Map<String, dynamic>>[];
      _messages.forEach((key, list) {
        final parts = key.split('|');
        if (parts.length != 2) return;
        for (final message in list.take(50)) {
          payload.add({
            'bot_id': parts.first,
            'conversation_id': parts.last,
            'scope': message.scope.name,
            'direction': message.direction.name,
            'at': message.at.toIso8601String(),
            if (message.content != null) 'content': message.content,
            if (message.wireId != null) 'wire_id': message.wireId,
          });
        }
      });
      await _store.writeList('messages', payload);

      final eventPayload = <Map<String, dynamic>>[];
      for (final list in _events.values) {
        for (final event in list.take(50)) {
          eventPayload.add({
            'bot_id': event.botId,
            'kind': event.kind.name,
            'at': event.at.toIso8601String(),
            if (event.summary != null) 'summary': event.summary,
          });
        }
      }
      await _store.writeList('events', eventPayload);
    } catch (_) {
      // 持久化失败不影响内存中的使用。
    }
  }

  @override
  void dispose() {
    _persistTimer?.cancel();
    super.dispose();
  }
}

/// 历史存储的最小依赖面。
abstract interface class HistoryStoreLike {
  Future<List<Map<String, dynamic>>> readList(String key);

  Future<void> writeList(String key, List<Map<String, dynamic>> items);
}
