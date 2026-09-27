// AppExitResponse 由 dart:ui 提供（flutter/services 与 widgets 均不导出它，
// Flutter 自己的 binding 也是以 `ui.AppExitResponse` 的形式引用）。
import 'dart:async';
import 'dart:ui' as ui;

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
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    // 用 AppLifecycleListener.onExitRequested 而不是 detached：
    // 前者只在「应用确实要退出」时触发，后者在引擎与视图分离时也会触发
    // （例如平台侧重建视图），那时把连接与插件进程全停掉会造成误伤。
    //
    // 收起资源的必要性：Python 插件是独立进程，不显式结束会在系统里
    // 留下孤儿进程；WSS 连接不主动关闭则由系统回收，回收时机不可控。
    _lifecycleListener = AppLifecycleListener(
      onExitRequested: () async {
        await ref.read(appServicesProvider).shutdown();
        return ui.AppExitResponse.exit;
      },
      // 回到前台时补一次保活。
      //
      // 必要性：Android 12 起禁止从后台启动前台服务，若保活服务曾被系统
      // 回收、重启时又恰好处于后台，那次 startForeground 会被拒。
      // 应用回到前台是唯一能补救的时机，而 Dart 侧是知道这个时机的唯一一方——
      // 不补这一下，用户会遇到「开关是开的、但机器人就是不在线」。
      onResume: () => unawaited(
        ref.read(appServicesProvider).keepAlive.reassert(),
      ),
    );
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final services = ref.watch(appServicesProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 必须监听日志服务：未读错误数会随着连接失败、接口报错而变化，
    // 而外壳本身不会因为这些事情重建 —— 不监听的话角标会一直停在
    // 首次构建时的数字上（等于这个提示功能形同不存在）。
    return ListenableBuilder(
      listenable: services.log,
      builder: (context, _) => GlassScaffold(
        body: SafeArea(
          bottom: false,
          child: IndexedStack(
            index: _index,
            children: [
              for (var i = 0; i < homeTabs.length; i++)
                _TabFade(
                  active: i == _index,
                  child: homeTabs[i].builder(),
                ),
            ],
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
            onDestinationSelected: (value) {
              setState(() => _index = value);
              // 切到日志页即视为「已读」，清掉角标。
              if (homeTabs[value].label == '日志') {
                services.log.markProblemsRead();
              }
            },
            destinations: [
              for (final tab in homeTabs)
                NavigationDestination(
                  icon: _TabIcon(
                    icon: tab.icon,
                    // 日志 Tab 有未读错误时打一个小红点：
                    // 连接失败这类问题如果只写在日志里，用户永远不知道去看。
                    // 用「未读」而非「累计」计数，否则角标会一直挂着，反而被无视。
                    badge: tab.label == '日志' ? services.log.unreadProblems : 0,
                  ),
                  selectedIcon: Icon(tab.selectedIcon),
                  label: tab.label,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tab 内容切换时的淡入。
///
/// 不销毁子树（外层是 IndexedStack，非活动页仍在树上但不绘制），
/// 因此滚动位置与输入内容都能保留，只补一个视觉过渡。
class _TabFade extends StatelessWidget {
  const _TabFade({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: active ? 1 : 0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: child,
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
