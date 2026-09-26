part of 'qq_event.dart';

/// 事件解析的共用小助手。
///
/// 抽出来的原因：几乎每个事件都含 `author`、`message_scene`、`ark_data`
/// 这类「可空子对象」，如果每个事件文件各写一遍判空逻辑，
/// 迟早会出现某处忘了判空而在 `map == null` 时抛异常。
abstract final class EventParse {
  EventParse._();

  /// 解析可空的 `User` 子对象。
  static QqUser? user(Object? raw) {
    final map = QqJson.map(raw);
    return map == null ? null : QqUser.fromJson(map);
  }

  /// 解析可空的 `User` 数组。
  static List<QqUser>? users(Object? raw) => QqJson.list(raw, QqUser.fromJson);

  /// 解析可空的 `MessageScene` 子对象。
  static MessageScene? scene(Object? raw) {
    final map = QqJson.map(raw);
    return map == null ? null : MessageScene.fromJson(map);
  }

  /// 解析可空的 `ARKData` 子对象。
  static ArkData? ark(Object? raw) {
    final map = QqJson.map(raw);
    return map == null ? null : ArkData.fromJson(map);
  }

  /// 把不可识别的 `d` 归一为对象。
  ///
  /// 用于字段表未完全确定的事件：保留原始 JSON，便于后续补建模与排查。
  static Map<String, dynamic> rawMap(Object? raw) =>
      QqJson.map(raw) ?? const {};

  /// 从原始 JSON 中尽力提取一个字符串字段。
  static String? pick(Object? raw, String key) =>
      QqJson.str(rawMap(raw)[key]);
}

/// 供事件模型复用的不可变原始载荷包装。
///
/// 设计意图：当官方事件的具体字段表尚未确认（例如 C2C_MSG_RECEIVE
/// 这类只确认了触发时机的事件）时，**不能凭印象编造字段名**，
/// 但也不能丢弃内容。做法是把原始 JSON 原样保留下来，
/// 同时尽力解析几个跨事件通用的字段（时间、id）。
@immutable
class RawEventPayload {
  const RawEventPayload(this.raw);

  /// 官方原始 `d` 对象。
  final Map<String, dynamic> raw;

  /// 尽力提取 `timestamp`（官方在不同事件里可能是 RFC3339 或 Unix 秒）。
  Object? get timestamp => raw['timestamp'];

  /// 尽力提取用户 OpenID。
  String? get openid => QqJson.str(raw['openid']);

  /// 尽力提取群 OpenID。
  String? get groupOpenid => QqJson.str(raw['group_openid']);

  /// 取任意字段的字符串形式。
  String? str(String key) => QqJson.str(raw[key]);

  /// 该事件是否携带了任何可用字段。
  bool get isEmpty => raw.isEmpty;
}
