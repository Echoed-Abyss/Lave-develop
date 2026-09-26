import 'package:flutter/material.dart';

import '../api/interaction_api.dart';
import '../api/media_api.dart';
import '../api/message_api.dart';
import '../api/qq_http_client.dart';
import '../api/token_api.dart';
import '../core/constants/app_config.dart';
import '../core/logging/app_logger.dart';
import '../core/logging/log_service.dart';
import '../data/local/credential_store.dart';
import '../data/local/json_doc_store.dart';
import '../data/repository/bot_repository.dart';
import '../data/repository/history_repository.dart';
import '../domain/models/log_entry.dart';
import '../gateway/connection_registry.dart';
import '../gateway/gateway_api.dart';
import '../plugins/plugin_manager.dart';

/// 应用服务装配。
///
/// 为什么用一个「手写容器」而不是让 Riverpod 逐层构建：
/// 这些服务之间存在**明确的启动顺序**（先恢复本地数据，再探测插件平台能力，
/// 最后才建连接），而且都是单例、长生命周期。
/// 手写装配让顺序一目了然，也避免了异步 Provider 之间的隐式依赖。
/// Riverpod 仍然负责把本对象注入到 UI 树（见 `main.dart` 的 override）。
class AppServices {
  AppServices({AppConfig? config, JsonDocStore? store})
      : config = config ?? AppConfig.current,
        store = store ?? JsonDocStore(fileName: 'lave_store.json') {
    log = LogService(store: this.store);
    credentials = CredentialStore();

    bots = BotRepository(store: this.store, config: this.config);
    history = HistoryRepository(store: this.store);

    plugins = PluginManager(
      log: log,
      store: JsonPluginStateStore(store: this.store),
    );

    http = QqHttpClient(log: log, config: this.config);
    tokens = AccessTokenManager(
      http: http,
      credentials: credentials,
      log: log,
      config: this.config,
    );

    gatewayApi = GatewayApi(http: http, tokens: tokens, log: log);
    messageApi = MessageApi(http: http, tokens: tokens, log: log);
    mediaApi = MediaApi(httpClient: http, tokens: tokens, log: log);
    interactionApi = InteractionApi(http: http, tokens: tokens, log: log);

    registry = ConnectionRegistry(
      log: log,
      config: this.config,
      bots: bots,
      history: history,
      plugins: plugins,
      tokens: tokens,
      gatewayApi: gatewayApi,
      messageApi: messageApi,
      mediaApi: mediaApi,
      interactionApi: interactionApi,
    );
  }

  /// 运行配置（调试 / 生产）。
  final AppConfig config;

  /// 本地 JSON 存储。
  final JsonDocStore store;

  /// 日志服务。
  late final LogService log;

  /// 凭证安全存储。
  late final CredentialStore credentials;

  /// 机器人账号仓库。
  late final BotRepository bots;

  /// 消息与事件仓库。
  late final HistoryRepository history;

  /// 插件管理。
  late final PluginManager plugins;

  /// HTTP 客户端。
  late final QqHttpClient http;

  /// 访问凭证管理。
  late final AccessTokenManager tokens;

  /// WSS 接入点获取。
  late final GatewayApi gatewayApi;

  /// 消息接口。
  late final MessageApi messageApi;

  /// 富媒体上传接口。
  late final MediaApi mediaApi;

  /// 互动回应接口（消息按钮 / 快捷菜单必须回应，否则客户端一直 loading）。
  late final InteractionApi interactionApi;

  /// 多机器人连接注册表。
  late final ConnectionRegistry registry;

  /// 界面主题模式控制器。
  final ValueNotifier<ThemeMode> themeMode =
      ValueNotifier<ThemeMode>(ThemeMode.system);

  /// 是否已完成初始化。
  bool get isInitialized => _initialized;
  bool _initialized = false;

  /// 启动初始化。
  ///
  /// 顺序刻意固定：
  /// 1. 先恢复日志与本地数据 —— 后面任何一步失败都要有日志可查；
  /// 2. 再探测插件平台能力 —— 结论要写进日志，让用户知道插件为何不可用；
  /// 3. 最后才建立连接 —— 连接会持续产生事件，必须在前面都就绪之后。
  Future<void> initialize() async {
    if (_initialized) return;
    log.info(
      LogSource.system,
      '应用启动（环境 ${AppEnvironment.label}，'
      '并发上限 ${config.maxConcurrentConnections}）',
    );

    await log.restore();
    await bots.restore();
    await history.restore();
    await _restoreTheme();

    await plugins.initialize();

    await registry.syncWithBots();

    _initialized = true;
    log.info(
      LogSource.system,
      '初始化完成：账号 ${bots.bots.length} 个，'
      '启用 ${bots.enabledBots.length} 个，'
      '插件 ${plugins.plugins.length} 个'
      '${plugins.isSupported ? '' : '（当前平台不支持运行）'}',
    );
  }

  /// 切换主题并持久化。
  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode.value = mode;
    final doc = await store.read();
    doc['theme_mode'] = mode.name;
    await store.write(doc);
  }

  Future<void> _restoreTheme() async {
    final doc = await store.read();
    final name = doc['theme_mode']?.toString();
    for (final mode in ThemeMode.values) {
      if (mode.name == name) {
        themeMode.value = mode;
        return;
      }
    }
  }

  /// 退出前的收尾：停连接、停插件进程。
  ///
  /// 必须显式调用：插件是独立进程，不主动结束会在系统里留下孤儿进程。
  Future<void> shutdown() async {
    AppLogger.info('开始收起应用资源', tag: 'lifecycle');
    await registry.shutdown();
    await plugins.shutdownAll();
    http.dispose();
    mediaApi.dispose();
  }
}
