import 'dart:async';
import 'dart:collection';

import '../api/bot_message_service.dart';
import '../api/interaction_api.dart';
import '../core/constants/qq_limits.dart';
import '../core/logging/log_service.dart';
import '../data/repository/history_repository.dart';
import '../domain/command/command_engine.dart';
import '../domain/models/bot_event.dart';
import '../domain/models/log_entry.dart';
import '../domain/models/qq_enums.dart';
import '../domain/models/qq_message.dart';
import '../plugins/plugin_manager.dart';
import 'message_mapper.dart';
import 'protocol/events/qq_event.dart';

/// 事件分发层。
///
/// 官方对事件流的两条硬要求决定了本类的顺序（知识库 3.7 / 5.1 节）：
/// 1. **「相同 msg_id 可能重复推送」，需结合 `message_scene.ext` 的 `msg_idx` 去重**；
/// 2. **「在处理过事件之后记录下 s」** —— 因此 `acknowledgeSeq` 必须在落库之后调用。
///
/// 处理管线（与架构文档 3.4 节一致）：
/// 解码 → 去重 → 归一为领域模型 → 落库 → 推进水位 → 广播给指令引擎与插件。
class EventDispatcher {
  EventDispatcher({
    required this.botId,
    required HistoryRepository history,
    required LogService log,
    required MessageSender sender,
    required CommandEngine commands,
    required PluginManager plugins,
    required InteractionApi interactionApi,
    required Future<void> Function(int? seq) acknowledgeSeq,
    void Function()? onIncomingMessage,
  })  : _history = history,
        _log = log,
        _sender = sender,
        _commands = commands,
        _plugins = plugins,
        _interactionApi = interactionApi,
        _onIncomingMessage = onIncomingMessage,
        _acknowledgeSeq = acknowledgeSeq;

  final String botId;
  final HistoryRepository _history;
  final LogService _log;
  final MessageSender _sender;
  final CommandEngine _commands;
  final PluginManager _plugins;
  final InteractionApi _interactionApi;
  final Future<void> Function(int? seq) _acknowledgeSeq;

  /// 收到一条**去重后**的入站消息时回调（统计用）。
  final void Function()? _onIncomingMessage;

  /// 去重集合。
  ///
  /// 用 `LinkedHashSet` 保留插入顺序，超出上限时淘汰最早的键——
  /// 这比「只存最后一次」更能覆盖官方「同一事件重复推送」的场景。
  final LinkedHashSet<String> _seenKeys = LinkedHashSet<String>();

  /// 去重表容量。
  static const int _dedupCapacity = 2000;

  /// 统计（界面可展示）。
  int handledCount = 0;
  int duplicatedCount = 0;

  /// 处理一个事件。
  Future<void> handle(QqEvent event) async {
    try {
      await _route(event);
    } catch (error, stack) {
      // 任何单条事件的处理失败都不能中断事件流，
      // 否则一次脏数据就会让机器人「突然不再响应任何消息」。
      _log.error(
        LogSource.event,
        '事件处理异常（已跳过该事件）：${event.typeName}',
        botId: botId,
        detail: '$error\n$stack',
      );
    } finally {
      // 无论成功与否都要推进水位：事件已经「被处理过」，
      // 卡住水位会导致每次重连都重复补发同一批事件。
      await _acknowledgeSeq(event.seq);
    }
  }

  Future<void> _route(QqEvent event) async {
    // ── 生命周期事件：写事件日志，并同步推送开关状态 ──
    if (event.isLifecycleEvent) {
      final botEvent = _toBotEvent(event);
      if (botEvent != null) {
        _history.addEvent(botEvent);
        _log.info(
          LogSource.event,
          botEvent.displayText,
          botId: botId,
        );
        _applySwitchSideEffects(event);
      }
      // 互动事件必须先回应，否则用户侧会一直转圈直到超时。
      // 官方只要求 type=11（消息按钮）与 type=12（快捷菜单）回应，
      // 这个判定封装在模型的 requiresAck 上。
      if (event is InteractionCreate && event.requiresAck && event.id != null) {
        await _interactionApi.acknowledge(
          botId: botId,
          interactionId: event.id!,
        );
      }

      // 生命周期事件同样投递给插件：加群 / 加好友是插件最关心的时机。
      await _plugins.dispatch(
        _payloadFor(event),
        eventType: event.typeName,
        botId: botId,
      );
      handledCount++;
      return;
    }

    // ── 消息类事件 ──
    final message = _toMessage(event);
    if (message == null) {
      // 非消息、非生命周期（例如未知事件走了生命周期分支，这里兜底）。
      await _plugins.dispatch(
        _payloadFor(event),
        eventType: event.typeName,
        botId: botId,
      );
      handledCount++;
      return;
    }

    // 去重：官方明确存在重复推送。
    final key = '${message.conversationId}|${message.deduplicationKey ?? message.wireId ?? ''}';
    if (message.deduplicationKey != null || message.wireId != null) {
      if (_seenKeys.contains(key)) {
        duplicatedCount++;
        _log.warn(
          LogSource.event,
          '收到重复推送，已跳过（key=${message.deduplicationKey ?? message.wireId}）',
          botId: botId,
        );
        return;
      }
      _seenKeys.add(key);
      if (_seenKeys.length > _dedupCapacity) {
        _seenKeys.remove(_seenKeys.first);
      }
    }

    _history.addMessage(message);
    // 统计「收到消息数」。放在**去重之后**：官方明确「相同 msg_id 可能重复推送」，
    // 在去重前计数会把一次消息算成两次，用户看到的数字会持续虚高。
    _onIncomingMessage?.call();
    _log.info(
      LogSource.event,
      '${message.scope.label}消息：${message.preview}',
      botId: botId,
      detail: '来自 ${message.sender.label}'
          '（会话 ${message.conversationId}）'
          '${message.canReplyAt(DateTime.now()) ? '' : '，被动回复窗口已关闭'}',
    );

    // 先给指令引擎：内置指令（#help 等）响应最快。
    final handled = await _commands.tryHandle(message, _sender);
    if (!handled) {
      // 未被指令消费的事件再交给插件。
      final delivered = await _plugins.dispatch(
        _payloadFor(event, message: message),
        eventType: event.typeName,
        botId: botId,
      );
      // 内置指令不认、也没有任何插件订阅时才提示「可用 #help」。
      //
      // 早期版本由指令引擎对所有 `#` 开头的消息一律回「已消费」，
      // 于是插件永远收不到这类消息；改成「不认就放行」之后，
      // 提示必须挪到这里，否则用户在插件已经处理了的情况下
      // 还会看到一句「未知指令」，反而怀疑插件没生效。
      if (delivered == 0 && _commands.looksLikeUnknownCommand(message.content)) {
        _commands.logUnknownCommand(message);
      }
    }
    handledCount++;
  }

  /// 构造投递给插件的归一化载荷。
  ///
  /// 刻意**不投递官方原始 JSON**：插件作者看到的是稳定结构，
  /// 官方字段改名不会直接打断插件；同时这也让插件无法依赖内部实现细节。
  ///
  /// 注意协议版本**只在信封上**（`dispatch` 写入的 `payload.protocol_version`）：
  /// 这里曾额外放一份硬编码的版本号，结果是信封说 v2、事件体说 v1，
  /// 插件作者根本不知道该信哪个。
  Map<String, dynamic> _payloadFor(QqEvent event, {QqMessage? message}) {
    final payload = <String, dynamic>{
      't': event.typeName,
      'bot_id': botId,
      'seq': event.seq,
      if (event.eventId != null) 'event_id': event.eventId,
    };

    if (message != null) {
      payload
        ..['scope'] = message.scope.value
        ..['conversation_id'] = message.conversationId
        ..['message_id'] = message.wireId
        ..['content'] = message.content
        ..['timestamp'] = message.at.toIso8601String()
        ..['sender'] = {
          'id': message.sender.scopeId,
          'name': message.sender.displayName,
          'role': message.sender.role?.value,
          'is_bot': message.sender.isBot,
        }
        ..['attachments'] = message.attachments
            .map(
              (a) => {
                'url': a.url,
                'filename': a.filename,
                'content_type': a.contentType,
                'size': a.size,
                'width': a.width,
                'height': a.height,
                'voice_wav_url': a.voiceWavUrl,
                'asr_text': a.asrText,
              },
            )
            .toList(growable: false)
        ..['can_reply'] = message.canReplyAt(DateTime.now())
        ..['remaining_replies'] = message.remainingRepliesAt(DateTime.now())
        // @ 到的人：`openid → 昵称`。
        //
        // 正文里的占位符是 `<@openid>` 或 `<qqbot-at-user id="..." />`，
        // 插件拿不到昵称就只能显示一串十六进制。官方没有说明占位符与
        // `mentions` 元素如何对应，所以这里把每个被 @ 用户的每一种标识
        // 都作为 key 一起下发，插件按内容里的 id 直接查即可。
        ..['mentions'] = message.mentions;
      return payload;
    }

    // 生命周期事件：把已归一的事件对象摊平，便于插件读取。
    switch (event) {
      case GroupAddRobot():
        payload
          ..['group_openid'] = event.groupOpenid
          ..['op_member_openid'] = event.opMemberOpenid;
      case GroupDelRobot():
        payload
          ..['group_openid'] = event.groupOpenid
          ..['op_member_openid'] = event.opMemberOpenid;
      case GroupMemberRemove():
        payload
          ..['group_openid'] = event.groupOpenid
          ..['member_openid'] = event.memberOpenid
          ..['user_openid'] = event.userOpenid;
      case GroupMemberAdd():
        payload
          ..['group_openid'] = event.groupOpenid
          ..['member_openid'] = event.memberOpenid
          ..['user_openid'] = event.userOpenid;
      case GroupJoinRequest():
        payload
          ..['group_openid'] = event.groupOpenid
          ..['join_request_id'] = event.joinRequestId
          ..['username'] = event.username
          ..['risk_tips'] = event.riskTips
          ..['apply_source'] = event.applySource;
      case FriendAdd():
        payload
          ..['openid'] = event.openid
          ..['scene'] = event.scene
          ..['scene_param'] = event.sceneParam;
      case FriendDel():
        payload['openid'] = event.openid;
      case MessageSwitchEvent():
        payload
          ..['target'] = event.target.name
          ..['enabled'] = event.enabled
          ..['openid'] = event.openid
          ..['group_openid'] = event.groupOpenid;
      case InteractionCreate():
        payload
          ..['interaction_id'] = event.id
          ..['interaction_type'] = event.type
          ..['requires_ack'] = event.requiresAck
          ..['group_openid'] = event.groupOpenid
          ..['user_openid'] = event.userOpenid
          ..['button_data'] = event.data?.resolved?.buttonData;
      case SubscribeMessageStatus():
        payload
          ..['openid'] = event.openid
          ..['group_openid'] = event.groupOpenid
          ..['granted'] = event.granted.length
          ..['rejected'] = event.rejected.length;
      case UnknownEvent():
        payload['raw'] = event.raw;
      default:
        break;
    }
    return payload;
  }

  /// 把协议事件归一为领域消息。
  ///
  /// 这里只做「组装」：字段怎么从官方结构映射到领域模型，
  /// 全部交给 [MessageMapper]（那部分没有 IO，可以单独测）。
  QqMessage? _toMessage(QqEvent event) {
    final now = DateTime.now();
    switch (event) {
      case C2cMessageCreate():
        final scopeId = event.conversationId;
        if (scopeId == null) return null;
        final senderId =
            event.author?.userOpenid ?? event.author?.id ?? 'unknown';
        return QqMessage(
          localId: _history.nextLocalId(),
          botId: botId,
          scope: ConversationScope.c2c,
          conversationId: scopeId,
          sender: ActorRef(
            scopeId: senderId,
            displayName: event.author?.username,
            avatarUrl: MessageMapper.avatarOf(
              event,
              botId: botId,
              senderId: senderId,
            ),
            unionId: event.author?.unionOpenid,
            isBot: event.author?.bot ?? false,
          ),
          direction: MessageDirection.incoming,
          at: event.timestamp ?? now,
          wireId: event.id,
          eventId: event.eventId,
          content: event.content,
          attachments: MessageMapper.attachmentsOf(event),
          ark: MessageMapper.arkOf(event),
          quote: MessageMapper.quoteOf(event, botId: botId),
          replyDeadline: now.add(QqLimits.c2cReplyWindow),
          deduplicationKey: event.dedupKey,
          mentions: MessageMapper.mentionsOf(event),
          messageType: event.messageType,
        );

      case GroupAtMessageCreate():
        final groupId = event.groupOpenid;
        if (groupId == null) return null;
        final senderId =
            event.author?.memberOpenid ?? event.author?.id ?? 'unknown';
        return QqMessage(
          localId: _history.nextLocalId(),
          botId: botId,
          scope: ConversationScope.group,
          conversationId: groupId,
          sender: ActorRef(
            scopeId: senderId,
            displayName: event.author?.username,
            avatarUrl: MessageMapper.avatarOf(
              event,
              botId: botId,
              senderId: senderId,
            ),
            role: GroupRole.fromValue(event.author?.memberRole),
            isBot: event.author?.bot ?? false,
          ),
          direction: MessageDirection.incoming,
          at: event.timestamp ?? now,
          wireId: event.id,
          eventId: event.eventId,
          content: event.content,
          attachments: MessageMapper.attachmentsOf(event),
          ark: MessageMapper.arkOf(event),
          quote: MessageMapper.quoteOf(event, botId: botId),
          replyDeadline: now.add(QqLimits.groupReplyWindow),
          deduplicationKey: event.dedupKey,
          mentions: MessageMapper.mentionsOf(event),
          messageType: event.messageType,
        );

      case _:
        return null;
    }
  }

  /// 把协议事件归一为生命周期事件。
  BotEvent? _toBotEvent(QqEvent event) {
    final now = DateTime.now();
    switch (event) {
      case GroupAddRobot():
        return BotEvent(
          botId: botId,
          kind: BotEventKind.groupAddRobot,
          at: event.timestamp ?? now,
          groupOpenid: event.groupOpenid,
          actorOpenid: event.opMemberOpenid,
          summary: '机器人被拉入群'
              '${event.opMemberOpenid == null ? '' : '（操作人 ${event.opMemberOpenid}）'}',
          eventId: event.eventId,
          rawEventType: event.typeName,
        );

      case GroupDelRobot():
        return BotEvent(
          botId: botId,
          kind: BotEventKind.groupDelRobot,
          at: event.timestamp ?? now,
          groupOpenid: event.groupOpenid,
          actorOpenid: event.opMemberOpenid,
          summary: '机器人被移出群'
              '${event.opMemberOpenid == null ? '' : '（操作人 ${event.opMemberOpenid}）'}',
          eventId: event.eventId,
          rawEventType: event.typeName,
        );

      // 注意顺序：GroupMemberRemove 继承自 GroupMemberAdd，
      // Dart 的 switch 模式会先匹配父类，因此子类必须写在前面的分支，
      // 否则「成员退群」会被当成「成员加入」处理。
      case GroupMemberRemove():
        return BotEvent(
          botId: botId,
          kind: BotEventKind.groupMemberRemove,
          at: event.timestamp ?? now,
          groupOpenid: event.groupOpenid,
          actorOpenid: event.memberOpenid,
          summary: '成员退出群（${event.memberOpenid ?? '未知成员'}）',
          eventId: event.eventId,
          rawEventType: event.typeName,
        );

      case GroupMemberAdd():
        return BotEvent(
          botId: botId,
          kind: BotEventKind.groupMemberAdd,
          at: event.timestamp ?? now,
          groupOpenid: event.groupOpenid,
          actorOpenid: event.memberOpenid,
          summary: '新成员加入群（${event.memberOpenid ?? '未知成员'}）',
          eventId: event.eventId,
          rawEventType: event.typeName,
        );

      case GroupJoinRequest():
        return BotEvent(
          botId: botId,
          kind: BotEventKind.groupJoinRequest,
          at: event.applyAt ?? now,
          groupOpenid: event.groupOpenid,
          actorOpenid: event.memberOpenid,
          actorName: event.username,
          summary: '${event.username ?? '用户'} 申请加群'
              '${event.hasRiskTip ? '（平台风险提示：${event.riskTips}）' : ''}',
          eventId: event.eventId,
          rawEventType: event.typeName,
        );

      case FriendAdd():
        return BotEvent(
          botId: botId,
          kind: BotEventKind.friendAdd,
          at: event.timestamp ?? now,
          actorOpenid: event.openid,
          summary: '用户添加了机器人'
              '${event.sceneParam == null ? '' : '（来源标识 ${event.sceneParam}）'}',
          eventId: event.eventId,
          rawEventType: event.typeName,
        );

      case FriendDel():
        return BotEvent(
          botId: botId,
          kind: BotEventKind.friendDel,
          at: event.timestamp ?? now,
          actorOpenid: event.openid,
          summary: '用户删除了机器人',
          eventId: event.eventId,
          rawEventType: event.typeName,
        );

      case MessageSwitchEvent():
        final isGroup = event.target == MessageSwitchTarget.group;
        final kind = isGroup
            ? (event.enabled
                ? BotEventKind.groupPushSwitchOn
                : BotEventKind.groupPushSwitchOff)
            : (event.enabled
                ? BotEventKind.c2cPushSwitchOn
                : BotEventKind.c2cPushSwitchOff);
        return BotEvent(
          botId: botId,
          kind: kind,
          at: event.timestamp ?? now,
          groupOpenid: event.groupOpenid,
          actorOpenid: event.openid,
          summary: event.enabled
              ? '${event.target.label}主动消息推送已开启'
              : '${event.target.label}主动消息推送已关闭（此后无法发送主动消息）',
          eventId: event.eventId,
          rawEventType: event.typeName,
        );

      case InteractionCreate():
        final type = event.interactionType;
        return BotEvent(
          botId: botId,
          kind: BotEventKind.interaction,
          at: event.timestamp ?? now,
          groupOpenid: event.groupOpenid,
          actorOpenid: event.userOpenid ?? event.groupMemberOpenid,
          summary: '互动事件：${type?.label ?? '未知类型'}'
              '${event.requiresAck ? '（需要回应）' : ''}',
          eventId: event.eventId,
          rawEventType: event.typeName,
        );

      case SubscribeMessageStatus():
        return BotEvent(
          botId: botId,
          kind: BotEventKind.subscribeStatus,
          at: now,
          groupOpenid: event.groupOpenid,
          actorOpenid: event.openid,
          summary: '订阅授权状态变更：允许 ${event.granted.length} 项，'
              '拒绝 ${event.rejected.length} 项',
          eventId: event.eventId,
          rawEventType: event.typeName,
        );

      case UnknownEvent():
        return BotEvent(
          botId: botId,
          kind: BotEventKind.unknown,
          at: now,
          summary: '收到尚未支持的事件类型：${event.typeName}',
          eventId: event.eventId,
          rawEventType: event.typeName,
        );

      default:
        return null;
    }
  }

  /// 推送开关类事件的副作用：同步到历史仓库，供发送面板提前提示。
  void _applySwitchSideEffects(QqEvent event) {
    if (event is! MessageSwitchEvent) return;
    final conversationId = event.groupOpenid ?? event.openid;
    if (conversationId == null) return;
    _history.setActiveMessageEnabled(botId, conversationId, event.enabled);
  }

  /// 手动清空去重表（切换账号或排障时使用）。
  void resetDeduplication() {
    _seenKeys.clear();
    duplicatedCount = 0;
    handledCount = 0;
  }
}
