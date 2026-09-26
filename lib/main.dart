import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/app_services.dart';
import 'core/constants/app_config.dart';
import 'core/logging/app_logger.dart';
import 'domain/models/log_entry.dart';

/// 应用入口。
///
/// 启动顺序是刻意的：
/// 1. 绑定 Flutter 引擎（`flutter_secure_storage` 等插件依赖它）；
/// 2. 构造服务容器并完成初始化（恢复数据 → 探测插件能力 → 建连接）；
/// 3. 再渲染界面。
///
/// 这样界面第一次出现时状态就是真实的，不会出现「先显示空的账号列表，
/// 半秒后突然冒出来」这种闪烁。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final services = AppServices(config: AppConfig.current);

  try {
    await services.initialize();
  } catch (error, stack) {
    // 初始化失败也要让应用能打开：否则用户只会看到一个白屏，
    // 连日志都看不到（而日志正是排查的入口）。
    AppLogger.error('初始化失败', error: error, stackTrace: stack, tag: 'boot');
    services.log.error(
      LogSource.system,
      '初始化过程中出现异常：$error',
      detail: '$stack',
    );
  }

  runApp(
    ProviderScope(
      overrides: [appServicesProvider.overrideWithValue(services)],
      child: const LaveApp(),
    ),
  );

  AppLogger.info(
    '应用已启动（环境 ${AppEnvironment.label}）',
    tag: 'boot',
  );
  // 说明：Flutter 没有跨平台的「应用即将退出」回调（Android 与 iOS 的
  // 生命周期语义不同），因此子进程的兜底方案是插件自身监听 stdin 关闭
  // 后自行退出 —— 主进程消失时 stdin 会 EOF。
}
