import 'package:flutter/foundation.dart';

import '../../../core/utils/qq_json.dart';

/// 官方 `MessageScene` —— 消息场景上下文。
///
/// 官方字段说明（知识库 5.1 节）：
/// - `source`：场景来源，`default` = 默认聊天窗口；
/// - `ext`：扩展数据列表，**`key=value` 格式的字符串数组**，
///   已知三个 key：`msg_idx`（消息索引）、`ref_msg_idx`（引用的消息索引）、
///   `auth_token`（鉴权令牌）。
///
/// 关键点：`ext` 在官方 JSON 里是**字符串数组而非对象**，形如：
/// ```json
/// "ext": ["msg_idx=REFIDX_xxxxxxxxxxxxxxx==", "auth_token=xxxx"]
/// ```
/// 因此必须先解析成 Map 才能使用。这里保留原始数组与解析结果两种视图：
/// 解析后的 Map 供业务读取，原始数组供「引用回复」时回填使用
/// （官方 `MessageReference.message_id` 需要 `msg_idx` 的原值）。
@immutable
class MessageScene {
  const MessageScene({this.source, this.ext = const {}, this.rawExt = const []});

  /// 场景来源。官方：`default` = 默认聊天窗口。
  final String? source;

  /// 解析后的扩展数据（`key=value` 拆解结果）。
  final Map<String, String> ext;

  /// 官方原始 `ext` 数组，用于原样回填。
  final List<String> rawExt;

  /// 消息索引。官方要求用它做消息去重（「需结合 message_scene.ext 中的
  /// msg_idx 做去重」），也是引用回复时的目标消息标识来源。
  String? get msgIdx => ext['msg_idx'];

  /// 被引用消息的索引。仅在 `message_type = 103`（引用消息）时出现。
  String? get refMsgIdx => ext['ref_msg_idx'];

  /// 鉴权令牌。官方在群聊事件中下发，供需要鉴权的后续操作使用。
  String? get authToken => ext['auth_token'];

  /// 是否为引用消息（官方：`message_type=103` 时 ext 含 `ref_msg_idx`）。
  bool get isQuote => refMsgIdx != null;

  factory MessageScene.fromJson(Map<String, dynamic> json) {
    // `ext` 是字符串数组，不能走 QqJson.list（它按 Map 元素映射）。
    final raw = json['ext'];
    final normalized = <String>[];
    if (raw is List) {
      for (final item in raw) {
        final text = item?.toString() ?? '';
        if (text.isNotEmpty) normalized.add(text);
      }
    }
    return MessageScene(
      source: QqJson.str(json['source']),
      ext: _parseKeyValuePairs(normalized),
      rawExt: normalized,
    );
  }

  /// 把 `["k1=v1", "k2=v2"]` 解析为 `{k1: v1, k2: v2}`。
  ///
  /// 只按**第一个** `=` 切分：`auth_token` 之类的值可能自身包含 `=` 或 `+`
  /// （base64 形态），按最后一个等号切分会截断令牌。
  /// 无法解析的条目直接跳过，不抛异常。
  static Map<String, String> _parseKeyValuePairs(List<String> entries) {
    final result = <String, String>{};
    for (final entry in entries) {
      final separator = entry.indexOf('=');
      if (separator <= 0) continue;
      final key = entry.substring(0, separator).trim();
      if (key.isEmpty) continue;
      result[key] = entry.substring(separator + 1);
    }
    return result;
  }
}
