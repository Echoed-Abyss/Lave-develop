import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../api/bot_message_service.dart';
import '../api/qq_http_client.dart';
import '../core/logging/app_logger.dart';
import '../core/logging/log_service.dart';
import '../domain/models/log_entry.dart';
import '../domain/models/plugin_models.dart';
import '../domain/models/qq_enums.dart';
import 'plugin_runtime.dart';

/// 插件管理。
///
/// ## 崩溃隔离是怎么做到的
///
/// 每个插件跑在**独立的操作系统进程**里。因此：
/// - 插件抛未捕获异常 → 进程退出 → 只有这个插件变「已崩溃」，
///   主程序与其它插件完全不受影响；
/// - 插件死循环 → 只占用它自己的 CPU 时间片，主程序的 UI 与连接照常；
/// - 插件写出超长 stdout → 只影响它自己那条管道。
///
/// 崩溃后**不自动重启**：崩溃往往是插件代码的确定性缺陷，
/// 自动重启只会形成「崩溃 → 重启 → 再崩溃」的循环，白白耗电。
/// 界面会显示「已崩溃 N 次」并给出手动重启按钮。
class PluginManager extends ChangeNotifier {
  PluginManager({
    required LogService log,
    required PluginStateStoreLike store,
  })  : _log = log,
        _store = store;

  final LogService _log;
  final PluginStateStoreLike _store;

  PluginRuntime? _runtime;

  /// 当前平台能力。初始化前为「未知（按不支持处理）」。
  PluginRuntimeCapability _capability = PluginRuntimeCapability.unsupported(
    platform: 'unknown',
    reason: '尚未完成平台能力探测',
  );

  PluginRuntimeCapability get capability => _capability;

  /// 是否支持运行插件。
  bool get isSupported => _capability.supported;

  /// 全部插件（按 ID 排序，保证界面顺序稳定）。
  List<PluginDescriptor> get plugins {
    final list = _plugins.values.toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    return List.unmodifiable(list);
  }

  /// 正在运行的插件数量。
  int get runningCount => _plugins.values.where((e) => e.isRunning).length;

  /// 是否有插件处于崩溃态（界面据此显示提示）。
  bool get hasCrashed => _plugins.values.any((e) => e.status.isFailure);

  final Map<String, PluginDescriptor> _plugins = {};
  final Map<String, PluginProcess> _processes = {};
  final Map<String, StreamSubscription<PluginMessage>> _messageSubs = {};
  final Map<String, StreamSubscription<int>> _exitSubs = {};
  int _requestSeed = 0;

  /// 插件根目录（应用文档目录下的 `plugins`）。
  Future<Directory> pluginsDirectory() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'plugins'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// 初始化：探测平台能力 → 扫描插件目录 → 恢复启用状态。
  Future<void> initialize() async {
    _runtime = await PluginRuntime.probe();
    _capability = _runtime!.capability;

    _log.log(
      LogEntry(
        level: _capability.supported ? LogLevel.info : LogLevel.warn,
        source: LogSource.plugin,
        message: _capability.describe,
        at: DateTime.now(),
      ),
    );

    await refresh();
  }

  /// 重新扫描插件目录。
  Future<void> refresh() async {
    final dir = await pluginsDirectory();
    final enabled = await _store.readSet('enabled');
    final crashCounts = await _store.readIntMap('crash_count');
    final found = <String, PluginDescriptor>{};

    await for (final entity in dir.list()) {
      if (entity is! Directory) continue;
      final manifestFile = File(p.join(entity.path, 'plugin.json'));
      if (!await manifestFile.exists()) continue;
      try {
        final decoded = jsonDecode(await manifestFile.readAsString());
        if (decoded is! Map) continue;
        final manifest =
            PluginManifest.fromJson(decoded.cast<String, dynamic>());
        if (manifest.id.isEmpty) continue;

        final isEnabled = enabled.contains(manifest.id) ||
            (manifest.enabledByDefault && !enabled.contains('!${manifest.id}'));

        found[manifest.id] = PluginDescriptor(
          manifest: manifest,
          status: !_capability.supported
              ? PluginStatus.unsupported
              : (isEnabled ? PluginStatus.stopped : PluginStatus.disabled),
          enabled: isEnabled && _capability.supported,
          crashCount: crashCounts[manifest.id] ?? 0,
        );
      } catch (error) {
        _log.warn(
          LogSource.plugin,
          '插件清单解析失败，已跳过：${p.basename(entity.path)}',
          detail: '$error',
        );
      }
    }

    _plugins
      ..clear()
      ..addAll(found);
    notifyListeners();
  }

  /// 启用 / 禁用插件。
  Future<void> setEnabled(String pluginId, bool enabled) async {
    final descriptor = _plugins[pluginId];
    if (descriptor == null) return;

    if (enabled && !_capability.supported) {
      _log.warn(
        LogSource.plugin,
        '当前平台不支持运行插件，无法启用 ${descriptor.manifest.name}',
        pluginId: pluginId,
        detail: _capability.reason,
      );
      return;
    }

    final names = await _store.readSet('enabled');
    if (enabled) {
      names.add(pluginId);
      names.remove('!$pluginId');
    } else {
      names.remove(pluginId);
      names.add('!$pluginId');
    }
    await _store.writeSet('enabled', names);

    _plugins[pluginId] = descriptor.copyWith(
      enabled: enabled,
      status: enabled ? PluginStatus.stopped : PluginStatus.disabled,
      clearError: true,
    );
    notifyListeners();

    if (!enabled) await stop(pluginId);
  }

  /// 启动插件。
  Future<void> start(String pluginId) async {
    final descriptor = _plugins[pluginId];
    if (descriptor == null || !_capability.supported) return;
    if (_processes.containsKey(pluginId)) return;

    final dir = await pluginsDirectory();
    final pluginDir = p.join(dir.path, pluginId);

    _plugins[pluginId] = descriptor.copyWith(
      status: PluginStatus.starting,
      clearError: true,
    );
    notifyListeners();

    final process = await _runtime!.startProcess(
      manifest: descriptor.manifest,
      directory: pluginDir,
      onStderr: (line) => _log.log(
        LogEntry(
          level: LogLevel.warn,
          source: LogSource.plugin,
          message: line,
          at: DateTime.now(),
          pluginId: pluginId,
        ),
      ),
    );

    if (process == null) {
      _plugins[pluginId] = descriptor.toCrashed(
        reason: '进程启动失败，详见日志',
        at: DateTime.now(),
      );
      await _bumpCrashCount(pluginId);
      notifyListeners();
      return;
    }

    _processes[pluginId] = process;

    // 插件自身的日志（含 print 与 stderr）全部转进日志服务，
    // 这样用户在「日志」Tab 里就能看到插件输出，不必另连调试器。
    process.logLines.listen((message) {
      _log.log(
        LogEntry(
          level: message.logLevel,
          source: LogSource.plugin,
          message: message.logMessage,
          at: DateTime.now(),
          pluginId: pluginId,
        ),
      );
    });

    _messageSubs[pluginId] = process.messages.listen(
      (message) => _onPluginMessage(pluginId, message),
    );

    _exitSubs[pluginId] = process.exits.listen((code) async {
      // 崩溃隔离的落点：进程退出只标记这一个插件。
      final current = _plugins[pluginId];
      _processes.remove(pluginId);
      await _messageSubs.remove(pluginId)?.cancel();
      await _exitSubs.remove(pluginId)?.cancel();
      await _bumpCrashCount(pluginId);
      if (current != null) {
        _plugins[pluginId] = current.toCrashed(
          reason: code == 0 ? '进程正常退出' : '进程异常退出（退出码 $code）',
          at: DateTime.now(),
        );
        notifyListeners();
      }
      _log.error(
        LogSource.plugin,
        '插件 ${descriptor.manifest.name} 的进程已退出（退出码 $code）',
        pluginId: pluginId,
      );
    });

    // 下发 init：插件据此完成自身初始化并回 ready。
    process.send(
      PluginMessage(
        type: PluginMessageType.init,
        payload: {
          'plugin_id': pluginId,
          'manifest': descriptor.manifest.toJson(),
          'capability': {
            'platform': _capability.platform,
            'python': _capability.pythonExecutable,
          },
        },
      ),
    );

    _plugins[pluginId] = descriptor.copyWith(
      status: PluginStatus.running,
      pid: process.pid,
      lastStartedAt: DateTime.now(),
      clearError: true,
    );
    notifyListeners();
    _log.info(
      LogSource.plugin,
      '插件 ${descriptor.manifest.name} 已启动（PID ${process.pid}）',
      pluginId: pluginId,
    );
  }

  /// 停止插件。
  Future<void> stop(String pluginId) async {
    final process = _processes.remove(pluginId);
    if (process != null) {
      await process.stop();
    }
    await _messageSubs.remove(pluginId)?.cancel();
    await _exitSubs.remove(pluginId)?.cancel();

    final descriptor = _plugins[pluginId];
    if (descriptor != null) {
      _plugins[pluginId] = descriptor.copyWith(
        status: descriptor.enabled ? PluginStatus.stopped : PluginStatus.disabled,
        lastStoppedAt: DateTime.now(),
        clearPid: true,
      );
      notifyListeners();
      _log.info(
        LogSource.plugin,
        '插件 ${descriptor.manifest.name} 已停止',
        pluginId: pluginId,
      );
    }
  }

  /// 删除插件（停止进程并删除整个插件目录）。
  Future<void> remove(String pluginId) async {
    await stop(pluginId);
    final dir = await pluginsDirectory();
    final pluginDir = Directory(p.join(dir.path, pluginId));
    if (await pluginDir.exists()) {
      await pluginDir.delete(recursive: true);
      _log.info(LogSource.plugin, '已删除插件目录：$pluginId');
    }
    _plugins.remove(pluginId);
    final names = await _store.readSet('enabled');
    names.remove(pluginId);
    names.remove('!$pluginId');
    await _store.writeSet('enabled', names);
    notifyListeners();
  }

  /// 停止全部插件（应用退出时调用）。
  Future<void> shutdownAll() async {
    for (final id in _processes.keys.toList()) {
      await stop(id);
    }
  }

  /// 把事件投递给插件。
  ///
  /// [eventPayload] 是**归一化后的事件载荷**（不是官方原始 JSON）：
  /// 插件作者看到的是稳定结构，官方字段改名不会直接打断插件。
  /// 载荷结构见 `docs/qq-bot/app-architecture.html` 的插件协议说明。
  Future<void> dispatch(
    Map<String, dynamic> eventPayload, {
    required String eventType,
    required String botId,
  }) async {
    if (_processes.isEmpty) return;
    final requestId = 'evt-${++_requestSeed}';
    final message = PluginMessage(
      type: PluginMessageType.event,
      requestId: requestId,
      payload: {
        't': eventType,
        'bot_id': botId,
        'event': eventPayload,
      },
    );

    for (final entry in _processes.entries) {
      final descriptor = _plugins[entry.key];
      if (descriptor == null) continue;
      // 按插件声明的订阅范围过滤：不声明则视为订阅全部。
      if (!descriptor.manifest.subscribesTo(eventType)) continue;
      entry.value.send(message);
    }
  }

  Future<void> _onPluginMessage(String pluginId, PluginMessage message) async {
    switch (message.type) {
      case PluginMessageType.ready:
        _log.info(
          LogSource.plugin,
          '插件已就绪（handshake 完成）',
          pluginId: pluginId,
        );
      case PluginMessageType.reply:
        await _handleReplyRequest(pluginId, message);
      case PluginMessageType.log:
        _log.log(
          LogEntry(
            level: message.logLevel,
            source: LogSource.plugin,
            message: message.logMessage,
            at: DateTime.now(),
            pluginId: pluginId,
          ),
        );
      default:
        break;
    }
  }

  /// 处理插件发来的「代发消息」请求。
  ///
  /// 设计上**由主进程代为调用官方接口**，而不是把凭据交给插件：
  /// 这样插件永远拿不到 access_token，插件被恶意替换也无法直接控制机器人。
  Future<void> _handleReplyRequest(String pluginId, PluginMessage message) async {
    final payload = message.payload;
    final botId = payload['bot_id'] as String?;
    final sender = botId == null ? null : _senders[botId];
    if (sender == null) {
      _log.warn(
        LogSource.plugin,
        '插件请求发送消息，但找不到对应的机器人通道',
        pluginId: pluginId,
        detail: 'bot_id=$botId',
      );
      return;
    }

    final conversationId = payload['conversation_id'] as String?;
    final text = payload['text'] as String?;
    if (conversationId == null || text == null) {
      _log.warn(
        LogSource.plugin,
        '插件请求参数不完整，已忽略',
        pluginId: pluginId,
        detail: '$payload',
      );
      return;
    }

    final scope = payload['scope'] == 'group'
        ? ConversationScope.group
        : ConversationScope.c2c;

    final ApiResponse response = await sender.sendText(
      conversationId: conversationId,
      scope: scope,
      text: text,
      passive: payload['passive'] as bool? ?? true,
      msgId: payload['msg_id'] as String?,
      eventId: payload['event_id'] as String?,
    );

    _log.log(
      LogEntry(
        level: response.isSuccess ? LogLevel.info : LogLevel.error,
        source: LogSource.plugin,
        message: response.isSuccess
            ? '插件消息已发送'
            : '插件消息发送失败：${response.failure!.userMessage}',
        at: DateTime.now(),
        pluginId: pluginId,
        officialCode: response.failure?.officialCode,
        traceId: response.traceId,
      ),
    );
  }

  /// 各机器人的代发通道（由上层在连接建立后注入）。
  ///
  /// 按 botId 分开存而不是只留一个：本应用支持多个机器人同时在线，
  /// 插件必须能把回复发回**触发它的那个机器人**，否则会出现
  /// 「A 机器人的插件回复发到 B 机器人的会话里」这种严重错乱。
  final Map<String, MessageSender> _senders = {};

  /// 注入 / 解除某个机器人的代发通道。
  void bindSender(String botId, MessageSender? sender) {
    if (sender == null) {
      _senders.remove(botId);
    } else {
      _senders[botId] = sender;
    }
  }

  Future<void> _bumpCrashCount(String pluginId) async {
    final counts = await _store.readIntMap('crash_count');
    counts[pluginId] = (counts[pluginId] ?? 0) + 1;
    await _store.writeIntMap('crash_count', counts);
  }

  @override
  void dispose() {
    for (final sub in _messageSubs.values) {
      unawaited(sub.cancel());
    }
    for (final sub in _exitSubs.values) {
      unawaited(sub.cancel());
    }
    for (final process in _processes.values) {
      unawaited(process.stop());
    }
    super.dispose();
  }
}

/// 插件状态的持久化依赖面。
abstract interface class PluginStateStoreLike {
  Future<Set<String>> readSet(String key);

  Future<void> writeSet(String key, Set<String> values);

  Future<Map<String, int>> readIntMap(String key);

  Future<void> writeIntMap(String key, Map<String, int> values);
}

/// 基于 JSON 文档的默认实现。
class JsonPluginStateStore implements PluginStateStoreLike {
  JsonPluginStateStore({required JsonDocStoreLike store}) : _store = store;

  final JsonDocStoreLike _store;

  @override
  Future<Set<String>> readSet(String key) async {
    final items = await _store.readList(key);
    return items
        .map((e) => e['value']?.toString())
        .whereType<String>()
        .toSet();
  }

  @override
  Future<void> writeSet(String key, Set<String> values) => _store.writeList(
        key,
        values.map((v) => {'value': v}).toList(),
      );

  @override
  Future<Map<String, int>> readIntMap(String key) async {
    final items = await _store.readList(key);
    final result = <String, int>{};
    for (final item in items) {
      final k = item['key']?.toString();
      final v = item['value'];
      if (k == null || v is! num) continue;
      result[k] = v.toInt();
    }
    return result;
  }

  @override
  Future<void> writeIntMap(String key, Map<String, int> values) =>
      _store.writeList(
        key,
        values.entries
            .map((e) => {'key': e.key, 'value': e.value})
            .toList(),
      );
}

/// 插件协议版本。插件可据此判断主程序能力。
const int pluginProtocolVersion = 1;

/// 启动时打印一次，便于日志里确认协议版本。
void logProtocolVersion(LogService log) {
  AppLogger.info('插件协议版本：$pluginProtocolVersion', tag: 'plugin');
  log.info(LogSource.plugin, '插件协议版本 $pluginProtocolVersion');
}
