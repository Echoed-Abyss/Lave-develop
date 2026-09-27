import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/utils/qq_json.dart';
import 'log_entry.dart';

/// 插件协议版本。
///
/// ## 版本历史
///
/// | 版本 | 变更 |
/// | --- | --- |
/// | 1 | 初版：`init` / `ready` / `event` / `reply` / `log` / `shutdown` / `ping` / `pong` |
/// | 2 | `init` 增加 `config` / `state` / `data_dir` / `protocol_version`；新增 `state_set`、`state_remove`、`config_update` |
///
/// 插件在 `plugin.json` 里用 `protocol_version` 声明自己针对哪一版编写。
/// 声明值**大于**当前版本会被拒绝加载——那意味着插件依赖了主程序还不认识的
/// 字段，放行只会让它在运行时静默行为异常，比直接拒绝更难排查。
/// 小于等于当前版本则照常加载（旧插件能跑就不要拦住它）。
const int pluginProtocolVersion = 2;

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

  /// 已卡死（进程还在，但连续多次心跳无响应）。
  ///
  /// 与 [crashed] 分开的原因：卡死的进程**仍然占着内存**，而且
  /// 事件会继续往它的 stdin 里堆。这类故障原先完全不可见——
  /// 界面显示「运行中」，用户却在疑惑「插件怎么没反应」。
  /// 现在会被探测出来，并允许用户在界面上直接重启。
  hung('无响应'),

  /// 正在停止（已发出 shutdown，等待进程自行退出）。
  stopping('停止中'),

  /// 已崩溃（进程异常退出）。
  crashed('已崩溃'),

  /// 当前平台不支持运行插件。
  unsupported('平台不支持');

  const PluginStatus(this.label);

  final String label;

  /// 是否处于需要用户注意的异常态。
  bool get isFailure =>
      this == PluginStatus.crashed ||
      this == PluginStatus.hung ||
      this == PluginStatus.unsupported;

  /// 是否可被启动。
  bool get canStart =>
      this == PluginStatus.stopped ||
      this == PluginStatus.disabled ||
      this == PluginStatus.crashed ||
      this == PluginStatus.hung;

  /// 进程是否活着（含「活着但不响应」）。
  bool get hasProcess =>
      this == PluginStatus.starting ||
      this == PluginStatus.running ||
      this == PluginStatus.hung ||
      this == PluginStatus.stopping;
}

/// 插件配置项的声明（写在 `plugin.json` 的 `config` 数组里）。
///
/// 为什么让**插件声明**而不是让用户直接改 JSON：
/// 用户不需要知道配置存在哪里、结构是什么，插件作者也不必自己解析命令行或
/// 环境变量。主程序按声明渲染表单、把值存进自己的 JSON 文档
/// （键为 `config_<pluginId>`，与 `state_<pluginId>` 并列，**不在插件目录内**），
/// 并在 `init` 里连同默认值一起下发。
/// 这样「插件可配置」这件事在协议层就是一等公民。
@immutable
class PluginConfigField {
  const PluginConfigField({
    required this.key,
    required this.label,
    this.type = PluginConfigType.text,
    this.defaultValue,
    this.description,
    this.required = false,
  });

  /// 配置键（下发到插件 `config` 对象里的字段名）。
  final String key;

  /// 表单上的显示名。
  final String label;

  /// 控件类型。
  final PluginConfigType type;

  /// 默认值（缺省时按类型给空值）。
  final Object? defaultValue;

  /// 说明文字（表单下方的小字）。
  final String? description;

  /// 是否必填。必填项为空时插件不应被启动。
  final bool required;

  /// 当前值是否可视为「未填写」。
  bool isBlank(Object? value) {
    if (!required) return false;
    if (value == null) return true;
    if (value is String) return value.trim().isEmpty;
    return false;
  }

  factory PluginConfigField.fromJson(Map<String, dynamic> json) =>
      PluginConfigField(
        key: QqJson.str(json['key']) ?? '',
        label: QqJson.str(json['label']) ?? QqJson.str(json['key']) ?? '',
        type: PluginConfigType.fromWire(QqJson.str(json['type'])),
        defaultValue: json['default'],
        description: QqJson.str(json['description']),
        required: QqJson.boolean(json['required']) ?? false,
      );

  Map<String, dynamic> toJson() => {
        'key': key,
        'label': label,
        'type': type.wireName,
        if (defaultValue != null) 'default': defaultValue,
        if (description != null) 'description': description,
        'required': required,
      };
}

/// 配置项控件类型。
enum PluginConfigType {
  /// 单行文本。
  string('string'),

  /// 多行文本。
  text('text'),

  /// 布尔开关。
  boolean('boolean'),

  /// 整数。
  integer('integer'),

  /// 浮点数。
  number('number');

  const PluginConfigType(this.wireName);

  final String wireName;

  /// 未知类型一律按多行文本处理：**宁可退化成文本框，也不要丢掉这个配置项**。
  static PluginConfigType fromWire(String? name) {
    for (final type in values) {
      if (type.wireName == name) return type;
    }
    return PluginConfigType.text;
  }

  /// 解析用户输入的字符串。
  ///
  /// 解析失败返回 [PluginConfigField.defaultValue] 之外的原字符串，
  /// 由界面负责提示——这里不抛异常，避免一个手滑的数字让整张表单崩掉。
  Object? parse(String raw) {
    final text = raw.trim();
    switch (this) {
      case PluginConfigType.boolean:
        return text == 'true' || text == '1' || text == '是';
      case PluginConfigType.integer:
        return int.tryParse(text) ?? (text.isEmpty ? null : text);
      case PluginConfigType.number:
        return num.tryParse(text) ?? (text.isEmpty ? null : text);
      case PluginConfigType.string:
      case PluginConfigType.text:
        return text;
    }
  }

  /// 把值渲染回表单文本。
  String render(Object? value) {
    if (value == null) return '';
    if (value is bool) return value ? 'true' : 'false';
    return '$value';
  }
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
    this.protocolVersion = pluginProtocolVersion,
    this.config = const [],
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

  /// 插件编写时针对的协议版本。
  ///
  /// 主程序据此判断兼容性：版本比主程序新（插件用了未来字段）会拒绝加载，
  /// 比主程序旧则照常加载但记一条提示——**旧插件能跑就不要拦住它**，
  /// 真正危险的是「主程序不认识插件依赖的字段」，那会静默行为异常。
  final int protocolVersion;

  /// 插件声明的配置项。
  final List<PluginConfigField> config;

  /// 协议版本是否被当前主程序支持。
  bool get isProtocolSupported => protocolVersion <= pluginProtocolVersion;

  /// 配置项的默认值集合。
  Map<String, Object?> get configDefaults => {
        for (final field in config) field.key: field.defaultValue,
      };

  factory PluginManifest.fromJson(Map<String, dynamic> json) => PluginManifest(
        id: QqJson.str(json['id']) ?? '',
        name: QqJson.str(json['name']) ?? QqJson.str(json['id']) ?? '',
        version: QqJson.str(json['version']),
        description: QqJson.str(json['description']),
        author: QqJson.str(json['author']),
        entry: QqJson.str(json['entry']) ?? 'main.py',
        events: _stringList(json['events']),
        enabledByDefault: QqJson.boolean(json['enabled_by_default']) ?? false,
        protocolVersion:
            QqJson.integer(json['protocol_version']) ?? pluginProtocolVersion,
        config: _configList(json['config']),
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
        'protocol_version': protocolVersion,
        if (config.isNotEmpty) 'config': config.map((e) => e.toJson()).toList(),
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

  /// 解析配置声明。
  ///
  /// **跳过没有 `key` 的项**而不是整体失败：一个写错的配置项不该让插件
  /// 完全无法加载，用户至少还能用插件的其余功能并在日志里看到提示。
  static List<PluginConfigField> _configList(Object? raw) {
    if (raw is! List) return const [];
    final result = <PluginConfigField>[];
    for (final item in raw) {
      final map = QqJson.map(item);
      if (map == null) continue;
      final field = PluginConfigField.fromJson(map);
      if (field.key.isEmpty) continue;
      result.add(field);
    }
    return List.unmodifiable(result);
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
    this.restartCount = 0,
    this.lastError,
    this.lastStartedAt,
    this.lastStoppedAt,
    this.lastReadyAt,
    this.lastPongAt,
    this.missedPongs = 0,
    this.sentEvents = 0,
    this.droppedLogs = 0,
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
  ///
  /// **只统计非预期退出**：用户主动停止、以及我们主动重启都不计。
  /// 早期实现把主动停止也算进来，结果是「停一次插件就多一次崩溃记录」，
  /// 界面显示「已崩溃 N 次」，而用户其实只按了一次停止。
  final int crashCount;

  /// 本次会话内的自动重启次数（用于展示退避是否已在工作）。
  final int restartCount;

  /// 最近一次错误信息（崩溃原因或启动失败原因）。
  final String? lastError;

  /// 最近一次启动时间。
  final DateTime? lastStartedAt;

  /// 最近一次停止时间。
  final DateTime? lastStoppedAt;

  /// 最近一次握手完成时间（收到插件 `ready`）。
  final DateTime? lastReadyAt;

  /// 最近一次收到 `pong` 的时间。
  final DateTime? lastPongAt;

  /// 连续未响应的心跳次数。
  final int missedPongs;

  /// 累计投递给本插件的事件数。
  final int sentEvents;

  /// 因限流被丢弃的日志行数。
  ///
  /// 插件在死循环里 `print` 会瞬间产生上万行，全部落库会拖垮整个应用。
  /// 丢弃本身是必要的，但**必须让用户知道丢了**，否则排障时会以为插件没输出。
  final int droppedLogs;

  /// 插件 ID。
  String get id => manifest.id;

  /// 是否在运行。
  bool get isRunning => status == PluginStatus.running;

  /// 是否反复崩溃（阈值 3 次），界面应据此给出更强提示。
  bool get isFlapping => crashCount >= 3;

  /// 是否缺少必填配置。
  bool hasMissingConfig(Map<String, Object?> config) {
    for (final field in manifest.config) {
      if (field.isBlank(config[field.key])) return true;
    }
    return false;
  }

  PluginDescriptor copyWith({
    PluginManifest? manifest,
    PluginStatus? status,
    bool? enabled,
    int? pid,
    int? crashCount,
    int? restartCount,
    String? lastError,
    DateTime? lastStartedAt,
    DateTime? lastStoppedAt,
    DateTime? lastReadyAt,
    DateTime? lastPongAt,
    int? missedPongs,
    int? sentEvents,
    int? droppedLogs,
    bool clearError = false,
    bool clearPid = false,
  }) =>
      PluginDescriptor(
        manifest: manifest ?? this.manifest,
        status: status ?? this.status,
        enabled: enabled ?? this.enabled,
        pid: clearPid ? null : (pid ?? this.pid),
        crashCount: crashCount ?? this.crashCount,
        restartCount: restartCount ?? this.restartCount,
        lastError: clearError ? null : (lastError ?? this.lastError),
        lastStartedAt: lastStartedAt ?? this.lastStartedAt,
        lastStoppedAt: lastStoppedAt ?? this.lastStoppedAt,
        lastReadyAt: lastReadyAt ?? this.lastReadyAt,
        lastPongAt: lastPongAt ?? this.lastPongAt,
        missedPongs: missedPongs ?? this.missedPongs,
        sentEvents: sentEvents ?? this.sentEvents,
        droppedLogs: droppedLogs ?? this.droppedLogs,
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
  /// 主进程 → 插件：初始化（下发配置、状态、数据目录与能力声明）。
  init('init'),

  /// 插件 → 主进程：握手完成，可以接收事件。
  ready('ready'),

  /// 主进程 → 插件：投递一个 QQ 事件。
  event('event'),

  /// 插件 → 主进程：请求发送消息（由主进程代为调用官方接口）。
  reply('reply'),

  /// 插件 → 主进程：写一条日志。插件自身的 `print` 也会被归到这里。
  log('log'),

  /// 插件 → 主进程：持久化自己的状态（顶层合并，见 [PluginMessage.statePayload]）。
  stateSet('state_set'),

  /// 插件 → 主进程：删除若干状态键。
  stateRemove('state_remove'),

  /// 主进程 → 插件：配置在运行中被修改（插件应重新读取 `payload.config`）。
  configUpdate('config_update'),

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

  /// `state_set` 携带的状态对象。
  ///
  /// **语义是顶层合并**，不是整体替换：插件可以只发变化的那几个键。
  /// 之所以不做整体替换——插件很容易只记住自己关心的字段，
  /// 整体替换会把主程序维护的其它字段一并抹掉，而且那种丢失是静默的。
  Map<String, dynamic> get statePayload =>
      QqJson.map(payload['state']) ?? const {};

  /// `state_remove` 要删除的键列表。
  List<String> get stateRemoveKeys {
    final raw = payload['keys'];
    if (raw is! List) return const [];
    return raw
        .map((e) => QqJson.str(e))
        .whereType<String>()
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }
}

