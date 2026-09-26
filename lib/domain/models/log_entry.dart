import 'package:flutter/foundation.dart';

/// 日志级别。
///
/// 与 `core/logging/app_logger.dart` 的区别：那个是**开发期控制台日志**，
/// 这个是**面向用户与插件系统的结构化日志条目**（要落库、要在「日志」Tab 里
/// 按级别筛选、要能被插件读取）。两者刻意不合并——控制台日志量级远大于
/// 结构化日志，混在一起会让「日志」Tab 被逐帧调试信息淹没。
enum LogLevel {
  trace(0, 'TRACE'),
  debug(1, 'DEBUG'),
  info(2, 'INFO'),
  warn(3, 'WARN'),
  error(4, 'ERROR');

  const LogLevel(this.severity, this.label);

  /// 严重程度，数值越大越严重。用于「只看 WARN 及以上」这类筛选。
  final int severity;

  /// 界面展示用的短标签。
  final String label;

  /// 是否不低于给定级别。
  bool atLeast(LogLevel other) => severity >= other.severity;

  static LogLevel fromName(String? name) {
    for (final level in values) {
      if (level.name == name) return level;
    }
    return LogLevel.info;
  }

  /// 解析形如 `INFO` / `warn` 的文本。
  static LogLevel fromLabel(String? label) {
    final normalized = label?.trim().toLowerCase();
    for (final level in values) {
      if (level.name == normalized) return level;
    }
    return LogLevel.info;
  }
}

/// 日志来源。
///
/// 独立成枚举而不是字符串，是为了让「日志」Tab 能按来源筛选，
/// 并且让插件产生的日志与主程序日志在界面上可区分——
/// 排查插件问题时最怕分不清「这行是谁打的」。
enum LogSource {
  /// 应用自身（启动、退出、平台能力探测）。
  system('系统'),

  /// WSS 网关（连接、心跳、会话、重连）。
  gateway('网关'),

  /// HTTP 接口（鉴权、发消息、上传）。
  api('接口'),

  /// 事件分发与指令引擎。
  event('事件'),

  /// Python 插件运行时（含插件自身的 stdout / stderr）。
  plugin('插件'),

  /// 界面层。
  ui('界面');

  const LogSource(this.label);

  final String label;
}

/// 一条结构化日志。
@immutable
class LogEntry {
  const LogEntry({
    required this.level,
    required this.source,
    required this.message,
    required this.at,
    this.id,
    this.botId,
    this.pluginId,
    this.officialCode,
    this.traceId,
    this.detail,
  });

  /// 本地自增主键（落库后由数据库回填）。
  final int? id;

  /// 级别。
  final LogLevel level;

  /// 来源。
  final LogSource source;

  /// 日志正文。
  final String message;

  /// 发生时间。
  final DateTime at;

  /// 所属机器人 AppID（可空：应用级日志不属于任何机器人）。
  final String? botId;

  /// 所属插件 ID（仅 [LogSource.plugin] 时有值）。
  final String? pluginId;

  /// 官方错误码（若有）。
  final int? officialCode;

  /// 平台链路追踪 ID（官方 `X-Tps-trace-ID` / `trace_id`）。
  ///
  /// 必须保留：官方明确「有无法自己定位的问题需要找平台协助时可以提取这个 ID」，
  /// 丢了这个字段等于丢掉了唯一的求助凭据。
  final String? traceId;

  /// 详细信息（异常栈、请求体摘要等）。展示时可折叠。
  final String? detail;

  /// 界面上的一行摘要。
  ///
  /// 格式对齐需求：「时间戳 + 等级 + 内容」。
  String get shortLine =>
      '${formatTime(at)}  ${level.label.padRight(5)}  '
      '${botId == null ? '' : '[$botId] '}$message';

  /// 是否建议在列表中以高亮样式呈现。
  bool get isHighlighted =>
      level == LogLevel.error || level == LogLevel.warn;

  /// 格式化时间（`HH:mm:ss`，毫秒级排查时用 [formatTimeWithMillis]）。
  static String formatTime(DateTime time) {
    final local = time.toLocal();
    return '${_two(local.hour)}:${_two(local.minute)}:${_two(local.second)}';
  }

  /// 带毫秒的时间（排查时序问题，例如「心跳发出去多久后断的」）。
  static String formatTimeWithMillis(DateTime time) {
    final local = time.toLocal();
    return '${formatTime(local)}.${local.millisecond.toString().padLeft(3, '0')}';
  }

  /// 带日期的时间（跨天查看历史日志时使用）。
  static String formatDateTime(DateTime time) {
    final local = time.toLocal();
    return '${local.year}-${_two(local.month)}-${_two(local.day)} '
        '${formatTime(local)}';
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  LogEntry copyWithId(int id) => LogEntry(
        id: id,
        level: level,
        source: source,
        message: message,
        at: at,
        botId: botId,
        pluginId: pluginId,
        officialCode: officialCode,
        traceId: traceId,
        detail: detail,
      );

  static LogEntry fromJson(Map<String, dynamic> json) => LogEntry(
        id: (json['id'] as num?)?.toInt(),
        level: LogLevel.fromLabel(json['level'] as String?),
        source: LogSource.values.firstWhere(
          (e) => e.name == json['source'],
          orElse: () => LogSource.system,
        ),
        message: (json['message'] as String?) ?? '',
        at: DateTime.tryParse((json['at'] as String?) ?? '') ?? DateTime.now(),
        botId: json['bot_id'] as String?,
        pluginId: json['plugin_id'] as String?,
        officialCode: (json['official_code'] as num?)?.toInt(),
        traceId: json['trace_id'] as String?,
        detail: json['detail'] as String?,
      );

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'level': level.name,
        'source': source.name,
        'message': message,
        'at': at.toIso8601String(),
        if (botId != null) 'bot_id': botId,
        if (pluginId != null) 'plugin_id': pluginId,
        if (officialCode != null) 'official_code': officialCode,
        if (traceId != null) 'trace_id': traceId,
        if (detail != null) 'detail': detail,
      };
}

/// 日志接收口。
///
/// 存在的意义是**解耦**：网关层、接口层、插件层都只需要知道「往哪里写一条日志」，
/// 不需要知道日志是进内存、进 SQLite 还是进文件。
/// 测试时注入一个内存实现即可断言「关键时刻有没有产生日志」。
abstract interface class AppLogSink {
  /// 写入一条日志。
  void log(LogEntry entry);

  /// 便捷方法：按级别写入。
  void info(
    LogSource source,
    String message, {
    String? botId,
    String? pluginId,
    String? detail,
  });

  /// 便捷方法：写入警告。
  void warn(
    LogSource source,
    String message, {
    String? botId,
    String? pluginId,
    String? detail,
  });

  /// 便捷方法：写入错误。
  void error(
    LogSource source,
    String message, {
    String? botId,
    String? pluginId,
    String? detail,
    int? officialCode,
    String? traceId,
  });
}

/// 便于在测试与早期实现中使用的空实现。
///
/// 用它替代 `null`，可以让调用方不必到处判空。
class NoopLogSink implements AppLogSink {
  const NoopLogSink();

  @override
  void log(LogEntry entry) {}

  @override
  void info(
    LogSource source,
    String message, {
    String? botId,
    String? pluginId,
    String? detail,
  }) {}

  @override
  void warn(
    LogSource source,
    String message, {
    String? botId,
    String? pluginId,
    String? detail,
  }) {}

  @override
  void error(
    LogSource source,
    String message, {
    String? botId,
    String? pluginId,
    String? detail,
    int? officialCode,
    String? traceId,
  }) {}
}

/// 日志工厂：把「构造 [LogEntry] 时容易漏字段」这件事收敛到一处。
extension AppLogSinkX on AppLogSink {
  /// 构造并写入一条日志。
  LogEntry emit({
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
    final entry = LogEntry(
      level: level,
      source: source,
      message: message,
      at: at ?? DateTime.now(),
      botId: botId,
      pluginId: pluginId,
      officialCode: officialCode,
      traceId: traceId,
      detail: detail,
    );
    log(entry);
    return entry;
  }
}
