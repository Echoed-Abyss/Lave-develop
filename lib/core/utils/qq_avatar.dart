/// QQ 用户头像地址构造。
///
/// ## 来源与可靠性（实测记录）
///
/// 官方文档只提供机器人自己的头像（`GET /users/@me` 的 `avatar`），
/// 单聊/群聊消息事件里的 `author` **没有** `avatar` 字段，也没有
/// 「按 openid 查用户资料」的接口。但腾讯的头像 CDN 支持按
/// `AppID + openid` 直接取用户头像：
///
/// ```
/// https://q.qlogo.cn/qqapp/{appid}/{openid}/{size}
/// ```
///
/// 本项目在真实数据上实测过（`appid=102810595`，`openid` 取自事件里的
/// 群成员 openid）：
///
/// | 路径 | 结果 |
/// | --- | --- |
/// | `.../100` | `200 image/jpeg` 2200 字节 |
/// | `.../640` | `200 image/jpeg` 27003 字节 |
/// | `.../0`（原图） | `200 image/jpeg` 57567 字节 |
/// | `q.qlogo.cn` 与 `thirdqq.qlogo.cn` | 两个域名返回一致 |
/// | 响应头 | `Cache-Control: max-age=2592000`（30 天），`Last-Modified` 随头像更新 |
/// | **不存在的 openid** | 仍是 `200 image/jpeg`，返回 1512 字节的**默认灰色头像** |
///
/// ## 三条必须知道的限制
///
/// 1. **这是未在官方文档中出现的 CDN 地址**，不属于承诺的对外接口，
///    随时可能变更。因此界面必须保留占位兜底（见 `shared/widgets/avatars.dart`），
///    不能假设它永远可用；
/// 2. **无法通过状态码或响应体判断「有没有头像」**：openid 无效时同样返回 200，
///    只是内容换成默认灰头像。所以「显示出来的灰头像」不等于「代码写错了」；
/// 3. openid 是**按 AppID 隔离**的，因此 URL 必须带上这个 openid 所属的 AppID，
///    拿 A 机器人的 AppID 配 B 机器人收到的 openid 取不到任何东西。
///
/// 这个地址不含任何凭证，请求直接发往腾讯的 CDN，不经过第三方；
/// 因此它不涉及「逆向 QQ 客户端协议」，只是取一张公开的图片。
abstract final class QqAvatar {
  /// CDN 主机。`thirdqq.qlogo.cn` 是等价域名，实测返回一致。
  static const String host = 'https://q.qlogo.cn';

  /// 尺寸阶梯（CDN 实际支持的档位）。
  ///
  /// 默认取 [medium] 而不是 [large]：头像在列表与气泡里的显示尺寸
  /// 只有 26~30 逻辑像素，100 像素足够 3x 屏，而 640 档是它的 12 倍体积
  /// （27KB vs 2.2KB）。一屏二十个头像就是数百 KB 的差别。
  static const int small = 40;
  static const int medium = 100;
  static const int large = 640;

  /// 原图。体积不可控（实测 57KB 起），列表场景不要用。
  static const int original = 0;

  /// 由机器人的 AppID 与用户 openid 构造头像地址。
  ///
  /// [openid] 为空时返回 `null`——调用方据此退回占位，
  /// 而不是拼出一个必然指向默认灰头像的地址。
  static String? forOpenid({
    required String? appId,
    required String? openid,
    int size = medium,
  }) {
    final id = appId?.trim();
    final user = openid?.trim();
    if (id == null || id.isEmpty) return null;
    if (user == null || user.isEmpty) return null;
    // openid 由十六进制字符组成，本身是 URL 安全的；这里仍然编码，
    // 是因为万一官方换成含特殊字符的形态，拼串会静默错误。
    return '$host/qqapp/${Uri.encodeComponent(id)}/'
        '${Uri.encodeComponent(user)}/$size';
  }
}
