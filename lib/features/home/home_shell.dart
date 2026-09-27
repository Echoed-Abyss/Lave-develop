// AppExitResponse 由 dart:ui 提供（flutter/services 与 widgets 均不导出它，
// Flutter 自己的 binding 也是以 `ui.AppExitResponse` 的形式引用）。
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app.dart';
import '../../app/theme.dart';
import '../../core/logging/log_service.dart';
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
  int _index = initialHomeTabIndex;
  late final AppLifecycleListener _lifecycleListener;

  /// 已经构建过的 Tab 下标。
  ///
  /// 必须懒构建：`IndexedStack` 会一次性构建**全部**子树，
  /// 也就是说冷启动首帧就要跑完机器人页、日志页、统计页、插件页、设置页
  /// 的 `build`（含日志列表与折线图）。改成「首次切到才构建、构建后保活」，
  /// 既省掉首帧的大头开销，又保留「切回来时滚动位置与输入内容不丢」这个好处。
  final Set<int> _built = {initialHomeTabIndex};

  @override
  void initState() {
    super.initState();
    // 用 AppLifecycleListener.onExitRequested 而不是 detached：
    // 前者只在「应用确实要退出」时触发，后者在引擎与视图分离时也会触发
    // （例如平台侧重建视图），那时把连接与插件进程全停掉会造成误伤。
    //
    // 但「退出」在这里**不等于「停止服务」**：只要后台保活开着，
    // 退出后机器人与插件必须继续在线（那正是保活的意义）。
    // 具体分派交给 AppServices.handleExitRequest——它按保活开关决定
    // 是「只落盘」还是「完整收尾」。原生侧的 FlutterEngine 在
    // Activity 销毁后依然存活（shouldDestroyEngineWithHost 为 false），
    // 因此 Dart 的定时器与 WSS 心跳不会随界面一起消失。
    _lifecycleListener = AppLifecycleListener(
      onExitRequested: () async {
        await ref.read(appServicesProvider).handleExitRequest();
        // 始终返回 exit：把「要不要继续在线」交给保活开关表达，
        // 而不是用「拒绝退出」来留住用户——那会变成一个退不掉的界面。
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

    // 刻意**不**在这里整体监听 LogService。
    //
    // 原先的写法是给整棵树套一个 ListenableBuilder(log)，结果是每产生一条日志
    // ——连接事件、每条消息、每次接口调用都会产生——整个外壳连同五个页面
    // 全部重建一次。这正是「滚动时发涩、消息一多就卡」的主因。
    // 现在只让角标那一个小图标订阅日志，页面本身不再受影响。
    return GlassScaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _index,
          children: [
            for (var i = 0; i < homeTabs.length; i++)
              if (_built.contains(i))
                _TabFade(active: i == _index, child: homeTabs[i].builder())
              else
                const SizedBox.shrink(),
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
            setState(() {
              _index = value;
              _built.add(value);
            });
            // 切到日志页即视为「已读」，清掉角标。
            if (homeTabs[value].label == '日志') {
              services.log.markProblemsRead();
            }
          },
          destinations: [
            for (final tab in homeTabs)
              NavigationDestination(
                // 日志 Tab 有未读错误时打一个小红点：连接失败这类问题
                // 如果只写在日志里，用户永远不知道去看。
                // 用「未读」而非「累计」计数，否则角标会一直挂着，反而被无视。
                icon: tab.label == '日志'
                    ? _LogBadge(log: services.log, icon: tab.icon)
                    : Icon(tab.icon),
                selectedIcon: Icon(tab.selectedIcon),
                label: tab.label,
              ),
          ],
        ),
      ),
    );
  }
}

/// 日志未读角标。
///
/// 单独抽成一个订阅日志的小组件，是为了把「日志变化」引发的重建
/// 限制在这一个图标上，而不是整棵页面树——详见 `build` 里的说明。
class _LogBadge extends StatelessWidget {
  const _LogBadge({required this.log, required this.icon});

  final LogService log;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: log,
      builder: (context, _) {
        final unread = log.unreadProblems;
        if (unread <= 0) return Icon(icon);
        return Badge(
          label: Text(unread > 99 ? '99+' : '$unread'),
          child: Icon(icon),
        );
      },
    );
  }
}

/// Tab 内容切换时的淡入。
///
/// 不销毁子树（外层是 IndexedStack，非活动页仍在树上但不绘制），
/// 因此滚动位置与输入内容都能保留，只补一个视觉过渡。
///
/// 外面套一层 `RepaintBoundary`：这五个页面大量使用 `BackdropFilter`，
/// 不隔离的话每次不透明度变化都会让整页的模糊重新合成一遍。
class _TabFade extends StatelessWidget {
  const _TabFade({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: active ? 1 : 0,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      child: RepaintBoundary(child: child),
    );
  }
}
