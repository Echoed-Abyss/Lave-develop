import 'package:flutter/foundation.dart';

import '../api/qq_http_client.dart';
import '../api/token_api.dart';
import '../core/constants/qq_endpoints.dart';
import '../core/error/app_error.dart';
import '../core/logging/log_service.dart';
import '../domain/models/log_entry.dart';

/// WSS 接入点信息。
@immutable
class GatewayEndpoint {
  const GatewayEndpoint({
    required this.url,
    this.shards,
    this.sessionLimit,
    this.fetchedAt,
  });

  /// 官方返回的 WebSocket 连接地址。
  ///
  /// **必须使用本字段，不要硬编码** —— 官方文档中的
  /// `wss://api.bot.qq.com/websocket/` 只是示例。
  final String url;

  /// 官方建议的 shard 数。本项目不做分片，仅记录用于日志。
  final int? shards;

  /// Session 创建限额。
  final SessionStartLimit? sessionLimit;

  final DateTime? fetchedAt;

  /// 是否可用于建连。
  bool get isUsable => url.isNotEmpty && url.startsWith('ws');

  factory GatewayEndpoint.fromJson(Map<String, dynamic> json) =>
      GatewayEndpoint(
        url: (json['url'] as String?) ?? '',
        shards: (json['shards'] as num?)?.toInt(),
        sessionLimit: json['session_start_limit'] == null
            ? null
            : SessionStartLimit.fromJson(
                (json['session_start_limit'] as Map).cast<String, dynamic>(),
              ),
        fetchedAt: DateTime.now(),
      );
}

/// 官方 `SessionStartLimit`。
///
/// 官方字段表（知识库 3.1 节）：
/// `total` 每 24 小时可创建 Session 数、`remaining` 目前还可以创建的 Session 数、
/// `reset_after` 重置计数的剩余时间(ms)、`max_concurrency` 每 5s 可以创建的 Session 数。
@immutable
class SessionStartLimit {
  const SessionStartLimit({
    this.total,
    this.remaining,
    this.resetAfter,
    this.maxConcurrency,
  });

  final int? total;
  final int? remaining;
  final int? resetAfter;
  final int? maxConcurrency;

  factory SessionStartLimit.fromJson(Map<String, dynamic> json) =>
      SessionStartLimit(
        total: (json['total'] as num?)?.toInt(),
        remaining: (json['remaining'] as num?)?.toInt(),
        resetAfter: (json['reset_after'] as num?)?.toInt(),
        maxConcurrency: (json['max_concurrency'] as num?)?.toInt(),
      );

  /// 剩余额度是否已用尽。
  ///
  /// 官方原文：**每个机器人创建的连接数不能超过 `remaining` 剩余连接数**。
  bool get isExhausted => remaining != null && remaining! <= 0;

  /// 重置剩余时间。
  Duration? get resetAfterDuration =>
      resetAfter == null ? null : Duration(milliseconds: resetAfter!);
}

/// WSS 接入点获取。
///
/// 官方限制 `GET /gateway` 为 **2 QPM**（另有 10 QPM burst），
/// 因此本类**必须带缓存**：缓存不是优化，而是避免触发限流的必要措施。
/// 缓存时长来自 `AppConfig.endpointCacheTtl`。
class GatewayApi {
  GatewayApi({
    required QqHttpClient http,
    required AccessTokenManager tokens,
    required LogService log,
  })  : _http = http,
        _tokens = tokens,
        _log = log;

  final QqHttpClient _http;
  final AccessTokenManager _tokens;
  final LogService _log;

  final Map<String, GatewayEndpoint> _cache = {};

  /// 获取接入点。
  ///
  /// [forceRefresh] 为 `true` 时跳过缓存（用于「连接反复失败」的排障场景）。
  Future<GatewayEndpoint?> fetch(
    String botId, {
    bool forceRefresh = false,
    Duration cacheTtl = const Duration(minutes: 5),
  }) async {
    if (!forceRefresh) {
      final cached = _cache[botId];
      if (cached != null && _isFresh(cached, cacheTtl)) return cached;
    }

    final token = await _tokens.accessToken(botId);
    if (token == null) {
      _log.warn(
        LogSource.gateway,
        '无法获取接入点：缺少可用的访问凭证',
        botId: botId,
      );
      return null;
    }

    // 使用带分片的端点：它会额外返回 session_start_limit，
    // 便于在界面上展示连接额度（官方两个端点的 url 返回值一致）。
    final response = await _http.get(
      QqEndpoints.gatewayBot,
      authToken: token,
    );

    if (!response.isSuccess) {
      _log.error(
        LogSource.gateway,
        '获取 WSS 接入点失败：${response.failure!.userMessage}',
        botId: botId,
        officialCode: response.failure!.officialCode,
        traceId: response.traceId,
      );
      if (response.failure!.isCredentialIssue) _tokens.invalidate(botId);
      return null;
    }

    final endpoint = GatewayEndpoint.fromJson(response.body);
    if (!endpoint.isUsable) {
      _log.error(
        LogSource.gateway,
        '接入点地址异常，无法建立连接',
        botId: botId,
        detail: '实际响应：${response.body}',
      );
      return null;
    }

    _cache[botId] = endpoint;
    final limit = endpoint.sessionLimit;
    _log.info(
      LogSource.gateway,
      '已获取 WSS 接入点'
      '${limit?.remaining == null ? '' : '（Session 剩余额度 ${limit!.remaining}）'}',
      botId: botId,
    );
    return endpoint;
  }

  /// 清除缓存（切换账号或排障时使用）。
  void invalidate(String botId) => _cache.remove(botId);

  bool _isFresh(GatewayEndpoint endpoint, Duration ttl) {
    final fetchedAt = endpoint.fetchedAt;
    if (fetchedAt == null) return false;
    return DateTime.now().difference(fetchedAt) < ttl;
  }
}
