import 'package:flutter/foundation.dart';

import '../core/constants/qq_endpoints.dart';
import '../core/error/app_error.dart';
import '../core/logging/log_service.dart';
import '../domain/models/log_entry.dart';
import 'qq_http_client.dart';
import 'token_api.dart';

/// 互动回应接口。
///
/// 官方约束（知识库 5.6 节）：
/// - 收到 `INTERACTION_CREATE` 且 `type = 11`（消息按钮）或 `type = 12`（快捷菜单）
///   时，**必须调用 `PUT /interactions/{interaction_id}` 回应**，
///   否则客户端会一直处于 loading 状态直到超时；
/// - 其他互动类型无需回应；
/// - **同一 `interaction_id` 只能回应一次**，重复调用会失败。
///
/// 官方未给出该接口的完整请求体字段表，只说明「需回应」这一行为；
/// 因此请求体按官方示例的最小形态 `{"code": 0}` 发送，并保留 `data` 透传位。
class InteractionApi {
  InteractionApi({
    required QqHttpClient http,
    required AccessTokenManager tokens,
    required LogService log,
  })  : _http = http,
        _tokens = tokens,
        _log = log;

  final QqHttpClient _http;
  final AccessTokenManager _tokens;
  final LogService _log;

  /// 已回应过的互动 id。
  ///
  /// 官方明确「同一个 interaction_id 只能回应一次」，重复回应会报错。
  /// 事件流本身可能重复推送（官方承认存在重复推送），所以这里必须自己兜一层，
  /// 否则会出现「用户点一次按钮 → 报一次错」的噪音。
  final Set<String> _acknowledged = {};

  /// 回应一次互动。
  ///
  /// [code] 为业务应答码，官方示例默认为 0。
  /// 返回 `null` 表示「无需回应或已回应过」（不是错误）。
  Future<ApiResponse?> acknowledge({
    required String botId,
    required String interactionId,
    int code = 0,
    Map<String, dynamic> extra = const {},
  }) async {
    if (interactionId.isEmpty) return null;
    if (!_acknowledged.add(interactionId)) {
      // 已回应过：直接返回，不产生错误日志（这是预期路径，不是异常）。
      return null;
    }
    // 控制内存：只保留最近的记录。
    if (_acknowledged.length > 500) {
      _acknowledged.remove(_acknowledged.first);
    }

    final token = await _tokens.accessToken(botId);
    if (token == null) {
      // 拿不到凭证时把 id 从已回应集合里移除，让下次事件可以重试。
      _acknowledged.remove(interactionId);
      return ApiResponse.failure(
        AuthError(userMessage: '缺少可用的访问凭证，无法回应互动。'),
      );
    }

    final response = await _http.send(
      method: 'PUT',
      url: QqEndpoints.interaction(interactionId),
      body: {'code': code, ...extra},
      authToken: token,
    );

    if (response.isSuccess) {
      _log.info(
        LogSource.api,
        '已回应互动事件（interaction_id=$interactionId）',
        botId: botId,
      );
    } else {
      // 失败时同样移除，避免「一次网络抖动导致该互动永久无法回应」。
      _acknowledged.remove(interactionId);
      _log.error(
        LogSource.api,
        '回应互动事件失败：${response.failure!.userMessage}',
        botId: botId,
        officialCode: response.failure!.officialCode,
        traceId: response.traceId,
      );
    }
    return response;
  }

  /// 清空已回应记录（切换账号或排障时使用）。
  @visibleForTesting
  void reset() => _acknowledged.clear();
}
