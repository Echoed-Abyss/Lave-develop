import '../core/utils/qq_avatar.dart';
import '../domain/models/qq_enums.dart';
import '../domain/models/qq_message.dart';
import 'protocol/events/qq_event.dart';
import 'protocol/models/ark_data.dart';
import 'protocol/models/message_attachment.dart';
import 'protocol/models/msg_element.dart';

/// 事件 → 领域字段的映射。
///
/// 从 [EventDispatcher] 里拆出来的原因很直接：这些函数**一行 IO 都没有**，
/// 全是纯映射，却原来和事件流、去重、落库、插件投递混在一个类里，
/// 想单独验证「@ 提到的人有没有正确建立索引」就得先把日志服务、插件管理器、
/// 互动接口全部造出来。拆开之后它们可以直接拿一个解码好的事件对象来测。
///
/// 这里不引入任何状态：同一个事件进来，出去的结果永远一样。
abstract final class MessageMapper {
  /// 引用消息的 `message_type`（官方：103=引用消息）。
  static const int _quoteMessageType = 103;

  /// 建立「openid → 昵称」索引，供正文渲染 @ 使用。
  ///
  /// **把该用户的每一种标识都作为 key**：官方只说明了
  /// 「`mentions` 是 `[]User`、不含 @机器人自身」，没有说明正文里的
  /// `<@...>` 用的是哪一个字段。`id` / `member_openid` / `user_openid` /
  /// `union_openid` 四个都登记一遍，正文里出现哪个都能命中——
  /// 只挑一个字段的话，官方换一个就变成静默失败（界面上只显示 `@某人`，
  /// 看不出是解析没命中还是本来就没有昵称）。
  ///
  /// 昵称为空的条目会被跳过：用空字符串做 value 会让渲染层拿到一个
  /// 「解析成功但显示为空」的假结果。
  static Map<String, String> mentionsOf(QqEvent event) {
    final users = switch (event) {
      C2cMessageCreate() => event.mentions,
      GroupAtMessageCreate() => event.mentions,
      _ => null,
    };
    if (users == null || users.isEmpty) return const {};

    final result = <String, String>{};
    for (final user in users) {
      final name = user.username?.trim();
      if (name == null || name.isEmpty) continue;
      for (final id in [
        user.id,
        user.memberOpenid,
        user.userOpenid,
        user.unionOpenid,
      ]) {
        final key = id?.trim().toLowerCase();
        if (key == null || key.isEmpty) continue;
        result[key] = name;
      }
    }
    return result;
  }

  /// 从 `msg_elements` 里取出被引用的那条消息。
  ///
  /// **只在 `message_type = 103` 时成立**。官方把 `msg_elements` 定义为
  /// 「`message_type = 103`（引用消息）时包含被引用内容」，而 101（并行消息）
  /// 与 102（聊天记录）虽然也可能带 `msg_elements`，按官方口径那是**本条消息
  /// 自己的内容**，不是引用。不加这道判定的话，一条并行消息会被渲染成一个
  /// 标着「引用」的块，内容还被截断——比不渲染错得多。
  ///
  /// 引用关系的定位：官方对 103 只给了「`msg_elements` 携带嵌套内容」这一句，
  /// 示例里被引用内容直接躺在元素的 `content` 上。这里优先按
  /// `message_scene.ref_msg_idx` 精确定位，取不到就退化为「第一个有内容的元素」——
  /// 引用关系不明确时，显示一段看起来相关的上下文也比什么都不显示要好。
  static QqMessage? quoteOf(QqEvent event, {required String botId}) {
    final messageType = switch (event) {
      C2cMessageCreate() => event.messageType,
      GroupAtMessageCreate() => event.messageType,
      _ => null,
    };
    if (messageType != _quoteMessageType) return null;

    final elements = switch (event) {
      C2cMessageCreate() => event.msgElements,
      GroupAtMessageCreate() => event.msgElements,
      _ => null,
    };
    if (elements == null || elements.isEmpty) return null;

    final refIdx = switch (event) {
      C2cMessageCreate() => event.messageScene?.refMsgIdx,
      GroupAtMessageCreate() => event.messageScene?.refMsgIdx,
      _ => null,
    };

    final flat = <MsgElement>[];
    void collect(List<MsgElement>? list) {
      if (list == null) return;
      for (final element in list) {
        flat.add(element);
        collect(element.msgElements);
      }
    }

    collect(elements);

    MsgElement? picked;
    if (refIdx != null) {
      for (final element in flat) {
        if (element.msgIdx == refIdx) {
          picked = element;
          break;
        }
      }
    }
    picked ??= firstWithBody(flat);
    if (picked == null) return null;

    final senderId = quoteSenderId(picked);
    return QqMessage(
      localId: 0,
      botId: botId,
      scope: scopeOf(event),
      conversationId: conversationOf(event) ?? '',
      sender: ActorRef(
        scopeId: senderId,
        displayName: picked.author?.username,
        avatarUrl: QqAvatar.forOpenid(appId: botId, openid: senderId),
        isBot: picked.author?.bot ?? false,
      ),
      direction: MessageDirection.incoming,
      at: _timestampOf(event),
      content: picked.content,
      attachments: attachmentsOfElement(picked),
      ark: arkOfElement(picked),
      messageType: picked.messageType,
    );
  }

  /// 事件所属会话场景。
  static ConversationScope scopeOf(QqEvent event) => switch (event) {
        C2cMessageCreate() => ConversationScope.c2c,
        _ => ConversationScope.group,
      };

  /// 事件里的会话标识（单聊 `user_openid` / 群聊 `group_openid`）。
  static String? conversationOf(QqEvent event) => switch (event) {
        C2cMessageCreate() => event.conversationId,
        GroupAtMessageCreate() => event.groupOpenid,
        _ => null,
      };

  /// 事件的归一附件列表。
  static List<AttachmentRef> attachmentsOf(QqEvent event) {
    final raw = switch (event) {
      C2cMessageCreate() => event.attachments,
      GroupAtMessageCreate() => event.attachments,
      _ => null,
    };
    if (raw == null) return const [];
    return raw.map(attachmentRefOf).toList(growable: false);
  }

  /// 单个附件的归一。
  ///
  /// 抽出来是因为引用消息（`msg_elements`）里也有附件，两处必须用同一套映射，
  /// 否则同一种附件在正文与引用块里会显示成两样。
  static AttachmentRef attachmentRefOf(MessageAttachment a) => AttachmentRef(
        url: a.url,
        filename: a.filename,
        contentType: a.contentType,
        size: a.size,
        width: a.width,
        height: a.height,
        voiceWavUrl: a.voiceWavUrl,
        asrText: a.asrReferText,
      );

  /// 事件的结构化卡片摘要。
  static ArkSummary? arkOf(QqEvent event) {
    final ark = switch (event) {
      C2cMessageCreate() => event.arkData,
      GroupAtMessageCreate() => event.arkData,
      _ => null,
    };
    return ark == null ? null : arkSummaryOf(ark);
  }

  /// 结构化卡片的归一摘要。
  static ArkSummary arkSummaryOf(ArkData ark) => ArkSummary(
        type: ark.arkType,
        displayName: ark.displayName,
        title: ark.title,
        description: ark.description,
        jumpUrl: ark.jumpUrl,
        previewUrl: ark.field('preview'),
        prompt: ark.prompt,
      );

  /// 发送者的头像地址。
  ///
  /// 两级来源：
  /// 1. 事件里带的 `author.avatar`——官方对单聊/群聊事件**目前不返回**该字段，
  ///    但一旦补上就直接生效，属于前瞻性写法；
  /// 2. 用 `本机器人 AppID + 发送者 openid` 从腾讯头像 CDN 取。
  ///    这是消息场景下拿到用户头像的**唯一**途径（官方没有按 openid
  ///    查资料的接口），可用性与限制见 `core/utils/qq_avatar.dart`。
  ///
  /// [senderId] 是 `'unknown'` 时返回 `null`：那种情况下拼出来的地址必然只
  /// 指向 CDN 的默认灰头像，不如让界面用「首字 + 配色」的占位——后者还能
  /// 区分不同的人。
  static String? avatarOf(
    QqEvent event, {
    required String botId,
    required String senderId,
  }) {
    final fromEvent = switch (event) {
      C2cMessageCreate() => event.author?.avatar,
      GroupAtMessageCreate() => event.author?.avatar,
      _ => null,
    };
    if (fromEvent != null && fromEvent.isNotEmpty) return fromEvent;
    if (senderId == 'unknown') return null;
    return QqAvatar.forOpenid(appId: botId, openid: senderId);
  }

  /// 该元素是否有可展示的引用内容。
  static bool hasQuoteBody(MsgElement element) {
    final content = element.content?.trim();
    if (content != null && content.isNotEmpty) return true;
    if (element.attachments?.isNotEmpty ?? false) return true;
    return element.arkData != null;
  }

  /// 取第一个有内容的元素（按扁平化后的顺序）。
  static MsgElement? firstWithBody(List<MsgElement> elements) {
    for (final element in elements) {
      if (hasQuoteBody(element)) return element;
    }
    return null;
  }

  /// 被引用消息的发送者标识。
  static String quoteSenderId(MsgElement element) =>
      element.author?.memberOpenid ??
      element.author?.userOpenid ??
      element.author?.id ??
      'unknown';

  static List<AttachmentRef> attachmentsOfElement(MsgElement element) {
    final raw = element.attachments;
    if (raw == null) return const [];
    return raw.map(attachmentRefOf).toList(growable: false);
  }

  static ArkSummary? arkOfElement(MsgElement element) {
    final ark = element.arkData;
    return ark == null ? null : arkSummaryOf(ark);
  }

  /// 被引用消息的时间。
  ///
  /// 官方在 `msg_elements` 里**没有给时间字段**，因此只能退回当前时间：
  /// 引用块只显示内容与发送者，界面不展示它自己的时间戳，
  /// 避免出现「引用消息的时间和原消息一样」这种假信息。
  static DateTime _timestampOf(QqEvent event) => switch (event) {
        C2cMessageCreate() => event.timestamp ?? DateTime.now(),
        GroupAtMessageCreate() => event.timestamp ?? DateTime.now(),
        _ => DateTime.now(),
      };
}
