import 'package:flutter/foundation.dart';

import '../../../core/utils/qq_json.dart';
import '../../../core/utils/qq_time.dart';
import '../models/ark_data.dart';
import '../models/message_attachment.dart';
import '../models/message_scene.dart';
import '../models/msg_element.dart';
import '../models/qq_user.dart';

// 事件模型全部声明在同一个 library 内（通过 part 拆分文件），
// 原因是 Dart 的 `sealed` 要求所有子类型与基类处于同一 library。
// 这样既保留了「一个事件一个文件」的可维护性，又能让上层对
// `QqEvent` 做穷尽匹配（编译器会检查 switch 是否覆盖全部子类型）。
part 'friend_events.dart';
part 'group_lifecycle_events.dart';
part 'interaction_event.dart';
part 'message_events.dart';
part 'message_switch_events.dart';
part 'parse_helpers.dart';
part 'subscribe_event.dart';
part 'unknown_event.dart';

/// QQ 事件模型基类。
///
/// 用 `sealed` 修饰的意义：**上层消费事件时必须穷尽匹配**，
/// 编译器会强制处理每一种已建模的事件类型，避免新增事件后
/// 某处 switch 忘记处理而静默丢弃。
///
/// 但事件的**产生**侧刻意不穷尽：官方事件超过 24 种且会持续新增，
/// 因此 [decode] 对未知 `t` 返回 [UnknownEvent] 而不是抛异常——
/// 一条不认识的推送绝不能让整条事件流中断。
@immutable
sealed class QqEvent {
  const QqEvent({required this.eventId, required this.seq});

  /// 事件 id —— 取自**外层 payload 的 `id`**，不是 `d.id`。
  ///
  /// 官方要求被动回复「响应事件」时把该值作为 `event_id` 传入，
  /// 与消息事件里作为 `msg_id` 的 `d.id` 是两个不同的东西。
  final String? eventId;

  /// 该事件在外层载荷中的序列号 `s`。
  ///
  /// 保留它的目的是让事件分发层能在「业务处理完成」后回写水位，
  /// 用于 Resume（官方要求记录「处理过的事件」的 `s`）。
  final int? seq;

  /// 事件类型名（外层 `t`），用于日志与去重键。
  String get typeName;

  /// 是否为需要落库到「事件日志」的机器人生命周期事件
  /// （进群、退群、成员变动、加好友等），与消息类事件区分存储。
  bool get isLifecycleEvent => false;

  /// 把 `t` + `d` 解码为具体事件模型。
  ///
  /// 设计要点：
  /// 1. `d` 不是对象时（官方在 RESUMED 中用空字符串 `""`）统一按空对象处理，
  ///    保证各 `fromJson` 不必各自判空；
  /// 2. 未知 `t` 落到 [UnknownEvent]，保留原始 JSON 以便排查与后续补建模。
  static QqEvent decode(String? type, Object? data, {String? id, int? seq}) {
    final map = _asStringKeyedMap(data);
    return switch (type) {
      // ── 单聊 / 群聊消息 ──────────────────────────────────
      'C2C_MESSAGE_CREATE' => C2cMessageCreate.fromJson(map, id, seq),
      'GROUP_AT_MESSAGE_CREATE' => GroupAtMessageCreate.fromJson(map, id, seq),
      'GROUP_MESSAGE_CREATE' => GroupMessageCreate.fromJson(map, id, seq),

      // ── 消息推送开关（用户在资料页操作）─────────────────
      // 官方对这四个事件只确认了「触发时机」与所属 intent，
      // 未在本次抓取到的页面中给出完整字段表，因此统一用一个
      // 「保留原始载荷 + 只解析通用字段」的模型承接，
      // 具体见 message_switch_events.dart 的说明。
      'C2C_MSG_RECEIVE' ||
      'C2C_MSG_REJECT' ||
      'GROUP_MSG_RECEIVE' ||
      'GROUP_MSG_REJECT' =>
        MessageSwitchEvent.fromJson(
          type: type!,
          json: map,
          eventId: id,
          seq: seq,
        ),

      // ── 群生命周期 ──────────────────────────────────────
      'GROUP_ADD_ROBOT' => GroupAddRobot.fromJson(map, id, seq),
      'GROUP_DEL_ROBOT' => GroupDelRobot.fromJson(map, id, seq),
      'GROUP_MEMBER_ADD' => GroupMemberAdd.fromJson(map, id, seq),
      'GROUP_MEMBER_REMOVE' => GroupMemberRemove.fromJson(map, id, seq),
      'GROUP_JOIN_REQUEST' => GroupJoinRequest.fromJson(map, id, seq),

      // ── 好友 ────────────────────────────────────────────
      'FRIEND_ADD' => FriendAdd.fromJson(map, id, seq),
      'FRIEND_DEL' => FriendDel.fromJson(map, id, seq),

      // ── 互动与订阅 ──────────────────────────────────────
      'INTERACTION_CREATE' => InteractionCreate.fromJson(map, id, seq),
      'SUBSCRIBE_MESSAGE_STATUS' => SubscribeMessageStatus.fromJson(map, id, seq),

      _ => UnknownEvent(type: type, raw: map, eventId: id, seq: seq),
    };
  }

  /// 官方部分事件的 `d` 为空字符串（如 RESUMED），此处统一兜底。
  static Map<String, dynamic> _asStringKeyedMap(Object? data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return data.cast<String, dynamic>();
    return const {};
  }
}
