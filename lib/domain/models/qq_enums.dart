/// 领域层枚举。
///
/// 这些枚举是**官方文档中散落各处的数值枚举的规范化形式**，供 api 层与 UI 层共用。
/// 每个枚举都保留 `fromValue` 并在未知取值时返回 `null`——
/// 官方文档明确存在「同一枚举在不同页面列举不一致」的情况（见知识库 11.1 节），
/// 因此**必须假设会出现文档没写的取值**，不能抛异常。
library;

/// 发送侧消息类型（官方 `msg_type`）。
///
/// 官方 `type/overview.html` 只列出 0/2/7，而发消息接口的请求体说明写 0/2/3/4/7，
/// 单聊接口实务上还接受 6（输入中状态）。本项目按**接口页**口径实现，
/// 并对不支持的取值在发送前拦截。
enum QqSendMsgType {
  /// 纯文本，内容字段为 `content`。
  text(0, '纯文本'),

  /// Markdown，内容字段为 `markdown`（官方标注模板类字段已废弃，走原生 content）。
  markdown(2, 'Markdown'),

  /// 输入中状态，内容字段为 `input_notify`。仅单聊可用。
  inputNotify(6, '输入中状态'),

  /// 富媒体，内容字段为 `media`（需先上传拿 `file_info`）。
  media(7, '富媒体');

  const QqSendMsgType(this.value, this.label);

  final int value;
  final String label;

  /// 按官方数值解析；未知取值返回 `null`。
  static QqSendMsgType? fromValue(int? value) {
    if (value == null) return null;
    for (final type in values) {
      if (type.value == value) return type;
    }
    return null;
  }
}

/// 接收侧消息内容类型（官方 `message_type`）。
///
/// 官方对 101（并行消息）与 102（聊天记录）**只给了枚举值，没给 JSON 结构**，
/// 因此本枚举保留其取值但 UI 侧只能降级展示。
enum QqRecvMsgType {
  /// 普通文本，内容在 `content`。
  text(0, '普通文本'),

  /// 结构化卡片，内容在 `ark_data`。
  ark(3, '结构化卡片'),

  /// 并行消息。官方未提供结构。
  parallel(101, '并行消息'),

  /// 聊天记录。官方未提供结构。
  chatRecord(102, '聊天记录'),

  /// 引用消息，内容在 `msg_elements`。
  quote(103, '引用消息');

  const QqRecvMsgType(this.value, this.label);

  final int value;
  final String label;

  /// 按官方数值解析；未知取值返回 `null`（调用方应降级为纯文本摘要展示）。
  static QqRecvMsgType? fromValue(int? value) {
    if (value == null) return null;
    for (final type in values) {
      if (type.value == value) return type;
    }
    return null;
  }

  /// 官方未提供 JSON 结构、只能降级展示的类型。
  bool get isStructureUnknown => this == parallel || this == chatRecord;
}

/// 富媒体文件类型（官方 `file_type`）及其官方大小限制。
///
/// 官方规则：**超过软限制会降级为文件类型上传，超过硬限制会报错。**
enum QqMediaFileType {
  /// 图片：官方支持 png / jpg，软限制 20MB，硬限制 200MB。
  image(1, label: '图片', formats: 'png/jpg', softLimitMb: 20, hardLimitMb: 200),

  /// 视频：官方支持 mp4，软限制 30MB，硬限制 200MB。
  video(2, label: '视频', formats: 'mp4', softLimitMb: 30, hardLimitMb: 200),

  /// 语音：官方支持 silk，软限制 20MB，硬限制 200MB。
  audio(3, label: '语音', formats: 'silk', softLimitMb: 20, hardLimitMb: 200),

  /// 文件：任意格式，软硬限制均为 200MB。
  file(4, label: '文件', formats: '任意', softLimitMb: 200, hardLimitMb: 200);

  const QqMediaFileType(
    this.value, {
    required this.label,
    required this.formats,
    required this.softLimitMb,
    required this.hardLimitMb,
  });

  final int value;
  final String label;

  /// 官方允许的格式描述。
  final String formats;

  /// 软限制（MB）：超过后平台会降级为文件类型上传。
  final int softLimitMb;

  /// 硬限制（MB）：超过后平台直接报错。
  final int hardLimitMb;

  /// 软限制字节数。
  int get softLimitBytes => softLimitMb * 1024 * 1024;

  /// 硬限制字节数。
  int get hardLimitBytes => hardLimitMb * 1024 * 1024;

  /// 按官方数值解析；未知取值返回 `null`。
  static QqMediaFileType? fromValue(int? value) {
    if (value == null) return null;
    for (final type in values) {
      if (type.value == value) return type;
    }
    return null;
  }
}

/// 群内角色（官方 `member_role`）。
enum GroupRole {
  member('member', '普通成员'),
  admin('admin', '管理员'),
  owner('owner', '群主');

  const GroupRole(this.value, this.label);

  final String value;
  final String label;

  static GroupRole? fromValue(String? value) {
    if (value == null || value.isEmpty) return null;
    for (final role in values) {
      if (role.value == value) return role;
    }
    return null;
  }

  /// 群管理员或群主——官方明确「只有当机器人是群管理员时才可以收到加群申请事件」，
  /// 因此该判定会影响能力可用性。
  bool get isAdminOrOwner => this == admin || this == owner;
}

/// 对话场景。
enum ConversationScope {
  /// 单聊（C2C），会话 id 为 `user_openid`。
  c2c('c2c', '单聊'),

  /// 群聊，会话 id 为 `group_openid`。
  group('group', '群聊'),

  /// 频道（Guild），本项目仅做兼容展示。
  guild('guild', '频道');

  const ConversationScope(this.value, this.label);

  final String value;
  final String label;

  bool get isGroup => this == group;
}

/// 消息方向。
enum MessageDirection {
  /// 用户发给机器人。
  incoming,

  /// 机器人发给用户。
  outgoing,
}
