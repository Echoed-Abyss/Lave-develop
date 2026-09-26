part of 'qq_event.dart';

/// `INTERACTION_CREATE` —— 用户与机器人的互动事件。
///
/// 字段逐字对照官方文档（知识库 5.6 节）。
///
/// 官方关键约束：**收到事件后需调用 `PUT /interactions/{interaction_id}` 回应，
/// 否则客户端会一直 loading 直到超时**；但只有 `type = 11`（消息按钮）与
/// `type = 12`（快捷菜单）需要回应，其他类型无需回应，
/// 且同一 `interaction_id` 只能回应一次。
@immutable
class InteractionCreate extends QqEvent {
  const InteractionCreate({
    required super.eventId,
    required super.seq,
    this.id,
    this.type,
    this.scene,
    this.chatType,
    this.timestamp,
    this.guildId,
    this.channelId,
    this.userOpenid,
    this.groupOpenid,
    this.groupMemberOpenid,
    this.data,
    this.version,
    this.applicationId,
  });

  @override
  String get typeName => 'INTERACTION_CREATE';

  /// 事件 ID。官方说明用于被动消息发送和互动回调。
  ///
  /// 注意它与外层 payload 的 `id` 在本事件中通常一致，
  /// 但被动回复的 `event_id` 官方要求取**外层** id，因此分发层应使用
  /// [QqEvent.eventId]。
  final String? id;

  /// 互动类型（官方整数枚举，见 [InteractionType]）。
  final int? type;

  /// 事件发生场景：`c2c` = 单聊，`group` = 群聊，`guild` = 频道。
  final String? scene;

  /// 聊天场景（官方整数枚举，见 [InteractionChatType]）。
  final int? chatType;

  /// 触发时间（官方标注 RFC3339 格式）。
  final DateTime? timestamp;

  /// 频道 OpenID（仅频道场景有值）。
  final String? guildId;

  /// 子频道 OpenID（仅频道场景有值）。
  final String? channelId;

  /// 用户 OpenID（仅单聊场景有值）。
  final String? userOpenid;

  /// 群 OpenID（仅群聊场景有值）。
  final String? groupOpenid;

  /// 群成员 OpenID（仅群聊场景有值）。
  final String? groupMemberOpenid;

  /// 互动数据。
  final InteractionData? data;

  /// 版本号，官方默认 1。
  final int? version;

  /// 机器人 AppID。
  final String? applicationId;

  factory InteractionCreate.fromJson(
    Map<String, dynamic> json,
    String? eventId,
    int? seq,
  ) =>
      InteractionCreate(
        eventId: eventId,
        seq: seq,
        id: QqJson.str(json['id']),
        type: QqJson.integer(json['type']),
        scene: QqJson.str(json['scene']),
        chatType: QqJson.integer(json['chat_type']),
        timestamp: QqTime.tryParse(json['timestamp']),
        guildId: QqJson.str(json['guild_id']),
        channelId: QqJson.str(json['channel_id']),
        userOpenid: QqJson.str(json['user_openid']),
        groupOpenid: QqJson.str(json['group_openid']),
        groupMemberOpenid: QqJson.str(json['group_member_openid']),
        data: json['data'] == null
            ? null
            : InteractionData.fromJson(EventParse.rawMap(json['data'])),
        version: QqJson.integer(json['version']),
        applicationId: QqJson.str(json['application_id']),
      );

  /// 解析后的互动类型。
  InteractionType? get interactionType => InteractionType.fromValue(type);

  /// 解析后的聊天场景。
  InteractionChatType? get chatScene => InteractionChatType.fromValue(chatType);

  /// **是否必须回应**。
  ///
  /// 官方原文：仅 `type=11`（消息按钮）和 `type=12`（快捷菜单）
  /// 需要调用 `PUT /interactions/{interaction_id}` 回应；其他类型无需回应。
  /// 这个判断直接决定「用户会不会看到一个永远转圈的消息」，
  /// 因此做成模型上的显式属性，而不是散落在业务代码里做整数比较。
  bool get requiresAck => interactionType?.requiresAck ?? false;

  /// 会话标识（按场景取对应的 openid）。
  ///
  /// 频道场景返回 `guild_id`，单聊返回 `user_openid`，群聊返回 `group_openid`。
  String? get conversationId {
    return switch (chatScene) {
      InteractionChatType.guild => guildId,
      InteractionChatType.group => groupOpenid,
      InteractionChatType.c2c => userOpenid,
      null => userOpenid ?? groupOpenid ?? guildId,
    };
  }
}

/// 官方互动类型枚举。
enum InteractionType {
  /// 消息按钮回调（INLINE_KEYBOARD）：用户点击消息中的内联键盘按钮。
  inlineKeyboard(11, '消息按钮', requiresAck: true),

  /// 单聊快捷菜单回调（CALLBACK_COMMAND）：用户点击单聊场景下的自定义菜单。
  callbackCommand(12, '快捷菜单', requiresAck: true),

  /// 消息反馈（MESSAGE_FEEDBACK）：用户对智能体消息进行点赞/点踩反馈。
  messageFeedback(13, '消息反馈'),

  /// 清空会话（CLEAR_SESSION）：用户清空智能体会话历史。
  clearSession(14, '清空会话'),

  /// 进出故事集（IN_OUT_STORY）：用户进入或退出故事集。
  inOutStory(15, '进出故事集'),

  /// 切换模型（SWITCH_MODEL）：用户切换智能体模型。
  switchModel(16, '切换模型'),

  /// 用户授权（USER_AUTHORIZE）。
  userAuthorize(18, '用户授权'),

  /// 群授权（GROUP_AUTHORIZE）。
  groupAuthorize(19, '群授权'),

  /// 群授权状态变更（GROUP_AUTHORIZE_STATUS）。
  groupAuthorizeStatus(20, '群授权状态变更');

  const InteractionType(this.value, this.label, {this.requiresAck = false});

  final int value;
  final String label;

  /// 是否需要调用 `PUT /interactions/{id}` 回应。
  final bool requiresAck;

  static InteractionType? fromValue(int? value) {
    if (value == null) return null;
    for (final item in values) {
      if (item.value == value) return item;
    }
    return null;
  }
}

/// 官方 `chat_type` 枚举。
enum InteractionChatType {
  guild(0, '频道'),
  group(1, '群聊'),
  c2c(2, '单聊');

  const InteractionChatType(this.value, this.label);

  final int value;
  final String label;

  static InteractionChatType? fromValue(int? value) {
    if (value == null) return null;
    for (final item in values) {
      if (item.value == value) return item;
    }
    return null;
  }
}

/// 官方 `InteractionData`。
@immutable
class InteractionData {
  const InteractionData({this.type, this.resolved});

  /// 互动数据类型，官方说明与外层 `type` 含义一致。
  final int? type;

  /// 解析后的互动数据。
  final InteractionResolved? resolved;

  factory InteractionData.fromJson(Map<String, dynamic> json) =>
      InteractionData(
        type: QqJson.integer(json['type']),
        resolved: json['resolved'] == null
            ? null
            : InteractionResolved.fromJson(EventParse.rawMap(json['resolved'])),
      );
}

/// 官方 `InteractionResolved`。
@immutable
class InteractionResolved {
  const InteractionResolved({
    this.buttonData,
    this.buttonId,
    this.userId,
    this.featureId,
    this.messageId,
    this.feedbackOpt,
    this.checked,
    this.action,
    this.messageScene,
    this.authorizeData,
  });

  /// 按钮的 `data` 字段值（发送消息按钮时设置）；消息反馈场景下为回调数据。
  final String? buttonData;

  /// 按钮的 `id` 字段值。
  final String? buttonId;

  /// 操作用户 ID（仅频道场景有值）。
  final String? userId;

  /// 功能 ID（仅快捷菜单有值，管理端设置）。
  final String? featureId;

  /// 操作的消息 ID（频道场景为消息 OpenID；消息反馈场景为机器人消息 ID）。
  final String? messageId;

  /// 反馈选项（仅 `type=13` 消息反馈）：`LIKE` 点赞 / `UNLIKE` 点踩。
  final String? feedbackOpt;

  /// 反馈选项是否选中（仅 `type=13`）。
  final int? checked;

  /// 操作类型（`type=15` 故事集：`ENTER_STORY` 进入 / `QUIT_STORY` 退出；
  /// `type=16` 切换模型：对应操作动作）。
  final String? action;

  /// 消息场景信息（仅 `type=13` 消息反馈）。
  final InteractionMessageScene? messageScene;

  /// 授权数据（仅 `type=18/19` 用户 / 群授权事件）。
  final AuthorizeData? authorizeData;

  factory InteractionResolved.fromJson(Map<String, dynamic> json) =>
      InteractionResolved(
        buttonData: QqJson.str(json['button_data']),
        buttonId: QqJson.str(json['button_id']),
        userId: QqJson.str(json['user_id']),
        featureId: QqJson.str(json['feature_id']),
        messageId: QqJson.str(json['message_id']),
        feedbackOpt: QqJson.str(json['feedback_opt']),
        checked: QqJson.integer(json['checked']),
        action: QqJson.str(json['action']),
        messageScene: json['message_scene'] == null
            ? null
            : InteractionMessageScene.fromJson(
                EventParse.rawMap(json['message_scene']),
              ),
        authorizeData: json['authorize_data'] == null
            ? null
            : AuthorizeData.fromJson(
                EventParse.rawMap(json['authorize_data']),
              ),
      );

  /// 是否为点赞。
  bool get isLike => feedbackOpt == 'LIKE';

  /// 是否为点踩。
  bool get isUnlike => feedbackOpt == 'UNLIKE';
}

/// 官方 `InteractionMessageScene`。
@immutable
class InteractionMessageScene {
  const InteractionMessageScene({this.ext = const []});

  /// 扩展信息键值对列表，官方举例 `disable_net_search=1` 表示关闭联网搜索。
  final List<String> ext;

  factory InteractionMessageScene.fromJson(Map<String, dynamic> json) {
    final raw = json['ext'];
    if (raw is! List) return const InteractionMessageScene();
    return InteractionMessageScene(
      ext: raw
          .map((e) => e?.toString() ?? '')
          .where((e) => e.isNotEmpty)
          .toList(growable: false),
    );
  }

  /// 是否关闭了联网搜索（官方示例键值）。
  bool get isNetSearchDisabled => ext.contains('disable_net_search=1');
}

/// 官方 `AuthorizeData` —— 授权数据。
@immutable
class AuthorizeData {
  const AuthorizeData({this.optScene, this.scope});

  /// 授权操作场景：`setting` = 资料页设置，`dialog` = 弹窗授权。
  final String? optScene;

  /// 授权范围：`c2c_push` = C2C 主动消息推送，`group_push` = 群主动消息推送。
  final String? scope;

  factory AuthorizeData.fromJson(Map<String, dynamic> json) => AuthorizeData(
        optScene: QqJson.str(json['opt_scene']),
        scope: QqJson.str(json['scope']),
      );

  /// 是否为单聊主动消息推送授权。
  bool get isC2cPush => scope == 'c2c_push';

  /// 是否为群主动消息推送授权。
  bool get isGroupPush => scope == 'group_push';

  /// 中文描述，供界面与日志使用。
  String get scopeLabel => switch (scope) {
        'c2c_push' => '单聊主动消息推送',
        'group_push' => '群主动消息推送',
        _ => scope ?? '未知授权范围',
      };
}
