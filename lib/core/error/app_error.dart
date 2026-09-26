import 'package:flutter/foundation.dart';

/// 语义化异常基类。
///
/// 设计目标：把官方文档中**两百多条错误码**收敛为**一组可穷尽匹配的行为类别**。
/// UI 只做 `switch`，业务层只判断「是否可重试」「是否需要人工介入」，
/// 不允许在各处散落 `if (code == 40034128)` 这类判断。
///
/// 每个子类都携带三样东西：
/// 1. [officialCode] / [officialMessage]：官方原始错误码与文案，用于日志与「复制诊断信息」；
/// 2. [userMessage]：面向用户的中文提示，统一在这里给，不在 UI 里拼；
/// 3. [retryable]：是否值得自动重试——这决定了重试层的行为，是错误处理的核心分叉点。
sealed class AppError implements Exception {
  const AppError({
    required this.userMessage,
    this.officialCode,
    this.officialMessage,
    this.traceId,
    this.cause,
  });

  /// 面向用户的提示文案（中文，界面直接展示）。
  final String userMessage;

  /// 官方错误码（HTTP body 的 `err_code`，或 WSS 关闭码）。
  final int? officialCode;

  /// 官方原始错误信息，仅用于日志与排查，不作为逻辑判据
  /// （官方明确说明 message 内容可能随时调整）。
  final String? officialMessage;

  /// 平台链路追踪 ID，来自响应头 `X-Tps-trace-ID` 或响应体 `trace_id`。
  final String? traceId;

  /// 底层原因（网络异常等），便于日志保留调用链。
  final Object? cause;

  /// 是否值得自动重试。
  ///
  /// 官方对「内容违规」「URL 未报备」「参数错误」这类问题不会因为重试而变成成功，
  /// 因此这些类别必须返回 `false`，否则只会浪费配额并放大限流风险。
  bool get retryable;

  /// 是否需要人工介入（配置错误、权限、封禁等），UI 应引导用户去处理而不是静默重试。
  bool get needsUserAction => false;

  @override
  String toString() {
    final buffer = StringBuffer(runtimeType.toString());
    if (officialCode != null) buffer.write('(official=$officialCode)');
    if (officialMessage != null) buffer.write(' officialMessage=$officialMessage');
    if (traceId != null) buffer.write(' traceId=$traceId');
    if (cause != null) buffer.write(' cause=$cause');
    return buffer.toString();
  }
}

/// 配置类错误：凭证缺失或非法，属于本机配置问题，重试无用。
class ConfigError extends AppError {
  const ConfigError({
    required super.userMessage,
    super.officialCode,
    super.officialMessage,
    super.traceId,
    super.cause,
  });

  @override
  bool get retryable => false;

  @override
  bool get needsUserAction => true;
}

/// 网络不可用或连接被拒。
class NetworkError extends AppError {
  const NetworkError({required super.userMessage, super.cause});

  @override
  bool get retryable => true;
}

/// 请求超时。
///
/// 注意：超时**不代表消息没发出去**。官方提示发消息接口 timeout 建议最低 5 秒，
/// 就是为了规避「实际已发送成功但没收到同步结果」。因此超时后如需重试，
/// 必须带业务幂等（同一 `msg_id` 递增 `msg_seq`），不能盲目重发。
class TimeoutError extends AppError {
  const TimeoutError({required super.userMessage, super.cause});

  @override
  bool get retryable => true;
}

/// 凭证无效或已过期。
class AuthError extends AppError {
  const AuthError({
    required super.userMessage,
    super.officialCode,
    super.officialMessage,
    super.traceId,
    super.cause,
  });

  @override
  bool get retryable => false;

  @override
  bool get needsUserAction => true;
}

/// 接口权限不足：该机器人未获得调用该接口的权限，或该接口被封禁。
///
/// 与 [AuthError] 的区别很关键：这里**凭证本身是有效的**，问题出在接口授权上，
/// 因此提示用户去重填密钥是错误指引，正确动作是到开放平台查看 / 申请接口权限。
class PermissionDeniedError extends AppError {
  const PermissionDeniedError({
    required super.userMessage,
    super.officialCode,
    super.officialMessage,
    super.traceId,
  });

  @override
  bool get retryable => false;

  @override
  bool get needsUserAction => true;
}

/// 触发平台频率限制。
class RateLimitedError extends AppError {
  const RateLimitedError({
    required super.userMessage,
    super.officialCode,
    super.officialMessage,
    super.traceId,
    this.suggestedDelay,
  });

  /// 建议的等待时长（若能从响应中推断）。
  final Duration? suggestedDelay;

  @override
  bool get retryable => true;
}

/// 请求参数非法（官方消息类型与内容不匹配、消息类型无效、消息内容无效等）。
class InvalidRequestError extends AppError {
  const InvalidRequestError({
    required super.userMessage,
    super.officialCode,
    super.officialMessage,
    super.traceId,
  });

  @override
  bool get retryable => false;
}

/// 被动回复窗口已关闭或次数用尽。
///
/// 官方：单聊 60 分钟、群聊 5 分钟；超过有效期或超过可回复次数都会失败。
/// 这不是异常场景而是正常业务分支，UI 应引导改用主动消息（受主动消息频控约束）。
class ReplyWindowExpiredError extends AppError {
  const ReplyWindowExpiredError({
    required super.userMessage,
    super.officialCode,
    super.officialMessage,
    super.traceId,
  });

  @override
  bool get retryable => false;

  @override
  bool get needsUserAction => true;
}

/// 主动消息被拒绝：用户已关闭主动消息开关，或召回配额已用完。
class ActiveMessageDeniedError extends AppError {
  const ActiveMessageDeniedError({
    required super.userMessage,
    super.officialCode,
    super.officialMessage,
    super.traceId,
  });

  @override
  bool get retryable => false;

  @override
  bool get needsUserAction => true;
}

/// 消息被去重：相同的 `msg_id + msg_seq` 重复发送会失败。
///
/// 处理方式不是重试原请求，而是**递增 `msg_seq`** 后重发。
class DuplicateMessageError extends AppError {
  const DuplicateMessageError({
    required super.userMessage,
    super.officialCode,
    super.officialMessage,
    super.traceId,
  });

  @override
  bool get retryable => false;
}

/// 内容被平台拦截（安全打击、内容违规）。
class ContentRejectedError extends AppError {
  const ContentRejectedError({
    required super.userMessage,
    super.officialCode,
    super.officialMessage,
    super.traceId,
  });

  @override
  bool get retryable => false;

  @override
  bool get needsUserAction => true;
}

/// 消息包含未报备的 URL。
///
/// 官方要求含 URL 的消息需先在开放平台后台「消息URL配置」报备，否则发送失败。
class UrlNotRegisteredError extends AppError {
  const UrlNotRegisteredError({
    required super.userMessage,
    super.officialCode,
    super.officialMessage,
    super.traceId,
  });

  @override
  bool get retryable => false;

  @override
  bool get needsUserAction => true;
}

/// 媒体文件不合规：格式不支持、超过大小限制、当日容量用完。
class MediaRejectedError extends AppError {
  const MediaRejectedError({
    required super.userMessage,
    super.officialCode,
    super.officialMessage,
    super.traceId,
  });

  @override
  bool get retryable => false;

  @override
  bool get needsUserAction => true;
}

/// 媒体转存 / 上传过程中的可恢复失败。
///
/// 官方对这类错误明确「请重试」（如下载原始文件失败、富媒体信息转存失败），
/// 因此是本项目少数几类**值得自动重试**的错误。
class MediaTransferError extends AppError {
  const MediaTransferError({
    required super.userMessage,
    super.officialCode,
    super.officialMessage,
    super.traceId,
    super.cause,
  });

  @override
  bool get retryable => true;
}

/// 机器人被禁言。
class MutedError extends AppError {
  const MutedError({
    required super.userMessage,
    super.officialCode,
    super.officialMessage,
    super.traceId,
  });

  @override
  bool get retryable => false;

  @override
  bool get needsUserAction => true;
}

/// 机器人不在目标群内。
class NotInGroupError extends AppError {
  const NotInGroupError({
    required super.userMessage,
    super.officialCode,
    super.officialMessage,
    super.traceId,
  });

  @override
  bool get retryable => false;

  @override
  bool get needsUserAction => true;
}

/// 机器人已下线或被下架（仅允许连接沙箱环境）。
class BotOfflineError extends AppError {
  const BotOfflineError({
    required super.userMessage,
    super.officialCode,
    super.officialMessage,
    super.traceId,
  });

  @override
  bool get retryable => false;

  @override
  bool get needsUserAction => true;
}

/// 机器人已被平台封禁。
///
/// 官方对 WSS 关闭码 4915 与 HTTP 错误码 11265 都标注为不可重试，
/// 必须停止重连并提示用户联系官方解封，否则会表现为「无限重连 + 耗电 + 日志刷屏」。
class BotBannedError extends AppError {
  const BotBannedError({
    required super.userMessage,
    super.officialCode,
    super.officialMessage,
    super.traceId,
  });

  @override
  bool get retryable => false;

  @override
  bool get needsUserAction => true;
}

/// WSS 协议层参数或权限错误（无效 opcode / payload / shard / version / intent，intent 无权限）。
///
/// 官方对 4001、4002、4010~4014 的「是否可 RESUME / 是否可 IDENTIFY」两列全为「否」，
/// 说明属于代码或权限问题，重试不会自愈。
class ProtocolRejectedError extends AppError {
  const ProtocolRejectedError({
    required super.userMessage,
    super.officialCode,
    super.officialMessage,
    super.traceId,
  });

  @override
  bool get retryable => false;

  @override
  bool get needsUserAction => true;
}

/// WSS 会话失效（4006 无效 session id、4007 seq 错误）。
///
/// 官方要求丢弃旧会话重新 Identify，因此对上层是「可自动恢复」的。
class SessionInvalidError extends AppError {
  const SessionInvalidError({
    required super.userMessage,
    super.officialCode,
    super.officialMessage,
    super.traceId,
  });

  @override
  bool get retryable => true;
}

/// 服务端瞬时故障（HTTP 500 / 504、WSS 4900~4913 内部错误）。
class TransientServerError extends AppError {
  const TransientServerError({
    required super.userMessage,
    super.officialCode,
    super.officialMessage,
    super.traceId,
    super.cause,
  });

  @override
  bool get retryable => true;
}

/// 未归类错误。
///
/// 刻意保留官方原始码与文案：官方错误码有 200 多条且会新增，
/// 未归类时必须让原始信息可见，而不是被吞成一个笼统的「未知错误」。
class UnknownApiError extends AppError {
  const UnknownApiError({
    required super.userMessage,
    super.officialCode,
    super.officialMessage,
    super.traceId,
    super.cause,
  });

  @override
  bool get retryable => false;
}

/// 便于判定的扩展方法。
extension AppErrorX on AppError {
  /// 是否属于「凭证问题」，UI 据此决定是否跳到设置页。
  bool get isCredentialIssue =>
      this is AuthError || this is ConfigError;

  /// 是否属于「机器人不可用」的终态，UI 据此提示联系平台。
  bool get isTerminalForBot => this is BotBannedError || this is BotOfflineError;

  /// 调试信息（含官方码与 traceId），用于「复制诊断信息」。
  @visibleForTesting
  String get diagnostic =>
      'kind=${runtimeType.toString()} official=$officialCode '
      'message=$officialMessage trace=$traceId';
}
