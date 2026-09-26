import 'package:flutter/foundation.dart';

import '../../../core/utils/qq_json.dart';
import 'ark_data.dart';
import 'message_attachment.dart';
import 'qq_user.dart';

/// 官方 `MsgElement` —— 消息元素。
///
/// 官方在 `message_type = 103`（引用消息）时通过 `msg_elements`
/// 携带被引用的内容（知识库 5.1 节）。
///
/// **官方明确定义为递归结构**（`msg_elements` 字段的说明是
/// 「嵌套消息元素列表（递归结构）」），因此本类自嵌套。
/// 解析时限制最大深度，避免官方数据异常导致栈溢出——
/// 官方未给出深度上限，属于需要自行设防的点。
@immutable
class MsgElement {
  const MsgElement({
    this.msgIdx,
    this.author,
    this.messageType,
    this.content,
    this.attachments,
    this.arkData,
    this.msgElements,
  });

  /// 消息元素在列表中的引用消息索引。
  final String? msgIdx;

  /// 该元素对应的消息发送者。
  final QqUser? author;

  /// 消息内容类型（与事件体 `message_type` 同一枚举）。
  final int? messageType;

  /// 消息正文内容。官方示例中并行消息会用 `=== 消息 N ===` 的形式拼接多段。
  final String? content;

  /// 该元素携带的附件。
  final List<MessageAttachment>? attachments;

  /// 该元素携带的结构化卡片。
  final ArkData? arkData;

  /// 嵌套消息元素列表（递归）。
  final List<MsgElement>? msgElements;

  /// 递归解析的最大深度。
  ///
  /// 官方未定义深度上限，这里设一个保守值：超过后截断而不是继续递归。
  /// 目的是防止异常数据造成无限递归（现实中出现过平台侧数据异常的先例）。
  static const int maxDepth = 8;

  factory MsgElement.fromJson(Map<String, dynamic> json) =>
      MsgElement.fromJsonAtDepth(json, 0);

  /// 带深度限制的解析入口。
  factory MsgElement.fromJsonAtDepth(Map<String, dynamic> json, int depth) {
    if (depth >= maxDepth) {
      // 超深时只保留本层可读内容，丢弃更深的嵌套。
      return MsgElement(
        msgIdx: QqJson.str(json['msg_idx']),
        messageType: QqJson.integer(json['message_type']),
        content: QqJson.str(json['content']),
      );
    }
    return MsgElement(
      msgIdx: QqJson.str(json['msg_idx']),
      author: json['author'] == null
          ? null
          : QqUser.fromJson(QqJson.map(json['author'])!),
      messageType: QqJson.integer(json['message_type']),
      content: QqJson.str(json['content']),
      attachments: QqJson.list(json['attachments'], MessageAttachment.fromJson),
      arkData: json['ark_data'] == null
          ? null
          : ArkData.fromJson(QqJson.map(json['ark_data'])!),
      msgElements: _parseNested(json['msg_elements'], depth),
    );
  }

  static List<MsgElement>? _parseNested(Object? raw, int depth) {
    if (raw is! List) return null;
    final result = <MsgElement>[];
    for (final item in raw) {
      final map = QqJson.map(item);
      if (map == null) continue;
      result.add(MsgElement.fromJsonAtDepth(map, depth + 1));
    }
    return result;
  }
}
