import 'package:flutter/foundation.dart';

import '../../core/utils/qq_json.dart';

/// 机器人账号模型。
///
/// 一个 AppID 对应一个机器人，因此 [appId] 即业务主键。
@immutable
class BotProfile {
  const BotProfile({
    required this.appId,
    required this.displayName,
    this.officialName,
    this.avatarUrl,
    this.enabled = true,
    this.createdAt,
    this.lastConnectedAt,
    this.remark,
  });

  /// 机器人 AppID（官方称为「机器人 ID」，必须使用）。
  ///
  /// 作为本地主键的原因：官方没有提供「本地昵称」概念，
  /// 而 AppID 是唯一稳定标识；界面展示名允许用户自行修改。
  final String appId;

  /// 界面展示名（用户在编辑面板里填的备注名）。缺省时回退到官方昵称或 AppID。
  final String displayName;

  /// 官方返回的机器人昵称（来自 `GET /users/@me` 的 `username`）。
  ///
  /// 与 [displayName] 分开存的原因：用户填的备注名是他的选择，
  /// 不该被一次资料刷新悄悄覆盖；两者都在界面上有用
  /// （列表显示备注名，详情里可以对照官方昵称）。
  final String? officialName;

  /// 头像地址（如有）。
  ///
  /// 来源是 `GET /users/@me` 的 `avatar`：**这是官方唯一提供头像的机器人相关接口**
  /// （`GET /gateway/bot` 不含该字段，消息事件里也没有）。
  final String? avatarUrl;

  /// 是否启用。关闭后不建立连接，但仍保留配置与历史。
  final bool enabled;

  /// 本地添加时间。
  final DateTime? createdAt;

  /// 最近一次连接成功时间。
  final DateTime? lastConnectedAt;

  /// 用户备注。
  final String? remark;

  /// 用于界面展示的名称。
  ///
  /// 优先级：用户备注名 → 官方昵称 → AppID。
  String get title {
    if (displayName.isNotEmpty) return displayName;
    final official = officialName?.trim();
    if (official != null && official.isNotEmpty) return official;
    return appId;
  }

  /// 用于日志与列表的短标识：保留 AppID 后 6 位便于区分。
  String get shortId => appId.length <= 6 ? appId : appId.substring(appId.length - 6);

  factory BotProfile.fromJson(Map<String, dynamic> json) => BotProfile(
        appId: QqJson.str(json['app_id']) ?? '',
        displayName: QqJson.str(json['display_name']) ?? '',
        officialName: QqJson.str(json['official_name']),
        avatarUrl: QqJson.str(json['avatar_url']),
        enabled: QqJson.boolean(json['enabled']) ?? true,
        createdAt: _dateTime(json['created_at']),
        lastConnectedAt: _dateTime(json['last_connected_at']),
        remark: QqJson.str(json['remark']),
      );

  Map<String, dynamic> toJson() => {
        'app_id': appId,
        'display_name': displayName,
        if (officialName != null) 'official_name': officialName,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
        'enabled': enabled,
        if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
        if (lastConnectedAt != null)
          'last_connected_at': lastConnectedAt!.toIso8601String(),
        if (remark != null) 'remark': remark,
      };

  BotProfile copyWith({
    String? displayName,
    String? officialName,
    String? avatarUrl,
    bool? enabled,
    DateTime? lastConnectedAt,
    String? remark,
  }) =>
      BotProfile(
        appId: appId,
        displayName: displayName ?? this.displayName,
        officialName: officialName ?? this.officialName,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        enabled: enabled ?? this.enabled,
        createdAt: createdAt,
        lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
        remark: remark ?? this.remark,
      );

  static DateTime? _dateTime(Object? raw) {
    final text = QqJson.str(raw);
    return text == null ? null : DateTime.tryParse(text);
  }
}

/// WSS Identify 报文的 `token` 拼接方式。
///
/// **官方存在口径冲突**（知识库 11.1 节第 1 项）：字段表写
/// `格式为 "QQBot {AccessToken}"`，另一页正文写
/// `格式为 Bot {appid}.{app_token}`，官方未指明以哪个为准。
///
/// 因此把「拼法」做成账号上的一个可选设置，允许在真机上切换验证，
/// 而不是把某一种拼法写死在代码里——否则一旦猜错，
/// 表现是「连接被拒但错误码不指向 token」，排查成本极高。
enum TokenScheme {
  /// `QQBot {AccessToken}`（官方字段表口径）。
  qqBotAccessToken('QQBot {token}'),

  /// `Bot {appid}.{app_token}`（官方另一页正文口径）。
  botAppToken('Bot {appid}.{token}');

  const TokenScheme(this.template);

  /// 拼接模板，`{token}` 与 `{appid}` 为占位符。
  final String template;

  /// 按本拼法生成 Identify 用的 token。
  String build({required String appId, required String token}) =>
      template
          .replaceAll('{appid}', appId)
          .replaceAll('{token}', token);

  static TokenScheme fromName(String? name) {
    for (final scheme in values) {
      if (scheme.name == name) return scheme;
    }
    return TokenScheme.qqBotAccessToken;
  }
}

/// 机器人凭证。
///
/// **安全约定**：**本对象只以内存形态存在**，绝不能被序列化进普通数据库、
/// 日志或崩溃上报。持久化必须走 `flutter_secure_storage`（见 data 层），
/// 且 `toString` 已覆写为脱敏形态，避免被日志无意打印。
///
/// 关于 [appSecret]：本项目采用「用户在设置页手动输入 AppSecret 并存入设备」
/// 的方案（架构文档决策 D1）。其代价是设备被 root / App 被反编译时存在泄露风险，
/// 因此相关防护（FLAG_SECURE、掩码显示、禁止导出）必须在 UI 层落实。
@immutable
class BotCredential {
  const BotCredential({
    required this.appId,
    this.appSecret,
    this.botToken,
    this.tokenScheme = TokenScheme.qqBotAccessToken,
  });

  /// 机器人 AppID。
  final String appId;

  /// 机器人密钥（AppSecret / ClientSecret）。
  ///
  /// 用途：调用 `POST /app/getAppAccessToken` 换取 access_token。
  /// 官方明确「用于在 oauth 场景进行请求签名的密钥」，且强调
  /// 「为了安全考虑，请勿在应用前端使用访问凭证」——本项目的取舍见类文档。
  final String? appSecret;

  /// 机器人 Token（官方已标注「已弃用」，但 Identify 的另一种官方写法需要它）。
  ///
  /// 保留该字段的原因：官方 `reference` 页给出 `Bot {appid}.{app_token}` 的
  /// Identify 拼法，其中的 `app_token` 正是管理端直接获得的 Token。
  /// 若实测确认该拼法可用，则无需 AppSecret 即可连接（但 HTTP 接口仍需要
  /// access_token，故 AppSecret 依然是必需的）。
  final String? botToken;

  /// Identify 的 token 拼接方式。
  final TokenScheme tokenScheme;

  /// 是否具备换取 access_token 的条件。
  bool get canExchangeAccessToken =>
      appSecret != null && appSecret!.isNotEmpty;

  /// 是否具备 Identify 所需的最小信息。
  ///
  /// 两种路径任一成立即可：有 appSecret（先换 access_token 再拼），
  /// 或直接有 botToken（按 `Bot {appid}.{token}` 拼）。
  bool get canIdentify =>
      canExchangeAccessToken || (botToken != null && botToken!.isNotEmpty);

  /// 生成 Identify 用的 token 字符串。
  ///
  /// `accessToken` 由调用方（凭证层）在需要时换取，本模型不承担网络职责。
  String? buildIdentifyToken({String? accessToken}) {
    final token = switch (tokenScheme) {
      TokenScheme.qqBotAccessToken => accessToken ?? botToken,
      TokenScheme.botAppToken => botToken ?? accessToken,
    };
    if (token == null || token.isEmpty) return null;
    return tokenScheme.build(appId: appId, token: token);
  }

  /// 脱敏输出。
  ///
  /// 覆写 `toString` 是必须的：Dart 默认的对象字符串不含字段值，
  /// 但一旦有人给它加了 `toString` 或把字段拼进日志，密钥就会外泄。
  /// 这里主动给出脱敏版本，任何 `'$credential'` 形式的打印都是安全的。
  @override
  String toString() =>
      'BotCredential(appId=$appId, appSecret=${_mask(appSecret)}, '
      'botToken=${_mask(botToken)}, tokenScheme=${tokenScheme.name})';

  static String _mask(String? value) {
    if (value == null || value.isEmpty) return '<empty>';
    if (value.length <= 4) return '***';
    return '${value.substring(0, 2)}***${value.substring(value.length - 2)}';
  }
}
