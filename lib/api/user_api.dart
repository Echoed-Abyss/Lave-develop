import 'package:flutter/foundation.dart';

import '../core/constants/qq_endpoints.dart';
import '../core/error/app_error.dart';
import '../core/logging/log_service.dart';
import '../domain/models/log_entry.dart';
import 'qq_http_client.dart';
import 'token_api.dart';

/// 机器人自身资料。
///
/// 官方字段表（`GET /users/@me`）：`id`、`username`、`avatar`、`bot`，
/// 以及需特殊申请的 `union_openid` / `union_user_account`。
@immutable
class BotIdentity {
  const BotIdentity({
    this.id,
    this.username,
    this.avatarUrl,
    this.isBot,
  });

  final String? id;

  /// 官方昵称。
  final String? username;

  /// 头像 URL。
  ///
  /// **这是官方唯一提供机器人头像的地方**：`GET /gateway/bot` 的响应里没有
  /// `avatar`，单聊 / 群聊的消息事件里也没有。
  final String? avatarUrl;

  final bool? isBot;

  factory BotIdentity.fromJson(Map<String, dynamic> json) => BotIdentity(
        id: json['id']?.toString(),
        username: _text(json['username']),
        avatarUrl: _text(json['avatar']),
        isBot: json['bot'] is bool ? json['bot'] as bool : null,
      );

  /// 是否拿到了任何可用的展示信息。
  bool get hasAnything =>
      (username?.isNotEmpty ?? false) || (avatarUrl?.isNotEmpty ?? false);

  static String? _text(Object? raw) {
    if (raw is! String) return null;
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

/// 机器人自身资料接口。
///
/// 只做一件事：`GET /users/@me`。
///
/// 为什么需要它：官方在**单聊与群聊的消息事件里不返回头像**——
/// 那些事件里的 `author` 只有各种 openid 与昵称。想要显示真实头像，
/// 只能取机器人自己的（[BotIdentity.avatarUrl]）。
/// 用户侧的头像官方没有提供任何查询接口，界面只能退回确定性占位。
class UserApi {
  UserApi({
    required QqHttpClient http,
    required AccessTokenManager tokens,
    required LogService log,
  })  : _http = http,
        _tokens = tokens,
        _log = log;

  final QqHttpClient _http;
  final AccessTokenManager _tokens;
  final LogService _log;

  /// 拉取机器人自身资料；失败返回 `null`（调用方保持原有资料即可）。
  Future<BotIdentity?> fetchSelf(String botId) async {
    final token = await _tokens.accessToken(botId);
    if (token == null) {
      // 没有可用凭证不算异常：用户可能只填了 Bot Token 而没填 AppSecret，
      // 那种情况下连接能用但 HTTP 接口用不了，头像保持占位即可。
      _log.warn(
        LogSource.api,
        '跳过机器人资料刷新：缺少可用的访问凭证',
        botId: botId,
        detail: '官方要求用 access_token 调用 GET /users/@me；'
            '若只填了 Bot Token，请补上 AppSecret。',
      );
      return null;
    }

    final response = await _http.get(QqEndpoints.usersMe, authToken: token);
    if (!response.isSuccess) {
      final failure = response.failure!;
      // 凭证失效时顺手作废，下一次会重新换取。
      if (failure.isCredentialIssue) _tokens.invalidate(botId);
      // 取头像失败不影响任何核心功能，因此只记 warning，不打扰用户。
      _log.warn(
        LogSource.api,
        '获取机器人资料失败：${failure.userMessage}',
        botId: botId,
        detail: '该接口只用于展示昵称与头像，失败不影响收发消息。',
      );
      return null;
    }

    final identity = BotIdentity.fromJson(response.body);
    _log.info(
      LogSource.api,
      '已获取机器人资料'
      '${identity.username == null ? '' : '：${identity.username}'}'
      '${identity.avatarUrl == null ? '（无头像）' : ''}',
      botId: botId,
    );
    return identity;
  }
}
