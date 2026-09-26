import 'package:flutter/foundation.dart';

import '../../core/error/app_error.dart';

/// WSS 连接阶段。
///
/// 与 `docs/qq-bot/app-architecture.html` 第 3.3 节的状态机一一对应。
/// 刻意**包含一个终态** [blocked]：官方对封禁（4915）、下架（4914）、
/// intents 无权限（4014）等错误码明确标注「不可重试」，
/// 如果代码统一走「无限重连」，表现就是无休止地重连失败、耗电、日志刷屏，
/// 而用户看不到任何有效信息。
enum ConnectionPhase {
  /// 未启动。
  idle('空闲'),

  /// 正在获取 WSS 接入点（`GET /gateway/bot`）。
  fetchingEndpoint('获取接入点'),

  /// 已建立 TCP/WS 连接，等待 Op10 Hello。
  connecting('建立连接'),

  /// 已发出 Identify 或 Resume，等待 READY / RESUMED。
  authenticating('鉴权中'),

  /// 在线，正在接收事件并发送心跳。
  online('在线'),

  /// 断开后处于退避等待。
  backoff('退避重连'),

  /// 需要人工介入的终态（封禁 / 下架 / 参数与权限错误）。
  blocked('已停止'),

  /// 当前平台不支持运行（例如 iOS 上无法启动 Python 子进程）。
  ///
  /// 放在连接状态里而不是插件状态里，是因为「能力不可用」需要被
  /// 统一呈现在机器人卡片上，而不是散落在各功能页。
  unsupported('平台不支持'),
  ;

  const ConnectionPhase(this.label);

  /// 中文短标签，供界面直接展示。
  final String label;

  /// 是否处于「已连上、可收发」状态。
  bool get isOnline => this == ConnectionPhase.online;

  /// 是否处于自动恢复流程中（界面上应显示为「进行中」而非「故障」）。
  bool get isRecovering =>
      this == ConnectionPhase.backoff ||
      this == ConnectionPhase.connecting ||
      this == ConnectionPhase.authenticating ||
      this == ConnectionPhase.fetchingEndpoint;

  /// 是否已停止且不会自动恢复。
  bool get isStopped =>
      this == ConnectionPhase.blocked || this == ConnectionPhase.unsupported;
}

/// 连接状态快照。
///
/// 这是一个**不可变快照**而非可变对象：状态机每次迁移都产出新快照，
/// 便于 UI 用 `AsyncValue`/`Stream` 直接比较与渲染，也便于日志记录
/// 「什么时候从什么状态变成了什么状态」。
@immutable
class ConnectionSnapshot {
  const ConnectionSnapshot({
    required this.botId,
    required this.phase,
    required this.changedAt,
    this.attempt = 0,
    this.sessionId,
    this.seq,
    this.heartbeatInterval,
    this.lastError,
    this.nextRetryAt,
  });

  /// 所属机器人 AppID。
  final String botId;

  /// 当前阶段。
  final ConnectionPhase phase;

  /// 本次阶段开始时间。
  final DateTime changedAt;

  /// 当前重连尝试次数（0 表示首连）。
  final int attempt;

  /// 当前会话 id（Identify 成功后由 READY 下发）。
  final String? sessionId;

  /// 已处理完成的最大事件序列号。
  final int? seq;

  /// 服务端下发的心跳周期。
  final Duration? heartbeatInterval;

  /// 最近一次错误。仅用于展示与日志，不作为业务判据。
  final AppError? lastError;

  /// 下次重连时间（[ConnectionPhase.backoff] 时有值）。
  final DateTime? nextRetryAt;

  /// 初始空闲状态。
  factory ConnectionSnapshot.idle(String botId, DateTime now) =>
      ConnectionSnapshot(
        botId: botId,
        phase: ConnectionPhase.idle,
        changedAt: now,
      );

  /// 是否在线。
  bool get isOnline => phase.isOnline;

  /// 是否已停止且不会自动恢复。
  bool get isStopped => phase.isStopped;

  /// 是否有可用会话（可尝试 Resume）。
  ///
  /// 判定条件：**必须同时具备 `session_id` 与 `seq`**。
  /// 只有 session_id 而没有 seq 时，Resume 会缺少「从哪补发」的水位，
  /// 官方未说明这种情况的行为，因此保守地改走 Identify。
  bool get canResume =>
      sessionId != null && sessionId!.isNotEmpty && seq != null;

  /// 是否携带了需要用户处理的错误。
  bool get needsUserAction => lastError?.needsUserAction ?? false;

  /// 从本次阶段开始到现在经过的时间。
  Duration elapsedSinceChange(DateTime now) => now.difference(changedAt);

  /// 距离下次重连还有多久（无重连计划时为 `null`）。
  Duration? remainingBackoff(DateTime now) {
    final target = nextRetryAt;
    if (target == null) return null;
    final remaining = target.difference(now);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// 迁移到新阶段。
  ConnectionSnapshot transition(
    ConnectionPhase next,
    DateTime now, {
    int? attempt,
    String? sessionId,
    int? seq,
    Duration? heartbeatInterval,
    AppError? lastError,
    DateTime? nextRetryAt,
    bool clearError = false,
  }) =>
      ConnectionSnapshot(
        botId: botId,
        phase: next,
        changedAt: now,
        attempt: attempt ?? (next == ConnectionPhase.backoff ? this.attempt : 0),
        sessionId: sessionId ?? this.sessionId,
        seq: seq ?? this.seq,
        heartbeatInterval: heartbeatInterval ?? this.heartbeatInterval,
        lastError: clearError ? null : (lastError ?? this.lastError),
        nextRetryAt: nextRetryAt,
      );

  /// 更新会话水位（seq 只在「事件处理完成」后推进，见架构文档 3.4 节）。
  ConnectionSnapshot withSeq(int? newSeq) => ConnectionSnapshot(
        botId: botId,
        phase: phase,
        changedAt: changedAt,
        attempt: attempt,
        sessionId: sessionId,
        seq: newSeq,
        heartbeatInterval: heartbeatInterval,
        lastError: lastError,
        nextRetryAt: nextRetryAt,
      );

  /// 清空会话（Identify 重新开始或 Resume 失败后使用）。
  ConnectionSnapshot withoutSession() => ConnectionSnapshot(
        botId: botId,
        phase: phase,
        changedAt: changedAt,
        attempt: attempt,
        heartbeatInterval: heartbeatInterval,
        lastError: lastError,
        nextRetryAt: nextRetryAt,
      );

  @override
  String toString() =>
      'ConnectionSnapshot($botId, ${phase.name}, attempt=$attempt, '
      'session=${sessionId == null ? '-' : 'yes'}, seq=${seq ?? '-'})';
}
