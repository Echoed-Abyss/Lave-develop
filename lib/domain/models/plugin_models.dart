import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/utils/qq_json.dart';
import 'log_entry.dart';

/// Python 插件的运行状态。
enum PluginStatus {
  /// 已禁用（用户手动关闭，不启动进程）。
  disabled('已禁用'),

  /// 未启动（启用但尚未拉起）。
  stopped('未启动'),

  /// 正在启动（进程已创建，等待握手完成）。
  starting('启动中'),

  /// 运行中（握手完成，可收发消息）。
  running('运行中'),

  /// 已崩溃（进程异常退出）。崩溃后不自动重启，避免崩溃循环，
  /// 由用户在插件页手动重启——这是刻意的设计，理由见 [PluginDescriptor]。
  crashed('已崩溃'),

  /// 当前平台不支持运行插件。
  unsupported('平台不支持');

  const PluginStatus(this.label);

  final String label;

  /// 是否处于需要用户注意的异常态。
  bool get isFailure => this == PluginStatus.crashed || this == PluginStatus.unsupported;

  /// 是否可被启动。
  bool get canStart =>
      this == PluginStatus.stopped ||
      this == PluginStatus.disabled ||
      this == PluginStatus.crashed;
}

/// 插件清单（来自插件目录下的 `plugin.json`，由 Python 侧解析后回传）。
///
/// 字段设计对齐「插件加载 / 启用禁用 / 删除」这三项需求：
/// - 身份与展示：`id` / `name` / `version` / `description` / `author`；
/// - 运行入口：`entry`（相对插件目录的 Python 文件路径）；
/// - 订阅声明：`events`（声明关心哪些事件，用于减少无用投递）。
@immutable
class PluginManifest {
  const PluginManifest({
    required this.id,
    required this.name,
    this.version,
    this.description,
    this.author,
    this.entry = 'main.py',
    this.events = const [],
    this.enabledByDefault = false,
  });

  /// 插件唯一 ID（目录名必须与之一致，便于删除时定位）。
  final String id;

  /// 展示名。
  final String name;

  /// 版本号。
  final String? version;

  /// 描述。
  final String? description;

  /// 作者。
  final String? author;

  /// 入口文件名，相对于插件目录。
  final String entry;

  /// 声明订阅的事件类型（官方 `t` 值，如 `C2C_MESSAGE_CREATE`）。
  ///
  /// 空列表表示订阅全部事件。设计这个字段的用途：
  /// 事件分发层可以据此跳过无关插件，避免「每个事件都唤醒所有插件」。
  final List<String> events;

  /// 首次发现时是否默认启用。
  ///
  /// 默认 `false`：**新插件不应自动获得处理用户消息的能力**，
  /// 否则用户装了插件包就等于把机器人交给了它。
  final bool enabledByDefault;

  factory PluginManifest.fromJson(Map<String, dynamic> json) => PluginManifest(
        id: QqJson.str(json['id']) ?? '',
        name: QqJson.str(json['name']) ?? QqJson.str(json['id']) ?? '',
        version: QqJson.str(json['version']),
        description: QqJson.str(json['description']),
        author: QqJson.str(json['author']),
        entry: QqJson.str(json['entry']) ?? 'main.py',
        events: _stringList(json['events']),
        enabledByDefault: QqJson.boolean(json['enabled_by_default']) ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (version != null) 'version': version,
        if (description != null) 'description': description,
        if (author != null) 'author': author,
        'entry': entry,
        'events': events,
        'enabled_by_default': enabledByDefault,
      };

  /// 是否订阅某个事件类型。
  bool subscribesTo(String eventType) =>
      events.isEmpty || events.contains(eventType);

  /// 是否订阅全部事件。
  bool get subscribesToAll => events.isEmpty;

  static List<String> _stringList(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .map((e) => QqJson.str(e))
        .whereType<String>()
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }
}

/// 插件的运行时快照。
///
/// **崩溃隔离的表现层**：需求要求「单个插件崩溃不影响主机器人程序」，
/// 那么界面必须能明确说出「哪个插件崩了、崩了几次、上次为什么崩」，
/// 否则用户只会看到「插件没反应」。因此这里保留崩溃次数与最近错误。
@immutable
class PluginDescriptor {
  const PluginDescriptor({
    required this.manifest,
    required this.status,
    this.enabled = false,
    this.pid,
    this.crashCount = 0,
    this.lastError,
    this.lastStartedAt,
    this.lastStoppedAt,
  });

  /// 插件清单。
  final PluginManifest manifest;

  /// 当前状态。
  final PluginStatus status;

  /// 用户是否启用。
  final bool enabled;

  /// 子进程 PID（进程型运行时且有值）。
  final int? pid;

  /// 累计崩溃次数。用于判断是否需要提示用户「这个插件反复崩溃」。
  final int crashCount;

  /// 最近一次错误信息（崩溃原因或启动失败原因）。
  final String? lastError;

  /// 最近一次启动时间。
  final DateTime? lastStartedAt;

  /// 最近一次停止时间。
  final DateTime? lastStoppedAt;

  /// 插件 ID。
  String get id => manifest.id;

  /// 是否在运行。
  bool get isRunning => status == PluginStatus.running;

  /// 是否反复崩溃（阈值 3 次），界面应据此给出更强提示。
  bool get isFlapping => crashCount >= 3;

  PluginDescriptor copyWith({
    PluginManifest? manifest,
    PluginStatus? status,
    bool? enabled,
    int? pid,
    int? crashCount,
    String? lastError,
    DateTime? lastStartedAt,
    DateTime? lastStoppedAt,
    bool clearError = false,
    bool clearPid = false,
  }) =>
      PluginDescriptor(
        manifest: manifest ?? this.manifest,
        status: status ?? this.status,
        enabled: enabled ?? this.enabled,
        pid: clearPid ? null : (pid ?? this.pid),
        crashCount: crashCount ?? this.crashCount,
        lastError: clearError ? null : (lastError ?? this.lastError),
        lastStartedAt: lastStartedAt ?? this.lastStartedAt,
        lastStoppedAt: lastStoppedAt ?? this.lastStoppedAt,
      );

  PluginDescriptor toUnsupported(String reason) => copyWith(
        status: PluginStatus.unsupported,
        enabled: false,
        lastError: reason,
        clearPid: true,
      );

  PluginDescriptor toCrashed({required String reason, required DateTime at}) =>
      copyWith(
        status: PluginStatus.crashed,
        crashCount: crashCount + 1,
        lastError: reason,
        lastStoppedAt: at,
        clearPid: true,
      );
}

/// 插件运行时的平台能力。
///
/// **这个模型是本项目对「Python 子进程」这一需求的诚实回答**：
/// `dart:io` 的 `Process.start` 不支持 iOS，Android 系统也没有 `python`
/// 可执行文件。因此运行时必须先自检能力，并把结论上报给界面，
/// 而不是假装启动成功、然后在用户点击时静默失败。
@immutable
class PluginRuntimeCapability {
  const PluginRuntimeCapability({
    required this.supported,
    required this.platform,
    this.pythonExecutable,
    this.reason,
  });

  /// 当前平台是否支持运行 Python 插件。
  final bool supported;

  /// 平台标识（`android` / `ios` / `windows` / `macos` / `linux`）。
  final String platform;

  /// 实际探测到的 Python 可执行文件路径（`supported` 为 true 时通常有值）。
  final String? pythonExecutable;

  /// 不支持的原因，用于界面直接展示（要给用户可操作的说明，而不是一句「不支持」）。
  final String? reason;

  /// 不可用的能力。
  factory PluginRuntimeCapability.unsupported({
    required String platform,
    required String reason,
  }) =>
      PluginRuntimeCapability(
        supported: false,
        platform: platform,
        reason: reason,
      );

  /// 支持运行的能力。
  factory PluginRuntimeCapability.available({
    required String platform,
    required String pythonExecutable,
  }) =>
      PluginRuntimeCapability(
        supported: true,
        platform: platform,
        pythonExecutable: pythonExecutable,
      );

  /// 面向用户的说明文案。
  String get describe => supported
      ? '当前平台（$platform）支持运行 Python 插件'
      : '当前平台（$platform）不支持运行 Python 插件：${reason ?? '未探测到可用的 Python 运行时'}';
}

/// 插件协议消息类型（主进程 ↔ 插件进程的 JSON 行协议）。
enum PluginMessageType {
  /// 主进程 → 插件：初始化（下发插件配置与能力声明）。
  init('init'),

  /// 插件 → 主进程：握手完成，可以接收事件。
  ready('ready'),

  /// 主进程 → 插件：投递一个 QQ 事件。
  event('event'),

  /// 插件 → 主进程：请求发送消息（由主进程代为调用官方接口）。
  reply('reply'),

  /// 插件 → 主进程：写一条日志。插件自身的 `print` 也会被归到这里。
  log('log'),

  /// 主进程 → 插件：优雅停止。
  shutdown('shutdown'),

  /// 双向：心跳（用于探测插件进程是否还活着）。
  ping('ping'),
  pong('pong');

  const PluginMessageType(this.wireName);

  /// 线上传输用的字符串名。
  final String wireName;

  static PluginMessageType? fromWire(String? name) {
    for (final type in values) {
      if (type.wireName == name) return type;
    }
    return null;
  }
}

/// 插件协议消息（一行一条 JSON）。
///
/// 协议形态：
/// ```json
/// {"type":"event","id":"evt-1","payload":{"t":"C2C_MESSAGE_CREATE","d":{...}}}
/// ```
/// 选 JSON Lines 而不是长连接框架的原因：`stdout` 天然按行分帧，
/// 不需要额外定长头或分隔协议，插件作者用 `print` 就能调试。
@immutable
class PluginMessage {
  const PluginMessage({
    required this.type,
    this.requestId,
    this.payload = const {},
  });

  /// 消息类型。
  final PluginMessageType type;

  /// 请求 id。用于把插件的回复与原事件对应起来。
  final String? requestId;

  /// 载荷。
  final Map<String, dynamic> payload;

  factory PluginMessage.fromJson(Map<String, dynamic> json) => PluginMessage(
        type: PluginMessageType.fromWire(QqJson.str(json['type'])) ??
            PluginMessageType.log,
        requestId: QqJson.str(json['id']),
        payload: QqJson.map(json['payload']) ?? const {},
      );

  Map<String, dynamic> toJson() => {
        'type': type.wireName,
        if (requestId != null) 'id': requestId,
        'payload': payload,
      };

  /// 解析为一行 JSON（JSON Lines 协议：一行一条消息）。
  String toLine() => jsonEncode(toJson());

  /// 是否为「插件请求主进程发送消息」。
  bool get isReplyRequest => type == PluginMessageType.reply;

  /// 插件自报的日志级别。
  LogLevel get logLevel => LogLevel.fromLabel(QqJson.str(payload['level']));

  /// 插件自报的日志正文。
  String get logMessage => QqJson.str(payload['message']) ?? '';

  /// 插件自报的日志来源标记（便于区分「插件业务日志」与「插件崩溃 stderr」）。
  String? get logTag => QqJson.str(payload['tag']);
}

