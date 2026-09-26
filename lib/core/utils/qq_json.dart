import 'package:flutter/foundation.dart';

/// JSON 安全取值助手。
///
/// 官方接口返回的 JSON 存在若干「类型不稳定」的情况，直接 `as` 强转会崩：
/// - `expires_in` 官方文档标为 number，但示例里是字符串 `"7200"`；
/// - `message_type`、`file_type`、`size` 等在文档里是 integer，实际可能是 num；
/// - 可选字段在未命中时可能整个缺失，也可能是显式 `null`；
/// - `message_scene.ext` 是字符串数组而非对象。
///
/// 因此所有协议模型的 `fromJson` 一律走本工具的取值方法，
/// 绝不直接 `json['x'] as int`。
@immutable
class QqJson {
  const QqJson._();

  /// 取字符串。
  ///
  /// **只接受 `String`，不做隐式转换**：`message_type` 之类的数字字段若被转成字符串，
  /// 会在下游解析时产生难以定位的类型问题。官方文档中 `union_openid` 等字段
  /// 明确「可能为空」，因此空字符串会原样返回而不是视为缺失。
  static String? str(Object? raw) => raw is String ? raw : null;

  /// 取整数，容忍三种官方实际形态：整数、浮点数、数字字符串。
  ///
  /// 浮点数按 Dart 的 `toInt()` 规则向零截断。
  /// 无法解析时返回 `null`，不抛异常。
  static int? integer(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return null;
      // 官方 expires_in 示例为字符串 "7200"，故先试整数再试浮点。
      return int.tryParse(trimmed) ?? double.tryParse(trimmed)?.toInt();
    }
    return null;
  }

  /// 取布尔值，容忍官方实际可能出现的四种形态：`bool`、`"true"/"false"`、`1/0`。
  ///
  /// 除上述之外一律返回 `null`：宁可让字段为空，也不要凭猜测把 `2` 当成 `true`。
  static bool? boolean(Object? raw) {
    if (raw is bool) return raw;
    if (raw is num) {
      if (raw == 1) return true;
      if (raw == 0) return false;
      return null;
    }
    if (raw is String) {
      final normalized = raw.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1') return true;
      if (normalized == 'false' || normalized == '0') return false;
    }
    return null;
  }

  /// 取对象。非 `Map` 一律返回 `null`（数组、字符串、null 都不是对象）。
  static Map<String, dynamic>? map(Object? raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return raw.cast<String, dynamic>();
    return null;
  }

  /// 取对象数组并映射为模型列表。
  ///
  /// 返回值的语义刻意区分：
  /// - 输入为 `null`（官方未携带该字段）→ 返回 `null`，让调用方能够区分
  ///   「平台没给这个字段」与「平台给了但内容为空」；
  /// - 输入为列表 → 返回映射结果；**元素不是对象时跳过**，避免单条脏数据
  ///   导致整个 `attachments` 数组解析失败。
  static List<T>? list<T>(
    Object? raw,
    T Function(Map<String, dynamic> json) fromJson,
  ) {
    if (raw is! List) return null;
    final result = <T>[];
    for (final item in raw) {
      final map = QqJson.map(item);
      if (map == null) continue;
      result.add(fromJson(map));
    }
    return result;
  }
}
