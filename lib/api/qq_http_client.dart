import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/constants/app_config.dart';
import '../core/error/app_error.dart';
import '../core/error/error_mapper.dart';
import '../core/logging/app_logger.dart';
import '../core/logging/log_service.dart';
import '../domain/models/log_entry.dart';
import 'dto/qq_api_error_body.dart';

/// 一次 HTTP 调用的结果。
///
/// 成功与失败都通过本对象返回，**不抛异常**：
/// 调用方（发送消息、上传、取 token）几乎都需要处理失败，
/// 用异常会让「忘记 try-catch」变成崩溃而不是一条错误提示。
@immutable
class ApiResponse {
  const ApiResponse({
    this.statusCode,
    this.body = const {},
    this.traceId,
    this.error,
  });

  /// 成功。
  factory ApiResponse.success({
    required int statusCode,
    Map<String, dynamic> body = const {},
    String? traceId,
  }) =>
      ApiResponse(statusCode: statusCode, body: body, traceId: traceId);

  /// 失败。
  factory ApiResponse.failure(AppError error) => ApiResponse(error: error);

  final int? statusCode;
  final Map<String, dynamic> body;

  /// 平台链路追踪 ID（响应头 `X-Tps-trace-ID` 或响应体 `trace_id`）。
  ///
  /// 官方说明：有无法自行定位的问题时可以把它提交给平台方查日志。
  final String? traceId;

  final AppError? error;

  bool get isSuccess => error == null;

  /// 失败时的语义化异常（成功时为 `null`）。
  AppError? get failure => error;

  /// 以错误结果取数据会抛异常——这是刻意的：调用方必须先判断 [isSuccess]。
  Map<String, dynamic> get data {
    final err = error;
    if (err != null) {
      throw StateError('请求失败，不应读取数据：${err.officialCode} ${err.userMessage}');
    }
    return body;
  }
}

/// QQ 开放平台 HTTP 客户端。
///
/// 统一承担四件事，避免散落在各 API 类里：
/// 1. **域名与鉴权头**：官方唯一域名 `https://api.bot.qq.com`，
///    鉴权头固定为 `Authorization: QQBot {ACCESS_TOKEN}`；
/// 2. **超时**：官方建议发消息接口 timeout 最低 5 秒，
///    这里默认 10 秒并允许单次覆盖；
/// 3. **trace_id 采集**：响应头与响应体两处都取，供排查使用；
/// 4. **错误归一**：所有失败都交给 `ErrorMapper`，
///    调用方只看到语义化异常，不再接触裸错误码。
class QqHttpClient {
  QqHttpClient({
    required LogService log,
    required AppConfig config,
    http.Client? client,
  })  : _log = log,
        _config = config,
        _client = client ?? http.Client();

  final LogService _log;
  final AppConfig _config;
  final http.Client _client;

  /// 发送请求。
  ///
  /// [authToken] 为 `null` 表示**不带鉴权头**——只有
  /// `POST /app/getAppAccessToken` 属于这种情况（它用 appId + secret 换 token）。
  Future<ApiResponse> send({
    required String method,
    required String url,
    Map<String, dynamic>? body,
    String? authToken,
    Duration? timeout,
  }) async {
    final uri = Uri.parse(url);
    final headers = <String, String>{
      // 官方示例使用 `application/json; charset=utf-8`。
      'Content-Type': 'application/json; charset=utf-8',
      'Accept': 'application/json',
      if (authToken != null && authToken.isNotEmpty)
        'Authorization': 'QQBot $authToken',
    };

    final effectiveTimeout = timeout ?? _config.httpTimeout;
    _log.network(
      '→ $method ${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}',
      tag: 'http',
    );

    try {
      final request = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) request.body = jsonEncode(body);

      final streamed = await _client.send(request).timeout(effectiveTimeout);
      final response = await http.Response.fromStream(streamed)
          .timeout(effectiveTimeout);

      final traceId = _traceIdFrom(response);
      final parsed = _decodeBody(response.body);

      _log.network(
        '← ${response.statusCode} ${uri.path}'
        '${traceId == null ? '' : ' trace=$traceId'}',
        tag: 'http',
      );

      return _interpret(
        statusCode: response.statusCode,
        body: parsed,
        traceId: traceId,
      );
    } on TimeoutException catch (error) {
      // 超时**不代表请求没发出去**，官方建议把 timeout 设到 5 秒以上
      // 正是为了规避「已发送成功但没收到结果」。调用方若要重试，
      // 必须带业务幂等（同一 msg_id 递增 msg_seq）。
      final appError = TimeoutError(
        userMessage: '请求超时（${effectiveTimeout.inSeconds} 秒），'
            '请确认网络后重试。',
        cause: error,
      );
      _recordFailure(appError, uri.path);
      return ApiResponse.failure(appError);
    } on SocketException catch (error) {
      final appError = ErrorMapper.fromHttp(statusCode: null, cause: error);
      _recordFailure(appError, uri.path);
      return ApiResponse.failure(appError);
    } catch (error, stack) {
      AppLogger.error('HTTP 调用异常：${uri.path}',
          error: error, stackTrace: stack, tag: 'http');
      final appError = NetworkError(
        userMessage: '网络异常，未能完成请求。',
        cause: error,
      );
      _recordFailure(appError, uri.path);
      return ApiResponse.failure(appError);
    }
  }

  /// GET。
  Future<ApiResponse> get(String url, {String? authToken, Duration? timeout}) =>
      send(
        method: 'GET',
        url: url,
        authToken: authToken,
        timeout: timeout,
      );

  /// POST（JSON 体）。
  Future<ApiResponse> postJson(
    String url,
    Map<String, dynamic> body, {
    String? authToken,
    Duration? timeout,
  }) =>
      send(
        method: 'POST',
        url: url,
        body: body,
        authToken: authToken,
        timeout: timeout,
      );

  /// DELETE。
  Future<ApiResponse> delete(
    String url, {
    String? authToken,
    Duration? timeout,
  }) =>
      send(
        method: 'DELETE',
        url: url,
        authToken: authToken,
        timeout: timeout,
      );

  /// 释放底层连接池。
  void dispose() => _client.close();

  // ───────────────────────── 内部实现 ─────────────────────────

  /// 把 HTTP 结果翻译为成功或语义化失败。
  ///
  /// 关键点：**不能只看 HTTP 状态码**。官方取 token 接口在业务失败时
  /// 仍返回 200，必须检查响应体的 `code` / `err_code`。
  ApiResponse _interpret({
    required int statusCode,
    required Map<String, dynamic> body,
    String? traceId,
  }) {
    final errorBody = QqApiErrorBody.fromJson(body)
        .withTraceIdFrom(traceId);

    final is2xx = statusCode >= 200 && statusCode < 300;
    if (is2xx) {
      // 业务码为 0 或缺失视为成功；非 0 即使在 2xx 下也是失败。
      final code = errorBody.errCode;
      if (code == null || code == 0) {
        return ApiResponse.success(
          statusCode: statusCode,
          body: body,
          traceId: traceId,
        );
      }
      final appError = ErrorMapper.fromHttp(
        statusCode: statusCode,
        errCode: code,
        message: errorBody.message,
        traceId: traceId,
      );
      _recordFailure(appError, null);
      return ApiResponse.failure(appError);
    }

    final appError = ErrorMapper.fromHttp(
      statusCode: statusCode,
      errCode: errorBody.errCode,
      message: errorBody.message,
      traceId: traceId,
    );
    _recordFailure(appError, null, statusCode: statusCode);
    return ApiResponse.failure(appError);
  }

  /// 解析响应体。非 JSON（例如网关返回的 HTML 错误页）按空对象处理。
  Map<String, dynamic> _decodeBody(String raw) {
    if (raw.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return decoded.cast<String, dynamic>();
      return const {};
    } catch (_) {
      return const {};
    }
  }

  String? _traceIdFrom(http.Response response) {
    // 官方给出两种获取方式，两处都试。
    final header = response.headers['x-tps-trace-id'];
    if (header != null && header.isNotEmpty) return header;
    final decoded = _decodeBody(response.body);
    final body = QqApiErrorBody.fromJson(decoded);
    return body.traceId;
  }

  /// 把失败写入日志服务。
  ///
  /// 凭证类错误单独标红：它会直接导致后续全部接口失败，
  /// 是排查时第一个要看的东西。
  void _recordFailure(AppError error, String? path, {int? statusCode}) {
    final detail = StringBuffer();
    if (path != null) detail.writeln('path: $path');
    if (statusCode != null) detail.writeln('http: $statusCode');
    if (error.officialCode != null) detail.writeln('code: ${error.officialCode}');
    if (error.officialMessage != null) detail.writeln('message: ${error.officialMessage}');
    if (error.traceId != null) detail.writeln('trace: ${error.traceId}');

    final isCredential = error.isCredentialIssue;
    _log.log(
      LogEntry(
        level: isCredential ? LogLevel.error : LogLevel.warn,
        source: LogSource.api,
        message: error.userMessage,
        at: DateTime.now(),
        officialCode: error.officialCode,
        traceId: error.traceId,
        detail: detail.toString().trim(),
      ),
    );
  }
}
