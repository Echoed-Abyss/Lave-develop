import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app.dart';
import '../../app/app_services.dart';
import '../../app/theme.dart';
import '../../core/constants/app_config.dart';
import '../../core/constants/qq_limits.dart';
import '../../domain/models/log_entry.dart';
import '../../shared/widgets/glass.dart';

/// 设置 Tab。
///
/// 内容取舍：只放**真正会影响运行行为**的项。
/// 不放「关于作者」这类装饰，也不放会造成误解的开关
/// （例如「无限重连」——官方对封禁类错误明确不可重试）。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(appServicesProvider);
    final config = services.config;
    final manager = services.plugins;

    return ListenableBuilder(
      listenable: Listenable.merge([services.themeMode, services.plugins]),
      builder: (context, _) => GlassScaffold(
        title: '设置',
        body: ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 40),
          children: [
            GlassSectionTitle(text: '外观'),
            GlassPanel(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '主题',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: GlassTheme.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    children: [
                      GlassChip(
                        label: '跟随系统',
                        selected: services.themeMode.value == ThemeMode.system,
                        onTap: () => services.setThemeMode(ThemeMode.system),
                      ),
                      GlassChip(
                        label: '浅色',
                        selected: services.themeMode.value == ThemeMode.light,
                        onTap: () => services.setThemeMode(ThemeMode.light),
                      ),
                      GlassChip(
                        label: '深色',
                        selected: services.themeMode.value == ThemeMode.dark,
                        onTap: () => services.setThemeMode(ThemeMode.dark),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            GlassSectionTitle(text: '运行环境'),
            GlassPanel(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _row(context, '环境', AppEnvironment.label),
                  _row(
                    context,
                    '日志级别',
                    config.enableFrameLog ? '调试（含逐帧日志）' : '生产（已关闭逐帧日志）',
                  ),
                  _row(context, 'HTTP 超时', '${config.httpTimeout.inSeconds} 秒'),
                  _row(
                    context,
                    '并发连接上限',
                    '${config.maxConcurrentConnections} 个机器人同时在线',
                  ),
                  _row(
                    context,
                    '心跳判死阈值',
                    '连续 ${config.heartbeatTimeoutMultiplier} 次未收到 ACK',
                  ),
                  _row(
                    context,
                    '重连退避',
                    '${config.reconnectBaseDelay.inSeconds} 秒起，'
                        '上限 ${config.reconnectMaxDelay.inSeconds} 秒（含抖动）',
                  ),
                  _row(
                    context,
                    '接入点缓存',
                    '${config.endpointCacheTtl.inMinutes} 分钟'
                        '（官方限制 2 QPM，必须缓存）',
                  ),
                ],
              ),
            ),

            GlassSectionTitle(text: '官方限制速查'),
            GlassPanel(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _row(
                    context,
                    '被动回复窗口',
                    '群聊 ${QqLimits.groupReplyWindow.inMinutes} 分钟 / '
                        '单聊 ${QqLimits.c2cReplyWindow.inMinutes} 分钟',
                  ),
                  _row(
                    context,
                    '被动回复次数',
                    '群聊 ${QqLimits.groupMaxRepliesPerMessage} 次 / '
                        '单聊 ${QqLimits.c2cMaxRepliesPerMessage} 次（每条原消息）',
                  ),
                  _row(
                    context,
                    '发消息 QPS',
                    '${QqLimits.sendMessageQps} QPS',
                  ),
                  _row(
                    context,
                    '主动消息频控',
                    '单关系 ${QqLimits.perRelationshipQpm} 条/分钟，'
                        '每日每关系 ${QqLimits.perRelationshipDailyLimit} 条',
                  ),
                  _row(
                    context,
                    '撤回时限',
                    '发送后 ${QqLimits.recallDeadline.inMinutes} 分钟内可撤回',
                  ),
                  _row(
                    context,
                    'access_token 有效期',
                    '${QqLimits.accessTokenTtl.inHours} 小时'
                        '（过期前 ${QqLimits.tokenRefreshLead.inSeconds} 秒自动换新）',
                  ),
                ],
              ),
            ),

            GlassSectionTitle(text: '插件运行环境'),
            GlassPanel(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              accent: manager.isSupported
                  ? const Color(0xFF2E9E6B)
                  : const Color(0xFFD08A1E),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _row(context, '平台', manager.capability.platform),
                  _row(
                    context,
                    'Python',
                    manager.capability.pythonExecutable ?? '未探测到',
                  ),
                  const SizedBox(height: 6),
                  Text(
                    manager.capability.reason ?? manager.capability.describe,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.65,
                      color: GlassTheme.textSecondary(context),
                    ),
                  ),
                ],
              ),
            ),

            GlassSectionTitle(text: '诊断'),
            GlassPanel(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  GlassButton(
                    label: '复制诊断信息',
                    icon: Icons.copy_all_outlined,
                    dense: true,
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: services.log.exportText()),
                      );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已复制到剪贴板')),
                      );
                    },
                  ),
                  GlassButton(
                    label: '重建全部连接',
                    icon: Icons.restart_alt,
                    dense: true,
                    onPressed: () async {
                      await services.registry.shutdown();
                      await services.registry.syncWithBots();
                    },
                  ),
                  GlassButton(
                    label: '清空消息与事件',
                    icon: Icons.cleaning_services_outlined,
                    dense: true,
                    onPressed: () => _confirmClearHistory(context, services),
                  ),
                  GlassButton(
                    label: '清空全部数据',
                    icon: Icons.delete_forever_outlined,
                    dense: true,
                    onPressed: () => _confirmClearAll(context, services),
                  ),
                ],
              ),
            ),

            GlassSectionTitle(text: '关于'),
            GlassPanel(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _row(context, '协议来源', 'QQ 机器人开放平台官方文档（api-v2）'),
                  _row(context, '事件通道', 'Gateway WebSocket 长连接（非 Webhook）'),
                  _row(context, '后端依赖', '无（事件链路设备直连官方网关）'),
                  const SizedBox(height: 6),
                  Text(
                    '本应用仅使用官方 Gateway WebSocket 与 HTTP OpenAPI，'
                    '不包含任何非官方协议实现。',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.65,
                      color: GlassTheme.textSecondary(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _row(BuildContext context, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 104,
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

  Future<void> _confirmClearHistory(
    BuildContext context,
    AppServices services,
  ) async {
    final confirmed = await _confirm(
      context,
      '清空消息与事件',
      '将删除本机保存的消息缓存与事件日志，不影响账号与密钥。',
    );
    if (confirmed != true) return;
    for (final bot in services.bots.bots) {
      services.history.clearBot(bot.appId);
    }
    services.log.info(LogSource.system, '已清空消息与事件缓存');
  }

  Future<void> _confirmClearAll(BuildContext context, AppServices services) async {
    final confirmed = await _confirm(
      context,
      '清空全部数据',
      '将删除全部账号、密钥、消息、事件与日志。\n'
          '该操作不可撤销，且删除后需要重新添加机器人账号。\n'
          '（建议先「复制诊断信息」留档）',
    );
    if (confirmed != true) return;

    await services.registry.shutdown();
    for (final bot in services.bots.bots) {
      await services.credentials.delete(bot.appId);
      await services.bots.remove(bot.appId);
      services.history.clearBot(bot.appId);
    }
    services.log.clear();
    await services.store.clear();
    services.log.info(
      LogSource.system,
      '已清空全部本地数据。账号与密钥已删除，请重新添加。',
    );
  }

  Future<bool?> _confirm(BuildContext context, String title, String content) =>
      showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认'),
            ),
          ],
        ),
      );
}
