import 'package:flutter/foundation.dart';

import 'qq_enums.dart';

/// 领域消息模型。
///
/// 与`gateway/protocol` 下的协议模型是**两套不同用途的结构**：
/// - 协议模型：字段名与官方 JSON 逐字一致，只负责解析；
/// - 本模型：把官方的四套 id 体系归一为 [ActorRef]，
///   把 RFC3339 字符串与 Unix 秒统一为 `DateTime`，
///   并携带「被动回复窗口」这类业务状态。
///
/// UI 与插件层只消费本模型，不接触 openid 家族——这样官方一旦调整字段命名，
/// 改动被限制在解析层。
@immutable
class QqMessage {
  const QqMessage({
    required this.localId,
    required this.botId,
    required this.scope,
    required this.conversationId,
    required this.sender,
    required this.direction,
    required this.at,
    this.wireId,
    this.eventId,
    this.content,
    this.attachments = const [],
    this.ark,
    this.quote,
    this.replyDeadline,
    this.repliesUsed = 0,
    this.deduplicationKey,
  });

  /// 本地自增主键。未落库时为 0。
  final int localId;

  /// 所属机器人 AppID。
  final String botId;

  /// 会话场景。
  final ConversationScope scope;

  /// 会话标识：单聊为 `user_openid`，群聊为 `group_openid`。
  final String conversationId;

  /// 发送者（已归一）。
  final ActorRef sender;

  /// 消息方向。
  final MessageDirection direction;

  /// 消息时间（已归一为 `DateTime`）。
  final DateTime at;

  /// 官方消息 id。撤回与引用都需要它。
  final String? wireId;

  /// 外层的 event id。用于「响应事件」式的被动回复。
  final String? eventId;

  /// 文本内容。群聊场景下官方已去除 @机器人前缀。
  final String? content;

  /// 附件（已归一）。
  final List<AttachmentRef> attachments;

  /// 结构化卡片摘要。
  final ArkSummary? ark;

  /// 被引用的消息（`message_type = 103` 时）。
  final QqMessage? quote;

  /// 被动回复窗口截止时间。
  ///
  /// 单聊 60 分钟、群聊 5 分钟（官方口径存在冲突，取保守值，见 [QqLimits]）。
  /// 由分发层在建消息时按官方窗口计算并写入——**不能等到发送时才算**，
  /// 因为用户可能隔很久才回复，那时原始事件的接收时间已经不在内存里了。
  final DateTime? replyDeadline;

  /// 已用掉的被动回复次数。
  final int repliesUsed;

  /// 去重键（官方 `message_scene.ext` 的 `msg_idx`，回退到官方消息 id）。
  final String? deduplicationKey;

  /// 是否为收到的消息。
  bool get isIncoming => direction == MessageDirection.incoming;

  /// 是否还可进行被动回复。
  bool canReplyAt(DateTime now) {
    if (scope == ConversationScope.guild) return false;
    final deadline = replyDeadline;
    if (deadline == null) return false;
    if (!now.isBefore(deadline)) return false;
    return repliesUsed < maxReplies;
  }

  /// 本条消息的被动回复次数上限。
  int get maxReplies => scope == ConversationScope.group
      ? 5
      : 4;

  /// 剩余被动回复次数。
  int remainingRepliesAt(DateTime now) {
    if (!canReplyAt(now)) return 0;
    return (maxReplies - repliesUsed).clamp(0, maxReplies);
  }

  /// 是否含图片附件（列表预览时需要）。
  bool get hasImage =>
      attachments.any((e) => e.isImage);

  /// 是否含语音附件。
  bool get hasVoice => attachments.any((e) => e.isVoice);

  /// 列表展示用的单行摘要。
  String get preview {
    final text = content?.trim();
    if (text != null && text.isNotEmpty) return text;
    if (hasImage) return '[图片]';
    if (hasVoice) return '[语音]';
    if (attachments.any((e) => e.isVideo)) return '[视频]';
    if (attachments.any((e) => e.isFile)) return '[文件]';
    if (ark != null) return '[卡片] ${ark!.displayName ?? ''}'.trim();
    if (quote != null) return '[引用] ${quote!.preview}';
    return '[未知消息]';
  }

  QqMessage copyWith({
    int? localId,
    DateTime? replyDeadline,
    int? repliesUsed,
    List<AttachmentRef>? attachments,
  }) =>
      QqMessage(
        localId: localId ?? this.localId,
        botId: botId,
        scope: scope,
        conversationId: conversationId,
        sender: sender,
        direction: direction,
        at: at,
        wireId: wireId,
        eventId: eventId,
        content: content,
        attachments: attachments ?? this.attachments,
        ark: ark,
        quote: quote,
        replyDeadline: replyDeadline ?? this.replyDeadline,
        repliesUsed: repliesUsed ?? this.repliesUsed,
        deduplicationKey: deduplicationKey,
      );
}

/// 归一后的参与者身份。
///
/// 官方在 `User` 对象里同时给了 `id`、`union_openid`、`user_openid`、
/// `member_openid` 四个标识，用途各不相同。领域层把它收敛成一个概念：
/// 「在这个会话里，是谁」。
@immutable
class ActorRef {
  const ActorRef({
    required this.scopeId,
    this.displayName,
    this.role,
    this.unionId,
    this.isBot = false,
  });

  /// 会话内的身份标识：单聊取 `user_openid`，群聊取 `member_openid`。
  final String scopeId;

  /// 昵称（官方可能为空）。
  final String? displayName;

  /// 群内角色（仅群聊场景有值）。
  final GroupRole? role;

  /// 跨应用统一标识（官方标注可能为空）。
  final String? unionId;

  /// 是否为机器人。
  final bool isBot;

  /// 展示名：昵称缺失时回退到 id 的尾部，避免界面上出现空白。
  String get label {
    final name = displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    if (scopeId.length <= 6) return scopeId;
    return '用户…${scopeId.substring(scopeId.length - 6)}';
  }

  /// 是否为管理员或群主。
  bool get isAdminOrOwner => role?.isAdminOrOwner ?? false;
}

/// 归一后的附件引用。
@immutable
class AttachmentRef {
  const AttachmentRef({
    required this.url,
    this.filename,
    this.contentType,
    this.size,
    this.width,
    this.height,
    this.voiceWavUrl,
    this.asrText,
  });

  /// 下载地址。
  final String? url;

  /// 文件名。
  final String? filename;

  /// 官方原始 `content_type`。
  final String? contentType;

  /// 字节数。
  final int? size;

  /// 图片宽度（非图片为 null）。
  final int? width;

  /// 图片高度（非图片为 null）。
  final int? height;

  /// 语音转 WAV 的地址（官方单列字段）。
  final String? voiceWavUrl;

  /// 语音的机器识别文本（官方 `asr_refer_text`，仅供参考）。
  final String? asrText;

  bool get isImage =>
      contentType == 'image/jpeg' ||
      contentType == 'image/png' ||
      contentType == 'image/gif';

  bool get isVoice => contentType == 'voice';

  bool get isVideo => contentType == 'video/mp4';

  bool get isFile => contentType == 'file';

  /// 是否为已知类型。
  bool get isKnown => isImage || isVoice || isVideo || isFile;

  /// 体积的可读文本。
  String? get sizeLabel {
    final bytes = size;
    if (bytes == null) return null;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}

/// 结构化卡片的归一摘要。
@immutable
class ArkSummary {
  const ArkSummary({
    this.type,
    this.displayName,
    this.title,
    this.description,
    this.jumpUrl,
    this.previewUrl,
    this.prompt,
  });

  /// 官方 `ark_type`。
  final String? type;

  /// 官方 `ark_name`（中文类型名）。
  final String? displayName;

  /// 标题（取自 `fields.title`）。
  final String? title;

  /// 描述（取自 `fields.desc`）。
  final String? description;

  /// 跳转链接。
  final String? jumpUrl;

  /// 预览图。
  final String? previewUrl;

  /// 官方 `prompt`（用户操作提示文本）。
  final String? prompt;
}
