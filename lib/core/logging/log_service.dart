import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/models/log_entry.dart';
import '../constants/app_config.dart';
import 'app_logger.dart';

/// 结构化日志服务。
///
/// 与 `AppLogger`（开发期控制台日志）分工不同：
/// - `AppLogger` 面向开发者，走 `debugPrint`，量大且不落库；
/// - 本服务面向**用户与插件系统**，落「日志」Tab、按级别与来源筛选、
///   并在需要时持久化。
///
/// 同时实现 [AppLogSink]，因此网关层 / 接口层 / 插件层只需依赖接口即可写日志，
/// 不需要知道日志最终去哪里。测试时换成 `NoopLogSink` 即可。
class LogService extends ChangeNotifier implements AppLogSink {
  LogService({this.maxEntries = 2000, JsonDocStoreLike? store})
      : _store = store;

  /// 内存中保留的最大条数。超出后丢弃最旧的。
  ///
  /// 为什么不限制：日志是排查问题的唯一凭据，但无限制增长会让
  /// 每次 notifyListeners 都变慢并吃满内存。2000 条对自用场景足够。
  final int maxEntries;

  final JsonDocStoreLike? _store;

  final List<LogEntry> _entries = [];
  int _dropped = 0;

  /// 已被丢弃的条数（界面提示「更早的日志已省略」）。
  int get droppedCount => _dropped;

  /// 全部日志（**最新在前**，界面直接顺序渲染即为倒序时间线）。
  List<LogEntry> get entries => List.unmodifiable(_entries);

  /// 当前筛选条件。
  LogLevel minLevel = LogLevel.debug;
  LogSource? sourceFilter;
  String keyword = '';

  // ───────────────────────── 筛选结果缓存 ─────────────────────────
  //
  // 这两个结果都会被界面在 build 里直接读取，而计算是 O(n)。
  // 不缓存的话，每次重建（滚动、切换筛选、任意一次 notifyListeners）
  // 都会对全量日志做两趟遍历，日志攒到上千条后就是可感知的卡顿。
  List<LogEntry>? _filteredCache;
  Map<LogSource, int>? _countsCache;

  void _invalidateCache() {
    _filteredCache = null;
    _countsCache = null;
  }

  /// 按当前筛选条件过滤后的日志（结果已缓存）。
  List<LogEntry> get filtered {
    final cached = _filteredCache;
    if (cached != null) return cached;

    final text = keyword.trim().toLowerCase();
    final result = _entries.where((entry) {
      if (!entry.level.atLeast(minLevel)) return false;
      if (sourceFilter != null && entry.source != sourceFilter) return false;
      if (text.isEmpty) return true;
      return entry.message.toLowerCase().contains(text) ||
          (entry.detail?.toLowerCase().contains(text) ?? false) ||
          (entry.botId?.toLowerCase().contains(text) ?? false);
    }).toList(growable: false);

    _filteredCache = result;
    return result;
  }

  /// 各来源的条数统计（结果已缓存）。
  Map<LogSource, int> get countsBySource {
    final cached = _countsCache;
    if (cached != null) return cached;

    final result = <LogSource, int>{};
    for (final entry in _entries) {
      result[entry.source] = (result[entry.source] ?? 0) + 1;
    }
    _countsCache = result;
    return result;
  }

  /// 可供筛选的日志级别。
  ///
  /// 不含 `trace`：它被 [_respectableLevel] 拦在存储之外，
  /// 放在筛选器上只会得到一个永远为空的选项。
  List<LogLevel> get selectableLevels =>
      LogLevel.values.where((level) => level != LogLevel.trace).toList();

  /// 错误与警告的未读条数（用于 Tab 上的小红点）。
  ///
  /// 与 [problemCount] 的区别：后者是「历史累计」，前者会在用户打开日志页后清零。
  /// 用累计值做红点会导致角标永远挂着数字，用户很快就学会无视它——
  /// 那样等于没有提示。
  int get unreadProblems => _unreadProblems;
  int _unreadProblems = 0;

  /// 用户查看过日志后清零未读计数。
  void markProblemsRead() {
    if (_unreadProblems == 0) return;
    _unreadProblems = 0;
    notifyListeners();
  }

  /// 历史累计的错误与警告条数。
  int get problemCount =>
      _entries.where((e) => e.level.atLeast(LogLevel.warn)).length;

  @override
  void log(LogEntry entry) {
    if (!entry.level.atLeast(_respectableLevel)) return;

    // 在唯一入口统一脱敏。
    //
    // 为什么放在这里而不是要求各调用方自觉：进入结构化日志的内容来源很杂——
    // 插件的 print、接口返回体摘要、异常栈——任何一处漏了，
    // 密钥就会明文落到本地 JSON 文件里，并被「复制诊断信息」带出去。
    final safe = _redact(entry);
    _entries.insert(0, safe);
    if (_entries.length > maxEntries) {
      final removed = _entries.length - maxEntries;
      _entries.removeRange(maxEntries, _entries.length);
      _dropped += removed;
    }
    if (safe.level.atLeast(LogLevel.warn)) {
      _unreadProblems++;
      // 控制台同步一份，方便开发期观察；正式环境由 AppConfig 控制量级。
      AppLogger.warn('[${safe.source.label}] ${safe.message}', tag: 'service');
    }
    _invalidateCache();
    notifyListeners();
    _schedulePersist();
  }

  /// 对一条日志的正文与详情做脱敏，其余字段原样保留。
  static LogEntry _redact(LogEntry entry) => LogEntry(
        id: entry.id,
        level: entry.level,
        source: entry.source,
        message: AppLogger.redact(entry.message),
        at: entry.at,
        botId: entry.botId,
        pluginId: entry.pluginId,
        officialCode: entry.officialCode,
        traceId: entry.traceId,
        detail: entry.detail == null ? null : AppLogger.redact(entry.detail!),
      );

  /// 写入的最低门槛。
  ///
  /// trace 级别只用于极细粒度排查，默认不落日志 Tab，避免淹没关键信息。
  LogLevel get _respectableLevel => LogLevel.debug;

  @override
  void info(
    LogSource source,
    String message, {
    String? botId,
    String? pluginId,
    String? detail,
  }) =>
      emit(
        level: LogLevel.info,
        source: source,
        message: message,
        botId: botId,
        pluginId: pluginId,
        detail: detail,
      );

  @override
  void warn(
    LogSource source,
    String message, {
    String? botId,
    String? pluginId,
    String? detail,
  }) =>
      emit(
        level: LogLevel.warn,
        source: source,
        message: message,
        botId: botId,
        pluginId: pluginId,
        detail: detail,
      );

  @override
  void error(
    LogSource source,
    String message, {
    String? botId,
    String? pluginId,
    String? detail,
    int? officialCode,
    String? traceId,
  }) =>
      emit(
        level: LogLevel.error,
        source: source,
        message: message,
        botId: botId,
        pluginId: pluginId,
        detail: detail,
        officialCode: officialCode,
        traceId: traceId,
      );

  /// 写入最低门槛之上的日志。
  ///
  /// 供插件与内部模块直接使用；网络与逐帧日志请用 [network] / [frame]，
  /// 那两类的量级与开关控制不同。
  void emit({
    required LogLevel level,
    required LogSource source,
    required String message,
    String? botId,
    String? pluginId,
    int? officialCode,
    String? traceId,
    String? detail,
    DateTime? at,
  }) {
    log(
      LogEntry(
        level: level,
        source: source,
        message: message,
        at: at ?? DateTime.now(),
        botId: botId,
        pluginId: pluginId,
        officialCode: officialCode,
        traceId: traceId,
        detail: detail,
      ),
    );
  }

  /// 网络明细日志。
  ///
  /// **刻意不写入「日志」Tab**：一次发消息会产生多条请求/响应记录，
  /// 写进去会把真正关键的连接错误与官方错误码冲掉。
  /// 它只走开发期控制台输出，且受 `AppConfig.enableNetworkLog` 控制。
  void network(String message, {String? tag}) =>
      AppLogger.network(message, tag: tag ?? 'http');

  /// 设置筛选条件。
  void setFilter({LogLevel? minLevel, LogSource? source, String? keyword, bool clearSource = false}) {
    if (minLevel != null) this.minLevel = minLevel;
    if (clearSource) {
      sourceFilter = null;
    } else if (source != null) {
      // 再次点击同一来源视为取消筛选，符合移动端习惯。
      sourceFilter = sourceFilter == source ? null : source;
    }
    if (keyword != null) this.keyword = keyword;
    _invalidateCache();
    notifyListeners();
  }

  /// 清空日志。
  void clear() {
    _entries.clear();
    _dropped = 0;
    _unreadProblems = 0;
    _invalidateCache();
    notifyListeners();
    _schedulePersist();
  }

  /// 导出为纯文本（供「复制诊断信息」使用）。
  String exportText({int limit = 500}) {
    final buffer = StringBuffer('Lave 诊断日志（环境：${AppEnvironment.label}）\n');
    for (final entry in _entries.take(limit)) {
      buffer.writeln(entry.shortLine);
      if (entry.detail != null) buffer.writeln('    ${entry.detail}');
      if (entry.traceId != null) buffer.writeln('    trace: ${entry.traceId}');
    }
    return buffer.toString();
  }

  // ───────────────────────── 持久化 ─────────────────────────

  Timer? _persistTimer;

  /// 延迟合并写入。
  ///
  /// 直接每条都落盘会造成 IO 抖动（连接高峰期每秒可能几十条日志），
  /// 因此合并到 3 秒一次。
  void _schedulePersist() {
    final store = _store;
    if (store == null) return;
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(seconds: 3), () {
      unawaited(_persist(store));
    });
  }

  Future<void> _persist(JsonDocStoreLike store) async {
    try {
      await store.writeList(
        'entries',
        _entries.take(500).map((e) => e.toJson()).toList(),
      );
    } catch (error) {
      AppLogger.warn('日志持久化失败：$error', tag: 'log');
    }
  }

  /// 启动时载入上次的日志。
  Future<void> restore() async {
    final store = _store;
    if (store == null) return;
    try {
      final items = await store.readList('entries');
      if (items.isEmpty) return;
      _entries
        ..clear()
        ..addAll(items.map(LogEntry.fromJson));
      _invalidateCache();
      notifyListeners();
    } catch (error) {
      AppLogger.warn('日志恢复失败：$error', tag: 'log');
    }
  }

  @override
  void dispose() {
    _persistTimer?.cancel();
    super.dispose();
  }
}

/// 对 `JsonDocStore` 的最小依赖面。
///
/// 独立成接口是为了让 LogService 不直接依赖 `path_provider`
/// （那会让纯逻辑单测必须跑在带平台通道的环境里）。
abstract interface class JsonDocStoreLike {
  Future<List<Map<String, dynamic>>> readList(String key);

  Future<void> writeList(String key, List<Map<String, dynamic>> items);
}
