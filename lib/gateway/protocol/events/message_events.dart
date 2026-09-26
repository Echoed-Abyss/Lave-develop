part of 'qq_event.dart';

/// 消息类事件：单聊、群 @机器人、群全量消息。
///
/// 字段逐字对照官方文档（知识库 5.1 / 5.2 / 5.3 节）。

/// `C2C_MESSAGE_CREATE` —— 单聊消息事件。
///
/// 官方触发时机：用户给机器人发送单聊消息时触发。
/// 官方提醒：相同 `msg_id` 可能重复推送，需结合 `msg_seq` 去重。
@immutable
class C2cMessageCreate extends QqEvent {
  const C2cMessageCreate({
    required super.eventId,
    required super.seq,
    this.id,
    this.author,
    this.content,
    this.timestamp,
    this.messageType,
    this.messageScene,
    this.attachments,
    this.arkData,
    this.msgElements,
  });

  @override
  String get typeName => 'C2C_MESSAGE_CREATE';

  /// 消息 ID，**被动回复时作为 `msg_id`**，也可用于撤回。
  final String? id;

  /// 发送者。本场景 `user_openid` 有值。
  final QqUser? author;

  /// 消息文本内容。
  final String? content;

  /// 消息发送时间（官方为 RFC3339 字符串）。
  final DateTime? timestamp;

  /// 消息内容类型：0=普通文本，3=结构化卡片，101=并行消息，
  /// 102=聊天记录，103=引用消息。
  final int? messageType;

  /// 消息场景上下文（含 `msg_idx` 去重键与 `ref_msg_idx` 引用键）。
  final MessageScene? messageScene;

  /// 消息附件（图片、文件、语音等）。
  final List<MessageAttachment>? attachments;

  /// 结构化卡片数据（`message_type = 3` 时有值）。
  final ArkData? arkData;

  /// 消息元素列表（`message_type = 103` 引用消息时含被引用内容）。
  final List<MsgElement>? msgElements;

  factory C2cMessageCreate.fromJson(
    Map<String, dynamic> json,
    String? eventId,
    int? seq,
  ) =>
      C2cMessageCreate(
        eventId: eventId,
        seq: seq,
        id: QqJson.str(json['id']),
        author: _user(json['author']),
        content: QqJson.str(json['content']),
        timestamp: QqTime.tryParse(json['timestamp']),
        messageType: QqJson.integer(json['message_type']),
        messageScene: _scene(json['message_scene']),
        attachments: QqJson.list(json['attachments'], MessageAttachment.fromJson),
        arkData: _ark(json['ark_data']),
        msgElements: QqJson.list(json['msg_elements'], MsgElement.fromJson),
      );

  /// 单聊会话标识（`user_openid`）。
  String? get conversationId => author?.c2cScopeId;

  /// 消息去重键：官方要求结合 `message_scene.ext` 的 `msg_idx` 去重。
  String? get dedupKey => messageScene?.msgIdx ?? id;
}

/// `GROUP_AT_MESSAGE_CREATE` —— 群内 @机器人消息事件。
///
/// 官方原文：用户在群里@机器人发送消息时触发。**这是机器人最常接收的事件。**
/// `content` 字段**已自动去除@机器人的前缀**，客户端不得再自行剥离。
@immutable
class GroupAtMessageCreate extends QqEvent {
  const GroupAtMessageCreate({
    required super.eventId,
    required super.seq,
    this.id,
    this.author,
    this.content,
    this.groupOpenid,
    this.timestamp,
    this.messageType,
    this.messageScene,
    this.attachments,
    this.mentions,
    this.arkData,
    this.msgElements,
  });

  @override
  String get typeName => 'GROUP_AT_MESSAGE_CREATE';

  @override
  bool get isLifecycleEvent => false;

  /// 消息 ID，被动回复时作为 `msg_id`。
  final String? id;

  /// 发送者。本场景 `member_openid` 有值。
  final QqUser? author;

  /// 消息文本内容（官方已去除 @机器人 前缀）。
  final String? content;

  /// 群 OpenID，群聊发消息接口的路径参数。
  final String? groupOpenid;

  /// 消息发送时间。
  final DateTime? timestamp;

  /// 消息内容类型（同单聊）。
  final int? messageType;

  /// 消息场景上下文（本事件额外携带 `auth_token`）。
  final MessageScene? messageScene;

  /// 消息附件。
  final List<MessageAttachment>? attachments;

  /// 消息中 @ 的用户列表。官方明确：**不含 @机器人自身**。
  final List<QqUser>? mentions;

  /// 结构化卡片数据。
  final ArkData? arkData;

  /// 消息元素列表。
  final List<MsgElement>? msgElements;

  factory GroupAtMessageCreate.fromJson(
    Map<String, dynamic> json,
    String? eventId,
    int? seq,
  ) =>
      GroupAtMessageCreate(
        eventId: eventId,
        seq: seq,
        id: QqJson.str(json['id']),
        author: _user(json['author']),
        content: QqJson.str(json['content']),
        groupOpenid: QqJson.str(json['group_openid']),
        timestamp: QqTime.tryParse(json['timestamp']),
        messageType: QqJson.integer(json['message_type']),
        messageScene: _scene(json['message_scene']),
        attachments: QqJson.list(json['attachments'], MessageAttachment.fromJson),
        mentions: QqJson.list(json['mentions'], QqUser.fromJson),
        arkData: _ark(json['ark_data']),
        msgElements: QqJson.list(json['msg_elements'], MsgElement.fromJson),
      );

  /// 群会话标识。
  String? get conversationId => groupOpenid;

  /// 发送者在群内的角色（`member` / `admin` / `owner`）。
  String? get senderRole => author?.memberRole;

  /// 消息去重键。
  String? get dedupKey => messageScene?.msgIdx ?? id;
}

/// `GROUP_MESSAGE_CREATE` —— 群全量消息事件。
///
/// 官方原文：当机器人开启了「接收所有消息」功能后，群里的每一条消息
/// （不限于@机器人）都会推送此事件。**各字段含义与 GROUP_AT_MESSAGE_CREATE 完全一致。**
///
/// 注意：官方 intents 清单中 `GROUP_AND_C2C_EVENT (1<<25)` 只列出了
/// `GROUP_AT_MESSAGE_CREATE`，未列本事件，其 intent 归属属于
/// 「需真机实测确认」项（知识库 11 章）。
@immutable
class GroupMessageCreate extends GroupAtMessageCreate {
  const GroupMessageCreate({
    required super.eventId,
    required super.seq,
    super.id,
    super.author,
    super.content,
    super.groupOpenid,
    super.timestamp,
    super.messageType,
    super.messageScene,
    super.attachments,
    super.mentions,
    super.arkData,
    super.msgElements,
  });

  @override
  String get typeName => 'GROUP_MESSAGE_CREATE';

  /// 复用与 `GROUP_AT_MESSAGE_CREATE` 完全相同的字段结构
  /// （官方原文：「各字段含义与 GROUP_AT_MESSAGE_CREATE 完全一致」）。
  factory GroupMessageCreate.fromJson(
    Map<String, dynamic> json,
    String? eventId,
    int? seq,
  ) {
    final base = GroupAtMessageCreate.fromJson(json, eventId, seq);
    return GroupMessageCreate(
      eventId: base.eventId,
      seq: base.seq,
      id: base.id,
      author: base.author,
      content: base.content,
      groupOpenid: base.groupOpenid,
      timestamp: base.timestamp,
      messageType: base.messageType,
      messageScene: base.messageScene,
      attachments: base.attachments,
      mentions: base.mentions,
      arkData: base.arkData,
      msgElements: base.msgElements,
    );
  }
}

// ───────────────────────── 内部解析助手 ─────────────────────────

QqUser? _user(Object? raw) {
  final map = QqJson.map(raw);
  return map == null ? null : QqUser.fromJson(map);
}

MessageScene? _scene(Object? raw) {
  final map = QqJson.map(raw);
  return map == null ? null : MessageScene.fromJson(map);
}

ArkData? _ark(Object? raw) {
  final map = QqJson.map(raw);
  return map == null ? null : ArkData.fromJson(map);
}
