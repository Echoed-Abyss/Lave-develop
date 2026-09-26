import 'package:flutter/foundation.dart';

import '../core/constants/qq_endpoints.dart';
import '../core/error/app_error.dart';
import '../core/logging/log_service.dart';
import '../domain/models/log_entry.dart';
import 'dto/send_message_request.dart';
import 'dto/send_message_response.dart';
import 'qq_http_client.dart';
import 'token_api.dart';

/// 消息类接口（发送、撤回）。
///
/// 官方端点与频率限制（知识库 7.1 / 7.3 节）：
/// - 发单聊 `POST /v2/users/{user_openid}/messages`，100 QPS；
/// - 发群聊 `POST /v2/groups/{group_openid}/messages`，100 QPS；
/// - 撤回单聊 / 群聊 `DELETE .../messages/{message_id}`，10 QPS；
/// - **发送超过 2 分钟的消息不可撤回。**
class MessageApi {
  MessageApi({
    required QqHttpClient http,
    required AccessTokenManager tokens,
    required LogService log,
  })  : _http = http,
        _tokens = tokens,
        _log = log;

  final QqHttpClient _http;
  final AccessTokenManager _tokens;
  final LogService _log;

  /// 发送单聊消息。
  Future<ApiResponse> sendC2c({
    required String botId,
    required String userOpenid,
    required SendMessageRequest request,
  }) =>
      _send(
        botId: botId,
        url: QqEndpoints.c2cMessages(userOpenid),
        request: request,
        targetLabel: '单聊',
      );

  /// 发送群聊消息。
  ///
  /// 注意：群聊场景的被动回复窗口只有 **5 分钟**（单聊 60 分钟），
  /// 且 `event_id` 支持的事件与单聊不同。
  Future<ApiResponse> sendGroup({
    required String botId,
    required String groupOpenid,
    required SendMessageRequest request,
  }) =>
      _send(
        botId: botId,
        url: QqEndpoints.groupMessages(groupOpenid),
        request: request,
        targetLabel: '群聊',
      );

  Future<ApiResponse> _send({
    required String botId,
    required String url,
    required SendMessageRequest request,
    required String targetLabel,
  }) async {
    // 发送前本地校验：把官方的互斥规则（22006 等）提前拦住，
    // 让用户看到明确的表单错误，而不是一次失败的请求。
    final errors = request.validate();
    if (errors.isNotEmpty) {
      final message = errors.join('；');
      _log.warn(
        LogSource.api,
        '消息未通过本地校验，已拦截：$message',
        botId: botId,
      );
      return ApiResponse.failure(
        InvalidRequestError(userMessage: '消息内容不合法：$message'),
      );
    }

    final token = await _tokens.accessToken(botId);
    if (token == null) {
      return ApiResponse.failure(
        AuthError(userMessage: '缺少可用的访问凭证，请到「设置」页检查机器人密钥。'),
      );
    }

    _log.info(
      LogSource.api,
      '发送$targetLabel消息'
      '（${request.isPassiveReply ? '被动回复 msg_seq=${request.effectiveMsgSeq}' : '主动消息'}）',
      botId: botId,
    );

    final response = await _http.postJson(
      url,
      request.toJson(),
      authToken: token,
    );

    if (!response.isSuccess) {
      final error = response.failure!;
      // 凭证类失败时作废缓存，下次调用会自动换新。
      if (error.isCredentialIssue) _tokens.invalidate(botId);
      return response;
    }
    return response;
  }

  /// 撤回单聊消息。
  Future<ApiResponse> recallC2c({
    required String botId,
    required String userOpenid,
    required String messageId,
  }) =>
      _recall(
        botId: botId,
        url: QqEndpoints.c2cMessageRecall(userOpenid, messageId),
      );

  /// 撤回群聊消息。
  Future<ApiResponse> recallGroup({
    required String botId,
    required String groupOpenid,
    required String messageId,
  }) =>
      _recall(
        botId: botId,
        url: QqEndpoints.groupMessageRecall(groupOpenid, messageId),
      );

  Future<ApiResponse> _recall({
    required String botId,
    required String url,
  }) async {
    final token = await _tokens.accessToken(botId);
    if (token == null) {
      return ApiResponse.failure(
        AuthError(userMessage: '缺少可用的访问凭证，无法撤回消息。'),
      );
    }
    final response = await _http.delete(url, authToken: token);
    if (response.isSuccess) {
      _log.info(LogSource.api, '已撤回消息', botId: botId);
    }
    return response;
  }

  /// 解析发送结果。
  ///
  /// 返回 `null` 表示响应不是成功态，具体原因在 [ApiResponse.failure] 里。
  @visibleForTesting
  SendMessageResponse? parseSendResult(ApiResponse response) =>
      response.isSuccess ? SendMessageResponse.fromJson(response.body) : null;
}
