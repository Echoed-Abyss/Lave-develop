import 'package:flutter/foundation.dart';

import '../core/constants/app_config.dart';
import '../core/constants/qq_endpoints.dart';
import '../core/constants/qq_limits.dart';
import '../core/error/error_mapper.dart';
import '../core/logging/log_service.dart';
import '../data/local/credential_store.dart';
import '../domain/models/bot_profile.dart';
import '../domain/models/log_entry.dart';
import 'dto/access_token_response.dart';
import 'qq_http_client.dart';

/// 访问凭证的获取与缓存。
///
/// 官方机制（知识库 2.2 / 2.3 节）：
/// - `POST /app/getAppAccessToken`，请求体 `{appId, clientSecret}`；
/// - 该接口**失败时 HTTP 仍返回 200**，必须看响应体的 `code`；
/// - 有效期默认 7200 秒；有效期内重复获取返回**相同的值**；
/// - 过期前 **60 秒**内再次获取会返回新 token，老 token 在这 60 秒内仍有效。
///
/// 因此缓存的必要性不只是性能：频繁换取会触发 `100001 Too many requests`。
class AccessTokenManager {
  AccessTokenManager({
    required QqHttpClient http,
    required CredentialStore credentials,
    required LogService log,
    required AppConfig config,
  })  : _http = http,
        _credentials = credentials,
        _log = log,
        _config = config;

  final QqHttpClient _http;
  final CredentialStore _credentials;
  final LogService _log;
  final AppConfig _config;

  /// 每个 AppID 的缓存。
  final Map<String, _CachedToken> _cache = {};

  /// 取可用的 access_token。
  ///
  /// [forceRefresh] 用于收到 401 / 11243 等凭证类错误后强制换新。
  /// 返回 `null` 表示「没有配置 AppSecret，无法换取」——调用方应提示用户去配置，
  /// 而不是当成网络错误重试。
  Future<String?> accessToken(String appId, {bool forceRefresh = false}) async {
    final cached = _cache[appId];
    if (!forceRefresh && cached != null && cached.isValid(_config)) {
      return cached.value;
    }

    final credential = await _credentials.load(appId);
    if (!credential.canExchangeAccessToken) {
      _log.warn(
        LogSource.api,
        '未配置 AppSecret，无法换取 access_token',
        botId: appId,
        detail: '请到「设置」页填写机器人密钥。仅靠 Bot Token 无法调用 HTTP 接口。',
      );
      return null;
    }

    final response = await _http.postJson(
      QqEndpoints.appAccessToken,
      {
        'appId': appId,
        'clientSecret': credential.appSecret,
      },
      // 取 token 接口本身不需要鉴权头。
    );

    if (!response.isSuccess) {
      final error = response.failure!;
      _log.error(
        LogSource.api,
        '获取 access_token 失败：${error.userMessage}',
        botId: appId,
        officialCode: error.officialCode,
        traceId: error.traceId,
      );
      return null;
    }

    final parsed = AccessTokenResponse.fromJson(response.body);
    if (!parsed.isSuccess) {
      // 走到这里说明 HTTP 200 但业务码非 0（例如 100016 密钥错误）。
      final error = ErrorMapper.fromHttp(
        statusCode: response.statusCode,
        errCode: parsed.code,
        message: parsed.message,
        traceId: response.traceId,
      );
      _log.error(
        LogSource.api,
        '获取 access_token 被拒：${error.userMessage}',
        botId: appId,
        officialCode: parsed.code,
        traceId: response.traceId,
      );
      return null;
    }

    final token = parsed.accessToken!;
    _cache[appId] = _CachedToken(
      value: token,
      issuedAt: DateTime.now(),
      ttl: parsed.ttl,
    );
    _log.info(
      LogSource.api,
      '已获取 access_token（有效期 ${parsed.ttl.inMinutes} 分钟）',
      botId: appId,
    );
    return token;
  }

  /// 主动作废缓存（收到凭证类错误时调用）。
  void invalidate(String appId) {
    _cache.remove(appId);
  }

  /// 是否已有可用缓存（界面可显示凭证状态）。
  bool hasValidToken(String appId) =>
      _cache[appId]?.isValid(_config) ?? false;

  /// 供 Identify 使用的 token 字符串。
  ///
  /// **官方口径冲突未解**（知识库 11.1 节第 1 项）：Identify 的 `token` 字段
  /// 一处写 `QQBot {AccessToken}`，另一处写 `Bot {appid}.{app_token}`。
  /// 因此这里按账号上配置的 [TokenScheme] 拼接，允许真机切换验证。
  Future<String?> buildIdentifyToken(String appId) async {
    final credential = await _credentials.load(appId);
    final token = await accessToken(appId);
    return credential.buildIdentifyToken(accessToken: token);
  }
}

/// 缓存的 token 条目。
@immutable
class _CachedToken {
  const _CachedToken({
    required this.value,
    required this.issuedAt,
    required this.ttl,
  });

  final String value;
  final DateTime issuedAt;
  final Duration ttl;

  /// 是否仍在有效期内（预留官方给的 60 秒提前换新窗口）。
  bool isValid(AppConfig config) {
    final refreshAt = issuedAt
        .add(ttl)
        .subtract(
          ttl > QqLimits.tokenRefreshLead
              ? QqLimits.tokenRefreshLead
              : Duration.zero,
        );
    return DateTime.now().isBefore(refreshAt);
  }
}
