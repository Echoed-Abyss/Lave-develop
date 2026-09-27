import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_services.dart';
import 'theme.dart';
import '../features/bot/bot_page.dart';
import '../features/home/home_shell.dart';
import '../features/logs/logs_page.dart';
import '../features/plugins/plugins_page.dart';
import '../features/settings/settings_page.dart';
import '../features/stats/stats_page.dart';

/// 应用服务容器。
///
/// 刻意不做成「逐层构建的 Provider 图」：这些服务有明确的启动顺序，
/// 由 `main.dart` 构造完成后通过 `overrideWithValue` 注入。
/// 这样异步初始化的顺序是显式的，不会出现「某个 Provider 在依赖还没就绪时被读取」。
final appServicesProvider = Provider<AppServices>(
  (ref) => throw UnimplementedError(
    'appServicesProvider 必须由 main.dart 在 ProviderScope 中覆盖',
  ),
);

/// 四个 Tab 的索引。
final homeTabProvider = Provider<int>((ref) => 0);

/// 应用根组件。
class LaveApp extends ConsumerWidget {
  const LaveApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(appServicesProvider);
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: services.themeMode,
      builder: (context, mode, _) => MaterialApp(
        title: 'Lave',
        debugShowCheckedModeBanner: false,
        theme: GlassTheme.light(),
        darkTheme: GlassTheme.dark(),
        themeMode: mode,
        home: const HomeShell(),
      ),
    );
  }
}

/// 页面注册表：顺序即 Tab 顺序（机器人 / 日志 / 统计 / 插件 / 设置）。
///
/// 独立成常量而不是写在 `HomeShell` 里，是为了让「Tab 数量与顺序」
/// 这个会变化的契约只有一处定义。
const List<HomeTabSpec> homeTabs = [
  HomeTabSpec(
    label: '机器人',
    icon: Icons.smart_toy_outlined,
    selectedIcon: Icons.smart_toy,
    builder: _buildBotPage,
  ),
  HomeTabSpec(
    label: '日志',
    icon: Icons.receipt_long_outlined,
    selectedIcon: Icons.receipt_long,
    builder: _buildLogsPage,
  ),
  HomeTabSpec(
    label: '统计',
    icon: Icons.insights_outlined,
    selectedIcon: Icons.insights,
    builder: _buildStatsPage,
  ),
  HomeTabSpec(
    label: '插件',
    icon: Icons.extension_outlined,
    selectedIcon: Icons.extension,
    builder: _buildPluginsPage,
  ),
  HomeTabSpec(
    label: '设置',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
    builder: _buildSettingsPage,
  ),
];

/// 进入应用时停留在哪个 Tab。
///
/// 统计页在正中间，也是首页：用户打开应用最想先确认的是
/// 「机器人今天有没有在收发消息」，而不是先去管理账号。
const int initialHomeTabIndex = 2;

Widget _buildBotPage() => const BotPage();
Widget _buildLogsPage() => const LogsPage();
Widget _buildStatsPage() => const StatsPage();
Widget _buildPluginsPage() => const PluginsPage();
Widget _buildSettingsPage() => const SettingsPage();

/// Tab 描述。
class HomeTabSpec {
  const HomeTabSpec({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.builder,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget Function() builder;
}
