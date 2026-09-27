import 'dart:async';

import 'package:flutter/foundation.dart';

import '../local/json_doc_store.dart';
import '../../core/utils/qq_avatar.dart';
import '../../domain/models/bot_event.dart';
import '../../domain/models/qq_enums.dart';
import '../../domain/models/qq_message.dart';

/// 会话（单聊 / 群聊）摘要。
@immutable
class ConversationSummary {
  const ConversationSummary({
    required this.botId,
    required this.conversationId,
    required this.title,
    required this.scope,
    required this.lastAt,
    this.lastPreview = '',
    this.messageCount = 0,
    this.canSendActive = true,
    this.peerAvatarUrl,
  });

  final String botId;
  final String conversationId;
  final String title;

  /// 会话场景。
  ///
  /// 用枚举而不是字符串标签：界面原本靠 `scopeLabel == '群聊'` 判断场景，
  /// 一旦标签文案改动（或做多语言）就会静默失配。
  final ConversationScope scope;

  /// 场景展示标签（单聊 / 群聊）。
  String get scopeLabel => scope.label;

  /// 会话对方的头像地址（拿不到时为 `null`）。
  ///
  /// 只有**单聊**能取到：群聊的会话标识是 group_openid，
  /// 而头像 CDN 对群 openid 只会返回一张默认灰头像（实测），
  /// 界面上用群图标占位更能区分不同会话。
  final String? peerAvatarUrl;

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
    required ListStoreLike store,
    this.maxMessagesPerConversation = 500,
    this.maxEvents = 500,
  }) : _store = store;

  final ListStoreLike _store;

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
            scope: last.scope,
            lastAt: last.at,
            lastPreview: last.preview,
            messageCount: list.length,
            canSendActive: isActiveMessageEnabled(botId, conversationId),
            peerAvatarUrl: _peerAvatarOf(
              botId: botId,
              conversationId: conversationId,
              last: last,
            ),
          ),
        );
    });
    result.sort((a, b) => b.lastAt.compareTo(a.lastAt));
    return result;
  }

  /// 会话对方的头像地址（见 [ConversationSummary.peerAvatarUrl]）。
  ///
  /// 优先取最后一条**入站**消息的发送者头像，而不是无条件自行拼 URL：
  /// 事件若带了官方 `avatar` 就该优先用它，拼串只是在官方没给时的补位。
  /// 最后一条若是我们自己发的，它的发送者头像是**机器人**的，不能拿来当对方头像。
  static String? _peerAvatarOf({
    required String botId,
    required String conversationId,
    required QqMessage last,
  }) {
    // 群聊取不到（群 openid 只会拿到默认灰头像），交给界面用群图标占位。
    if (last.scope != ConversationScope.c2c) return null;
    if (last.isIncoming && last.sender.avatarUrl != null) {
      return last.sender.avatarUrl;
    }
    return QqAvatar.forOpenid(appId: botId, openid: conversationId);
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

  /// 从本地载入历史。
  ///
  /// 说明：只恢复「展示所需的最小字段」（时间、方向、正文、官方消息 id、
  /// 发送者身份与头像地址、@ 到的人、被引用的那条消息），不恢复附件 ——
  /// 官方附件 URL 带签名且会过期，存下来也只会得到一堆失效图片，
  /// 反而让用户以为「消息坏了」。
  ///
  /// 发送者身份（`sender_scope_id`）必须落盘，不能拿会话标识顶替：
  /// 群聊的会话标识是 `group_openid`，而发言者是某个 `member_openid`，
  /// 两者混用会让重启后的历史气泡全部显示成「同一个人」，
  /// 头像与占位色也跟着错。这是真实存在过的缺陷。
  Future<void> restore() async {
    try {
      for (final item in await _store.readList('messages')) {
        final botId = item['bot_id'] as String?;
        final conversationId = item['conversation_id'] as String?;
        if (botId == null || conversationId == null) continue;

        final direction = item['direction'] == MessageDirection.outgoing.name
            ? MessageDirection.outgoing
            : MessageDirection.incoming;
        final scope = ConversationScope.values.firstWhere(
          (e) => e.value == item['scope'],
          orElse: () => ConversationScope.c2c,
        );
        final list = _messages.putIfAbsent(
          _key(botId, conversationId),
          () => <QqMessage>[],
        );
        final senderScopeId =
            (item['sender_scope_id'] as String?)?.trim();
        final effectiveScopeId = (senderScopeId != null && senderScopeId.isNotEmpty)
            ? senderScopeId
            : (direction == MessageDirection.incoming ? conversationId : 'robot');
        list.add(
          QqMessage(
            localId: nextLocalId(),
            botId: botId,
            scope: scope,
            conversationId: conversationId,
            sender: ActorRef(
              scopeId: effectiveScopeId,
              displayName: item['sender_name'] as String?,
              avatarUrl: _restoredAvatar(
                botId: botId,
                stored: item['sender_avatar'] as String?,
                outgoing: direction == MessageDirection.outgoing,
                senderScopeId: senderScopeId,
                // 单聊的会话标识本身就是对方 openid，可以安全地当作头像依据；
                // 群聊的会话标识是群，拿它拼只会得到默认灰头像。
                conversationId: conversationId,
                scope: scope,
              ),
              isBot: direction == MessageDirection.outgoing,
            ),
            direction: direction,
            at: DateTime.tryParse(item['at'] as String? ?? '') ?? DateTime.now(),
            wireId: item['wire_id'] as String?,
            content: item['content'] as String?,
            // @ 到的人跟着正文一起落盘：不存的话正文里的 `<@openid>`
            // 重启后就只能显示成 `@某人`，而这条消息本来是能显示昵称的。
            mentions: _stringMapOf(item['mentions']),
            messageType: item['message_type'] as int?,
            quote: _restoredQuote(
              item['quote'],
              botId: botId,
              conversationId: conversationId,
              scope: scope,
            ),
          ),
        );
      }

      for (final item in await _store.readList('events')) {
        final botId = item['bot_id'] as String?;
        final kindName = item['kind'] as String?;
        if (botId == null || kindName == null) continue;
        _events.putIfAbsent(botId, () => <BotEvent>[]).add(
              BotEvent(
                botId: botId,
                kind: BotEventKind.values.firstWhere(
                  (e) => e.name == kindName,
                  orElse: () => BotEventKind.unknown,
                ),
                at:
                    DateTime.tryParse(item['at'] as String? ?? '') ?? DateTime.now(),
                summary: item['summary'] as String?,
              ),
            );
      }

      // 消息展示需要时间正序，事件日志需要时间倒序（最新在前）。
      for (final list in _messages.values) {
        list.sort((a, b) => a.at.compareTo(b.at));
      }
      for (final list in _events.values) {
        list.sort((a, b) => b.at.compareTo(a.at));
      }
    } catch (_) {
      // 本地数据损坏不应导致应用打不开：忽略并按空历史继续。
    }
    notifyListeners();
  }

  static String _key(String botId, String conversationId) =>
      '$botId|$conversationId';

  /// 恢复一个发送者的头像地址。
  ///
  /// 顺序：落盘值 → 按 openid 推导 → `null`（交给界面用首字占位）。
  /// 推导只在**确实知道发送者自己的 openid** 时做：
  /// 单聊的会话标识就是对方 openid，可以直接用；群聊的会话标识是群，
  /// 拿它去拼只会得到 CDN 的默认灰头像——那种「看起来有头像但其实是错的」
  /// 比明确的占位更难排查，所以宁可返回 `null`。
  static String? _restoredAvatar({
    required String botId,
    required String? stored,
    required bool outgoing,
    required String? senderScopeId,
    required String conversationId,
    required ConversationScope scope,
  }) {
    final saved = stored?.trim();
    if (saved != null && saved.isNotEmpty) return saved;
    if (outgoing) return null;
    final own = senderScopeId?.trim();
    final openid = (own != null && own.isNotEmpty)
        ? own
        : (scope == ConversationScope.c2c ? conversationId : null);
    if (openid == null) return null;
    return QqAvatar.forOpenid(appId: botId, openid: openid);
  }

  /// 把持久化里的 `mentions` 读回成 `openid → 昵称`。
  ///
  /// 逐项校验类型：本地文档可能来自旧版本，一条脏数据不该让整个历史读不出来。
  static Map<String, String> _stringMapOf(Object? raw) {
    if (raw is! Map) return const {};
    final result = <String, String>{};
    raw.forEach((key, value) {
      if (key is! String || value is! String) return;
      if (key.isEmpty || value.isEmpty) return;
      result[key] = value;
    });
    return result;
  }

  /// 把被引用的消息压成可落盘的扁平结构。
  ///
  /// 只存展示要用的文本与发送者信息，附件同样不带（同顶层消息的理由：
  /// 预签名 URL 存下来只会变成失效图片）。
  static Map<String, dynamic> _packQuote(QqMessage quote) => {
        if (quote.content != null) 'content': quote.content,
        if (quote.sender.displayName != null)
          'sender_name': quote.sender.displayName,
        if (quote.sender.scopeId.isNotEmpty)
          'sender_scope_id': quote.sender.scopeId,
        if (quote.sender.avatarUrl != null)
          'sender_avatar': quote.sender.avatarUrl,
        'at': quote.at.toIso8601String(),
        if (quote.ark != null)
          'ark': {
            if (quote.ark!.displayName != null)
              'display_name': quote.ark!.displayName,
            if (quote.ark!.title != null) 'title': quote.ark!.title,
          },
      };

  /// 把落盘的引用块读回成一条（精简的）消息。
  static QqMessage? _restoredQuote(
    Object? raw, {
    required String botId,
    required String conversationId,
    required ConversationScope scope,
  }) {
    if (raw is! Map) return null;
    final map = raw.cast<Object?, Object?>();
    final content = map['content'] as String?;
    final name = map['sender_name'] as String?;
    final arkName = (map['ark'] is Map)
        ? (map['ark'] as Map)['display_name'] as String?
        : null;
    // 什么都没有的引用块不如不显示
    if ((content == null || content.isEmpty) && arkName == null) return null;

    final senderScopeId = map['sender_scope_id'] as String?;
    return QqMessage(
      localId: 0,
      botId: botId,
      scope: scope,
      conversationId: conversationId,
      sender: ActorRef(
        scopeId: (senderScopeId?.isNotEmpty ?? false)
            ? senderScopeId!
            : 'quoted',
        displayName: name,
        avatarUrl: _restoredAvatar(
          botId: botId,
          stored: map['sender_avatar'] as String?,
          outgoing: false,
          senderScopeId: senderScopeId,
          conversationId: conversationId,
          scope: scope,
        ),
        isBot: (senderScopeId?.isNotEmpty ?? false) &&
            senderScopeId == 'robot',
      ),
      direction: MessageDirection.incoming,
      at: DateTime.tryParse(map['at'] as String? ?? '') ?? DateTime.now(),
      content: content,
      ark: arkName == null ? null : ArkSummary(displayName: arkName),
    );
  }

  Timer? _persistTimer;

  /// 合并写入，避免消息密集时反复落盘。
  void _schedulePersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(seconds: 3), () {
      unawaited(_persist());
    });
  }

  /// 立即落盘（取消待执行的防抖写）。
  ///
  /// 应用退出时必须调一次：落盘走的是 3 秒防抖，
  /// 「刚收到几条消息就被系统回收 / 用户退出」会把这批消息丢掉，
  /// 而这类丢失在用户看来就是「消息记录莫名其妙少了几条」。
  /// 统计那边一直是这么做的（见 `AppServices.shutdown`），历史此前漏了。
  Future<void> flush() async {
    _persistTimer?.cancel();
    _persistTimer = null;
    await _persist();
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
            if (message.messageType != null) 'message_type': message.messageType,
            // 昵称、发送者身份与头像地址：会话页渲染头像与发言者需要，
            // 见 restore 的说明。
            if (message.sender.displayName != null)
              'sender_name': message.sender.displayName,
            if (message.sender.avatarUrl != null)
              'sender_avatar': message.sender.avatarUrl,
            if (message.sender.scopeId.isNotEmpty)
              'sender_scope_id': message.sender.scopeId,
            // @ 到的人：正文里的 `<@openid>` 要靠它才能渲染成昵称。
            if (message.mentions.isNotEmpty) 'mentions': message.mentions,
            if (message.quote != null) 'quote': _packQuote(message.quote!),
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

/// 历史存储的最小依赖面见 `data/local/json_doc_store.dart` 的 [ListStoreLike]。
