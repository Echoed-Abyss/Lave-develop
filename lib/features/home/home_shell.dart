import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app.dart';
import '../../app/theme.dart';
import '../../shared/widgets/glass.dart';

/// 应用外壳：四个 Tab。
///
/// 用 `IndexedStack` 而不是按需重建页面：四个页面都依赖长驻服务
/// （连接状态、日志流），销毁重建会让「日志滚动位置」「输入框内容」
/// 在切 Tab 时丢失，体验很糟。代价是四个页面同时驻留内存——
/// 对这类工具应用是可接受的。
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final services = ref.watch(appServicesProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GlassScaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _index,
          children: homeTabs.map((tab) => tab.builder()).toList(growable: false),
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: GlassTheme.surfaceOf(isDark: isDark, alpha: 0.5),
          border: Border(
            top: BorderSide(color: GlassTheme.borderOf(isDark: isDark)),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (value) => setState(() => _index = value),
          destinations: [
            for (final tab in homeTabs)
              NavigationDestination(
                icon: _TabIcon(
                  icon: tab.icon,
                  // 日志 Tab 有未读错误时打一个小红点：
                  // 连接失败这类问题如果只写在日志里，用户永远不知道去看。
                  badge: tab.label == '日志'
                      ? services.log.problemCount
                      : 0,
                ),
                selectedIcon: Icon(tab.selectedIcon),
                label: tab.label,
              ),
          ],
        ),
      ),
    );
  }
}

/// 带角标的 Tab 图标。
class _TabIcon extends StatelessWidget {
  const _TabIcon({required this.icon, required this.badge});

  final IconData icon;
  final int badge;

  @override
  Widget build(BuildContext context) {
    if (badge <= 0) return Icon(icon);
    return Badge(
      label: Text(badge > 99 ? '99+' : '$badge'),
      child: Icon(icon),
    );
  }
}
