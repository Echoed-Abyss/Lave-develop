import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lavedevelop/app/app.dart';
import 'package:lavedevelop/app/app_services.dart';
import 'package:lavedevelop/core/constants/app_info.dart';

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
  // 给 `lave/native` 通道打桩。
  //
  // 测试环境里没有原生实现，任何调用都会抛 MissingPluginException，
  // 于是「后台保活」区块会**正确地**判定为「当前平台不支持」并把内容藏起来——
  // 那是真实且合理的行为，但这样一来这段界面就永远测不到。
  // 打桩后走的是完整的真实路径：开关、服务状态、精确闹钟、电池优化都按返回值渲染。
  const nativeChannel = MethodChannel('lave/native');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeChannel, (call) async {
      // 全部返回 true 就够：本测试关心的是「拿到返回值后界面渲染成什么样」，
      // 而不是各方法的具体语义（那些由各自的单元测试覆盖）。
      return true;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeChannel, null);
  });

  testWidgets('应用可构建，五个 Tab 均能在空数据下渲染', (tester) async {
    final services = AppServices();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appServicesProvider.overrideWithValue(services)],
        child: const LaveApp(),
      ),
    );
    await tester.pumpAndSettle();

    // ── 首屏是统计页（按需求：统计 Tab 居中，同时作为进入应用的第一页） ──
    expect(find.text('累计'), findsOneWidget);
    expect(find.text('收到消息'), findsOneWidget);
    expect(find.text('发出消息'), findsOneWidget);
    expect(find.text('今日'), findsOneWidget);
    expect(find.text('趋势'), findsOneWidget);
    // 没有任何数据时不应出现负数或崩溃，而是给出说明。
    expect(find.textContaining('还没有数据'), findsOneWidget);

    // ── 机器人 Tab：无账号时应显示引导空状态 ──
    await tester.tap(find.byIcon(Icons.smart_toy_outlined));
    await tester.pumpAndSettle();
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
    // 插件协议说明已按要求移除。
    expect(find.text('插件协议'), findsNothing);

    // ── 设置 Tab ──
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.text('外观'), findsOneWidget);

    // 事件订阅范围必须可见且带风险提示：这是「收不到消息」这个 bug 的用户侧入口，
    // 默认只订阅必需位，可选位需用户按权限自行开启。
    expect(find.text('事件订阅范围（intents）'), findsOneWidget);
    expect(find.textContaining('会报错并直接关闭连接'), findsOneWidget);
    expect(find.text('GROUP_MEMBER_EVENT'), findsOneWidget);
    expect(find.text('该位不在官方 intents 清单中，风险最高'), findsOneWidget);

    // 已按要求移除的区块不应再出现。
    expect(find.text('运行环境'), findsNothing);
    expect(find.text('官方限制速查'), findsNothing);
    expect(find.text('诊断'), findsNothing);

    // 后台保活：这是「应用退到后台就掉线」的修复入口，必须可达。
    //
    // 分两次滚动而不是一次拖到底：列表是懒构建的，
    // 一次拖太远会跳过中间内容（未构建的条目根本不在树里，断言会失败）。
    final settingsList = find.byType(ListView).last;
    await tester.drag(settingsList, const Offset(0, -700), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('后台保活'), findsOneWidget);
    expect(find.text('保活前台服务'), findsOneWidget);

    // 保活的三个系统前提必须可见：只给开关不给事实，用户遇到
    // 「开关是开的但机器人不在线」时没有任何排查方向。
    await tester.drag(settingsList, const Offset(0, -400), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('服务状态'), findsOneWidget);
    expect(find.text('精确闹钟'), findsOneWidget);
    expect(find.text('电池优化'), findsOneWidget);

    // 关于：只保留当前版本与作者。
    await tester.drag(settingsList, const Offset(0, -700), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('关于'), findsOneWidget);
    expect(find.text(AppInfo.version), findsOneWidget);
    expect(find.text(AppInfo.author), findsOneWidget);
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
