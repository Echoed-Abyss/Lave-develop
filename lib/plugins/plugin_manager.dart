import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../api/bot_message_service.dart';
import '../api/dto/send_message_request.dart';
import '../api/qq_http_client.dart';
import '../core/logging/log_service.dart';
import '../core/utils/qq_json.dart';
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
    Future<String?> Function()? nativeDirectoryProvider,
    this.handshakeTimeout = const Duration(seconds: 20),
    this.pingInterval = const Duration(seconds: 30),
    this.maxMissedPongs = 3,
    this.autoStartDelay = const Duration(milliseconds: 400),
    this.maxAutoRestarts = 2,
    this.autoRestartDelay = const Duration(seconds: 2),
    this.logRateLimitPerSecond = 40,
  })  : _log = log,
        _store = store,
        _nativeDirectoryProvider = nativeDirectoryProvider;

  final LogService _log;
  final PluginStateStoreLike _store;

  /// 原生库目录来源（Android 上用于定位内置 Python 启动器）。
  final Future<String?> Function()? _nativeDirectoryProvider;

  /// 握手超时：进程起来了但迟迟不 `ready`，说明插件导入期就卡住了。
  final Duration handshakeTimeout;

  /// 心跳间隔。
  final Duration pingInterval;

  /// 连续多少次心跳无响应判定为卡死。
  ///
  /// 取 3 次（默认合计 90 秒静默）而不是 1 次：插件的正常业务处理
  /// 也可能占住事件循环几百毫秒，阈值太紧会误杀；而 90 秒的完全静默
  /// 基本只可能是死锁、`time.sleep` 长循环或子进程自身卡住。
  final int maxMissedPongs;

  /// 自动启动多个插件时的间隔，避免同一瞬间拉起一堆解释器。
  final Duration autoStartDelay;

  /// 单次会话内允许的自动重启次数。
  ///
  /// 早期设计是「崩溃后一律不自动重启」，理由是怕崩溃循环耗电。
  /// 但那样把**瞬时故障**（内存压力被杀、上游依赖抖动）也一并放弃了，
  /// 用户看到的是「插件莫名其妙不工作了」。改为有限次数的退避重启：
  /// 真崩的插件两次之后就会停下并标记为崩溃，不会形成循环。
  final int maxAutoRestarts;

  /// 自动重启前的等待时长（按重启次数线性退避）。
  final Duration autoRestartDelay;

  /// 每个插件每秒允许写入的日志行数上限。
  ///
  /// 插件在死循环里 `print` 会瞬间产生上万行；每一行都要落进日志服务
  /// （会通知界面刷新并排队写盘），足以让整个应用卡住。超限后丢弃并计数，
  /// 计数会显示在插件详情里——丢弃必须可见，否则排障时会以为插件没输出。
  final int logRateLimitPerSecond;

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
    final list = _plugins.values
        // 把实时事件计数合并进描述符（见 [_sentEvents] 的说明）。
        .map((d) => d.sentEvents == (_sentEvents[d.id] ?? 0)
            ? d
            : d.copyWith(sentEvents: _sentEvents[d.id]))
        .toList()
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
  final Map<String, StreamSubscription<PluginMessage>> _logSubs = {};
  final Map<String, StreamSubscription<int>> _exitSubs = {};
  int _requestSeed = 0;

  /// 主动停止（用户点了停止、或禁用/删除/退出应用）。
  ///
  /// 这个集合是**崩溃与主动停止的分界**：没有它，进程退出事件无法区分
  /// 「插件崩了」与「我让它停的」，于是每次主动停止都会被记成一次崩溃，
  /// 崩溃计数与「反复崩溃」提示都会失真。
  final Set<String> _intentionalStops = {};

  /// 本次会话内的自动重启次数（key = pluginId）。
  final Map<String, int> _autoRestarts = {};

  /// 已排定的重启定时器（key = pluginId）。
  final Map<String, Timer> _restartTimers = {};

  /// 每个插件的心跳定时器与连续未响应次数。
  final Map<String, Timer> _pingTimers = {};
  final Map<String, int> _missedPongs = {};

  /// 日志限流状态（key = pluginId）：当前秒窗口起始时刻与该窗口已放行行数。
  final Map<String, _LogBudget> _logBudgets = {};

  /// 已判定卡死、正在走重启流程的插件（避免重复触发）。
  final Set<String> _recovering = {};

  /// 插件根目录（应用文档目录下的 `plugins`）。
  Future<Directory> pluginsDirectory() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'plugins'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// 初始化：探测平台能力 → 扫描插件目录 → 恢复启用状态。
  Future<void> initialize() async {
    _runtime = await PluginRuntime.probe(
      nativeDirectoryProvider: _nativeDirectoryProvider,
    );
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

    // 自动拉起已启用的插件。
    //
    // **这一步曾经缺失**：刷新只把状态置为「未启动」，于是每次冷启动之后
    // 用户明明开着插件，它却一直是「未启动」——界面看起来没坏，
    // 但机器人对消息毫无反应，只能手动去点启动。这是插件系统最容易
    // 被误判为「插件坏了」的地方。
    //
    // 逐个错开启动：同一瞬间拉起多个解释器会让冷启动明显变卡，
    // 而且内置 Python 首次还要释放标准库（几百个文件）。
    unawaited(_autoStartEnabled());
  }

  /// 依次启动全部「用户已启用但当前没在跑」的插件。
  Future<void> _autoStartEnabled() async {
    if (!_capability.supported) return;
    final targets = _plugins.values
        .where((e) => e.enabled && e.status == PluginStatus.stopped)
        .map((e) => e.id)
        .toList(growable: false);
    if (targets.isEmpty) return;

    _log.info(
      LogSource.plugin,
      '正在自动启动 ${targets.length} 个已启用的插件',
      detail: targets.join('、'),
    );

    for (final id in targets) {
      // 每次循环都重新判断：用户可能在这期间手动停掉了它。
      if (_plugins[id]?.enabled != true) continue;
      if (_processes.containsKey(id)) continue;
      await start(id);
      if (!_isShuttingDown) await Future<void>.delayed(autoStartDelay);
    }
  }

  /// 应用是否正在退出（退出过程中不再自动重启、不再自动启动）。
  bool _isShuttingDown = false;

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

    // 把**正在运行**的插件的实时状态搬回来。
    //
    // refresh() 是从磁盘重建描述符的，若不合并，只要在插件运行期间调一次
    // refresh（例如导入新插件后重新扫描），运行中的插件就会显示回「未启动」，
    // 而进程其实还活着——界面与实际状态不一致是最难排查的一类问题。
    for (final id in _processes.keys) {
      final live = _liveSnapshot[id];
      final scanned = _plugins[id];
      if (live == null || scanned == null) continue;
      _plugins[id] = scanned.copyWith(
        status: live.status,
        pid: live.pid,
        lastStartedAt: live.lastStartedAt,
        lastReadyAt: live.lastReadyAt,
        lastPongAt: live.lastPongAt,
        missedPongs: live.missedPongs,
        sentEvents: live.sentEvents,
        droppedLogs: live.droppedLogs,
      );
    }

    notifyListeners();
  }

  /// 运行中插件的实时状态快照。
  ///
  /// 存在理由见 [refresh]：扫描结果来自磁盘，而进程状态只存在于内存，
  /// 两者必须合并，否则重新扫描会把「运行中」抹成「未启动」。
  final Map<String, PluginDescriptor> _liveSnapshot = {};

  /// 记录一次实时状态（每次描述符变更时同步调用）。
  void _publish(String pluginId, PluginDescriptor descriptor) {
    _plugins[pluginId] = descriptor;
    if (descriptor.status.hasProcess) {
      _liveSnapshot[pluginId] = descriptor;
    } else {
      _liveSnapshot.remove(pluginId);
    }
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

    _publish(pluginId, descriptor.copyWith(
      enabled: enabled,
      status: enabled ? PluginStatus.stopped : PluginStatus.disabled,
      clearError: true,
    ));

    if (!enabled) {
      await stop(pluginId);
    } else {
      // 启用即启动。
      //
      // 早先这里只把状态置为「未启动」：用户拨开开关，界面显示「已启用」，
      // 插件却一行代码都没跑，必须再单独点一次「启动」。这个两步操作
      // 是插件系统最容易被误判成「装了没用 / 插件坏了」的地方。
      // 顺便清掉自动重启预算——用户主动启用，理应拿到一次干净的重试机会。
      _autoRestarts.remove(pluginId);
      unawaited(start(pluginId));
    }
  }

  /// 用户显式重启。
  ///
  /// 与 [start] 只差一件事，但很关键：**清空本会话的自动重启预算**。
  /// 预算是用来拦住「崩溃—重启」死循环的；而用户亲手动这一下，说明他刚改完
  /// 代码或配置想再试一次。此时若还卡在「已自动重启 2 次」的额度上，
  /// 插件下次崩溃就再也不会自愈，用户会觉得重启按钮按了没用。
  /// 自动重启路径走的是 [start]，不会清预算，所以死循环仍然拦得住。
  Future<void> restart(String pluginId) async {
    final descriptor = _plugins[pluginId];
    if (descriptor == null) return;
    if (_processes.containsKey(pluginId)) await stop(pluginId);
    _cancelRestart(pluginId);
    _autoRestarts.remove(pluginId);
    _publish(pluginId, descriptor.copyWith(restartCount: 0));
    await start(pluginId);
  }

  /// 启动插件。
  ///
  /// 启动过程包含三道**加载前校验**与一次**握手等待**，顺序都是刻意的：
  ///
  /// 1. 协议版本：插件声明的版本高于主程序支持的版本时拒绝加载，
  ///    否则插件会依赖不存在的字段、以难以定位的方式行为异常；
  /// 2. 必填配置：缺失时直接拒绝并提示去配置，而不是启动一个注定不工作的进程；
  /// 3. 进程与握手：进程起来后立刻下发 `init`，并等待插件回 `ready`。
  ///    **只有收到 `ready` 才算「运行中」**——早先把「进程创建成功」当作运行中，
  ///    于是插件在导入期就报错或卡住时，界面依然显示「运行中」，
  ///    用户完全看不出插件其实没有工作。
  Future<void> start(String pluginId) async {
    final descriptor = _plugins[pluginId];
    if (descriptor == null || !_capability.supported) return;
    if (_processes.containsKey(pluginId)) return;

    // ── 校验 1：协议版本 ──
    if (!descriptor.manifest.isProtocolSupported) {
      await _rejectStart(
        pluginId,
        '插件声明的协议版本 ${descriptor.manifest.protocolVersion} '
            '高于当前主程序支持的 $pluginProtocolVersion，已拒绝加载。'
            '请升级应用，或改用针对当前版本编写的插件。',
      );
      return;
    }

    // ── 校验 2：必填配置 ──
    final config = await configOf(pluginId);
    if (descriptor.hasMissingConfig(config)) {
      final missing = descriptor.manifest.config
          .where((f) => f.isBlank(config[f.key]))
          .map((f) => f.label)
          .join('、');
      await _rejectStart(pluginId, '缺少必填配置：$missing。请先在插件详情里填写。');
      return;
    }

    final dir = await pluginsDirectory();
    final pluginDir = p.join(dir.path, pluginId);

    // 这一轮启动是「用户/主程序想要的」，因此清掉上一轮的主动停止标记。
    _intentionalStops.remove(pluginId);
    _recovering.remove(pluginId);
    _pendingExitReason.remove(pluginId);

    _publish(pluginId, descriptor.copyWith(
      status: PluginStatus.starting,
      clearError: true,
    ));

    final process = await _runtime!.startProcess(
      manifest: descriptor.manifest,
      directory: pluginDir,
      // 只处理「流级异常」（例如管道读取失败）。
      // 插件 stderr 的每一行会通过 logLines 进来，不在这里重复记一次。
      onDiagnostic: (line) => _log.warn(
        LogSource.plugin,
        '插件进程诊断：$line',
        pluginId: pluginId,
      ),
    );

    if (process == null) {
      await _rejectStart(pluginId, '进程启动失败，详见日志。');
      return;
    }

    _processes[pluginId] = process;
    _missedPongs[pluginId] = 0;

    _publish(pluginId, _plugins[pluginId]!.copyWith(pid: process.pid));

    // 插件自身的日志（含 print 与 stderr）全部转进日志服务，
    // 这样用户在「日志」Tab 里就能看到插件输出，不必另连调试器。
    // 订阅必须保存下来：不保存就无法在停止/删除插件时取消，
    // 反复启停会累积订阅（内存泄漏），且已停止插件的日志仍会继续写入。
    _logSubs[pluginId] = process.logLines.listen((message) {
      _emitPluginLog(pluginId, message);
    });

    _messageSubs[pluginId] = process.messages.listen(
      (message) => _onPluginMessage(pluginId, message),
    );

    _exitSubs[pluginId] = process.exits.listen(
      (code) => unawaited(_handleExit(pluginId, code)),
    );

    // 下发 init：插件据此完成自身初始化并回 ready。
    //
    // 相比协议 v1 多传了三样东西，都是「插件想认真做事就必须有」的：
    // `data_dir`（可写目录）、`config`（用户配置）、`state`（上次持久化的状态）。
    // 早先只给 manifest 与平台能力，插件连往哪写文件都不知道，
    // 只能去猜当前工作目录，在 Android 上几乎必然写错地方。
    process.send(
      PluginMessage(
        type: PluginMessageType.init,
        payload: {
          'plugin_id': pluginId,
          'protocol_version': pluginProtocolVersion,
          'manifest': descriptor.manifest.toJson(),
          'config': config,
          'state': await stateOf(pluginId),
          'data_dir': (await dataDirectory(pluginId)).path,
          'capability': {
            'platform': _capability.platform,
            'python': _capability.pythonExecutable,
          },
        },
      ),
    );

    _log.info(
      LogSource.plugin,
      '插件 ${descriptor.manifest.name} 进程已创建（PID ${process.pid}），等待握手',
      pluginId: pluginId,
    );

    final ready = await _awaitReady(pluginId);

    if (ready) return;

    // 握手超时：进程活着但始终不 ready，通常意味着插件在导入期就卡住或抛错。
    // 这时进程必须收掉——留着它既占内存，又会让后续事件继续堆进它的 stdin。
    if (_pendingExitReason[pluginId] == null) {
      _pendingExitReason[pluginId] = '进程启动后 ${handshakeTimeout.inSeconds} 秒内未完成握手'
          '（没有回 ready）。常见原因：导入阶段抛异常、或顶层代码里有阻塞调用。';
    }
    final pending = _processes[pluginId];
    if (pending != null) {
      _log.warn(
        LogSource.plugin,
        '插件 ${descriptor.manifest.name} 握手超时，正在结束该进程',
        pluginId: pluginId,
        detail: _pendingExitReason[pluginId],
      );
      pending.kill();
    }
  }

  /// 启动前的拒绝路径：标记为崩溃并计入次数。
  ///
  /// 与「进程崩溃」共用同一套计数，是因为对用户而言这两者的处置方式相同：
  /// 都需要去看原因。区别只在 `lastError` 的文案。
  Future<void> _rejectStart(String pluginId, String reason) async {
    final descriptor = _plugins[pluginId];
    if (descriptor == null) return;
    _publish(pluginId, descriptor.toCrashed(reason: reason, at: DateTime.now()));
    await _bumpCrashCount(pluginId);
    _log.error(LogSource.plugin, '插件启动被拒：$reason', pluginId: pluginId);
  }

  /// 停止插件。
  ///
  /// 顺序上有一处**必须**先做的事：先把这次停止登记为「主动停止」，
  /// 再动进程。退出事件是异步派发的，晚一步登记就会被当成崩溃——
  /// 早期版本正是如此，用户每点一次停止，插件就多记一次「已崩溃」。
  Future<void> stop(String pluginId) async {
    _intentionalStops.add(pluginId);
    _cancelRestart(pluginId);
    _stopPing(pluginId);
    _pendingExitReason.remove(pluginId);

    final descriptor = _plugins[pluginId];
    final process = _processes[pluginId];

    if (descriptor != null && process != null) {
      _publish(pluginId, descriptor.copyWith(status: PluginStatus.stopping));
    }

    if (process != null) {
      // 优雅停止：发 shutdown → 等宽限期 → 超时强杀。
      await process.stop();
    }

    await _messageSubs.remove(pluginId)?.cancel();
    await _logSubs.remove(pluginId)?.cancel();
    await _exitSubs.remove(pluginId)?.cancel();
    _processes.remove(pluginId);
    _missedPongs.remove(pluginId);
    _logBudgets.remove(pluginId);
    _recovering.remove(pluginId);

    // 兜底：退出事件没派发（或已被取消订阅）时也要把状态落到「已停止」。
    _finalizeStopped(pluginId);

    // **「主动停止」的标记要留给退出事件去消费，不能在这里删掉。**
    //
    // 进程退出事件是异步派发的，比这个函数返回得晚。早期版本在这里就
    // `_intentionalStops.remove(pluginId)`，于是晚到的那次退出被当成崩溃：
    // 日志里出现 `ERROR 插件 X 的进程已退出（退出码 0）`，崩溃次数 +1 并被
    // 持久化。删除插件时尤其明显——一次正常删除会给同名插件留下
    // 「已崩溃 N 次」的历史。
    //
    // 标记由 `_handleExit` 消费、由 `start()` 在新一轮启动时清掉，
    // 因此不会无限增长。
  }

  /// 把描述符落到「已停止」。**幂等**：状态本来就不在进程态时什么都不做。
  void _finalizeStopped(String pluginId) {
    final descriptor = _plugins[pluginId];
    if (descriptor == null || !descriptor.status.hasProcess) return;
    _liveSnapshot.remove(pluginId);
    _publish(pluginId, descriptor.copyWith(
      status: descriptor.enabled ? PluginStatus.stopped : PluginStatus.disabled,
      lastStoppedAt: DateTime.now(),
      clearPid: true,
    ));
    _log.info(
      LogSource.plugin,
      '插件 ${descriptor.manifest.name} 已停止',
      pluginId: pluginId,
    );
  }

  /// 进程退出后的统一处理：区分主动停止与崩溃，崩溃再尝试有限次自动重启。
  Future<void> _handleExit(String pluginId, int code) async {
    final intentional = _intentionalStops.remove(pluginId);
    final reason = _pendingExitReason.remove(pluginId);
    final current = _plugins[pluginId];

    _processes.remove(pluginId);
    _liveSnapshot.remove(pluginId);
    _stopPing(pluginId);
    _missedPongs.remove(pluginId);
    _logBudgets.remove(pluginId);
    _recovering.remove(pluginId);
    await _messageSubs.remove(pluginId)?.cancel();
    await _logSubs.remove(pluginId)?.cancel();
    await _exitSubs.remove(pluginId)?.cancel();

    if (current == null) return;

    if (intentional) {
      // 主动停止：**不算崩溃**，也不自动重启。
      _finalizeStopped(pluginId);
      return;
    }

    final name = current.manifest.name;
    final detail = reason ??
        (code == 0 ? '进程正常退出（退出码 0）' : '进程异常退出（退出码 $code）');
    _log.error(LogSource.plugin, '插件 $name 意外退出：$detail', pluginId: pluginId);

    await _bumpCrashCount(pluginId);
    _publish(pluginId, current.toCrashed(reason: detail, at: DateTime.now()));

    await _maybeAutoRestart(pluginId);
  }

  /// 有限次数的退避自动重启。
  ///
  /// 早先的设计是「崩溃后一律不重启」，理由是怕崩溃循环耗电。代价是把
  /// 瞬时故障（被系统内存压力杀掉、上游网络抖动导致插件自己退出）也一并放弃，
  /// 用户看到的是「插件莫名其妙不工作了」。现在改成有预算的退避重启：
  /// 真正有缺陷的插件在两次之后就会停下并保持「已崩溃」，不会形成循环；
  /// 而偶发故障能在几秒内自愈。
  Future<void> _maybeAutoRestart(String pluginId) async {
    if (_isShuttingDown) return;
    final current = _plugins[pluginId];
    if (current == null || !current.enabled) return;

    final used = _autoRestarts[pluginId] ?? 0;
    if (used >= maxAutoRestarts) {
      _log.warn(
        LogSource.plugin,
        '插件 ${current.manifest.name} 已自动重启 $used 次仍不稳定，停止自动重启',
        pluginId: pluginId,
        detail: '请查看上方的崩溃原因并修正插件代码，或在插件页手动重启。',
      );
      return;
    }

    final attempt = used + 1;
    _autoRestarts[pluginId] = attempt;
    final delay = autoRestartDelay * attempt;

    _log.warn(
      LogSource.plugin,
      '插件 ${current.manifest.name} 将在 ${delay.inSeconds} 秒后自动重启'
      '（第 $attempt / $maxAutoRestarts 次）',
      pluginId: pluginId,
    );

    _cancelRestart(pluginId);
    _restartTimers[pluginId] = Timer(delay, () {
      _restartTimers.remove(pluginId);
      if (_isShuttingDown) return;
      final target = _plugins[pluginId];
      if (target == null || !target.enabled) return;
      if (_processes.containsKey(pluginId)) return;
      _publish(pluginId, target.copyWith(restartCount: attempt));
      unawaited(start(pluginId));
    });
  }

  /// 取消已排定的重启。
  void _cancelRestart(String pluginId) {
    _restartTimers.remove(pluginId)?.cancel();
  }

  /// 等待插件完成握手，超时返回 `false`。
  Future<bool> _awaitReady(String pluginId) {
    // 已经 ready（极快或重入）时直接返回。
    if (_plugins[pluginId]?.status == PluginStatus.running) return Future.value(true);
    final completer = Completer<bool>();
    _readyWaiters[pluginId] = completer;
    return completer.future.timeout(
      handshakeTimeout,
      onTimeout: () {
        _readyWaiters.remove(pluginId);
        return false;
      },
    );
  }

  /// 收到 `ready`：完成握手并切到运行中。
  void _onPluginReady(String pluginId) {
    final completer = _readyWaiters.remove(pluginId);
    if (completer != null && !completer.isCompleted) completer.complete(true);

    final current = _plugins[pluginId];
    if (current == null) return;
    if (current.status == PluginStatus.running) return;

    _log.info(
      LogSource.plugin,
      '插件 ${current.manifest.name} 已就绪（handshake 完成，PID ${current.pid ?? '-'}）',
      pluginId: pluginId,
    );
    _publish(pluginId, current.copyWith(
      status: PluginStatus.running,
      lastReadyAt: DateTime.now(),
      clearError: true,
    ));
    _startPing(pluginId);
  }

  /// 等待握手的等待者（key = pluginId）。
  final Map<String, Completer<bool>> _readyWaiters = {};

  /// 进程退出的原因覆盖。
  ///
  /// 由主动结束进程的路径写入（握手超时、判定卡死），让退出处理能给出
  /// 「为什么结束它」而不是一句「退出码 -9」。
  final Map<String, String> _pendingExitReason = {};

  /// 启动心跳探测。
  ///
  /// 计数语义是「上一个心跳周期有没有被回应」，这里有两处极易写错、且
  /// 写错之后**从界面上完全看不出来**的细节：
  ///
  /// - **第一帧心跳立刻发**，而不是等一个周期再发。早先的实现把发 ping 放在
  ///   周期回调里，于是 t=30s 那一次先自增了 `missed` 才发出第一个 ping——
  ///   那时插件根本来不及回 pong，等于凭空记了一次「未响应」，
  ///   界面上显示的未响应次数比真实情况多 1。
  /// - 判定用 `>=` 而不是 `>`。参数名、注释与文档都说的是「连续 3 次无响应
  ///   判卡死（约 90 秒静默）」，写成 `>` 实际要等到第 4 个周期，
  ///   也就是 120 秒才动作，比声称的多出整整一个心跳间隔。
  void _startPing(String pluginId) {
    _stopPing(pluginId);
    _missedPongs[pluginId] = 0;
    _processes[pluginId]?.send(const PluginMessage(type: PluginMessageType.ping));

    _pingTimers[pluginId] = Timer.periodic(pingInterval, (_) {
      final process = _processes[pluginId];
      final current = _plugins[pluginId];
      if (process == null || current == null) {
        _stopPing(pluginId);
        return;
      }
      final missed = (_missedPongs[pluginId] ?? 0) + 1;
      _missedPongs[pluginId] = missed;

      if (missed >= maxMissedPongs) {
        unawaited(_handleHung(pluginId, missed));
        return;
      }
      _publish(pluginId, current.copyWith(missedPongs: missed));
      process.send(const PluginMessage(type: PluginMessageType.ping));
    });
  }

  void _stopPing(String pluginId) {
    _pingTimers.remove(pluginId)?.cancel();
  }

  /// 收到 `pong`。
  void _onPong(String pluginId) {
    _missedPongs[pluginId] = 0;
    final current = _plugins[pluginId];
    if (current == null) return;

    // 稳定运行超过 5 分钟即视为「自愈完成」，清空自动重启预算，
    // 免得一个插件在一天里偶发崩两次之后就再也不能自动恢复。
    final readyAt = current.lastReadyAt;
    if (readyAt != null &&
        DateTime.now().difference(readyAt) > const Duration(minutes: 5)) {
      _autoRestarts.remove(pluginId);
    }

    _publish(pluginId, current.copyWith(
      lastPongAt: DateTime.now(),
      missedPongs: 0,
    ));
  }

  /// 判定卡死：标记状态 → 结束进程 → 交给退出处理去决定是否重启。
  Future<void> _handleHung(String pluginId, int missed) async {
    if (_recovering.contains(pluginId)) return;
    _recovering.add(pluginId);
    _stopPing(pluginId);

    final current = _plugins[pluginId];
    if (current == null) return;

    final reason = '连续 $missed 次心跳无响应（间隔 ${pingInterval.inSeconds} 秒），'
        '判定为卡死。常见原因：死锁、长时间阻塞调用、或插件自身的子进程卡住。';
    _log.error(
      LogSource.plugin,
      '插件 ${current.manifest.name} 无响应，已判定卡死',
      pluginId: pluginId,
      detail: reason,
    );
    _pendingExitReason[pluginId] = reason;
    _publish(pluginId, current.copyWith(
      status: PluginStatus.hung,
      lastError: reason,
      missedPongs: missed,
    ));

    // 必须真的结束进程：卡死的插件仍占着内存，事件还会继续堆进它的 stdin。
    _processes[pluginId]?.kill();
  }

  /// 把插件日志写进日志服务，并做**每秒行数限流**。
  ///
  /// 不限流的后果很具体：插件在死循环里 `print`，每行都会触发
  /// 「日志服务通知界面 + 排队写盘」，几千行足以让界面卡死几秒。
  void _emitPluginLog(String pluginId, PluginMessage message) {
    final budget = _logBudgets.putIfAbsent(pluginId, _LogBudget.new);
    if (!budget.allow(logRateLimitPerSecond)) {
      final dropped = budget.dropped + 1;
      budget.dropped = dropped;
      // 每丢 100 条记一次，避免「为了报告丢包而又产生海量日志」。
      if (dropped % 100 == 1) {
        _log.warn(
          LogSource.plugin,
          '插件日志输出过快，已丢弃 $dropped 行',
          pluginId: pluginId,
          detail: '上限 $logRateLimitPerSecond 行/秒。'
              '插件里可能存在死循环 print；已丢弃的行数会显示在插件详情中。',
        );
        final current = _plugins[pluginId];
        if (current != null) {
          _publish(pluginId, current.copyWith(droppedLogs: dropped));
        }
      }
      return;
    }

    _log.log(
      LogEntry(
        level: message.logLevel,
        source: LogSource.plugin,
        message: message.logMessage,
        at: DateTime.now(),
        pluginId: pluginId,
      ),
    );
  }

  /// 删除插件（停止进程、删除整个插件目录、清理配置与状态）。
  Future<void> remove(String pluginId) async {
    await stop(pluginId);
    final dir = await pluginsDirectory();
    final pluginDir = Directory(p.join(dir.path, pluginId));
    if (await pluginDir.exists()) {
      await pluginDir.delete(recursive: true);
      _log.info(LogSource.plugin, '已删除插件目录：$pluginId');
    }
    _plugins.remove(pluginId);
    _liveSnapshot.remove(pluginId);
    _sentEvents.remove(pluginId);
    _autoRestarts.remove(pluginId);
    _missedPongs.remove(pluginId);
    _logBudgets.remove(pluginId);
    _recovering.remove(pluginId);
    _pendingExitReason.remove(pluginId);
    _cancelRestart(pluginId);
    _stopPing(pluginId);

    // 配置、状态与崩溃计数都存在主文档里（不在插件目录内），必须单独清理。
    // 不清配置会继承上一份的旧密钥；不清崩溃计数则会让**重新安装的同一个
    // 插件**一上来就显示「已崩溃 N 次」——那是上一次安装留下的账。
    await _store.writeJsonMap('config_$pluginId', {});
    await _store.writeJsonMap('state_$pluginId', {});
    final crashCounts = await _store.readIntMap('crash_count');
    if (crashCounts.remove(pluginId) != null) {
      await _store.writeIntMap('crash_count', crashCounts);
    }

    final names = await _store.readSet('enabled');
    names.remove(pluginId);
    names.remove('!$pluginId');
    await _store.writeSet('enabled', names);
    notifyListeners();
  }

  /// 停止全部插件（应用退出时调用）。
  Future<void> shutdownAll() async {
    // 先置位再逐个停：退出过程中任何进程退出都不得触发自动重启，
    // 否则会出现「正在关闭应用，插件却在被拉起来」的怪象。
    _isShuttingDown = true;
    for (final timer in _restartTimers.values) {
      timer.cancel();
    }
    _restartTimers.clear();
    for (final timer in _pingTimers.values) {
      timer.cancel();
    }
    _pingTimers.clear();

    for (final id in _processes.keys.toList()) {
      await stop(id);
    }
  }

  /// 把事件投递给插件，返回**实际收到它的插件个数**。
  ///
  /// [eventPayload] 是**归一化后的事件载荷**（不是官方原始 JSON）：
  /// 插件作者看到的是稳定结构，官方字段改名不会直接打断插件。
  ///
  /// 返回值不是装饰：调用方用「有没有插件接」来决定要不要对一条没人认领的
  /// 疑似指令给出提示。返回 0 与「插件都在忙」是两回事，不能混为一谈。
  Future<int> dispatch(
    Map<String, dynamic> eventPayload, {
    required String eventType,
    required String botId,
  }) async {
    if (_processes.isEmpty) return 0;
    final requestId = 'evt-${++_requestSeed}';
    final message = PluginMessage(
      type: PluginMessageType.event,
      requestId: requestId,
      payload: {
        't': eventType,
        'bot_id': botId,
        'protocol_version': pluginProtocolVersion,
        'event': eventPayload,
      },
    );

    var delivered = 0;
    for (final entry in _processes.entries) {
      final descriptor = _plugins[entry.key];
      if (descriptor == null) continue;
      // 只投给**已完成握手**的插件。
      //
      // 启动中的插件还没读完 init，此时投递事件会让它在自己的初始化逻辑
      // 尚未就绪时被唤醒；而「无响应」的插件更不该继续收——
      // 事件堆在它的 stdin 里只会让内存持续涨。
      if (descriptor.status != PluginStatus.running) continue;
      // 按插件声明的订阅范围过滤：不声明则视为订阅全部。
      if (!descriptor.manifest.subscribesTo(eventType)) continue;
      entry.value.send(message);
      _sentEvents[entry.key] = (_sentEvents[entry.key] ?? 0) + 1;
      delivered++;
    }
    return delivered;
  }

  /// 已投递的事件计数（key = pluginId）。
  ///
  /// 单独用一个 map 而不是直接写回描述符：事件可能是每秒几十条，
  /// 每次都 `notifyListeners()` 会让插件页不停地重建。
  /// 计数在 [plugins] 取值时合并进去，界面看到的就是最新的。
  final Map<String, int> _sentEvents = {};

  Future<void> _onPluginMessage(String pluginId, PluginMessage message) async {
    switch (message.type) {
      case PluginMessageType.ready:
        _onPluginReady(pluginId);
      case PluginMessageType.pong:
        _onPong(pluginId);
      case PluginMessageType.ping:
        // 插件主动探活：直接回一个 pong 即可。
        _processes[pluginId]?.send(
          const PluginMessage(type: PluginMessageType.pong),
        );
      case PluginMessageType.reply:
        await _handleReplyRequest(pluginId, message);
      case PluginMessageType.stateSet:
        await _mergeState(pluginId, message.statePayload);
      case PluginMessageType.stateRemove:
        await _removeState(pluginId, message.stateRemoveKeys);
      case PluginMessageType.log:
        _emitPluginLog(pluginId, message);
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
      credential: _credentialOf(pluginId, payload),
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

  /// 把插件上报的 id 归一为被动回复凭据。
  ///
  /// 官方把被动消息分成两条**互斥**的路径：回复用户消息带 `msg_id`、
  /// 响应事件带 `event_id`，请求体同时带两者会被直接拒绝
  /// （「msg_id 与 event_id 只能二选一」）。
  ///
  /// 因此插件同时提供两者时**保留 `msg_id`**：插件的绝大多数意图是
  /// 「回复刚才那条消息」，而 event_id 只对按钮回调、入群、开启推送、
  /// 加好友这几类事件有效——对一个消息事件填 event_id 本身就是无效的。
  /// 丢弃的同时记一条 WARN，让插件作者能定位到自己多传了字段，
  /// 而不是收到一个语焉不详的失败。
  PassiveCredential? _credentialOf(
    String pluginId,
    Map<String, dynamic> payload,
  ) {
    final msgId = payload['msg_id'] as String?;
    final eventId = payload['event_id'] as String?;

    if (msgId != null && msgId.isNotEmpty) {
      if (eventId != null && eventId.isNotEmpty) {
        _log.warn(
          LogSource.plugin,
          '插件同时提供了 msg_id 与 event_id，已按官方规则只取 msg_id',
          pluginId: pluginId,
          detail: '二者互斥：回复用户消息用 msg_id，响应事件才用 event_id。'
              'event_id 已被忽略。',
        );
      }
      return PassiveCredential.message(msgId);
    }
    if (eventId != null && eventId.isNotEmpty) {
      return PassiveCredential.event(eventId);
    }
    // 两者都没有 → 主动消息。
    return null;
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

  // ───────────────────────── 配置 ─────────────────────────

  /// 读取插件配置（清单里的默认值 + 用户保存的值）。
  Future<Map<String, Object?>> configOf(String pluginId) async {
    final defaults =
        _plugins[pluginId]?.manifest.configDefaults ?? const <String, Object?>{};
    final saved = await _store.readJsonMap('config_$pluginId');
    // 默认值在前、保存值在后：用户保存的值覆盖默认值，
    // 而「清单新增了配置项」时旧用户也能拿到该新项的默认值。
    return <String, Object?>{...defaults, ...saved};
  }

  /// 保存插件配置。
  ///
  /// 运行中的插件会**立刻**收到 `config_update`，不需要重启——
  /// 「改个开关还得重启插件」是很影响体验的一件事，而协议里加一条消息
  /// 就能避免它。
  Future<void> setConfig(String pluginId, Map<String, Object?> values) async {
    await _store.writeJsonMap('config_$pluginId', values);

    final descriptor = _plugins[pluginId];
    final process = _processes[pluginId];
    if (descriptor != null && process != null &&
        descriptor.status == PluginStatus.running) {
      process.send(
        PluginMessage(
          type: PluginMessageType.configUpdate,
          payload: {'plugin_id': pluginId, 'config': await configOf(pluginId)},
        ),
      );
      _log.info(
        LogSource.plugin,
        '配置已更新并已下发给插件',
        pluginId: pluginId,
      );
    }
    notifyListeners();
  }

  // ───────────────────────── 状态（插件自持久化）─────────────────────────

  /// 读取插件持久化的状态。
  Future<Map<String, Object?>> stateOf(String pluginId) =>
      _store.readJsonMap('state_$pluginId');

  /// 顶层合并写入状态（协议里的 `state_set`）。
  Future<void> _mergeState(String pluginId, Map<String, dynamic> patch) async {
    if (patch.isEmpty) return;
    final current = await stateOf(pluginId);
    current.addAll(patch);
    await _store.writeJsonMap('state_$pluginId', current);
  }

  /// 删除若干状态键（协议里的 `state_remove`）。
  Future<void> _removeState(String pluginId, List<String> keys) async {
    if (keys.isEmpty) return;
    final current = await stateOf(pluginId);
    for (final key in keys) {
      current.remove(key);
    }
    await _store.writeJsonMap('state_$pluginId', current);
  }

  /// 清空插件状态（插件详情里的「重置状态」）。
  Future<void> clearState(String pluginId) async {
    await _store.writeJsonMap('state_$pluginId', {});
    _log.info(LogSource.plugin, '已清空插件状态', pluginId: pluginId);
  }

  // ───────────────────────── 目录与文件 ─────────────────────────

  /// 插件自己的可写数据目录（`init` 里作为 `data_dir` 下发）。
  ///
  /// 单独开一个子目录而不是让插件往插件根目录写：插件根目录是**代码**，
  /// 数据混进去之后「升级插件」就变成了「怎么保住用户的运行时数据」，
  /// 也更容易在删除插件时误删或漏删。
  Future<Directory> dataDirectory(String pluginId) async {
    final base = await pluginsDirectory();
    final dir = Directory(p.join(base.path, pluginId, 'data'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// 插件根目录的绝对路径（界面上给用户复制，用于 ADB / 桌面端投放插件）。
  Future<String> pluginDirectoryPath(String pluginId) async {
    final base = await pluginsDirectory();
    return p.join(base.path, pluginId);
  }

  /// 数据目录在列表里排除掉：它是插件的运行时数据，不是可编辑的源码。
  static const String _dataDirName = 'data';

  /// 列出插件目录下的文件（相对路径，正斜杠分隔，已排序）。
  Future<List<String>> listFiles(String pluginId) async {
    final root = await pluginDirectoryPath(pluginId);
    final dir = Directory(root);
    if (!await dir.exists()) return const [];
    final result = <String>[];
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final relative = p.relative(entity.path, from: root).replaceAll('\\', '/');
      if (relative.split('/').first == _dataDirName) continue;
      result.add(relative);
    }
    result.sort();
    return result;
  }

  /// 允许在应用内编辑的扩展名。
  ///
  /// 只放文本类：二进制文件（`.pyc`、图片）在文本框里既看不懂也存不回去。
  static const Set<String> editableExtensions = {
    'py', 'json', 'md', 'txt', 'toml', 'yaml', 'yml', 'cfg', 'ini', 'csv',
  };

  /// 单文件读写上限。超过它的文件在应用内编辑没有意义（也不安全）。
  static const int maxEditableFileBytes = 512 * 1024;

  /// 读取插件内的文本文件；越界、不存在或过大时返回 `null`。
  Future<String?> readPluginFile(String pluginId, String relative) async {
    final root = await pluginDirectoryPath(pluginId);
    final full = _resolveInside(root, relative);
    if (full == null) return null;
    final file = File(full);
    if (!await file.exists()) return null;
    if (await file.length() > maxEditableFileBytes) return null;
    try {
      return await file.readAsString();
    } catch (_) {
      // 非 UTF-8 内容读不出来属正常情况（二进制文件），不当作错误。
      return null;
    }
  }

  /// 写入插件内的文本文件。返回错误说明；成功返回 `null`。
  Future<String?> writePluginFile(
    String pluginId,
    String relative,
    String content,
  ) async {
    final root = await pluginDirectoryPath(pluginId);
    final full = _resolveInside(root, relative);
    if (full == null) return '文件名不合法（不允许绝对路径或跳出插件目录）';
    final extension = p.extension(relative).replaceFirst('.', '').toLowerCase();
    if (!editableExtensions.contains(extension)) {
      return '不允许编辑 .$extension 文件，仅支持：${editableExtensions.join('、')}';
    }
    if (content.length > maxEditableFileBytes) return '内容过大';
    final file = File(full);
    await file.parent.create(recursive: true);
    await file.writeAsString(content, flush: true);
    _log.info(LogSource.plugin, '已保存插件文件：$relative', pluginId: pluginId);
    return null;
  }

  /// 在插件目录内新建一个空文件。返回错误说明；成功返回 `null`。
  Future<String?> createPluginFile(String pluginId, String relative) {
    return writePluginFile(pluginId, relative, '');
  }

  /// 删除插件内的文件。返回错误说明；成功返回 `null`。
  Future<String?> deletePluginFile(String pluginId, String relative) async {
    final root = await pluginDirectoryPath(pluginId);
    final full = _resolveInside(root, relative);
    if (full == null) return '文件名不合法';
    if (p.basename(full) == 'plugin.json') return 'plugin.json 是插件清单，不能删除';
    final file = File(full);
    if (!await file.exists()) return '文件不存在';
    await file.delete();
    _log.info(LogSource.plugin, '已删除插件文件：$relative', pluginId: pluginId);
    return null;
  }

  /// 把相对路径解析为**严格位于 [root] 之内**的绝对路径。
  ///
  /// 这是唯一的安全边界：插件目录来自插件包，`entry` 与文件路径都可能被
  /// 构造成 `../../xxx` 去读写插件目录之外的东西。越界一律返回 `null`。
  static String? _resolveInside(String root, String relative) {
    if (!_isSafeRelativePath(relative)) return null;
    final normalized = p.normalize(relative.replaceAll('\\', '/'));
    final full = p.normalize(p.join(root, normalized));
    if (!p.isWithin(root, full)) return null;
    return full;
  }

  /// 相对路径本身是否安全（与具体根目录无关）。
  ///
  /// 单独抽出来是为了让导入流程能**先把所有路径校验完再写盘**：
  /// 否则写到一半遇到非法路径会留下一个半成品插件目录。
  static bool _isSafeRelativePath(String relative) {
    if (relative.trim().isEmpty) return false;
    final normalized = p.normalize(relative.replaceAll('\\', '/'));
    if (p.isAbsolute(normalized)) return false;
    if (normalized == '.' || normalized.startsWith('..')) return false;
    return true;
  }

  // ───────────────────────── 导入 / 导出 ─────────────────────────

  /// 导出包的格式版本。
  static const int bundleVersion = 1;

  /// 导出插件为可复制的 JSON 包。
  ///
  /// 为什么做成 JSON 而不是 zip：手机上拿到 zip 之后没有可靠的解压入口，
  /// 而 JSON 可以直接走剪贴板——「复制 → 发给自己 → 在另一台设备粘贴导入」
  /// 是全平台都能用的最小闭环。
  Future<Map<String, dynamic>> exportBundle(String pluginId) async {
    final files = await listFiles(pluginId);
    final payload = <String, String>{};
    var total = 0;
    for (final relative in files) {
      final content = await readPluginFile(pluginId, relative);
      if (content == null) continue;
      total += content.length;
      if (total > 2 * 1024 * 1024) break;
      payload[relative] = content;
    }
    return {
      'lave_plugin_bundle': bundleVersion,
      'id': pluginId,
      'files': payload,
    };
  }

  /// 从 JSON 包导入（或覆盖）一个插件。返回错误说明；成功返回 `null`。
  Future<String?> importBundle(Map<String, dynamic> bundle) async {
    if (QqJson.integer(bundle['lave_plugin_bundle']) == null) {
      return '这不是 Lave 插件包（缺少 lave_plugin_bundle 标记）';
    }
    final rawId = QqJson.str(bundle['id']);
    final id = rawId?.trim();
    if (id == null || !_isSafePluginId(id)) {
      return '插件 ID 不合法：只允许字母、数字、下划线、连字符与点';
    }
    final files = QqJson.map(bundle['files']);
    if (files == null || files.isEmpty) return '插件包内没有文件';
    if (!files.keys.any((k) => p.basename(k) == 'plugin.json')) {
      return '插件包内缺少 plugin.json';
    }

    // **先把所有路径校验完，再动磁盘。**
    // 边校验边写的话，写到一半遇到非法路径会留下一个半成品插件目录
    // （有 plugin.json 却没有 main.py），而且它会出现在插件列表里。
    for (final key in files.keys) {
      if (!_isSafeRelativePath(key)) return '插件包内含非法路径：$key';
    }

    final base = await pluginsDirectory();
    final root = p.join(base.path, id);

    var written = 0;
    for (final entry in files.entries) {
      final content = QqJson.str(entry.value);
      if (content == null) continue;
      final full = _resolveInside(root, entry.key);
      if (full == null) return '插件包内含非法路径：${entry.key}';
      final file = File(full);
      await file.parent.create(recursive: true);
      await file.writeAsString(content, flush: true);
      written++;
    }
    if (written == 0) return '插件包内没有可写入的文本文件';

    // 覆盖导入时把运行中的旧进程停掉：否则新旧代码同时在跑，
    // 而界面显示的是新清单，行为对不上任何一份代码。
    await stop(id);

    // 配置与状态存在主程序的 JSON 文档里（键为 `config_<id>` / `state_<id>`），
    // **不在插件目录内**，所以删目录、重写文件都带不走它们。
    // 这里必须显式清空：否则「从别人那里导入一个同名插件」会读到上一份的旧配置，
    // 包括已经失效的 token 或指向错误群的 target，那种错配极难排查。
    await _store.writeJsonMap('config_$id', {});
    await _store.writeJsonMap('state_$id', {});

    await refresh();

    // 覆盖前本来就在跑的插件，导入完继续跑。
    // 不恢复的话，「更新插件」这个动作会顺带把机器人弄成停机状态，
    // 而用户很难联想到是导入操作的副作用。
    final restored = _plugins[id];
    if (restored != null && restored.enabled && !_isShuttingDown) {
      unawaited(start(id));
    }

    _log.info(
      LogSource.plugin,
      '已导入插件 $id（$written 个文件）',
      pluginId: id,
    );
    return null;
  }

  /// 插件 ID 是否可安全用作目录名。
  static bool _isSafePluginId(String id) {
    if (id == '.' || id == '..') return false;
    return RegExp(r'^[A-Za-z0-9_.-]{1,64}$').hasMatch(id);
  }

  /// 随包分发的示例插件目录（相对 assets 根）。
  static const String examplePluginAssetDir = 'assets/plugins/demo_plugin';

  /// 安装随包分发的示例插件。
  ///
  /// 存在的价值：让插件系统**可被验证**。否则「建目录、写清单、实现协议」
  /// 这套流程没人愿意为了试一下而走一遍。
  ///
  /// 从 assets 读取而不是把内容硬编码在 Dart 字符串里：
  /// 那些文件同时是插件作者的第一份参考实现，必须能被直接阅读与复制。
  /// 返回错误说明；成功返回 `null`。
  Future<String?> installBundledExample() async {
    const prefix = '$examplePluginAssetDir/';
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final keys = manifest
          .listAssets()
          .where((key) => key.startsWith(prefix))
          .toList(growable: false);
      if (keys.isEmpty) {
        return '构建产物里没有内置示例插件（$examplePluginAssetDir/）';
      }

      final base = await pluginsDirectory();
      final root = p.join(base.path, 'demo_plugin');
      var written = 0;
      for (final key in keys) {
        final relative = key.substring(prefix.length);
        if (relative.isEmpty) continue;
        final content = await rootBundle.loadString(key);
        final file = File(p.join(root, relative));
        await file.parent.create(recursive: true);
        await file.writeAsString(content, flush: true);
        written++;
      }

      // 覆盖安装时先把旧进程停掉，否则新旧代码同时在跑。
      await stop('demo_plugin');
      await refresh();
      _log.info(
        LogSource.plugin,
        '已安装示例插件（$written 个文件）到 $root',
      );
      return null;
    } catch (error) {
      return '安装示例插件失败：$error';
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
    for (final sub in _logSubs.values) {
      unawaited(sub.cancel());
    }
    for (final sub in _exitSubs.values) {
      unawaited(sub.cancel());
    }
    // 心跳与重启定时器必须显式取消：它们是周期性的，
    // 不取消就会在管理器已释放之后继续触发，对着已关闭的对象做事。
    for (final timer in _pingTimers.values) {
      timer.cancel();
    }
    _pingTimers.clear();
    for (final timer in _restartTimers.values) {
      timer.cancel();
    }
    _restartTimers.clear();
    for (final process in _processes.values) {
      unawaited(process.stop());
    }
    super.dispose();
  }
}

/// 单个「每秒日志行数」预算窗口。
///
/// 用「固定一秒窗口」而不是精确的令牌桶：插件日志的用途是给人看，
/// 秒级粒度完全够用，而实现简单到不会自身出错。
class _LogBudget {
  int _windowSecond = 0;
  int _used = 0;

  /// 累计被丢弃的行数。
  int dropped = 0;

  bool allow(int perSecond) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (now != _windowSecond) {
      _windowSecond = now;
      _used = 0;
    }
    if (_used >= perSecond) return false;
    _used++;
    return true;
  }
}

/// 插件状态的持久化依赖面。
abstract interface class PluginStateStoreLike {
  Future<Set<String>> readSet(String key);

  Future<void> writeSet(String key, Set<String> values);

  Future<Map<String, int>> readIntMap(String key);

  Future<void> writeIntMap(String key, Map<String, int> values);

  /// 读取一个 JSON 对象（用于插件配置与插件状态）。
  ///
  /// 单独要一组方法而不是把任意值塞进 [readSet]：配置与状态里会有
  /// 布尔、数字、嵌套结构，扁平化成字符串再解析回来既容易出错也不透明。
  Future<Map<String, Object?>> readJsonMap(String key);

  Future<void> writeJsonMap(String key, Map<String, Object?> values);
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

  @override
  Future<Map<String, Object?>> readJsonMap(String key) async {
    final items = await _store.readList(key);
    final result = <String, Object?>{};
    for (final item in items) {
      final k = item['key']?.toString();
      if (k == null) continue;
      result[k] = item['value'];
    }
    return result;
  }

  @override
  Future<void> writeJsonMap(String key, Map<String, Object?> values) =>
      _store.writeList(
        key,
        values.entries.map((e) => {'key': e.key, 'value': e.value}).toList(),
      );
}

/// 插件协议版本见 `domain/models/plugin_models.dart` 的 [pluginProtocolVersion]。
///
/// 声明在协议层而不是这里：它是协议本身的属性，且清单模型需要用它做默认值；
/// 放在管理器里会造成「模型 → 管理器」的反向依赖。
