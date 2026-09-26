/// QQ 机器人开放平台官方频率限制与时效常量。
///
/// 全部数值逐字取自官方文档，见 `docs/qq-bot/knowledge-base.html`：
/// 接口级 QPS 见 7.6 节，被动回复窗口与主动消息频控见 9.1 节，富媒体限制见 7.4 节。
///
/// **集中在一处的原因**：这些数字同时被三处使用——接口层的令牌桶（RateLimitGuard）、
/// UI 的配额提示、以及发送前校验。散落会导致「界面提示 5 次、代码只允许 4 次」这类不一致。
///
/// 注意：官方文档存在若干口径冲突（详见知识库 11.1 节），本类统一采用**保守值**，
/// 并在字段注释里标注冲突出处，便于真机实测后调整。
abstract final class QqLimits {
  // ───────────────────────── 接口级 QPS ─────────────────────────

  /// 发送单聊 / 群聊消息：100 QPS（含主动、被动等所有消息类型）。
  static const int sendMessageQps = 100;

  /// 流式发送单聊消息：50 QPS。
  static const int streamMessageQps = 50;

  /// 撤回消息：10 QPS。
  static const int recallQps = 10;

  /// 富媒体上传（files）：50 QPS。
  static const int uploadFileQps = 50;

  /// 富媒体预上传 / 分片完成：10 QPS。
  static const int uploadPrepareQps = 10;

  /// 获取 WSS 接入点：2 QPM，另有 10 QPM burst。
  static const int gatewayQpm = 2;

  /// 获取 WSS 接入点的突发额度。
  static const int gatewayBurstQpm = 10;

  // ───────────────────────── 被动回复窗口 ─────────────────────────

  /// 单聊被动消息有效期：60 分钟。
  static const Duration c2cReplyWindow = Duration(minutes: 60);

  /// 群聊被动消息有效期：5 分钟。
  static const Duration groupReplyWindow = Duration(minutes: 5);

  /// 单聊每条消息最多回复次数。
  ///
  /// 官方口径冲突：`overview.html` 写 4 次，`send.html` 正文写 5 次，
  /// 但其 2026/01/10 更新说明又写「由 60 分钟 5 次调整为 60 分钟 4 次」。取保守值 4。
  static const int c2cMaxRepliesPerMessage = 4;

  /// 群聊每条消息最多回复次数：5 次。
  static const int groupMaxRepliesPerMessage = 5;

  /// 接口字段说明中标注的 `msg_id` 有效期。
  ///
  /// 官方口径冲突：接口页顶部写「被动消息有效期 60 分钟」，字段说明写「msg_id 5 分钟内有效」。
  /// 实现时以本常量做「尽快回复」的提示阈值，真正的窗口判定用 [replyWindowFor]。
  static const Duration msgIdSuggestedTtl = Duration(minutes: 5);

  // ───────────────────────── 主动消息频控 ─────────────────────────

  /// 单聊主动消息：Bot 维度 10 qps（未认证 5 qps 且 30 qpm）。
  static const int c2cActiveQps = 10;
  static const int c2cActiveQpsUnverified = 5;
  static const int c2cActiveQpmUnverified = 30;

  /// 群聊主动消息：Bot 维度企业 / 个人认证 60 qpm，未认证 30 qpm。
  static const int groupActiveQpm = 60;
  static const int groupActiveQpmUnverified = 30;

  /// 单关系维度频控：单聊与群聊均为 20 qpm。
  static const int perRelationshipQpm = 20;

  /// 单关系维度每日上限：每个用户 / 每个群 1000 条。
  static const int perRelationshipDailyLimit = 1000;

  // ───────────────────────── 其它硬约束 ─────────────────────────

  /// 消息撤回时限：发送超过 2 分钟不可撤回。
  static const Duration recallDeadline = Duration(minutes: 2);

  /// access_token 生命周期：默认 7200 秒。
  static const Duration accessTokenTtl = Duration(hours: 2);

  /// access_token 提前换新窗口：过期前 60 秒内再次获取会返回新 token。
  static const Duration tokenRefreshLead = Duration(seconds: 60);

  /// 分片上传默认块大小：官方默认 5MB（示例中出现 10485760 字节）。
  static const int uploadDefaultBlockSizeBytes = 5 * 1024 * 1024;

  /// `md5_10m` 的取样长度：文件前 10002432 字节（约 9.54 MB）。
  static const int md5PrefixBytes = 10002432;

  /// 按钮上限：最多 5 行、每行最多 5 个按钮。
  static const int keyboardMaxRows = 5;
  static const int keyboardMaxButtonsPerRow = 5;

  /// 按钮文字上限：10 字符。
  static const int buttonLabelMaxChars = 10;

  /// 二次确认提示文本上限：40 字符，且不能包含 URL。
  static const int modalContentMaxChars = 40;

  /// 二次确认按钮文字上限：4 字符。
  static const int modalButtonTextMaxChars = 4;

  /// 取被动回复窗口。
  static Duration replyWindowFor({required bool isGroup}) =>
      isGroup ? groupReplyWindow : c2cReplyWindow;

  /// 取每条消息最大可回复次数。
  static int maxRepliesFor({required bool isGroup}) =>
      isGroup ? groupMaxRepliesPerMessage : c2cMaxRepliesPerMessage;
}
