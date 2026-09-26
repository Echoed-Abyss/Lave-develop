/// QQ 机器人开放平台官方接口地址。
///
/// 全部路径逐字取自官方 api-v2 文档，见 `docs/qq-bot/knowledge-base.html` 第 7.6 节端点索引。
/// 唯一官方统一域名是 `https://api.bot.qq.com`（官方文档中未出现其他域名；旧版文档里的
/// `api.sgroup.qq.com` 与沙箱域名不在本项目使用范围内）。
///
/// 约定：
/// - `{user_openid}` / `{group_openid}` 是单聊、群聊场景的用户与群标识；
/// - `{user_id}` / `{group_id}` 是富媒体预上传与分片完成接口用的标识，官方参数名如此，
///   与 openid 不是同一个名字，不要互相替换。
abstract final class QqEndpoints {
  /// 官方统一请求地址（HTTPS）。
  static const String apiBase = 'https://api.bot.qq.com';

  /// WSS 接入点的官方示例地址。
  ///
  /// 仅作参考与排障对照：**实际必须使用 `GET /gateway` 或 `GET /gateway/bot` 返回的 `url`**，
  /// 不要硬编码直连。
  static const String gatewayWssExample = 'wss://api.bot.qq.com/websocket/';

  // ───────────────────────── 鉴权 ─────────────────────────

  /// 获取 access_token。
  ///
  /// 官方方法为 **POST**（不是 GET），请求体 `{appId, clientSecret}`。
  /// 特别注意：该接口失败时 HTTP 仍返回 200，必须读响应体的 `code`。
  /// 频率限制：官方未给出 QPS 数字，仅给出错误码 100001 Too many requests。
  static const String appAccessToken = '$apiBase/app/getAppAccessToken';

  /// 获取当前机器人信息（官方鉴权示例中出现的接口）。
  static const String usersMe = '$apiBase/users/@me';

  // ───────────────────────── WSS 接入点 ─────────────────────────

  /// 获取通用 WSS 接入点。频率限制 2 QPM / 10 QPM burst。
  static const String gateway = '$apiBase/gateway';

  /// 获取带分片 WSS 接入点，同时返回建议分片数与 Session 创建限额。
  static const String gatewayBot = '$apiBase/gateway/bot';

  // ───────────────────────── 单聊（C2C）─────────────────────────

  /// 发送单聊消息。频率限制 100 QPS。
  static String c2cMessages(String userOpenid) =>
      '$apiBase/v2/users/$userOpenid/messages';

  /// 流式发送单聊消息。频率限制 50 QPS。
  static String c2cStreamMessages(String userOpenid) =>
      '$apiBase/v2/users/$userOpenid/stream_messages';

  /// 撤回单聊消息。频率限制 10 QPS。
  static String c2cMessageRecall(String userOpenid, String messageId) =>
      '$apiBase/v2/users/$userOpenid/messages/$messageId';

  /// 单聊富媒体上传（返回 file_info）。频率限制 50 QPS。
  ///
  /// 上传的文件**仅能发送到单聊**，与群聊接口相互独立，不能跨场景复用。
  static String c2cFiles(String userOpenid) =>
      '$apiBase/v2/users/$userOpenid/files';

  /// 单聊富媒体预上传（分片上传第一步）。频率限制 10 QPS。
  static String c2cUploadPrepare(String userId) =>
      '$apiBase/v2/users/$userId/upload_prepare';

  /// 单聊分片上传完成通知（分片上传第三步）。频率限制 10 QPS。
  static String c2cUploadPartFinish(String userId) =>
      '$apiBase/v2/users/$userId/upload_part_finish';

  // ───────────────────────── 群聊（Group）────────────────────────

  /// 发送群聊消息。频率限制 100 QPS。
  static String groupMessages(String groupOpenid) =>
      '$apiBase/v2/groups/$groupOpenid/messages';

  /// 撤回群聊消息。频率限制 10 QPS。
  static String groupMessageRecall(String groupOpenid, String messageId) =>
      '$apiBase/v2/groups/$groupOpenid/messages/$messageId';

  /// 群聊富媒体上传（返回 file_info）。频率限制 50 QPS。
  static String groupFiles(String groupOpenid) =>
      '$apiBase/v2/groups/$groupOpenid/files';

  /// 群聊富媒体预上传。频率限制 10 QPS。
  static String groupUploadPrepare(String groupId) =>
      '$apiBase/v2/groups/$groupId/upload_prepare';

  /// 群聊分片上传完成通知。频率限制 10 QPS。
  static String groupUploadPartFinish(String groupId) =>
      '$apiBase/v2/groups/$groupId/upload_part_finish';

  // ───────────────────────── 互动与表情 ─────────────────────────

  /// 回应按钮 / 快捷菜单交互。
  ///
  /// 官方要求：收到 `INTERACTION_CREATE` 且 `type=11`（消息按钮）或 `type=12`（快捷菜单）
  /// 时必须调用本接口回应，否则客户端会一直处于 loading 直到超时；
  /// 同一 interaction_id 只能回应一次。
  static String interaction(String interactionId) =>
      '$apiBase/interactions/$interactionId';

  /// 表情表态（频道体系）：PUT 发表、DELETE 删除、GET 查询用户列表。
  ///
  /// `type` 为表情类型、`id` 为表情 id，均来自官方表情模型。
  static String messageReaction(
    String channelId,
    String messageId,
    String type,
    String id,
  ) =>
      '$apiBase/channels/$channelId/messages/$messageId/reactions/$type/$id';
}
