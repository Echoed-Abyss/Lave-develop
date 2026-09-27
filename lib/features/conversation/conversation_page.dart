import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/app.dart';
import '../../app/theme.dart';
import '../../core/utils/qq_avatar.dart';
import '../../domain/models/connection_status.dart';
import '../../domain/models/log_entry.dart';
import '../../domain/models/message_segment.dart';
import '../../domain/models/qq_enums.dart';
import '../../domain/models/qq_message.dart';
import '../../shared/widgets/avatars.dart';
import '../../shared/widgets/glass.dart';

/// 会话详情页：完整消息列表 + 图片预览 + 发送栏。
///
/// **这一页解决的是「看起来收不到消息」的问题**：此前消息只以
/// 「会话摘要」的形式出现在折叠卡片里，卡片一折起来就完全看不到内容，
/// 用户很容易判定为「机器人收不到消息」。实际上事件早已到达并落库。
///
/// 页面自上而下三部分：连接状态条、消息时间线、发送栏。
/// 状态条刻意常驻：排查「发不出去」时，第一件要确认的事就是连接是否在线。
class ConversationPage extends ConsumerStatefulWidget {
  const ConversationPage({
    super.key,
    required this.botId,
    required this.conversationId,
    required this.scope,
  });

  final String botId;

  /// 会话标识：单聊为 `user_openid`，群聊为 `group_openid`。
  final String conversationId;

  final ConversationScope scope;

  @override
  ConsumerState<ConversationPage> createState() => _ConversationPageState();
}

class _ConversationPageState extends ConsumerState<ConversationPage> {
  final TextEditingController _text = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _sending = false;

  /// 是否以被动回复方式发送（引用最后一条仍可回复的入站消息）。
  ///
  /// 默认开启：被动回复不受主动消息频控约束，是唯一「发得出去」的稳妥方式。
  bool _passive = true;

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final services = ref.watch(appServicesProvider);

    return ListenableBuilder(
      listenable: services.history,
      builder: (context, _) {
        final messages =
            services.history.messagesOf(widget.botId, widget.conversationId);
        final connection = services.registry.connectionFor(widget.botId);
        final canSendActive = services.history.isActiveMessageEnabled(
          widget.botId,
          widget.conversationId,
        );
        // 机器人昵称与头像：气泡右侧、以及占位色都以它为准。
        final bot = services.bots.find(widget.botId);
        final botName = bot?.title ?? '机器人';
        final botAvatarUrl = bot?.avatarUrl;

        // 会话对方（最后一位发言的入站用户）。
        //
        // 单聊时标题直接用对方昵称、头像用对方真实头像——「单聊 · …3E00D6BDF0」
        // 这种由 openid 尾巴拼出来的标题，用户根本认不出是谁。
        // 群聊则不这么做：最后发言的用户不等于这个群，拿他的名字当标题是误导，
        // 而且群头像官方与 CDN 都给不了，只能用群图标占位。
        final isC2c = widget.scope == ConversationScope.c2c;
        final peer = _lastIncoming(messages);
        final peerName = peer?.sender.displayName?.trim();
        final peerAvatarUrl = isC2c
            ? (peer?.sender.avatarUrl ??
                QqAvatar.forOpenid(
                  appId: widget.botId,
                  openid: widget.conversationId,
                ))
            : null;
        final title = isC2c && peerName != null && peerName.isNotEmpty
            ? peerName
            : _title();

        return ValueListenableBuilder<ConnectionSnapshot>(
          valueListenable: connection.status,
          builder: (context, snapshot, _) => GlassScaffold(
            title: title,
            titleLeading: LaveAvatar(
              seed: '${widget.botId}:${widget.conversationId}',
              imageUrl: peerAvatarUrl,
              label: title,
              radius: 14,
              fallbackIcon:
                  widget.scope == ConversationScope.group ? Icons.groups_outlined : null,
            ),
            actions: [
              IconButton(
                tooltip: '复制会话标识',
                icon: const Icon(Icons.copy_all_outlined),
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: widget.conversationId),
                  );
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('会话标识已复制')),
                  );
                },
              ),
            ],
            body: Column(
              children: [
                _StatusBar(
                  snapshot: snapshot,
                  scope: widget.scope,
                  messageCount: messages.length,
                  canSendActive: canSendActive,
                ),
                Expanded(
                  child: messages.isEmpty
                      ? GlassEmptyState(
                          icon: Icons.forum_outlined,
                          title: '这个会话还没有消息',
                          description: '让对方向机器人发一条消息，或直接在下方发送主动消息。\n\n'
                              '提示：主动消息受官方独立频控约束'
                              '（单关系 20 条/分钟），被动回复不受此限制。',
                        )
                      : ListView.builder(
                          controller: _scroll,
                          // 时间正序，最新在底部；reverse 后自动贴底，
                          // 新消息到达时无需手动滚动。
                          reverse: true,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            final message = messages[messages.length - 1 - index];
                            final bubble = _MessageBubble(
                              message: message,
                              botName: botName,
                              botAvatarUrl: botAvatarUrl,
                            );
                            // 只给最新一条做入场动效（reverse 列表里 index 0 即最新）。
                            // 给每条都做的话，滚动时不断有新条目挂载并播放动画，
                            // 既干扰阅读也白白消耗帧预算。
                            if (index != 0) return bubble;
                            return FadeSlideIn(offset: 0.16, child: bubble);
                          },
                        ),
                ),
                _ComposerBar(
                  controller: _text,
                  passive: _passive,
                  sending: _sending,
                  passiveRemaining: _passiveRemaining(messages),
                  onTogglePassive: (value) => setState(() => _passive = value),
                  onSendText: _sendText,
                  onSendImage: _pickAndSendImage,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _title() {
    final suffix = widget.conversationId.length <= 12
        ? widget.conversationId
        : '…${widget.conversationId.substring(widget.conversationId.length - 10)}';
    return '${widget.scope.label} · $suffix';
  }

  /// 取最后一条入站消息（用于标题与对方头像）。
  QqMessage? _lastIncoming(List<QqMessage> messages) {
    for (final message in messages.reversed) {
      if (message.isIncoming) return message;
    }
    return null;
  }

  /// 取最后一条「仍在被动回复窗口内且还有剩余次数」的入站消息。
  QqMessage? _latestRepliable(List<QqMessage> messages) {
    final now = DateTime.now();
    for (final message in messages.reversed) {
      if (message.isIncoming && message.canReplyAt(now)) return message;
    }
    return null;
  }

  /// 当前可被动回复的目标还剩几次额度；没有目标时返回 `null`。
  ///
  /// 次数取自发送层的**实时计数器**（按 `msg_id` 递增的 `msg_seq`），
  /// 而不是消息模型上的 `repliesUsed`：后者是持久化快照，
  /// 同一条消息被连续回复多次时它不会变，界面会一直显示「剩余满额」，
  /// 直到服务端把第 6 次请求拒绝——那时用户已经白等一次失败。
  int? _passiveRemaining(List<QqMessage> messages) {
    final target = _latestRepliable(messages);
    if (target == null) return null;
    final sender = ref.read(appServicesProvider).registry.senderFor(widget.botId);
    final used = sender?.repliesUsedFor(target.wireId) ?? 0;
    return (target.maxReplies - used).clamp(0, target.maxReplies);
  }

  Future<void> _sendText() async {
    final sender = ref.read(appServicesProvider).registry.senderFor(widget.botId);
    if (sender == null) return;
    final text = _text.text.trim();
    if (text.isEmpty) {
      _toast('请先输入内容');
      return;
    }

    final target = _passive ? _latestRepliable(
      ref.read(appServicesProvider).history.messagesOf(widget.botId, widget.conversationId),
    ) : null;

    setState(() => _sending = true);
    final response = await sender.sendText(
      conversationId: widget.conversationId,
      scope: widget.scope,
      text: text,
      // 手动回复这里刻意只传 msg_id：官方要求 msg_id（回复用户消息）
      // 与 event_id（响应事件）二选一，而这是一条消息。
      credential: target?.replyCredential,
    );
    if (!mounted) return;
    setState(() => _sending = false);

    if (response.isSuccess) {
      _text.clear();
      _appendOutgoing(text);
      _toast('已发送');
    } else {
      _toast(response.failure!.userMessage);
    }
  }

  Future<void> _pickAndSendImage() async {
    final sender = ref.read(appServicesProvider).registry.senderFor(widget.botId);
    if (sender == null) return;

    final XFile? picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      // 官方图片软限制 20MB；先压到 1600px 宽，显著降低上传失败率与流量。
      maxWidth: 1600,
      imageQuality: 88,
    );
    if (picked == null) return;

    setState(() => _sending = true);
    final response = await sender.sendImage(
      conversationId: widget.conversationId,
      scope: widget.scope,
      filePath: picked.path,
      // 图片走主动消息：上传耗时可能超过群聊 5 分钟的被动回复窗口，
      // 带 msg_id 反而更容易失败。需要被动发图时请在文本里说明后由插件处理。
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (response.isSuccess) {
      _appendOutgoing('[图片]');
      _toast('图片已发送');
    } else {
      _toast(response.failure!.userMessage);
    }
  }

  /// 把「机器人发出的消息」写进本地历史。
  ///
  /// 官方不会把机器人自己发的消息作为事件回推，因此不本地补记的话，
  /// 用户发完消息在列表里看不到自己发的那条，会以为发送失败。
  void _appendOutgoing(String preview) {
    final services = ref.read(appServicesProvider);
    // 发出方是本机器人：带上它的昵称与头像，气泡右侧才能显示真实头像
    // 而不是一个通用机器人图标。
    final bot = services.bots.find(widget.botId);
    services.history.addMessage(
          QqMessage(
            localId: services.history.nextLocalId(),
            botId: widget.botId,
            scope: widget.scope,
            conversationId: widget.conversationId,
            sender: ActorRef(
              scopeId: 'robot',
              displayName: bot?.title ?? '机器人',
              avatarUrl: bot?.avatarUrl,
              isBot: true,
            ),
            direction: MessageDirection.outgoing,
            at: DateTime.now(),
            content: preview,
          ),
        );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

/// 顶部状态条。
class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.snapshot,
    required this.scope,
    required this.messageCount,
    required this.canSendActive,
  });

  final ConnectionSnapshot snapshot;
  final ConversationScope scope;
  final int messageCount;
  final bool canSendActive;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final online = snapshot.isOnline;
    return GlassPanel(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      radius: 12,
      blurSigma: GlassTheme.listBlurSigma,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      accent: online ? const Color(0xFF2E9E6B) : const Color(0xFFD08A1E),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                online ? Icons.wifi_tethering : Icons.wifi_tethering_off,
                size: 15,
                color: online ? const Color(0xFF2E9E6B) : const Color(0xFFD08A1E),
              ),
              const SizedBox(width: 6),
              Text(
                '连接：${snapshot.phase.label}',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: GlassTheme.textPrimary(context),
                ),
              ),
              const Spacer(),
              Text(
                '消息 $messageCount 条',
                style: TextStyle(
                  fontSize: 11.5,
                  color: GlassTheme.textSecondary(context),
                ),
              ),
            ],
          ),
          if (snapshot.lastError != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                snapshot.lastError!.userMessage,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.5,
                  color: GlassTheme.levelColor('WARN', isDark: isDark),
                ),
              ),
            ),
          if (!canSendActive)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '对方已关闭主动消息推送：主动消息会发送失败，'
                '请在被动回复窗口内回复（${scope.isGroup ? '群聊 5 分钟' : '单聊 60 分钟'}）。',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.5,
                  color: GlassTheme.levelColor('WARN', isDark: isDark),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 消息气泡。
///
/// 渲染顺序刻意固定为「引用 → 正文 → 附件 → 卡片」：附件在消息里通常
/// 是补充说明，把图片放在文字之前会把文字挤到屏幕外，而用户最先要读的是字。
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.botName,
    required this.botAvatarUrl,
  });

  final QqMessage message;

  /// 机器人昵称与头像：气泡右侧（机器人发言）用它，
  /// 因为这类消息的发送者是我们自己构造的，取账号上的资料更准。
  final String botName;
  final String? botAvatarUrl;

  /// 发送者头像地址。
  ///
  /// **在渲染时推导，而不是依赖消息上那个字段**：事件里带的 `avatar`
  /// 大多数时候是空的（官方消息事件不返回它），历史消息又是从落盘数据里
  /// 恢复出来的。只要知道「是哪个机器人 + 谁的 openid」就能算出头像地址，
  /// 让每个发言者都有头像，而不是一堆灰底首字。
  ///
  /// `scopeId` 是 `robot` / `unknown` 这类哨兵值时返回 `null`：
  /// 拿它们拼出来的地址必然只指向 CDN 的默认灰头像，
  /// 那比明确的占位更难排查（看起来「有头像」，其实是错的）。
  String? get _senderAvatarUrl {
    final stored = message.sender.avatarUrl;
    if (stored != null && stored.isNotEmpty) return stored;
    if (!message.isIncoming) return botAvatarUrl;
    final openid = message.sender.scopeId.trim();
    if (openid.isEmpty || openid == 'unknown' || openid == 'robot') return null;
    return QqAvatar.forOpenid(appId: message.botId, openid: openid);
  }

  @override
  Widget build(BuildContext context) {
    final mine = !message.isIncoming;
    final images = message.attachments.where((a) => a.isImage).toList();
    final others = message.attachments.where((a) => !a.isImage).toList();
    final segments = message.segments;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        mainAxisAlignment:
            mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!mine)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: LaveAvatar(
                seed: message.sender.scopeId,
                imageUrl: _senderAvatarUrl,
                label: message.sender.displayName ?? message.sender.label,
                radius: 13,
              ),
            ),
          Flexible(
            child: GlassPanel(
              radius: 14,
              blurSigma: GlassTheme.listBlurSigma,
              // 气泡在长列表里，**必须**关掉背景模糊：BackdropFilter 是
              // GPU 上最贵的常规操作，几十个气泡各做一次全屏模糊，
              // 滚动时在中低端机上会直接掉帧。关掉后仍有半透明底与描边，
              // 视觉上依然是玻璃。
              blur: false,
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
              accent: mine ? GlassTheme.brand : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        mine ? botName : message.sender.label,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: mine
                              ? GlassTheme.brand
                              : GlassTheme.textSecondary(context),
                        ),
                      ),
                      if (!mine && message.sender.isAdminOrOwner) ...[
                        const SizedBox(width: 4),
                        _Tag(
                          text: message.sender.role == GroupRole.owner
                              ? '群主'
                              : '管理员',
                        ),
                      ],
                      const SizedBox(width: 6),
                      Text(
                        LogEntry.formatTime(message.at),
                        style: TextStyle(
                          fontSize: 10.5,
                          color: GlassTheme.textSecondary(context),
                        ),
                      ),
                    ],
                  ),
                  if (message.quote != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: _QuoteBlock(quote: message.quote!),
                    ),
                  if (segments.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: _ContentText(segments: segments),
                    ),
                  // 图片预览：官方附件 URL 为预签名地址，可直接加载；
                  // 加载失败时给明确占位而不是空白（签名过期是常见情况）。
                  for (final image in images)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: _AttachmentImage(image: image),
                    ),
                  for (final item in others)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: _AttachmentLine(attachment: item),
                    ),
                  if (message.ark != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: _ArkBlock(ark: message.ark!),
                    ),
                ],
              ),
            ),
          ),
          if (mine)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: LaveAvatar(
                seed: 'robot:${message.botId}',
                imageUrl: botAvatarUrl,
                label: botName,
                radius: 13,
                isBot: true,
                accent: GlassTheme.brand,
              ),
            ),
        ],
      ),
    );
  }
}

/// 正文富文本。
///
/// 用 `SelectableText.rich` + `TextSpan` 而不是给每个元素套 `WidgetSpan`：
/// 后者会为每个片段建立一个真实子组件，长列表滚动时要走完整的布局流程，
/// 一条带三四个 @ 的消息就能看出差别。`TextSpan` 的 `backgroundColor`
/// 足以做出「@ 某人」的高亮效果。
class _ContentText extends StatelessWidget {
  const _ContentText({required this.segments});

  final List<MessageSegment> segments;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = GlassTheme.textSecondary(context);

    return SelectableText.rich(
      TextSpan(
        style: TextStyle(
          fontSize: 14,
          height: 1.5,
          color: GlassTheme.textPrimary(context),
        ),
        children: [
          for (final segment in segments)
            if (segment.text.isNotEmpty)
              TextSpan(
                text: segment.text,
                style: _styleFor(segment, isDark: isDark, muted: muted),
              ),
        ],
      ),
    );
  }

  /// 各元素的文字样式；`null` 表示沿用正文默认样式。
  ///
  /// 写成 switch 表达式而不是 switch 语句：前者由编译器保证穷尽，
  /// 以后给 [MessageSegmentKind] 加成员时会立刻在编译期报错，
  /// 而不是静默落到「没有样式」的分支上。
  TextStyle? _styleFor(
    MessageSegment segment, {
    required bool isDark,
    required Color muted,
  }) =>
      switch (segment.kind) {
        MessageSegmentKind.text => null,
        // 解析不出昵称时用中性色：既区别于普通文字（说明这里是个 @），
        // 又不要用品牌色假装「已经知道是谁」。
        MessageSegmentKind.mention => TextStyle(
            color: segment.resolved ? GlassTheme.brand : muted,
            fontWeight: FontWeight.w600,
            backgroundColor: segment.resolved
                ? GlassTheme.brand.withValues(alpha: isDark ? 0.22 : 0.12)
                : null,
          ),
        MessageSegmentKind.mentionEveryone => const TextStyle(
            color: Color(0xFFB5763D),
            fontWeight: FontWeight.w600,
          ),
        MessageSegmentKind.command =>
          TextStyle(color: GlassTheme.brand, fontWeight: FontWeight.w500),
        MessageSegmentKind.channel =>
          TextStyle(color: GlassTheme.brand, fontWeight: FontWeight.w500),
        MessageSegmentKind.face => TextStyle(
            color: muted,
            backgroundColor: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.04),
          ),
        MessageSegmentKind.unknownElement =>
          TextStyle(color: muted, fontStyle: FontStyle.italic),
      };
}

/// 引用块（官方 `message_type = 103`）。
class _QuoteBlock extends StatelessWidget {
  const _QuoteBlock({required this.quote});

  final QqMessage quote;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final author = quote.sender.displayName?.trim();

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: GlassTheme.surfaceOf(isDark: isDark, alpha: 0.32),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(color: GlassTheme.brand.withValues(alpha: 0.6), width: 2.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (author != null && author.isNotEmpty)
            Text(
              author,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: GlassTheme.brand,
              ),
            ),
          Text(
            quote.preview,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              color: GlassTheme.textSecondary(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// 结构化卡片。
class _ArkBlock extends StatelessWidget {
  const _ArkBlock({required this.ark});

  final ArkSummary ark;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = ark.title?.trim();
    final description = ark.description?.trim();
    final label = ark.displayName?.trim();

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: GlassTheme.surfaceOf(isDark: isDark, alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '[卡片]${label == null || label.isEmpty ? '' : ' $label'}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: GlassTheme.textSecondary(context),
            ),
          ),
          if (title != null && title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  color: GlassTheme.textPrimary(context),
                ),
              ),
            ),
          if (description != null && description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                description,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.45,
                  color: GlassTheme.textSecondary(context),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 非图片附件的一行展示。
///
/// 语音、视频、文件都拿不到可直接播放的地址：官方的 `url` 是**下载**链接
/// （预签名、会过期），播放需要自己下载再解码。所以这里给的是
/// 「一眼能看出是什么、以及能拿到什么信息」，而不是一个点了没反应的播放按钮。
/// 语音多给一行 ASR 文本，那是这条消息唯一能直接读到的内容。
class _AttachmentLine extends StatelessWidget {
  const _AttachmentLine({required this.attachment});

  final AttachmentRef attachment;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final type = attachment.contentType;
    final (icon, label) = switch (type) {
      'voice' => (Icons.graphic_eq, '语音'),
      'video/mp4' => (Icons.videocam_outlined, '视频'),
      'file' => (Icons.insert_drive_file_outlined, '文件'),
      _ => (Icons.attachment_outlined, '附件'),
    };

    final name = attachment.filename?.trim();
    final details = [
      if (name != null && name.isNotEmpty) name,
      ?attachment.sizeLabel,
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: GlassTheme.surfaceOf(isDark: isDark, alpha: 0.28),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: GlassTheme.textSecondary(context)),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  details.isEmpty ? label : '$label · $details',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: GlassTheme.textPrimary(context),
                  ),
                ),
              ),
            ],
          ),
          if (attachment.asrText != null &&
              attachment.asrText!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                // 官方明确 asr_refer_text 是「参考结果」，因此要标明是机器识别
                '识别文本（机器）：${attachment.asrText!.trim()}',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.45,
                  color: GlassTheme.textSecondary(context),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 小标签（群主 / 管理员）。
class _Tag extends StatelessWidget {
  const _Tag({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: GlassTheme.brand.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
          color: GlassTheme.brand,
        ),
      ),
    );
  }
}

/// 图片附件。
class _AttachmentImage extends StatelessWidget {
  const _AttachmentImage({required this.image});

  final AttachmentRef image;

  @override
  Widget build(BuildContext context) {
    final link = image.url;
    if (link == null || link.isEmpty) {
      return const _ImagePlaceholder(text: '图片地址缺失');
    }
    // 按官方给的原始比例摆图：固定 220 宽会把竖图裁得只剩中间一条，
    // 而图片尺寸是官方随附件一起给的，没有理由不用。
    final ratio = _ratio();
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        link,
        width: 220,
        height: ratio == null ? 160 : (220 / ratio).clamp(90, 280),
        fit: ratio == null ? BoxFit.cover : BoxFit.contain,
        // 头像之外，聊天里的图片同样按显示尺寸解码：一屏几张 4K 截图
        // 全尺寸解码会直接把内存顶上去。
        cacheWidth: (220 * MediaQuery.devicePixelRatioOf(context)).round(),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const SizedBox(
            width: 220,
            height: 120,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        },
        // 官方附件 URL 带签名且会过期，加载失败属常见情况，
        // 因此给出明确提示而不是留一片空白。
        errorBuilder: (context, error, stack) =>
            const _ImagePlaceholder(text: '图片已过期或无法加载'),
      ),
    );
  }

  /// 宽高比。官方只在图片附件上给 `width` / `height`，缺失或为 0 时返回 `null`。
  double? _ratio() {
    final width = image.width;
    final height = image.height;
    if (width == null || height == null) return null;
    if (width <= 0 || height <= 0) return null;
    return width / height;
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      height: 90,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          color: GlassTheme.textSecondary(context),
        ),
      ),
    );
  }
}

/// 底部发送栏。
class _ComposerBar extends StatelessWidget {
  const _ComposerBar({
    required this.controller,
    required this.passive,
    required this.sending,
    required this.passiveRemaining,
    required this.onTogglePassive,
    required this.onSendText,
    required this.onSendImage,
  });

  final TextEditingController controller;
  final bool passive;
  final bool sending;

  /// 被动回复剩余次数；`null` 表示当前没有可被动回复的目标。
  final int? passiveRemaining;

  final ValueChanged<bool> onTogglePassive;
  final Future<void> Function() onSendText;
  final Future<void> Function() onSendImage;

  @override
  Widget build(BuildContext context) {
    final remaining = passiveRemaining;
    final canReply = remaining != null && remaining > 0;
    return GlassPanel(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      radius: 14,
      blurSigma: GlassTheme.listBlurSigma,
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                passive
                    ? (canReply
                        ? '被动回复（剩余 $remaining 次）'
                        : '被动回复不可用，将按主动消息发送')
                    : '主动消息（受官方频控限制）',
                style: TextStyle(
                  fontSize: 11.5,
                  color: canReply || !passive
                      ? GlassTheme.textSecondary(context)
                      : GlassTheme.levelColor(
                          'WARN',
                          isDark: Theme.of(context).brightness == Brightness.dark,
                        ),
                ),
              ),
              const Spacer(),
              // 被动回复开关：默认开启，因为它是唯一不受频控约束的通道。
              Switch(
                value: passive,
                onChanged: sending ? null : onTogglePassive,
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  maxLines: 4,
                  minLines: 1,
                  decoration: const InputDecoration(
                    hintText: '输入消息…',
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
              IconButton(
                tooltip: '发送图片',
                onPressed: sending ? null : onSendImage,
                icon: const Icon(Icons.image_outlined),
              ),
              IconButton.filled(
                tooltip: '发送',
                onPressed: sending ? null : onSendText,
                icon: sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
