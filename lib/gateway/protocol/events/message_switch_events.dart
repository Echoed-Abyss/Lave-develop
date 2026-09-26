part of 'qq_event.dart';

/// 消息推送开关事件（4 类）。
///
/// 官方确认的信息只有「触发时机」与所属 intent，**未在本次抓取到的页面中
/// 给出完整字段表**（知识库 5.4 节）。因此本模块的处理方式是：
/// 1. 不凭印象编造字段名——原始 JSON 原样保留在 [payload] 中；
/// 2. 只解析跨事件通用的三个字段（时间、用户 OpenID、群 OpenID），
///    这三个字段名在官方同一体系的其他事件中一致出现；
/// 3. 用 [enabled] 与 [target] 表达业务语义，UI 与插件层只依赖语义，
///    将来官方补充字段表时只需在此文件内补齐，不影响上层。
@immutable
class MessageSwitchEvent extends QqEvent {
  const MessageSwitchEvent({
    required super.eventId,
    required super.seq,
    required this.typeName,
    required this.target,
    required this.enabled,
    required this.payload,
    this.timestamp,
  });

  @override
  final String typeName;

  @override
  bool get isLifecycleEvent => true;

  /// 开关作用对象：单聊（C2C）或群聊。
  final MessageSwitchTarget target;

  /// 开关状态：`true` = 用户/管理员**开启**了推送，`false` = 关闭。
  final bool enabled;

  /// 原始载荷。字段表未确认，故原样保留以便排查与后续补建模。
  final RawEventPayload payload;

  /// 事件时间（尽力解析，可能为空）。
  final DateTime? timestamp;

  /// 单聊场景的用户 OpenID（尽力解析）。
  String? get openid => payload.openid;

  /// 群聊场景的群 OpenID（尽力解析）。
  String? get groupOpenid => payload.groupOpenid;

  /// 通知开关被关闭。此时机器人无法向该用户 / 群发送主动消息，
  /// 属于必须落库并在界面上体现的状态（否则用户会一直困惑
  /// 「为什么发不出去」）。
  bool get isDisabled => !enabled;

  factory MessageSwitchEvent.fromJson({
    required String type,
    required Map<String, dynamic> json,
    required String? eventId,
    required int? seq,
  }) {
    final switchType = MessageSwitchType.fromTypeName(type);
    return MessageSwitchEvent(
      eventId: eventId,
      seq: seq,
      typeName: type,
      target: switchType?.target ?? MessageSwitchTarget.c2c,
      enabled: switchType?.enabled ?? true,
      payload: RawEventPayload(json),
      timestamp: _timestamp(json['timestamp']),
    );
  }
}

/// 开关作用对象。
enum MessageSwitchTarget {
  /// 单聊（C2C_MSG_RECEIVE / C2C_MSG_REJECT）。
  c2c('单聊'),

  /// 群聊（GROUP_MSG_RECEIVE / GROUP_MSG_REJECT）。
  group('群聊');

  const MessageSwitchTarget(this.label);

  final String label;
}

/// 官方四个开关事件与语义的对照表。
///
/// 官方触发时机原文：
/// - `C2C_MSG_RECEIVE`：用户在机器人资料卡手动开启「主动消息」推送开关时触发；
/// - `C2C_MSG_REJECT`：用户在机器人资料卡手动关闭「主动消息」推送时触发；
/// - `GROUP_MSG_RECEIVE`：群管理员在机器人资料页操作开启通知时触发；
/// - `GROUP_MSG_REJECT`：群管理员在机器人资料页操作关闭通知时触发。
enum MessageSwitchType {
  c2cReceive('C2C_MSG_RECEIVE', MessageSwitchTarget.c2c, true),
  c2cReject('C2C_MSG_REJECT', MessageSwitchTarget.c2c, false),
  groupReceive('GROUP_MSG_RECEIVE', MessageSwitchTarget.group, true),
  groupReject('GROUP_MSG_REJECT', MessageSwitchTarget.group, false);

  const MessageSwitchType(this.typeName, this.target, this.enabled);

  final String typeName;
  final MessageSwitchTarget target;

  /// `true` = 开启推送，`false` = 关闭推送。
  final bool enabled;

  /// 按官方 `t` 值解析；未知返回 `null`。
  static MessageSwitchType? fromTypeName(String typeName) {
    for (final value in values) {
      if (value.typeName == typeName) return value;
    }
    return null;
  }
}

DateTime? _timestamp(Object? raw) => QqTime.tryParse(raw);
