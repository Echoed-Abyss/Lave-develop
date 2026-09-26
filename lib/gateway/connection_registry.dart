import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/bot_message_service.dart';
import '../api/media_api.dart';
import '../api/message_api.dart';
import '../api/token_api.dart';
import '../core/constants/app_config.dart';
import '../core/logging/log_service.dart';
import '../data/repository/bot_repository.dart';
import '../data/repository/history_repository.dart';
import '../domain/command/command_engine.dart';
import '../domain/models/bot_profile.dart';
import '../domain/models/connection_status.dart';
import '../plugins/plugin_manager.dart';
import 'event_dispatcher.dart';
import 'gateway_api.dart';
import 'gateway_connection.dart';
import 'gateway_socket.dart';

/// 多机器人连接注册表。
///
/// 按 `botId` 维度组织：每个机器人一条独立的 WSS 连接、独立的事件分发器、
/// 独立的消息代发通道。这样做的依据是**官方的 Session 限额是按 Bot 维度计算**的
/// （`session_start_limit` 在 `GET /gateway/bot` 的响应里），
/// 多个机器人同时在线不会互相挤占配额。
///
/// 代价是移动端的耗电与内存随连接数线性上升，因此并发数由
/// `AppConfig.maxConcurrentConnections` 限制（默认 3），
/// 超出的机器人在界面层被拒绝启用。
class ConnectionRegistry extends ChangeNotifier {
  ConnectionRegistry({
    required LogService log,
    required AppConfig config,
    required BotRepository bots,
    required HistoryRepository history,
    required PluginManager plugins,
    required AccessTokenManager tokens,
    required GatewayApi gatewayApi,
    required MessageApi messageApi,
    required MediaApi mediaApi,
    GatewaySocketFactory? socketFactory,
  })  : _log = log,
        _config = config,
        _bots = bots,
        _history = history,
        _plugins = plugins,
        _tokens = tokens,
        _gatewayApi = gatewayApi,
        _messageApi = messageApi,
        _mediaApi = mediaApi,
        _socketFactory = socketFactory,
        // 指令引擎只需要一个日志口，用注册表自己的 LogService 即可。
        commands = CommandEngine(log: log);

  final LogService _log;
  final AppConfig _config;
  final BotRepository _bots;
  final HistoryRepository _history;
  final PluginManager _plugins;
  final AccessTokenManager _tokens;
  final GatewayApi _gatewayApi;
  final MessageApi _messageApi;
  final MediaApi _mediaApi;
  final GatewaySocketFactory? _socketFactory;

  final Map<String, GatewayConnection> _connections = {};
  final Map<String, EventDispatcher> _dispatchers = {};
  final Map<String, BotMessageService> _senders = {};

  /// 指令引擎（全局共用；指令本身不区分机器人）。
  final CommandEngine commands;

  /// 当前已建立连接对象的机器人。
  List<String> get knownBotIds => _connections.keys.toList(growable: false);

  /// 在线的机器人数量。
  int get onlineCount =>
      _connections.values.where((c) => c.status.value.isOnline).length;

  /// 取（必要时创建）某个机器人的连接。
  GatewayConnection connectionFor(String botId) {
    final existing = _connections[botId];
    if (existing != null) return existing;

    final sender = BotMessageService(
      botId: botId,
      messageApi: _messageApi,
      mediaApi: _mediaApi,
    );
    _senders[botId] = sender;

    final connection = GatewayConnection(
      botId: botId,
      gatewayApi: _gatewayApi,
      tokens: _tokens,
      bots: _bots,
      log: _log,
      config: _config,
      socketFactory: _socketFactory,
    );

    final dispatcher = EventDispatcher(
      botId: botId,
      history: _history,
      log: _log,
      sender: sender,
      commands: commands,
      plugins: _plugins,
      // 官方要求「处理过事件之后记录下 s」，因此水位推进放在分发层内部、
      // 在落库完成之后调用。
      acknowledgeSeq: connection.acknowledgeSeq,
    );

    // 连接层只负责协议；所有业务语义都在分发层。
    connection.events.listen(dispatcher.handle);

    _connections[botId] = connection;
    _dispatchers[botId] = dispatcher;

    // 通知监听者（界面上的连接状态徽标依赖它）。
    connection.status.addListener(notifyListeners);

    // 让插件能代发消息（按 botId 路由，避免跨机器人错发）。
    _plugins.bindSender(botId, sender);

    return connection;
  }

  /// 取某个机器人的消息发送通道。
  MessageSender? senderFor(String botId) {
    connectionFor(botId);
    return _senders[botId];
  }

  /// 取某个机器人的事件分发器（供界面查看统计）。
  EventDispatcher? dispatcherFor(String botId) => _dispatchers[botId];

  /// 启动某个机器人的连接。
  Future<void> startBot(BotProfile bot) async {
    if (!bot.enabled) return;
    final connection = connectionFor(bot.appId);
    await connection.start();
    notifyListeners();
  }

  /// 停止某个机器人的连接。
  Future<void> stopBot(String botId) async {
    final connection = _connections[botId];
    if (connection == null) return;
    await connection.stop();
    notifyListeners();
  }

  /// 按账号的启用状态对齐连接：启用的连上，禁用的断开。
  ///
  /// 在应用启动、账号增删改后调用。
  Future<void> syncWithBots() async {
    final enabled = _bots.enabledBots.map((b) => b.appId).toSet();

    for (final bot in _bots.enabledBots) {
      await startBot(bot);
    }
    for (final botId in _connections.keys.toList()) {
      if (!enabled.contains(botId)) await stopBot(botId);
    }
  }

  /// 断开全部连接（应用退出时调用）。
  Future<void> shutdown() async {
    for (final connection in _connections.values) {
      await connection.stop();
      await connection.dispose();
    }
    for (final botId in _connections.keys.toList()) {
      _plugins.bindSender(botId, null);
    }
    _connections.clear();
    _dispatchers.clear();
    _senders.clear();
    notifyListeners();
  }

  /// 汇总各机器人的连接状态，便于界面一次性渲染。
  List<({String botId, ConnectionStatusView view})> get statuses => _connections
      .entries
      .map(
        (e) => (
          botId: e.key,
          view: ConnectionStatusView(
            phase: e.value.status.value.phase,
            online: e.value.status.value.isOnline,
            attempt: e.value.status.value.attempt,
            message: e.value.status.value.lastError?.userMessage,
          ),
        ),
      )
      .toList(growable: false);

  @override
  void dispose() {
    for (final connection in _connections.values) {
      unawaited(connection.dispose());
    }
    super.dispose();
  }
}

/// 供界面渲染的连接状态视图。
@immutable
class ConnectionStatusView {
  const ConnectionStatusView({
    required this.phase,
    required this.online,
    required this.attempt,
    this.message,
  });

  /// 当前连接阶段。
  final ConnectionPhase phase;

  /// 是否在线。
  final bool online;

  /// 当前重连尝试次数。
  final int attempt;

  /// 最近一次错误提示。
  final String? message;
}
