import 'package:flutter/foundation.dart';

/// 机器人生命周期事件类别。
///
/// 用途：需求要求「事件日志：记录进群、退群、@机器人等事件」。
/// 消息类事件已经在消息列表里，不需要重复记录；这里只承载
/// **状态变更类**事件，两者分开存的好处是日志页可以只按类别筛选，
/// 不被海量消息淹没。
enum BotEventKind {
  /// 机器人被拉进群。
  groupAddRobot('机器人入群'),

  /// 机器人被移出群。
  groupDelRobot('机器人退群'),

  /// 群成员加入。
  groupMemberAdd('群成员加入'),

  /// 群成员退出。
  groupMemberRemove('群成员退出'),

  /// 用户申请加群（仅机器人是群管理员时才会收到）。
  groupJoinRequest('加群申请'),

  /// 用户添加机器人为好友。
  friendAdd('添加好友'),

  /// 用户删除机器人好友。
  friendDel('删除好友'),

  /// 单聊主动消息推送被开启 / 关闭。
  c2cPushSwitchOn('单聊推送开启'),
  c2cPushSwitchOff('单聊推送关闭'),

  /// 群主动消息推送被开启 / 关闭。
  groupPushSwitchOn('群推送开启'),
  groupPushSwitchOff('群推送关闭'),

  /// 互动事件（按钮点击、快捷菜单、授权等）。
  interaction('互动'),

  /// 订阅消息授权状态变更。
  subscribeStatus('订阅授权'),

  /// 官方新增而本地尚未建模的事件（保留原始类型名）。
  unknown('未识别事件');

  const BotEventKind(this.label);

  /// 界面展示用的中文类别名。
  final String label;

  /// 是否为「需要用户关注」的事件（例如加群申请、推送被关闭）。
  ///
  /// 用于在日志页做视觉强调：推送被关闭这类事件如果被淹没在普通日志里，
  /// 用户会一直困惑「为什么我的机器人发不出主动消息」。
  bool get isNoteworthy =>
      this == BotEventKind.groupJoinRequest ||
      this == BotEventKind.c2cPushSwitchOff ||
      this == BotEventKind.groupPushSwitchOff ||
      this == BotEventKind.unknown;
}

/// 机器人生命周期事件。
///
/// 字段设计刻意保持「扁平 + 通用」：不同事件的原始 JSON 结构差异很大
/// （有的带 `user_openid`、有的带 `join_request_id`），
/// 但日志页只需要统一的几个维度：时间、类别、涉及对象、摘要、原始载荷。
@immutable
class BotEvent {
  const BotEvent({
    required this.botId,
    required this.kind,
    required this.at,
    this.id,
    this.groupOpenid,
    this.actorOpenid,
    this.actorName,
    this.summary,
    this.eventId,
    this.rawEventType,
    this.raw,
  });

  /// 本地自增主键。
  final int? id;

  /// 所属机器人 AppID。
  final String botId;

  /// 事件类别。
  final BotEventKind kind;

  /// 事件时间（已归一）。
  final DateTime at;

  /// 群 OpenID（群相关事件有值）。
  final String? groupOpenid;

  /// 涉及的用户 OpenID（可能为空，例如退群场景）。
  final String? actorOpenid;

  /// 涉及的昵称（可能为空）。
  final String? actorName;

  /// 一句话摘要，直接用于日志页展示。
  final String? summary;

  /// 外层 event id。
  final String? eventId;

  /// 官方原始事件类型（`t`）。用于未建模事件与排查。
  final String? rawEventType;

  /// 官方原始载荷（仅未建模事件保留，避免无节制膨胀数据库）。
  final Map<String, dynamic>? raw;

  /// 展示文本：摘要缺失时按类别与对象拼一句。
  String get displayText {
    final text = summary?.trim();
    if (text != null && text.isNotEmpty) return text;
    final who = actorName?.trim();
    if (who != null && who.isNotEmpty) {
      return '${kind.label}：$who';
    }
    if (groupOpenid != null) {
      return '${kind.label}（群 ${_shortId(groupOpenid!)}）';
    }
    return kind.label;
  }

  /// 是否需要在日志页高亮。
  bool get isHighlighted => kind.isNoteworthy;

  static String _shortId(String value) =>
      value.length <= 6 ? value : '…${value.substring(value.length - 6)}';
}
