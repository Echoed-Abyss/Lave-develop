/// 官方错误码常量表（机器可读形式）。
///
/// 逐条对照 `docs/qq-bot/knowledge-base.html` 第 10 章与架构文档第 8 章的异常处理矩阵。
/// 把这些数字集中成常量而不是散落在 `ErrorMapper` 里，好处有三：
/// 1. 官方新增码时只改一处；
/// 2. 集合（如 [authCodes]）可直接用于分类，避免长 if-else；
/// 3. 单测可以逐个断言分类结果，形成回归网。
///
/// 说明：官方公共错误码共 200+ 条，本类只收录**本项目实际会处理**的高频项；
/// 未收录的码由 `ErrorMapper` 统一落到 `UnknownApiError` 并保留原始码。
abstract final class QqErrorCodes {
  // ───────────────────────── 鉴权与凭证 ─────────────────────────

  /// 参数中缺少 token。
  static const int wrongToken = 11241;

  /// 校验 token 失败（系统错误，官方建议最多重试一次）。
  static const int checkTokenFailed = 11242;

  /// 校验 token 未通过（token 本身错误）。
  static const int checkTokenNotPass = 11243;

  /// appid 错误 / 无法识别。
  static const int wrongAppId = 11251;

  /// 参数中缺少 appid。
  static const int missingAppId = 11261;

  /// 无 appid。
  static const int noAppId = 11275;

  /// 当前接口不支持使用机器人 Bot Token 调用。
  static const int robotTokenNotAllowed = 11262;

  /// 检查应用权限不通过：该机器人未获得调用该接口的权限，需要向平台申请。
  static const int checkAppPrivilegeNotPass = 11253;

  /// 应用接口被封禁：机器人虽已获得该接口权限，但该接口被封禁。
  ///
  /// **注意与 [robotHasBanned] 区分**：官方把「接口被封禁」与「机器人被封禁」
  /// 列为两个不同的码，用户可见的处理动作也不同（前者是接口权限问题，
  /// 后者需要联系官方解封机器人）。混为一类会让界面给出错误指引。
  static const int interfaceForbidden = 11254;

  /// 机器人已经被封禁。
  static const int robotHasBanned = 11265;

  // 取 access_token 接口的业务错误码（该接口失败时 HTTP 仍为 200）。

  /// Too many requests。
  static const int tokenTooManyRequests = 100001;

  /// appid invalid。
  static const int tokenAppIdInvalid = 100007;

  /// invalid appid or secret。
  static const int tokenAppIdOrSecretInvalid = 100016;

  /// 机器人不存在。
  static const int tokenRobotNotFound = 10004;

  /// 判定为「凭证问题」的码集合。
  ///
  /// 刻意**不含** [interfaceForbidden] 与 [checkAppPrivilegeNotPass]：
  /// 那两项是接口权限问题，凭证本身是有效的，归到「凭证无效」会让用户
  /// 去重填一个本来就正确的密钥。
  static const Set<int> authCodes = {
    wrongToken,
    checkTokenFailed,
    checkTokenNotPass,
    wrongAppId,
    missingAppId,
    noAppId,
    robotTokenNotAllowed,
    tokenAppIdInvalid,
    tokenAppIdOrSecretInvalid,
    tokenRobotNotFound,
  };

  /// 判定为「接口权限不足」的码集合。该类问题不可重试，需在开放平台申请权限。
  static const Set<int> permissionDeniedCodes = {
    checkAppPrivilegeNotPass,
    interfaceForbidden,
  };

  // ───────────────────────── 频率限制 ─────────────────────────

  /// 消息发送超频。
  static const int msgLimitExceed = 22009;

  /// 主动消息发送超过频控限制。
  static const int activeMessageRateLimited = 40034100;

  /// 流式消息频率限制。
  static const int streamRateLimited = 50002;

  /// 子频道消息触发限频。
  static const int channelWriteRateLimit = 20028;

  /// 安全打击：消息被限频。
  static const int securityRateLimited = 1100100;

  /// 判定为「限流」的码集合。
  static const Set<int> rateLimitCodes = {
    msgLimitExceed,
    activeMessageRateLimited,
    streamRateLimited,
    channelWriteRateLimit,
    securityRateLimited,
  };

  // ───────────────────────── 消息请求合法性 ─────────────────────────

  /// 消息类型与内容不匹配（例如同时传了 content 与 markdown）。
  static const int msgTypeMismatch = 22006;

  /// 消息内容无效。
  static const int invalidMessageContent = 304061;

  /// 消息类型无效。
  static const int invalidMsgType = 340069;

  /// 内联键盘行 / 列超限。
  static const int keyboardLimitExceeded = 40034029;

  /// 键盘样式参数错误。
  static const int keyboardStyleInvalid = 305007;

  /// 消息长度超限。
  static const int messageTooLong = 40054007;

  /// markdown 参数有空值。
  static const int markdownEmptyValue = 40034008;

  /// markdown 参数有换行符。
  static const int markdownNewline = 40034009;

  /// 无效的 markdown 内容。
  static const int markdownInvalid = 40034011;

  /// markdown 消息参数错误。
  static const int markdownParamError = 40034124;

  /// 指令参数长度超限。
  static const int commandParamTooLong = 40034108;

  /// 判定为「请求参数非法」的码集合。
  static const Set<int> invalidRequestCodes = {
    msgTypeMismatch,
    invalidMessageContent,
    invalidMsgType,
    keyboardLimitExceeded,
    keyboardStyleInvalid,
    messageTooLong,
    markdownEmptyValue,
    markdownNewline,
    markdownInvalid,
    markdownParamError,
    commandParamTooLong,
  };

  // ───────────────────────── 被动回复窗口 ─────────────────────────

  /// 被动回复时间或次数超限。
  static const int replyWindowExceeded = 40034128;

  /// 消息 ID 已过期，不能回复。
  static const int messageIdExpired = 304103;

  /// 回复消息 msg_id 已过期。
  static const int replyMsgIdExpired = 40034005;

  /// 请求参数 event_id 已过期。
  static const int eventIdExpired = 40034026;

  /// 请求参数 msg_id 无效或越权。
  static const int msgIdInvalid = 40034024;

  /// 请求参数 event_id 无效。
  static const int eventIdInvalid = 40034025;

  /// 该事件不支持回复消息。
  static const int eventNotRepliable = 40034027;

  /// 判定为「被动回复窗口已关闭」的码集合。
  static const Set<int> replyWindowCodes = {
    replyWindowExceeded,
    messageIdExpired,
    replyMsgIdExpired,
    eventIdExpired,
  };

  // ───────────────────────── 主动消息与召回 ─────────────────────────

  /// 主动消息发送失败，无权限。
  static const int activeMessageNoPermission = 40034105;

  /// 召回消息已达区间上限。
  static const int recallQuotaExceeded = 40034122;

  /// 不支持召回消息。
  static const int recallNotSupported = 40034123;

  /// 判定为「主动消息被拒绝」的码集合。
  static const Set<int> activeMessageDeniedCodes = {
    activeMessageNoPermission,
    recallQuotaExceeded,
    recallNotSupported,
  };

  // ───────────────────────── 去重 ─────────────────────────

  /// 消息被去重（相同的 msg_id + msg_seq 重复发送）。
  static const int messageDuplicated = 40054005;

  // ───────────────────────── 内容与 URL ─────────────────────────

  /// 消息内容违规。
  static const int contentViolation = 40034006;

  /// 安全打击：内容涉及敏感。
  static const int securityContent = 1100101;

  /// 不允许发送 URL。
  static const int urlNotAllowed = 40054010;

  /// url 未报备。
  static const int urlNotRegistered = 304003;

  /// 判定为「内容被拦截」的码集合。
  static const Set<int> contentRejectedCodes = {
    contentViolation,
    securityContent,
  };

  // ───────────────────────── 富媒体 ─────────────────────────

  /// 富媒体信息转存失败（官方建议重试）。
  static const int mediaTransferFailed = 40034004;

  /// upload media info fail（官方建议重试）。
  static const int uploadMediaInfoFailed = 304082;

  /// convert media info fail（官方建议重试）。
  static const int convertMediaInfoFailed = 304083;

  /// 下载原始文件失败（官方建议重试）。
  static const int downloadSourceFailed = 850026;

  /// 发送数据超时（官方建议重试）。
  static const int uploadTimeout = 850027;

  /// 文件上传失败（BDH 通道异常，请重试）。
  static const int uploadFailed = 40093001;

  /// 文件信息无效。
  static const int fileInfoInvalid = 304080;

  /// 不支持的文件格式。
  static const int unsupportedFileFormat = 850019;

  /// 上传文件超过大小限制。
  static const int fileTooLarge = 850031;

  /// 超过今天发送文件容量上限。
  static const int dailyFileQuotaExceeded = 40093002;

  /// 判定为「媒体可重试失败」的码集合。
  static const Set<int> mediaTransferCodes = {
    mediaTransferFailed,
    uploadMediaInfoFailed,
    convertMediaInfoFailed,
    downloadSourceFailed,
    uploadTimeout,
    uploadFailed,
    fileInfoInvalid,
  };

  /// 判定为「媒体不合规」的码集合。
  static const Set<int> mediaRejectedCodes = {
    unsupportedFileFormat,
    fileTooLarge,
    dailyFileQuotaExceeded,
  };

  // ───────────────────────── 禁言 / 群成员 / 下线 ─────────────────────────

  /// 机器人被禁言。
  static const int robotMuted = 40054002;

  /// 群被禁言或者机器人被禁言。
  static const int groupOrRobotMuted = 850018;

  /// 机器人非群成员。
  static const int robotNotGroupMember = 40034101;

  /// 机器人不是群成员。
  static const int robotNotInGroup = 40054003;

  /// 机器人已下线。
  static const int robotOffline = 40054016;

  /// 判定为「禁言」的码集合。
  static const Set<int> mutedCodes = {robotMuted, groupOrRobotMuted};

  /// 判定为「不在群内」的码集合。
  static const Set<int> notInGroupCodes = {robotNotGroupMember, robotNotInGroup};

  /// 机器人已被平台封禁的码集合。
  static const Set<int> bannedCodes = {robotHasBanned};

  /// 判定为「机器人已下线」的码集合。
  static const Set<int> offlineCodes = {robotOffline};
}
