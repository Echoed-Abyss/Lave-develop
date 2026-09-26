import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app.dart';
import '../../app/app_services.dart';
import '../../app/theme.dart';
import '../../domain/models/bot_profile.dart';
import '../../domain/models/connection_status.dart';
import '../../domain/models/qq_enums.dart';
import '../../shared/widgets/glass.dart';
import '../conversation/conversation_page.dart';

/// 机器人 Tab。
///
/// 承载三件事：账号管理、连接状态、消息发送。
/// 用可折叠卡片而不是「列表 + 二级页」：自用场景下账号通常只有
/// 一到三个，展开态能省掉大量来回跳转。
class BotPage extends ConsumerStatefulWidget {
  const BotPage({super.key});

  @override
  ConsumerState<BotPage> createState() => _BotPageState();
}

class _BotPageState extends ConsumerState<BotPage> {
  @override
  Widget build(BuildContext context) {
    final services = ref.watch(appServicesProvider);

    return ListenableBuilder(
      // 三个可监听对象都要订阅：账号变化、连接状态变化、消息变化。
      listenable: Listenable.merge([services.bots, services.registry, services.history]),
      builder: (context, _) {
        final bots = services.bots.bots;
        return GlassScaffold(
          title: '机器人',
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Text(
                  '在线 ${services.registry.onlineCount} / ${bots.length}',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: GlassTheme.textSecondary(context),
                  ),
                ),
              ),
            ),
          ],
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _showBotEditor(context, services, null),
            icon: const Icon(Icons.add),
            label: const Text('添加机器人'),
          ),
          body: bots.isEmpty
              ? GlassEmptyState(
                  icon: Icons.smart_toy_outlined,
                  title: '还没有机器人账号',
                  description: '添加一个 QQ 机器人，填入开放平台的 AppID 与密钥后即可'
                      '直连官方 Gateway 网关接收消息。\n'
                      '不需要部署任何公网服务器。',
                  action: GlassButton(
                    label: '立即添加',
                    icon: Icons.add,
                    onPressed: () => _showBotEditor(context, services, null),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(top: 8, bottom: 96),
                  itemCount: bots.length,
                  itemBuilder: (context, index) => _BotCard(
                    services: services,
                    bot: bots[index],
                    onEdit: () => _showBotEditor(
                      context,
                      services,
                      bots[index],
                    ),
                  ),
                ),
        );
      },
    );
  }

  Future<void> _showBotEditor(
    BuildContext context,
    AppServices services,
    BotProfile? existing,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BotEditorSheet(services: services, existing: existing),
    );
  }
}

/// 单个机器人卡片。
class _BotCard extends StatelessWidget {
  const _BotCard({
    required this.services,
    required this.bot,
    required this.onEdit,
  });

  final AppServices services;
  final BotProfile bot;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final connection = services.registry.connectionFor(bot.appId);
    final conversations = services.history.conversationsOf(bot.appId);

    return ValueListenableBuilder<ConnectionSnapshot>(
      valueListenable: connection.status,
      builder: (context, snapshot, _) => GlassExpandableCard(
        title: bot.title,
        subtitle: '${snapshot.phase.label}'
            '${snapshot.lastError == null ? '' : ' · ${snapshot.lastError!.userMessage}'}',
        accent: _accentFor(snapshot.phase),
        leading: CircleAvatar(
          radius: 15,
          backgroundColor: _accentFor(snapshot.phase).withValues(alpha: 0.18),
          child: Icon(
            snapshot.isOnline ? Icons.wifi_tethering : Icons.wifi_tethering_off,
            size: 16,
            color: _accentFor(snapshot.phase),
          ),
        ),
        trailing: Switch(
          value: bot.enabled,
          onChanged: (value) => _toggle(context, value),
        ),
        children: [
          _InfoRow(label: 'AppID', value: bot.appId),
          _InfoRow(
            label: '会话',
            value: snapshot.sessionId == null
                ? '未建立'
                : '已建立（seq=${snapshot.seq ?? '-'}）',
          ),
          _InfoRow(
            label: '心跳',
            value: snapshot.heartbeatInterval == null
                ? '-'
                : '${snapshot.heartbeatInterval!.inMilliseconds} 毫秒 '
                    '（官方下发值，判死阈值 ${services.config.heartbeatTimeoutMultiplier} 倍）',
          ),
          if (snapshot.attempt > 0)
            _InfoRow(label: '重连', value: '第 ${snapshot.attempt} 次尝试'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              GlassButton(
                label: '重连',
                icon: Icons.refresh,
                dense: true,
                onPressed: () => unawaited(connection.reconnectNow()),
              ),
              GlassButton(
                label: '断开',
                icon: Icons.link_off,
                dense: true,
                onPressed: snapshot.phase == ConnectionPhase.idle
                    ? null
                    : () => unawaited(connection.stop()),
              ),
              GlassButton(
                label: '编辑',
                icon: Icons.edit_outlined,
                dense: true,
                onPressed: onEdit,
              ),
              GlassButton(
                label: '删除',
                icon: Icons.delete_outline,
                dense: true,
                onPressed: () => _confirmDelete(context),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Divider(),
          GlassSectionTitle(text: '会话（${conversations.length}）'),
          if (conversations.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Text(
                '还没有会话。让用户给机器人发一条消息，这里就会出现。',
                style: TextStyle(
                  fontSize: 12.5,
                  color: GlassTheme.textSecondary(context),
                ),
              ),
            )
          else
            ...conversations.take(5).map(
                  (conversation) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${conversation.scopeLabel} · '
                                '${_short(conversation.conversationId)}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: GlassTheme.textPrimary(context),
                                ),
                              ),
                              Text(
                                conversation.lastPreview,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: GlassTheme.textSecondary(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!conversation.canSendActive)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Text(
                              '主动消息已关闭',
                              style: TextStyle(
                                fontSize: 11,
                                color: GlassTheme.levelColor(
                                  'WARN',
                                  isDark: Theme.of(context).brightness ==
                                      Brightness.dark,
                                ),
                              ),
                            ),
                          ),
                        // 点开进入完整会话页。消息内容不再挤在折叠卡片里 ——
                        // 卡片里只有摘要，折叠状态下完全看不到消息，
                        // 很容易被误判为「机器人收不到消息」。
                        IconButton(
                          tooltip: '打开会话',
                          icon: const Icon(Icons.chevron_right),
                          onPressed: () => _openConversation(
                            context,
                            services,
                            bot,
                            conversation.conversationId,
                            conversation.scopeLabel == '群聊'
                                ? ConversationScope.group
                                : ConversationScope.c2c,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          const SizedBox(height: 6),
          const Divider(),
          GlassSectionTitle(text: '发送消息'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              GlassButton(
                label: '手动指定会话',
                icon: Icons.edit_location_alt_outlined,
                dense: true,
                // 没有会话时（用户尚未发消息）也能主动发起，
                // 这是自用场景下的常见需求。
                onPressed: () => _openManualConversation(context, services, bot),
              ),
              GlassButton(
                label: '打开第一个会话',
                icon: Icons.forum_outlined,
                dense: true,
                onPressed: conversations.isEmpty
                    ? null
                    : () => _openConversation(
                          context,
                          services,
                          bot,
                          conversations.first.conversationId,
                          conversations.first.scopeLabel == '群聊'
                              ? ConversationScope.group
                              : ConversationScope.c2c,
                        ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '被动回复不受频控限制但需在窗口内（群聊 5 分钟 / 单聊 60 分钟）；'
            '主动消息受独立频控（单关系 20 条/分钟，每日 1000 条）。',
            style: TextStyle(
              fontSize: 11,
              height: 1.5,
              color: GlassTheme.textSecondary(context),
            ),
          ),
        ],
      ),
    );
  }

  /// 打开会话详情页。
  void _openConversation(
    BuildContext context,
    AppServices services,
    BotProfile bot,
    String conversationId,
    ConversationScope scope,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ConversationPage(
          botId: bot.appId,
          conversationId: conversationId,
          scope: scope,
        ),
      ),
    );
  }

  /// 手动输入会话标识后打开会话详情页。
  Future<void> _openManualConversation(
    BuildContext context,
    AppServices services,
    BotProfile bot,
  ) async {
    final controller = TextEditingController();
    var scope = ConversationScope.c2c;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('指定会话'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  GlassChip(
                    label: '单聊',
                    selected: scope == ConversationScope.c2c,
                    onTap: () =>
                        setDialogState(() => scope = ConversationScope.c2c),
                  ),
                  GlassChip(
                    label: '群聊',
                    selected: scope == ConversationScope.group,
                    onTap: () =>
                        setDialogState(() => scope = ConversationScope.group),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  labelText:
                      scope == ConversationScope.c2c ? 'user_openid' : 'group_openid',
                  helperText: '官方要求按场景使用对应 openid，两者不能互换',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('打开'),
            ),
          ],
        ),
      ),
    );

    final id = controller.text.trim();
    controller.dispose();
    if (confirmed != true || id.isEmpty || !context.mounted) return;
    _openConversation(context, services, bot, id, scope);
  }

  Future<void> _toggle(BuildContext context, bool value) async {
    final error = await services.bots.setEnabled(bot.appId, value);
    if (!context.mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.userMessage)));
      return;
    }
    if (value) {
      await services.registry.startBot(bot);
    } else {
      await services.registry.stopBot(bot.appId);
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除机器人'),
        content: Text(
          '将删除「${bot.title}」的本地配置与密钥，并清空其消息与事件记录。\n'
          '该操作不可撤销。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await services.registry.stopBot(bot.appId);
    await services.bots.remove(bot.appId);
    await services.credentials.delete(bot.appId);
    services.history.clearBot(bot.appId);
  }

  static Color _accentFor(ConnectionPhase phase) {
    switch (phase) {
      case ConnectionPhase.online:
        return const Color(0xFF2E9E6B);
      case ConnectionPhase.backoff:
      case ConnectionPhase.connecting:
      case ConnectionPhase.authenticating:
      case ConnectionPhase.fetchingEndpoint:
        return const Color(0xFFD08A1E);
      case ConnectionPhase.blocked:
        return const Color(0xFFD04A3E);
      case ConnectionPhase.unsupported:
        return const Color(0xFF7A7A8C);
      case ConnectionPhase.idle:
        return const Color(0xFF7A8CA0);
    }
  }

  static String _short(String value) =>
      value.length <= 10 ? value : '${value.substring(0, 6)}…${value.substring(value.length - 4)}';
}

/// 信息行。
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 62,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: GlassTheme.textSecondary(context),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12.5,
                color: GlassTheme.textPrimary(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 机器人新增 / 编辑面板。
class _BotEditorSheet extends StatefulWidget {
  const _BotEditorSheet({required this.services, this.existing});

  final AppServices services;
  final BotProfile? existing;

  @override
  State<_BotEditorSheet> createState() => _BotEditorSheetState();
}

class _BotEditorSheetState extends State<_BotEditorSheet> {
  final TextEditingController _appId = TextEditingController();
  final TextEditingController _secret = TextEditingController();
  final TextEditingController _token = TextEditingController();
  final TextEditingController _name = TextEditingController();
  TokenScheme _scheme = TokenScheme.qqBotAccessToken;
  bool _reveal = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _appId.text = existing.appId;
      _name.text = existing.displayName;
      unawaited(_loadCredential());
    }
  }

  Future<void> _loadCredential() async {
    final credential = await widget.services.credentials.load(_appId.text);
    if (!mounted) return;
    setState(() {
      _secret.text = credential.appSecret ?? '';
      _token.text = credential.botToken ?? '';
      _scheme = credential.tokenScheme;
    });
  }

  @override
  void dispose() {
    _appId.dispose();
    _secret.dispose();
    _token.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF14192B) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 26),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.existing == null ? '添加机器人' : '编辑机器人',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              GlassTextField(
                controller: _appId,
                label: 'AppID',
                hint: '开放平台「机器人 ID」',
                enabled: widget.existing == null,
                helper: '作为本地账号主键，添加后不可修改。',
              ),
              GlassTextField(
                controller: _name,
                label: '备注名',
                hint: '可留空，默认显示 AppID',
              ),
              GlassTextField(
                controller: _secret,
                label: 'AppSecret（机器人密钥）',
                obscure: !_reveal,
                suffix: IconButton(
                  icon: Icon(_reveal ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _reveal = !_reveal),
                ),
                helper: '用于换取 access_token（有效期 2 小时，程序会自动续期）。',
              ),
              GlassTextField(
                controller: _token,
                label: 'Bot Token（可选）',
                obscure: !_reveal,
                helper: '官方标注为「已弃用」，仅在 Identify 的另一种拼法下需要。',
              ),
              const SizedBox(height: 6),
              Text(
                'Identify 的 token 拼法',
                style: TextStyle(
                  fontSize: 12.5,
                  color: GlassTheme.textSecondary(context),
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                children: [
                  for (final scheme in TokenScheme.values)
                    GlassChip(
                      label: scheme.template,
                      selected: _scheme == scheme,
                      onTap: () => setState(() => _scheme = scheme),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF4E5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFF3D9B0)),
                ),
                child: const Text(
                  '安全提示：密钥保存在本机安全存储中（iOS Keychain / '
                  'Android KeyStore）。官方建议不要在客户端使用访问凭证，'
                  '本方案定位为自用与内测，请勿在共享设备上使用。',
                  style: TextStyle(fontSize: 11.5, height: 1.6),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? '保存中…' : '保存'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final appId = _appId.text.trim();
    if (appId.isEmpty) {
      _toast('AppID 不能为空');
      return;
    }
    setState(() => _saving = true);

    await widget.services.credentials.save(
      BotCredential(
        appId: appId,
        appSecret: _secret.text.trim().isEmpty ? null : _secret.text.trim(),
        botToken: _token.text.trim().isEmpty ? null : _token.text.trim(),
        tokenScheme: _scheme,
      ),
    );

    final name = _name.text.trim();
    if (widget.existing == null) {
      final added = await widget.services.bots.add(
        BotProfile(
          appId: appId,
          displayName: name,
          enabled: true,
          createdAt: DateTime.now(),
        ),
      );
      if (!added) {
        if (mounted) {
          setState(() => _saving = false);
          _toast('该 AppID 已存在');
        }
        return;
      }
    } else {
      await widget.services.bots.update(
        widget.existing!.copyWith(displayName: name),
      );
    }

    // 凭证变更后旧 token 作废，避免继续用一个已被替换的密钥。
    widget.services.tokens.invalidate(appId);
    widget.services.gatewayApi.invalidate(appId);

    final bot = widget.services.bots.find(appId);
    if (bot != null && bot.enabled) {
      await widget.services.registry.startBot(bot);
    }

    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}
