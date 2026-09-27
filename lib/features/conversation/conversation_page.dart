import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/app.dart';
import '../../app/theme.dart';
import '../../domain/models/connection_status.dart';
import '../../domain/models/log_entry.dart';
import '../../domain/models/qq_enums.dart';
import '../../domain/models/qq_message.dart';
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

        return ValueListenableBuilder<ConnectionSnapshot>(
          valueListenable: connection.status,
          builder: (context, snapshot, _) => GlassScaffold(
            title: _title(),
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
                            final bubble = _MessageBubble(message: message);
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
                  passiveTarget: _latestRepliable(messages),
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

  /// 取最后一条「仍在被动回复窗口内且还有剩余次数」的入站消息。
  QqMessage? _latestRepliable(List<QqMessage> messages) {
    final now = DateTime.now();
    for (final message in messages.reversed) {
      if (message.isIncoming && message.canReplyAt(now)) return message;
    }
    return null;
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
      passive: target != null,
      msgId: target?.wireId,
      eventId: target?.eventId,
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
      passive: false,
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
    ref.read(appServicesProvider).history.addMessage(
          QqMessage(
            localId: ref.read(appServicesProvider).history.nextLocalId(),
            botId: widget.botId,
            scope: widget.scope,
            conversationId: widget.conversationId,
            sender: const ActorRef(scopeId: 'robot', displayName: '机器人'),
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
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final QqMessage message;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mine = !message.isIncoming;
    final images = message.attachments.where((a) => a.isImage).toList();
    final others = message.attachments.where((a) => !a.isImage).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        mainAxisAlignment:
            mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!mine) const _Avatar(isBot: false),
          Flexible(
            child: GlassPanel(
              radius: 14,
              blurSigma: GlassTheme.listBlurSigma,
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
              accent: mine ? GlassTheme.brand : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        mine ? '机器人' : message.sender.label,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: mine
                              ? GlassTheme.brand
                              : GlassTheme.textSecondary(context),
                        ),
                      ),
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
                  if (message.content != null &&
                      message.content!.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: SelectableText(
                        message.content!,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: GlassTheme.textPrimary(context),
                        ),
                      ),
                    ),
                  // 图片预览：官方附件 URL 为预签名地址，可直接加载；
                  // 加载失败时给明确占位而不是空白（签名过期是常见情况）。
                  for (final image in images)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: _AttachmentImage(url: image.url),
                    ),
                  if (others.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final item in others)
                            Text(
                              '📎 ${item.filename ?? item.contentType ?? '附件'}'
                              '${item.sizeLabel == null ? '' : '（${item.sizeLabel}）'}',
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.5,
                                color: GlassTheme.textSecondary(context),
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (message.ark != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: GlassTheme.surfaceOf(isDark: isDark, alpha: 0.3),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '[卡片] ${message.ark!.displayName ?? ''}'
                          '${message.ark!.title == null ? '' : '：${message.ark!.title}'}',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.5,
                            color: GlassTheme.textSecondary(context),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (mine) const _Avatar(isBot: true),
        ],
      ),
    );
  }
}

/// 小头像占位。
class _Avatar extends StatelessWidget {
  const _Avatar({required this.isBot});

  final bool isBot;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: CircleAvatar(
        radius: 12,
        backgroundColor: (isBot ? GlassTheme.brand : const Color(0xFF7A8CA0))
            .withValues(alpha: 0.18),
        child: Icon(
          isBot ? Icons.smart_toy : Icons.person,
          size: 13,
          color: isBot ? GlassTheme.brand : const Color(0xFF7A8CA0),
        ),
      ),
    );
  }
}

/// 图片附件。
class _AttachmentImage extends StatelessWidget {
  const _AttachmentImage({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final link = url;
    if (link == null || link.isEmpty) {
      return const _ImagePlaceholder(text: '图片地址缺失');
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        link,
        width: 220,
        fit: BoxFit.cover,
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
    required this.passiveTarget,
    required this.onTogglePassive,
    required this.onSendText,
    required this.onSendImage,
  });

  final TextEditingController controller;
  final bool passive;
  final bool sending;
  final QqMessage? passiveTarget;
  final ValueChanged<bool> onTogglePassive;
  final Future<void> Function() onSendText;
  final Future<void> Function() onSendImage;

  @override
  Widget build(BuildContext context) {
    final canReply = passiveTarget != null;
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
                        ? '被动回复（剩余 ${passiveTarget!.remainingRepliesAt(DateTime.now())} 次）'
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
