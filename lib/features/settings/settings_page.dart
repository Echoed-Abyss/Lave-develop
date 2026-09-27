import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app.dart';
import '../../app/keep_alive_coordinator.dart';
import '../../app/theme.dart';
import '../../core/constants/app_info.dart';
import '../../gateway/protocol/qq_opcode.dart';
import '../../platform/android_keep_alive.dart';
import '../../shared/widgets/glass.dart';

/// 设置 Tab。
///
/// 内容取舍：只保留**会影响运行行为、且只能在应用内调整**的项。
/// 常量速查、诊断导出、运行环境罗列这类信息已移除 ——
/// 它们要么是开发期才需要的（已写入文档），要么在出问题时可以直接从
/// 「日志」页复制，放在设置里只会让真正要改的开关被淹没。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(appServicesProvider);

    return ListenableBuilder(
      listenable: Listenable.merge([
        services.themeMode,
        services.intentsMask,
        services.keepAlive,
      ]),
      builder: (context, _) => GlassScaffold(
        title: '设置',
        body: ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 40),
          children: [
            GlassSectionTitle(text: '外观'),
            FadeSlideIn(
              child: GlassPanel(
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
                        for (final entry in const [
                          (ThemeMode.system, '跟随系统'),
                          (ThemeMode.light, '浅色'),
                          (ThemeMode.dark, '深色'),
                        ])
                          GlassChip(
                            label: entry.$2,
                            selected: services.themeMode.value == entry.$1,
                            onTap: () => services.setThemeMode(entry.$1),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            GlassSectionTitle(text: '事件订阅范围（intents）'),
            FadeSlideIn(
              delay: const Duration(milliseconds: 60),
              child: GlassPanel(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                accent: const Color(0xFFD08A1E),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '当前掩码 ${services.intentsMask.value}',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: GlassTheme.textPrimary(context),
                          ),
                        ),
                        const Spacer(),
                        PulseDot(
                          color: const Color(0xFFD08A1E),
                          size: 7,
                          animate: services.selectedOptionalIntents.isNotEmpty,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '「单聊与群聊事件」是必需项，已始终订阅。\n'
                      '官方原文：如果在鉴权时传递了无权限的 intents，websocket 会报错'
                      '并直接关闭连接 —— 多勾一位就可能让机器人完全收不到消息，'
                      '因此在开放平台后台申请到权限之前，请保持关闭。',
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.65,
                        color: GlassTheme.textSecondary(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final item in QqOptionalIntent.values)
                      _IntentToggleRow(
                        item: item,
                        enabled: services.selectedOptionalIntents.contains(item),
                        onChanged: (value) {
                          final next = {...services.selectedOptionalIntents};
                          if (value) {
                            next.add(item);
                          } else {
                            next.remove(item);
                          }
                          services.setOptionalIntents(next);
                        },
                      ),
                  ],
                ),
              ),
            ),

            GlassSectionTitle(text: '后台保活'),
            FadeSlideIn(
              delay: const Duration(milliseconds: 120),
              child: GlassPanel(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '保活前台服务',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: GlassTheme.textPrimary(context),
                            ),
                          ),
                        ),
                        Switch(
                          value: services.keepAlive.isEnabled,
                          onChanged: services.keepAlive.isSupported
                              ? (value) => services.keepAlive.setEnabled(value)
                              : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      services.keepAlive.isSupported
                          ? '应用退到后台后，系统会在约 10 秒后冻结进程；被冻结时心跳停发，'
                              '网关会直接关闭连接（这就是「后台容易掉线」的原因）。\n'
                              '开启后由前台服务让进程免于冻结，代价是有一条常驻通知，'
                              '它会显示当前在线的机器人数。\n'
                              '开启时退出应用不会让机器人下线：连接与插件会继续运行，'
                              '要真正停止请关掉本开关，或点通知上的「停止保活」。'
                          : '当前平台不支持前台服务保活（仅 Android 需要）。',
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.65,
                        color: GlassTheme.textSecondary(context),
                      ),
                    ),
                    if (services.keepAlive.isSupported) ...[
                      const SizedBox(height: 8),
                      _KeepAliveStatus(coordinator: services.keepAlive),
                    ],
                  ],
                ),
              ),
            ),

            GlassSectionTitle(text: '关于'),
            FadeSlideIn(
              delay: const Duration(milliseconds: 180),
              child: GlassPanel(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _row(context, '当前版本', AppInfo.version),
                    _row(context, '作者', AppInfo.author),
                  ],
                ),
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
              width: 76,
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
                  fontWeight: FontWeight.w600,
                  color: GlassTheme.textPrimary(context),
                ),
              ),
            ),
          ],
        ),
      );
}

/// 保活的**真实**状态与系统前提。
///
/// 为什么要单独列这几行：开关只表达用户意图，真正决定「后台能不能保住连接」
/// 的是五项互不相同的事实——服务有没有真的起来、起来的是哪种前台服务类型、
/// 有没有加电池优化白名单、有没有精确闹钟权限、应用被放在哪个待机分桶。
/// 只要开关不要事实，用户遇到「开关是开的、机器人就是不在线」时
/// 完全没有排查方向，而这几项里任意一项不合格都足以单独造成掉线。
///
/// 每次构建都重新查询而不是缓存：这几个值会被应用之外的操作改掉
/// （用户在系统设置里加白名单、系统回收服务、系统调整待机分桶），
/// 缓存只会给出过期结论。
class _KeepAliveStatus extends StatelessWidget {
  const _KeepAliveStatus({required this.coordinator});

  final KeepAliveCoordinator coordinator;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return FutureBuilder<KeepAliveStatus>(
      future: coordinator.status(),
      builder: (context, snapshot) {
        final status = snapshot.data;
        if (status == null || !status.available) {
          return Text(
            '正在查询保活状态…',
            style: TextStyle(
              fontSize: 11.5,
              color: GlassTheme.textSecondary(context),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _statusRow(
              context,
              label: '服务状态',
              value: status.running ? '已在后台常驻' : '未运行',
              ok: status.running,
              isDark: isDark,
            ),
            const SizedBox(height: 3),
            _statusRow(
              context,
              label: '服务类型',
              // dataSync 在 Android 15+ 每 24 小时只能累计跑 6 小时，
              // 到点会被系统强制停服；specialUse 没有时限。
              value: switch (status.foregroundType) {
                'specialUse' => 'specialUse（无时长上限）',
                'dataSync' => 'dataSync（有 6 小时/24 小时上限）',
                _ => '未知',
              },
              ok: status.foregroundType == 'specialUse',
              isDark: isDark,
            ),
            const SizedBox(height: 3),
            _statusRow(
              context,
              label: '电池优化',
              value: status.ignoringBatteryOptimizations
                  ? '已加白名单'
                  : '未加白名单，点此授权',
              ok: status.ignoringBatteryOptimizations,
              isDark: isDark,
              // 未加白名单时优先直接弹系统对话框，比打开列表页有效得多。
              onTap: status.ignoringBatteryOptimizations
                  ? null
                  : () => coordinator.requestIgnoreBatteryOptimizations(),
            ),
            const SizedBox(height: 3),
            _statusRow(
              context,
              label: '精确闹钟',
              value: status.canScheduleExactAlarms ? '已授权' : '未授权，点此开启',
              ok: status.canScheduleExactAlarms,
              isDark: isDark,
              onTap:
                  status.canScheduleExactAlarms ? null : coordinator.openExactAlarmSettings,
            ),
            const SizedBox(height: 3),
            _statusRow(
              context,
              label: '待机分桶',
              // RARE（极少使用）起系统会限制应用的互联网连接，
              // 这与前台服务是否在跑无关，是「放着一会儿就掉线」的独立原因。
              value: status.standbyBucketRestrictsNetwork
                  ? '${status.standbyBucketLabel}（可能限制网络）'
                  : status.standbyBucketLabel,
              ok: !status.standbyBucketRestrictsNetwork,
              isDark: isDark,
            ),
            if (status.standbyBucketRestrictsNetwork ||
                status.isLimitedForegroundType) ...[
              const SizedBox(height: 6),
              Text(
                [
                  if (status.isLimitedForegroundType)
                    '前台服务类型回落到了 dataSync：请重启应用；若持续如此，'
                        '说明系统拒绝了 specialUse 类型。',
                  if (status.standbyBucketRestrictsNetwork)
                    '应用已被系统放进低优先级分桶，后台网络会被限制。'
                        '多打开几次应用、把电池优化设为「不优化」可以脱离该分桶。',
                ].join('\n'),
                style: TextStyle(
                  fontSize: 11,
                  height: 1.6,
                  color: GlassTheme.levelColor('WARN', isDark: isDark),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _statusRow(
    BuildContext context, {
    required String label,
    required String value,
    required bool ok,
    required bool isDark,
    VoidCallback? onTap,
  }) {
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 76,
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
              fontWeight: FontWeight.w600,
              color: GlassTheme.levelColor(ok ? 'INFO' : 'WARN', isDark: isDark),
              decoration: onTap == null ? null : TextDecoration.underline,
            ),
          ),
        ),
      ],
    );
    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }
}

/// 单个可选 intents 的开关行。
class _IntentToggleRow extends StatelessWidget {
  const _IntentToggleRow({
    required this.item,
    required this.enabled,
    required this.onChanged,
  });

  final QqOptionalIntent item;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.officialName,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: GlassTheme.textPrimary(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.description,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.5,
                    color: GlassTheme.textSecondary(context),
                  ),
                ),
                if (!item.inOfficialList)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '该位不在官方 intents 清单中，风险最高',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: GlassTheme.levelColor('ERROR', isDark: isDark),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Switch(value: enabled, onChanged: onChanged),
        ],
      ),
    );
  }
}
