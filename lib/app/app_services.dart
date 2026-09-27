import 'dart:async';

import 'package:flutter/material.dart';

import '../api/interaction_api.dart';
import '../api/media_api.dart';
import '../api/message_api.dart';
import '../api/qq_http_client.dart';
import '../api/token_api.dart';
import '../api/user_api.dart';
import '../core/constants/app_config.dart';
import '../core/logging/app_logger.dart';
import '../core/logging/log_service.dart';
import '../data/local/credential_store.dart';
import '../data/local/json_doc_store.dart';
import '../data/repository/bot_repository.dart';
import '../data/repository/history_repository.dart';
import '../data/repository/stats_repository.dart';
import '../domain/models/log_entry.dart';
import '../gateway/connection_registry.dart';
import '../gateway/gateway_api.dart';
import '../gateway/protocol/qq_opcode.dart';
import '../plugins/native_runtime_info.dart';
import '../plugins/plugin_manager.dart';
import 'keep_alive_coordinator.dart';

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
    stats = StatsRepository(store: this.store);

    plugins = PluginManager(
      log: log,
      store: JsonPluginStateStore(store: this.store),
      // 内置 Python 的启动器与 libpython 都在原生库目录里，
      // 而该路径只能在 Android 侧拿到（含安装时生成的哈希）。
      nativeDirectoryProvider: nativeInfo.nativeLibraryDir,
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
    userApi = UserApi(http: http, tokens: tokens, log: log);

    registry = ConnectionRegistry(
      log: log,
      config: this.config,
      bots: bots,
      history: history,
      stats: stats,
      plugins: plugins,
      tokens: tokens,
      gatewayApi: gatewayApi,
      messageApi: messageApi,
      mediaApi: mediaApi,
      interactionApi: interactionApi,
      intentsMaskProvider: () => intentsMask.value,
      onIntentsDegraded: (attempted, degraded) {
        // 被网关以 4014 拒绝后把降级结果固化下来：
        // 只在内存里降级的话，下次冷启动又用回原掩码，会再失败一遍。
        unawaited(setIntentsMask(degraded, notifyDegraded: true));
      },
    );

    keepAlive = KeepAliveCoordinator(
      log: log,
      bots: bots,
      registry: registry,
      store: this.store,
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

  /// 消息收发统计（首页折线图的数据源）。
  late final StatsRepository stats;

  /// 插件管理。
  late final PluginManager plugins;

  /// 平台原生信息（原生库目录等）。
  final NativeRuntimeInfo nativeInfo = NativeRuntimeInfo();

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

  /// 机器人自身资料接口（唯一的头像来源）。
  late final UserApi userApi;

  /// 多机器人连接注册表。
  late final ConnectionRegistry registry;

  /// 后台保活协调器（前台服务起停 + 保活相关系统能力）。
  ///
  /// 它的重要性容易被低估：本应用全部功能都依赖那条 WSS 长连接，
  /// 而应用退到后台后进程会被 Android 冻结、心跳停发、连接必断。
  /// 保活不是「优化项」，是连接能否存活的前提。
  late final KeepAliveCoordinator keepAlive;

  /// 界面主题模式控制器。
  final ValueNotifier<ThemeMode> themeMode =
      ValueNotifier<ThemeMode>(ThemeMode.system);

  /// 当前生效的事件订阅掩码。
  ///
  /// 默认只含必需位（单聊与群聊事件）。**这不是保守，而是必须**：
  /// 官方明确「传递了无权限的 intents，websocket 会报错并直接关闭连接」，
  /// 而基础事件之外都需要申请权限。可选位由用户在设置页确认后再打开，
  /// 并在被网关拒绝时自动降级。
  final ValueNotifier<int> intentsMask =
      ValueNotifier<int>(QqIntents.defaultMask);

  /// 用户勾选的可选订阅位（与 [intentsMask] 双向对应）。
  Set<QqOptionalIntent> selectedOptionalIntents =
      QqIntents.extrasOf(QqIntents.defaultMask);

  /// 是否已完成初始化。
  bool get isInitialized => _initialized;
  bool _initialized = false;

  /// 启动初始化。
  ///
  /// 顺序刻意固定：
  /// 1. 先恢复日志与本地数据 —— 后面任何一步失败都要有日志可查；
  /// 2. 再探测插件平台能力 —— 结论要写进日志，让用户知道插件为何不可用；
  /// 3. 起保活前台服务 —— 必须早于建连接：等连接建立再保活的话，
  ///    首次冷启动到连上之间的这段时间进程还不是前台，
  ///    用户此刻切走应用就会让刚建立的连接立刻被冻结；
  /// 4. 最后才建立连接 —— 连接会持续产生事件，必须在前面都就绪之后。
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
    await stats.restore();
    await _restoreTheme();

    await plugins.initialize();

    await keepAlive.start();

    await registry.syncWithBots();

    // 资料刷新放在最后且不 await：它只是为了让列表与气泡显示真实昵称与头像，
    // 失败没有任何副作用，没必要挡住「初始化完成」这一步。
    if (bots.bots.isNotEmpty) unawaited(refreshBotIdentities());

    _initialized = true;
    log.info(
      LogSource.system,
      '初始化完成：账号 ${bots.bots.length} 个，'
      '启用 ${bots.enabledBots.length} 个，'
      '插件 ${plugins.plugins.length} 个'
      '${plugins.isSupported ? '' : '（当前平台不支持运行）'}',
    );
  }

  /// 拉取单个机器人的官方资料（昵称与头像）并写回账号。
  ///
  /// 只更新官方字段，不动用户填的备注名——见 `BotRepository.updateIdentity`。
  /// 失败静默返回：该接口只影响展示，不该在界面上冒出错误提示。
  Future<void> refreshBotIdentity(String appId) async {
    final identity = await userApi.fetchSelf(appId);
    if (identity == null || !identity.hasAnything) return;
    await bots.updateIdentity(
      appId,
      officialName: identity.username,
      avatarUrl: identity.avatarUrl,
    );
  }

  /// 刷新全部机器人的官方资料（启动时与新增账号后各调用一次）。
  Future<void> refreshBotIdentities() async {
    for (final bot in bots.bots) {
      await refreshBotIdentity(bot.appId);
    }
  }

  /// 切换主题并持久化。
  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode.value = mode;
    final doc = await store.read();
    doc['theme_mode'] = mode.name;
    await store.write(doc);
  }

  /// 修改事件订阅范围并持久化。
  ///
  /// [notifyDegraded] 为 `true` 时表示这次修改来自「网关拒绝后的自动降级」，
  /// 会额外写一条日志让用户知道订阅范围被收窄了——静默改变行为比报错更糟。
  Future<void> setIntentsMask(int mask, {bool notifyDegraded = false}) async {
    intentsMask.value = mask;
    selectedOptionalIntents = QqIntents.extrasOf(mask);

    final doc = await store.read();
    doc['intents_mask'] = mask;
    await store.write(doc);

    if (notifyDegraded) {
      log.warn(
        LogSource.gateway,
        '事件订阅范围已自动收窄至 recv=$mask，请到设置页确认',
        detail: '原因：网关以 4014（intent 无权限）拒绝了上一次订阅。'
            '如需恢复完整能力，请先在开放平台后台申请对应权限，'
            '再回到设置页重新勾选。',
      );
    }
  }

  /// 按用户勾选的可选位重建掩码。
  Future<void> setOptionalIntents(Set<QqOptionalIntent> extras) =>
      setIntentsMask(QqIntents.maskWith(extras));

  Future<void> _restoreTheme() async {
    final doc = await store.read();
    final name = doc['theme_mode']?.toString();
    for (final mode in ThemeMode.values) {
      if (mode.name == name) {
        themeMode.value = mode;
        break;
      }
    }
    final savedMask = doc['intents_mask'];
    if (savedMask is num) {
      // 安全兜底：读回来的掩码必须至少包含必需位，否则会「连上但什么都收不到」。
      final mask = savedMask.toInt() | QqIntents.minimal;
      intentsMask.value = mask;
      selectedOptionalIntents = QqIntents.extrasOf(mask);
    }
  }

  /// 用户请求退出应用时的收尾。返回「退出后是否仍保持在线」。
  ///
  /// ## 为什么不能一律 [shutdown]
  ///
  /// 这个应用的核心承诺是「机器人 24 小时在线」。若在用户离开应用时把网关
  /// 与保活前台服务一起拆掉，那么「离开」就等于「机器人下线」——
  /// 而用户之所以开保活，恰恰是不希望这样。
  ///
  /// 因此退出分成两种语义：
  /// - **开着保活**：只把数据落盘（统计与历史都走 3 秒防抖，不补一次立即写
  ///   就会丢掉最后几条消息），网关、插件与前台服务全部继续运行。
  ///   原生侧 `shouldDestroyEngineWithHost()` 为 false，所以 Activity 销毁后
  ///   Dart 依然活着、心跳照发、连接不断。
  /// - **没开保活**：用户要的就是「关掉」，此时才做完整收尾
  ///   （停连接、停插件进程、撤掉前台服务），避免留下孤儿进程与
  ///   一条内容与事实不符的常驻通知。
  ///
  /// 判断用 [KeepAliveCoordinator.isEnabled] **且**至少有一个启用的机器人：
  /// 与 [KeepAliveCoordinator] 内部「该不该起服务」的口径完全一致，
  /// 否则会出现「服务已停但这里以为还在保活」的错配。
  Future<bool> handleExitRequest() async {
    final stayingOnline = keepAlive.isEnabled && bots.enabledBots.isNotEmpty;

    if (!stayingOnline) {
      await shutdown();
      return false;
    }

    // 先把前台服务补一次（force）：退出瞬间是本进程最后一次能主动
    // 确认「保活是否真的在跑」的机会，若它其实没起来，
    // 放走 Activity 之后就更没有时机补救了。
    await keepAlive.reassert();
    // 统计与历史都走 3 秒防抖落盘，这里各补一次立即写，
    // 否则「刚收到最后几条消息就退出」会把它们丢掉。
    await stats.flush();
    await history.flush();

    log.info(
      LogSource.system,
      '应用已退到后台，机器人与插件继续在线',
      detail: '后台保活处于开启状态，因此这里只落盘、不停服务。'
          '要真正停止，请关闭「后台保活」开关，'
          '或点常驻通知上的「停止保活」。',
    );
    return true;
  }

  /// 退出前的完整收尾：停连接、停插件进程、撤掉保活前台服务。
  ///
  /// 必须显式调用：插件是独立进程，不主动结束会在系统里留下孤儿进程；
  /// 保活服务不撤掉则会留下一个「正在维持网关连接」的常驻通知，
  /// 而那时连接其实已经被关掉了——通知内容与事实不符是更糟的结果。
  Future<void> shutdown() async {
    AppLogger.info('开始收起应用资源', tag: 'lifecycle');
    await keepAlive.detach();
    // 统计与历史都走 3 秒防抖落盘，这里各补一次立即写，
    // 否则「刚收到最后几条消息就退出」会把它们丢掉。
    await stats.flush();
    await history.flush();
    await registry.shutdown();
    await plugins.shutdownAll();
    http.dispose();
    mediaApi.dispose();
  }
}
