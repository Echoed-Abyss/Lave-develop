import 'package:flutter/foundation.dart';

import '../../core/utils/qq_json.dart';
import '../../core/utils/qq_time.dart';

/// 发消息响应实体。字段逐字对照官方文档（知识库 7.1 节）。
@immutable
class SendMessageResponse {
  const SendMessageResponse({this.id, this.timestamp, this.extInfo});

  /// 消息 ID，**可用于后续撤回**。
  final String? id;

  /// 发送时间（官方标注 RFC3339 东八区）。
  final DateTime? timestamp;

  /// 扩展信息。
  final MessageExtInfo? extInfo;

  factory SendMessageResponse.fromJson(Map<String, dynamic> json) =>
      SendMessageResponse(
        id: QqJson.str(json['id']),
        timestamp: QqTime.tryParse(json['timestamp']),
        extInfo: json['ext_info'] == null
            ? null
            : MessageExtInfo.fromJson(QqJson.map(json['ext_info'])!),
      );

  /// 引用消息索引（对应消息事件 ext 里的 `msg_idx` 与 `ref_msg_idx`）。
  ///
  /// 机器人自己发送的消息，其引用目标必须用这个值，
  /// 而不是从消息事件里取（那只能取到别人发的消息）。
  String? get refIdx => extInfo?.refIdx;

  /// 是否可以撤回。
  ///
  /// 官方硬约束：**发送超过 2 分钟的消息不可撤回**（知识库 9.1 节）。
  /// 界面据此决定是否显示撤回按钮，避免用户点了才失败。
  bool canRecallAt(DateTime now) {
    final sentAt = timestamp;
    if (sentAt == null) return true;
    return now.difference(sentAt) < const Duration(minutes: 2);
  }
}

/// 官方 `MessageExtInfo`。
@immutable
class MessageExtInfo {
  const MessageExtInfo({this.refIdx});

  /// 引用消息索引。
  final String? refIdx;

  factory MessageExtInfo.fromJson(Map<String, dynamic> json) =>
      MessageExtInfo(refIdx: QqJson.str(json['ref_idx']));
}
