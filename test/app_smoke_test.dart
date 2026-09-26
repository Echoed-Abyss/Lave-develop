import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lavedevelop/app/app.dart';
import 'package:lavedevelop/app/app_services.dart';

/// 应用骨架的冒烟测试。
///
/// 存在理由：`flutter analyze` 只能证明**类型正确**，证明不了
/// 「把服务装配起来、渲染四个 Tab 不会抛异常」。而依赖装配恰恰是
/// 最容易出错的地方——Provider 覆盖漏了、某个页面在空数据下解引用了 null，
/// 这些都要真正构建一次 Widget 树才会暴露。
///
/// 这里刻意不调用 `AppServices.initialize()`：那一步会走
/// `path_provider` 等平台通道，在纯 Dart 测试环境里没有实现。
/// 构造函数本身是无 IO 的，因此可以直接构造。
void main() {
  testWidgets('应用可构建，四个 Tab 均能在空数据下渲染', (tester) async {
    final services = AppServices();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appServicesProvider.overrideWithValue(services)],
        child: const LaveApp(),
      ),
    );
    await tester.pumpAndSettle();

    // ── 机器人 Tab：无账号时应显示引导空状态 ──
    expect(find.text('还没有机器人账号'), findsOneWidget);
    expect(find.text('添加机器人'), findsWidgets);

    // ── 日志 Tab ──
    await tester.tap(find.byIcon(Icons.receipt_long_outlined));
    await tester.pumpAndSettle();
    expect(find.text('暂无日志'), findsOneWidget);

    // ── 插件 Tab：能力探测尚未执行，应显示原因而不是假装可用 ──
    await tester.tap(find.byIcon(Icons.extension_outlined));
    await tester.pumpAndSettle();
    expect(find.text('当前平台无法运行插件'), findsOneWidget);
    expect(find.text('还没有安装插件'), findsOneWidget);

    // ── 设置 Tab：官方限制速查必须在 ──
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.text('运行环境'), findsOneWidget);
    expect(find.text('官方限制速查'), findsOneWidget);
    // 被动回复窗口这两个数字来自官方文档，出现在界面上说明常量链路是通的。
    expect(
      find.textContaining('群聊 5 分钟 / 单聊 60 分钟'),
      findsOneWidget,
    );
  });

  test('空账号时并发上限判定与初始化状态', () {
    final services = AppServices();

    expect(services.bots.isEmpty, isTrue);
    expect(services.bots.reachedConcurrencyLimit, isFalse);
    expect(services.isInitialized, isFalse);
    expect(services.registry.onlineCount, 0);
    expect(services.plugins.plugins, isEmpty);
  });
}
