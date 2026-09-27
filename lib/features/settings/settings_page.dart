import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app.dart';
import '../../app/theme.dart';
import '../../core/constants/app_info.dart';
import '../../gateway/protocol/qq_opcode.dart';
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

            GlassSectionTitle(text: '关于'),
            FadeSlideIn(
              delay: const Duration(milliseconds: 120),
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
