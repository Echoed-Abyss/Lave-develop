part of 'qq_event.dart';

/// 群与成员相关的生命周期事件。
///
/// 字段逐字对照官方文档（知识库 5.4 节）。
/// 全部归为「事件日志」类（[QqEvent.isLifecycleEvent] 为 `true`），
/// 与消息类事件分开落库。

/// `GROUP_ADD_ROBOT` —— 机器人被添加到群聊。
///
/// 官方触发时机：机器人被添加到群聊时触发。
/// 官方允许用它作为被动回复的 `event_id`。
@immutable
class GroupAddRobot extends QqEvent {
  const GroupAddRobot({
    required super.eventId,
    required super.seq,
    this.timestamp,
    this.groupOpenid,
    this.opMemberOpenid,
  });

  @override
  String get typeName => 'GROUP_ADD_ROBOT';

  @override
  bool get isLifecycleEvent => true;

  /// 加入时间（官方标注为 **Unix 秒整数**）。
  final DateTime? timestamp;

  /// 群 OpenID。
  final String? groupOpenid;

  /// 操作添加机器人进群的群成员 OpenID。
  final String? opMemberOpenid;

  factory GroupAddRobot.fromJson(
    Map<String, dynamic> json,
    String? eventId,
    int? seq,
  ) =>
      GroupAddRobot(
        eventId: eventId,
        seq: seq,
        timestamp: QqTime.tryParse(json['timestamp']),
        groupOpenid: QqJson.str(json['group_openid']),
        opMemberOpenid: QqJson.str(json['op_member_openid']),
      );
}

/// `GROUP_DEL_ROBOT` —— 机器人被移出群聊。
@immutable
class GroupDelRobot extends QqEvent {
  const GroupDelRobot({
    required super.eventId,
    required super.seq,
    this.timestamp,
    this.groupOpenid,
    this.opMemberOpenid,
  });

  @override
  String get typeName => 'GROUP_DEL_ROBOT';

  @override
  bool get isLifecycleEvent => true;

  /// 移除时间（官方标注为 Unix 秒整数）。
  final DateTime? timestamp;

  /// 群 OpenID。
  final String? groupOpenid;

  /// 操作移除机器人退群的群成员 OpenID。
  final String? opMemberOpenid;

  factory GroupDelRobot.fromJson(
    Map<String, dynamic> json,
    String? eventId,
    int? seq,
  ) =>
      GroupDelRobot(
        eventId: eventId,
        seq: seq,
        timestamp: QqTime.tryParse(json['timestamp']),
        groupOpenid: QqJson.str(json['group_openid']),
        opMemberOpenid: QqJson.str(json['op_member_openid']),
      );
}

/// `GROUP_MEMBER_ADD` —— 有新成员加入群聊。
///
/// intent：`GROUP_MEMBER_EVENT (1<<24)`。
/// **该位未出现在官方 intents 清单中**，只出现在各群成员事件页的 Intent 字段里，
/// 属于知识库第 11 章的「官方内部不一致」项。
@immutable
class GroupMemberAdd extends QqEvent {
  const GroupMemberAdd({
    required super.eventId,
    required super.seq,
    this.timestamp,
    this.groupOpenid,
    this.memberOpenid,
    this.userOpenid,
  });

  @override
  String get typeName => 'GROUP_MEMBER_ADD';

  @override
  bool get isLifecycleEvent => true;

  /// 事件时间（Unix 秒整数）。
  final DateTime? timestamp;

  /// 群 OpenID。
  final String? groupOpenid;

  /// 新加入成员的 OpenID。
  final String? memberOpenid;

  /// 新成员的用户 OpenID（官方标注：跨应用统一标识，可能为空）。
  final String? userOpenid;

  factory GroupMemberAdd.fromJson(
    Map<String, dynamic> json,
    String? eventId,
    int? seq,
  ) =>
      GroupMemberAdd(
        eventId: eventId,
        seq: seq,
        timestamp: QqTime.tryParse(json['timestamp']),
        groupOpenid: QqJson.str(json['group_openid']),
        memberOpenid: QqJson.str(json['member_openid']),
        userOpenid: QqJson.str(json['user_openid']),
      );
}

/// `GROUP_MEMBER_REMOVE` —— 群成员退出或被移出群聊。
///
/// 字段结构与 [GroupMemberAdd] 相同，仅语义相反
/// （官方页面重复给出同一张字段表）。
@immutable
class GroupMemberRemove extends GroupMemberAdd {
  const GroupMemberRemove({
    required super.eventId,
    required super.seq,
    super.timestamp,
    super.groupOpenid,
    super.memberOpenid,
    super.userOpenid,
  });

  @override
  String get typeName => 'GROUP_MEMBER_REMOVE';

  factory GroupMemberRemove.fromJson(
    Map<String, dynamic> json,
    String? eventId,
    int? seq,
  ) {
    final base = GroupMemberAdd.fromJson(json, eventId, seq);
    return GroupMemberRemove(
      eventId: base.eventId,
      seq: base.seq,
      timestamp: base.timestamp,
      groupOpenid: base.groupOpenid,
      memberOpenid: base.memberOpenid,
      userOpenid: base.userOpenid,
    );
  }
}

/// `GROUP_JOIN_REQUEST` —— 用户申请加群。
///
/// 官方触发时机原文：用户申请加群请求触发此事件。
/// **1. 只有当机器人是群管理员时才可以收到此事件。**
@immutable
class GroupJoinRequest extends QqEvent {
  const GroupJoinRequest({
    required super.eventId,
    required super.seq,
    this.groupOpenid,
    this.joinRequestId,
    this.riskTips,
    this.unionOpenid,
    this.memberOpenid,
    this.username,
    this.applyAt,
    this.applySource,
    this.invitedBy,
    this.bot,
    this.verifyInfo,
    this.autoApproved,
  });

  @override
  String get typeName => 'GROUP_JOIN_REQUEST';

  @override
  bool get isLifecycleEvent => true;

  /// 群 OpenID。
  final String? groupOpenid;

  /// 申请 ID，需要在申请接口回传。
  final String? joinRequestId;

  /// 安全提示语。官方说明：可疑消息直接返回 `warning_tips`；
  /// 普通消息命中 `sec_risk_rules` 时返回 `top_tips`。
  final String? riskTips;

  /// 用户在应用 / 开放平台下的统一标识（如有）。
  final String? unionOpenid;

  /// 申请人 OpenID。
  final String? memberOpenid;

  /// 申请人昵称。
  final String? username;

  /// 申请时间（官方标注 RFC3339 格式）。
  final DateTime? applyAt;

  /// 申请来源：`self_apply` 主动申请，`invited` 被邀请。
  final String? applySource;

  /// 邀请人 OpenID（`apply_source = invited` 时有效）。
  final String? invitedBy;

  /// 是否为机器人账号。
  final bool? bot;

  /// 用户入群验证方式。
  final VerifyInfo? verifyInfo;

  /// 自动审批通过的扩展信息。官方标注：**只有在下行事件中会携带**。
  final AutoApproved? autoApproved;

  factory GroupJoinRequest.fromJson(
    Map<String, dynamic> json,
    String? eventId,
    int? seq,
  ) =>
      GroupJoinRequest(
        eventId: eventId,
        seq: seq,
        groupOpenid: QqJson.str(json['group_openid']),
        joinRequestId: QqJson.str(json['join_request_id']),
        riskTips: QqJson.str(json['risk_tips']),
        unionOpenid: QqJson.str(json['union_openid']),
        memberOpenid: QqJson.str(json['member_openid']),
        username: QqJson.str(json['username']),
        applyAt: QqTime.tryParse(json['apply_at']),
        applySource: QqJson.str(json['apply_source']),
        invitedBy: QqJson.str(json['invited_by']),
        bot: QqJson.boolean(json['bot']),
        verifyInfo: json['verify_info'] == null
            ? null
            : VerifyInfo.fromJson(EventParse.rawMap(json['verify_info'])),
        autoApproved: json['auto_approved'] == null
            ? null
            : AutoApproved.fromJson(EventParse.rawMap(json['auto_approved'])),
      );

  /// 是否为被邀请入群。
  bool get isInvited => applySource == 'invited';

  /// 是否命中安全风险提示（界面应显著提示管理员）。
  bool get hasRiskTip => riskTips != null && riskTips!.isNotEmpty;
}

/// 官方 `VerifyInfo` —— 用户入群验证方式。
@immutable
class VerifyInfo {
  const VerifyInfo({this.method, this.verifyMessage, this.reviewQaList});

  /// 入群验证方式：`verify_message` / `admin_review_qa`。
  ///
  /// 注意官方文档存在一处笔误：字段说明里写到「仅 auth_type=xxx 时可能携带」，
  /// 而字段本身名为 `method`。这里按字段名 `method` 实现，
  /// 并保留对 `auth_type` 的兼容读取（见 [VerifyInfo.fromJson]）。
  final String? method;

  /// 验证消息内容。
  final String? verifyMessage;

  /// 问答列表（管理员设置问题、申请人填写答案）。
  final List<ReviewQa>? reviewQaList;

  factory VerifyInfo.fromJson(Map<String, dynamic> json) {
    // 兼容 `method` 与官方说明文字中的 `auth_type` 两种键名。
    final method = QqJson.str(json['method']) ?? QqJson.str(json['auth_type']);
    return VerifyInfo(
      method: method,
      verifyMessage: QqJson.str(json['verify_message']),
      reviewQaList: QqJson.list(json['review_qa_list'], ReviewQa.fromJson),
    );
  }

  /// 是否为问答验证。
  bool get isQaReview => method == 'admin_review_qa';

  /// 是否为验证消息。
  bool get isMessageVerify => method == 'verify_message';
}

/// 官方 `ReviewQA`。
@immutable
class ReviewQa {
  const ReviewQa({this.question, this.answer});

  /// 管理员设置的问题。
  final String? question;

  /// 申请人填写的答案。
  final String? answer;

  factory ReviewQa.fromJson(Map<String, dynamic> json) => ReviewQa(
        question: QqJson.str(json['question']),
        answer: QqJson.str(json['answer']),
      );
}

/// 官方 `AutoAppproved`（保持官方拼写）。
@immutable
class AutoApproved {
  const AutoApproved({this.strategyId});

  /// 自动审批通过的策略 ID。
  final String? strategyId;

  factory AutoApproved.fromJson(Map<String, dynamic> json) =>
      AutoApproved(strategyId: QqJson.str(json['strategy_id']));
}
