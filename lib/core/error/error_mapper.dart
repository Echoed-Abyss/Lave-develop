import '../../gateway/protocol/qq_opcode.dart';
import 'app_error.dart';
import 'qq_error_codes.dart';

/// 官方错误码 → 语义化异常的映射器。
///
/// 这是「官方文档第 10 章错误码表」在代码中的唯一落点。所有 HTTP 失败与 WSS 关闭
/// 都必须经过这里，业务层与 UI 层不再接触裸错误码。
///
/// 判定顺序刻意编排如下，顺序本身承载了语义：
/// 1. **凭证** 先于其他——凭证不对时其他错误码没有参考意义；
/// 2. **接口权限 / 封禁 / 下架** 紧随其后——这三类都是终态，且容易被误判成
///    凭证或业务问题（官方 11253「接口未授权」、11254「接口被封」与 11265
///    「机器人被封」是三个不同的码，用户可见的处理动作也不同）；
/// 3. **WSS 内部错误段 4900~4913** 单独处理——官方错误码表把它归为
///    「内部错误，请重连」，与 4006/4007「会话失效」虽然动作都是重连，
///    但用户可见的语义完全不同（前者是服务端抽风，后者是本机会话状态失效）；
/// 4. **未知码** 一律保留官方原始码与文案，不吞成笼统错误——
///    官方错误码有 200+ 条且会持续新增。
abstract final class ErrorMapper {
  ErrorMapper._();

  /// 由 HTTP 响应构造异常。
  ///
  /// [statusCode] 为 HTTP 状态码，为 `null` 表示请求根本没到达服务端（DNS / 连接失败）；
  /// [errCode] 为响应体中的 `err_code`，或取 token 接口响应体的 `code`
  /// （该接口失败时 HTTP 仍返回 200，必须依据 `code` 判定）；
  /// [message] 为官方 `message`，仅用于日志，官方明确说明其内容可能随时调整；
  /// [traceId] 来自响应头 `X-Tps-trace-ID` 或响应体 `trace_id`；
  /// [retryAfter] 若响应带 Retry-After 或平台给出建议等待时长则透传。
  static AppError fromHttp({
    int? statusCode,
    int? errCode,
    String? message,
    String? traceId,
    Duration? retryAfter,
    Object? cause,
  }) {
    // ── 1. 凭证类 ──────────────────────────────────────────────
    if (statusCode == 401 ||
        (errCode != null && QqErrorCodes.authCodes.contains(errCode))) {
      return AuthError(
        userMessage: '机器人凭证无效或已过期，请在设置中重新填写 AppID 与密钥。',
        officialCode: errCode ?? statusCode,
        officialMessage: message,
        traceId: traceId,
        cause: cause,
      );
    }

    // ── 2. 接口权限 / 封禁 / 下架（终态，优先于其他业务判定）────
    //
    // 权限类必须早于其他判定：官方 11253 / 11254 是「接口未授权 / 接口被封」，
    // 与凭证无关，若被归到凭证问题会让用户去重填一个本来就正确的密钥。
    if (errCode != null &&
        QqErrorCodes.permissionDeniedCodes.contains(errCode)) {
      return PermissionDeniedError(
        userMessage: '该接口权限不足。请到 QQ 开放平台后台检查机器人'
            '是否已申请并开通对应接口权限。',
        officialCode: errCode,
        officialMessage: message,
        traceId: traceId,
      );
    }
    if (errCode != null && QqErrorCodes.bannedCodes.contains(errCode)) {
      return BotBannedError(
        userMessage: '机器人已被平台封禁，请断开连接并联系官方申请解封。',
        officialCode: errCode,
        officialMessage: message,
        traceId: traceId,
      );
    }
    if (errCode != null && QqErrorCodes.offlineCodes.contains(errCode)) {
      return BotOfflineError(
        userMessage: '机器人已下线，请到 QQ 开放平台后台检查机器人状态。',
        officialCode: errCode,
        officialMessage: message,
        traceId: traceId,
      );
    }

    // ── 3. 限流 ────────────────────────────────────────────────
    if (statusCode == 429 ||
        (errCode != null && QqErrorCodes.rateLimitCodes.contains(errCode))) {
      return RateLimitedError(
        userMessage: '触发平台频率限制，已自动排队稍后重试。',
        officialCode: errCode ?? statusCode,
        officialMessage: message,
        traceId: traceId,
        suggestedDelay: retryAfter,
      );
    }

    // ── 4. 被动回复窗口 ────────────────────────────────────────
    if (errCode != null && QqErrorCodes.replyWindowCodes.contains(errCode)) {
      return ReplyWindowExpiredError(
        userMessage: '回复窗口已关闭（群聊 5 分钟 / 单聊 60 分钟）'
            '，需改用主动消息，注意主动消息有独立频控。',
        officialCode: errCode,
        officialMessage: message,
        traceId: traceId,
      );
    }

    // ── 5. 主动消息被拒 ────────────────────────────────────────
    if (errCode != null &&
        QqErrorCodes.activeMessageDeniedCodes.contains(errCode)) {
      return ActiveMessageDeniedError(
        userMessage: '对方已关闭主动消息，或互动召回配额已用完，本条消息无法送达。',
        officialCode: errCode,
        officialMessage: message,
        traceId: traceId,
      );
    }

    // ── 6. 消息去重 ────────────────────────────────────────────
    if (errCode == QqErrorCodes.messageDuplicated) {
      return DuplicateMessageError(
        userMessage: '该回复已发送过（相同的 msg_id 与 msg_seq），已自动跳过。',
        officialCode: errCode,
        officialMessage: message,
        traceId: traceId,
      );
    }

    // ── 7. URL 未报备 ──────────────────────────────────────────
    if (errCode == QqErrorCodes.urlNotRegistered ||
        errCode == QqErrorCodes.urlNotAllowed) {
      return UrlNotRegisteredError(
        userMessage: '消息包含未报备的链接。请先在 QQ 开放平台后台'
            '「开发设置 - 消息URL配置」中登记该域名。',
        officialCode: errCode,
        officialMessage: message,
        traceId: traceId,
      );
    }

    // ── 8. 内容被拦截 ──────────────────────────────────────────
    if (errCode != null &&
        QqErrorCodes.contentRejectedCodes.contains(errCode)) {
      return ContentRejectedError(
        userMessage: '消息内容未通过平台审核，请修改后重试。',
        officialCode: errCode,
        officialMessage: message,
        traceId: traceId,
      );
    }

    // ── 9. 富媒体 ──────────────────────────────────────────────
    if (errCode != null &&
        QqErrorCodes.mediaTransferCodes.contains(errCode)) {
      return MediaTransferError(
        userMessage: '文件上传或转存失败，正在重试。',
        officialCode: errCode,
        officialMessage: message,
        traceId: traceId,
        cause: cause,
      );
    }
    if (errCode != null &&
        QqErrorCodes.mediaRejectedCodes.contains(errCode)) {
      return MediaRejectedError(
        userMessage: '文件不符合平台要求（格式不支持、超过大小限制，'
            '或今日文件容量已用完）。',
        officialCode: errCode,
        officialMessage: message,
        traceId: traceId,
      );
    }

    // ── 10. 禁言 / 不在群内 ────────────────────────────────────
    if (errCode != null && QqErrorCodes.mutedCodes.contains(errCode)) {
      return MutedError(
        userMessage: '机器人当前被禁言，请等待解禁后再发送。',
        officialCode: errCode,
        officialMessage: message,
        traceId: traceId,
      );
    }
    if (errCode != null && QqErrorCodes.notInGroupCodes.contains(errCode)) {
      return NotInGroupError(
        userMessage: '机器人不在该群内，请先将机器人邀请入群。',
        officialCode: errCode,
        officialMessage: message,
        traceId: traceId,
      );
    }

    // ── 11. 请求参数非法 ───────────────────────────────────────
    if (errCode != null &&
        QqErrorCodes.invalidRequestCodes.contains(errCode)) {
      return InvalidRequestError(
        userMessage: '消息参数不合法，请检查消息类型与内容是否匹配。',
        officialCode: errCode,
        officialMessage: message,
        traceId: traceId,
      );
    }

    // ── 12. 网络层 ─────────────────────────────────────────────
    if (statusCode == null) {
      return NetworkError(
        userMessage: '网络不可用，恢复后将自动重试。',
        cause: cause,
      );
    }

    // ── 13. 服务端瞬时故障 ─────────────────────────────────────
    if (statusCode == 500 || statusCode == 502 ||
        statusCode == 503 || statusCode == 504) {
      return TransientServerError(
        userMessage: '平台服务暂时不可用，正在重试。',
        officialCode: statusCode,
        officialMessage: message,
        traceId: traceId,
        cause: cause,
      );
    }

    // ── 14. 兜底：保留官方原始码与文案 ─────────────────────────
    return UnknownApiError(
      userMessage: message == null || message.isEmpty
          ? '请求失败（未识别的错误）。'
          : '请求失败：$message',
      officialCode: errCode ?? statusCode,
      officialMessage: message,
      traceId: traceId,
      cause: cause,
    );
  }

  /// 由 WSS 关闭码构造异常。
  ///
  /// 判定顺序与 [fromHttp] 同理：封禁 / 下架是终态，优先识别；
  /// 4900~4913 与未知码按网络类可重试处理；剩余按官方的
  /// 「是否可 RESUME / 是否可 IDENTIFY」折算出的动作分类。
  static AppError fromWsClose(int closeCode, {String? reason}) {
    final info = QqWsCloseInfo.resolve(closeCode, reason: reason);

    if (info.isBanned) {
      return BotBannedError(
        userMessage: '机器人已被平台封禁，无法连接。'
            '请断开连接并联系官方申请解封。',
        officialCode: closeCode,
        officialMessage: info.message,
      );
    }
    if (info.isOfflineSandboxOnly) {
      return BotOfflineError(
        userMessage: '机器人已下架，当前仅允许连接沙箱环境。',
        officialCode: closeCode,
        officialMessage: info.message,
      );
    }

    // 官方表中 4900~4913 是「内部错误，请重连」：服务端侧瞬时问题，
    // 与 4006/4007「本机会话失效」不是一回事，因此单独归类。
    if (QqWsCloseInfo.isInternalError(closeCode)) {
      return TransientServerError(
        userMessage: '连接被平台中断（内部错误），正在重连。',
        officialCode: closeCode,
        officialMessage: info.message,
      );
    }

    // 未收录的关闭码：含标准关闭码（如 1000 正常关闭、1006 异常关闭）
    // 与官方表中缺失的 4003~4005。按网络断开处理，退避重连并尝试 Resume。
    if (!info.known) {
      return TransientServerError(
        userMessage: '连接已断开，正在重新连接。',
        officialCode: closeCode,
        officialMessage: info.message,
      );
    }

    return switch (info.action) {
      WsRecoveryAction.identify => SessionInvalidError(
          userMessage: '会话已失效，正在重新鉴权。',
          officialCode: closeCode,
          officialMessage: info.message,
        ),
      WsRecoveryAction.resume => TransientServerError(
          userMessage: '连接已过期，正在恢复会话。',
          officialCode: closeCode,
          officialMessage: info.message,
        ),
      WsRecoveryAction.fatal => ProtocolRejectedError(
          userMessage: closeCode == 4014 || closeCode == 4013
              ? '事件订阅权限不足，请在设置中检查已开通的 intents。'
              : '连接参数被平台拒绝（错误码 $closeCode），'
                  '需修正配置后手动重连。',
          officialCode: closeCode,
          officialMessage: info.message,
        ),
    };
  }

  /// 由 HTTP 状态码与官方码组合出「是否值得重试」的判断。
  ///
  /// 供重试层使用，避免重试层自己再写一套码表判断。
  static bool isRetryable({int? statusCode, int? errCode}) =>
      fromHttp(statusCode: statusCode, errCode: errCode).retryable;

  /// 官方给出过「建议等待时长」的接口限流场景。
  ///
  /// 目前只覆盖主动消息频控：官方给出的时间窗是每分 / 每秒，
  /// 因此建议等待 1 分钟让配额滚动恢复。
  static Duration defaultRetryDelayFor(AppError error) {
    if (error is RateLimitedError) return const Duration(minutes: 1);
    if (error is MediaTransferError) return const Duration(seconds: 2);
    return const Duration(seconds: 1);
  }

  /// 便于 UI 展示的短提示（去掉句末标点的长句不适合放在 SnackBar）。
  static String shortHintFor(AppError error) {
    if (error is RateLimitedError) return '触发频率限制，稍后自动重试';
    if (error is ReplyWindowExpiredError) return '回复窗口已关闭';
    if (error is DuplicateMessageError) return '重复消息已跳过';
    if (error is UrlNotRegisteredError) return '链接未报备';
    if (error is ContentRejectedError) return '内容未通过审核';
    return error.userMessage;
  }
}
