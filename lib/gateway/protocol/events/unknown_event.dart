part of 'qq_event.dart';

/// 未知事件。
///
/// 存在的必要性：官方事件超过 24 种且会持续新增，而 `decode` 是对事件流的
/// **唯一入口**。如果遇到不认识的 `t` 就抛异常或丢弃，后果是：
/// 1. 抛异常 → 整条事件流中断，机器人表现为「突然不再收到任何消息」；
/// 2. 直接丢弃 → 事件静默消失，用户永远不知道发生了什么。
///
/// 因此这里把原始载荷完整保留，交给日志层与插件层处理：
/// 日志能留下证据，插件能自行决定是否处理。
@immutable
class UnknownEvent extends QqEvent {
  const UnknownEvent({
    required this.type,
    required this.raw,
    super.eventId,
    super.seq,
  });

  /// 官方原始 `t` 值。
  final String? type;

  /// 官方原始 `d` 载荷，原样保留。
  final Map<String, dynamic> raw;

  /// 由于类型未知，一律按生命周期事件处理并写入事件日志，
  /// 保证「有事件发生」这件事不会丢失。
  @override
  bool get isLifecycleEvent => true;

  @override
  String get typeName => type ?? 'UNKNOWN';

  /// `t` 是否缺失（连类型都没有，说明平台侧数据结构超预期）。
  bool get hasNoType => type == null || type!.isEmpty;

  /// 是否为待补建模的官方事件。
  ///
  /// 界面与日志据此提示「该事件类型尚未支持」，而不是静默忽略。
  bool get needsModeling => !hasNoType;
}
