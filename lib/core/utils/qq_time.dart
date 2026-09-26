import 'package:flutter/foundation.dart';

/// 时间解析工具。
///
/// 存在的唯一理由：**官方时间字段格式不统一**。
/// - 消息类事件（C2C_MESSAGE_CREATE、GROUP_AT_MESSAGE_CREATE 等）的 `timestamp`
///   是 RFC3339 字符串，形如 `2026-07-21T10:00:00+08:00`；
/// - 状态类事件（FRIEND_ADD、GROUP_ADD_ROBOT、GROUP_MEMBER_ADD 等）的 `timestamp`
///   是 `integer` 类型的 Unix 秒。
///
/// 如果不做统一容错，各事件解析器就会各写一套判断，最终出现某类事件时间恒为 null
/// 却不易察觉的问题。
@immutable
class QqTime {
  const QqTime._();

  /// 解析官方时间字段，同时接受两种格式。
  ///
  /// - `num`（含 `int` 与 `double`）：按 **Unix 秒** 处理；
  /// - `String`：按 **RFC3339 / ISO8601** 解析，允许带时区偏移（如 `+08:00`）或 `Z`；
  /// - 其他类型、空串、无法识别的字符串一律返回 `null`。
  ///
  /// 两点刻意设计：
  /// 1. **不抛异常**。事件解析链路中任何一条脏数据都不应中断整条事件流，
  ///    时间解析失败只应导致该字段为空；
  /// 2. **不把纯数字字符串当 Unix 秒**。官方明确标注状态类事件的 `timestamp` 是
  ///    `integer` 类型，若把 `"1784570534"` 也当时间处理，就可能把「内容里恰好是数字」
  ///    的字符串误判为时间。宁可返回 null。
  static DateTime? tryParse(Object? raw) {
    if (raw is num) {
      // 官方该字段为「Unix 秒」，Dart 的 fromMillisecondsSinceEpoch 需要毫秒。
      return DateTime.fromMillisecondsSinceEpoch(raw.toInt() * 1000);
    }
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return null;
      // 必须先做格式守门再交给 DateTime.tryParse。
      //
      // 原因（已实测）：Dart 的解析器过于宽松，会把纯数字串当作
      // 「年 + 月 + 日」的组合，例如 "1784570534" 会被解析成
      // 178457-06-03 并**成功返回**，而不是抛错。若不拦截，
      // 一个 Unix 秒字符串就会变成一个公元 18 万年的日期，
      // 且不会产生任何异常，属于最难排查的一类静默错误。
      if (!_looksLikeIso8601Date(trimmed)) return null;
      return DateTime.tryParse(trimmed);
    }
    return null;
  }

  /// 判断字符串是否以 `YYYY-MM-DD` 开头。
  ///
  /// 官方所有时间字段都使用带分隔符的 RFC3339 / ISO8601 形式，
  /// 因此不带分隔符的紧凑写法（如 `20260721`）也一并拒绝——
  /// 宁可让字段为空，也不接受来源不明的猜测。
  static bool _looksLikeIso8601Date(String value) =>
      _iso8601DatePrefix.hasMatch(value);

  /// `YYYY-MM-DD` 前缀。
  static final RegExp _iso8601DatePrefix = RegExp(r'^\d{4}-\d{2}-\d{2}');

  /// 输出合法的 RFC3339 字符串（UTC + 毫秒 + `Z` 后缀）。
  ///
  /// 统一转 UTC 的原因：Dart 的 `toIso8601String()` 对本地时间不带时区偏移，
  /// 那样的字符串不是合法 RFC3339，跨设备比对与入库排序都会出问题。
  static String toRfc3339(DateTime time) => time.toUtc().toIso8601String();
}
