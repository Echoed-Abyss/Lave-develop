part of 'qq_event.dart';

/// `SUBSCRIBE_MESSAGE_STATUS` —— 订阅消息授权状态变更。
///
/// 官方触发时机原文：用户对订阅消息模板的授权状态发生变化时触发。
/// 可用于判断用户是否允许/拒绝接收某个订阅消息模板。
/// 字段逐字对照官方文档（知识库 5.6 节）。
@immutable
class SubscribeMessageStatus extends QqEvent {
  const SubscribeMessageStatus({
    required super.eventId,
    required super.seq,
    this.groupOpenid,
    this.openid,
    this.result = const [],
  });

  @override
  String get typeName => 'SUBSCRIBE_MESSAGE_STATUS';

  @override
  bool get isLifecycleEvent => true;

  /// 群 OpenID（群订阅场景时有值）。
  final String? groupOpenid;

  /// 用户 OpenID（个人订阅场景时有值）。
  final String? openid;

  /// 各模板的授权结果列表。
  final List<SubscribeMsgTemplateResult> result;

  factory SubscribeMessageStatus.fromJson(
    Map<String, dynamic> json,
    String? eventId,
    int? seq,
  ) =>
      SubscribeMessageStatus(
        eventId: eventId,
        seq: seq,
        groupOpenid: QqJson.str(json['group_openid']),
        openid: QqJson.str(json['openid']),
        result: QqJson.list(
              json['result'],
              SubscribeMsgTemplateResult.fromJson,
            ) ??
            const [],
      );

  /// 是否为群订阅场景。
  bool get isGroupSubscription => groupOpenid != null && groupOpenid!.isNotEmpty;

  /// 已授权（允许订阅）的模板。
  List<SubscribeMsgTemplateResult> get granted =>
      result.where((e) => e.isGranted).toList(growable: false);

  /// 已拒绝订阅的模板。
  List<SubscribeMsgTemplateResult> get rejected =>
      result.where((e) => e.isRejected).toList(growable: false);
}

/// 官方 `SubscribeMsgTemplateResult`。
@immutable
class SubscribeMsgTemplateResult {
  const SubscribeMsgTemplateResult({
    this.templateId,
    this.customTemplateId,
    this.op,
    this.subscribeId,
    this.subscribeTs,
    this.updateTs,
  });

  /// 平台提供的订阅模板 ID。
  final int? templateId;

  /// 自定义订阅模板 ID。
  final String? customTemplateId;

  /// 用户操作：1 = 允许订阅，2 = 拒绝订阅。
  final int? op;

  /// 订阅 ID，发送订阅消息时需使用。
  final String? subscribeId;

  /// 订阅操作时间戳（Unix 秒）。
  final int? subscribeTs;

  /// 订阅状态最后更新时间戳（Unix 秒）。
  final int? updateTs;

  factory SubscribeMsgTemplateResult.fromJson(Map<String, dynamic> json) =>
      SubscribeMsgTemplateResult(
        templateId: QqJson.integer(json['template_id']),
        customTemplateId: QqJson.str(json['custom_template_id']),
        op: QqJson.integer(json['op']),
        subscribeId: QqJson.str(json['subscribe_id']),
        subscribeTs: QqJson.integer(json['subscribe_ts']),
        updateTs: QqJson.integer(json['update_ts']),
      );

  /// 用户是否允许订阅（官方 `op = 1`）。
  bool get isGranted => op == 1;

  /// 用户是否拒绝订阅（官方 `op = 2`）。
  bool get isRejected => op == 2;

  /// 订阅操作时间。
  DateTime? get subscribeAt => subscribeTs == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(subscribeTs! * 1000);

  /// 状态最后更新时间。
  DateTime? get updatedAt => updateTs == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(updateTs! * 1000);
}
