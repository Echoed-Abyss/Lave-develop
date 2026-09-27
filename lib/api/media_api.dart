import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/constants/qq_endpoints.dart';
import '../core/error/app_error.dart';
import '../core/logging/app_logger.dart';
import '../core/logging/log_service.dart';
import '../core/utils/media_checksum.dart';
import '../domain/models/log_entry.dart';
import '../domain/models/qq_enums.dart';
import 'dto/media_payloads.dart';
import 'qq_http_client.dart';
import 'token_api.dart';

/// 富媒体上传接口。
///
/// 官方流程（知识库 7.4 节，三段式四步）：
/// 1. `upload_prepare` → 拿 `upload_id` / `block_size` / 各分片预签名 URL；
/// 2. 逐片 HTTP PUT 到预签名 URL（**这一步不带 QQBot 鉴权头**，用的是 URL 自带签名）；
/// 3. 每片成功后 `upload_part_finish`；
/// 4. 携带 `upload_id` 调 `files` 完成合并，拿到 `file_info`。
///
/// **为什么移动端必须走分片**：官方的 URL 直传要求提供一个平台可下载的
/// 公网 URL，而 `image_picker` 给的是设备本地文件。
///
/// **上传的文件不能跨场景复用**：官方明确「单聊和群聊的文件上传接口相互独立」，
/// 因此同一张图要分别调 [uploadForC2c] 与 [uploadForGroup]。
class MediaApi {
  MediaApi({
    required QqHttpClient httpClient,
    required AccessTokenManager tokens,
    required LogService log,
    http.Client? rawClient,
  })  : _http = httpClient,
        _tokens = tokens,
        _log = log,
        _rawClient = rawClient ?? http.Client();

  final QqHttpClient _http;
  final AccessTokenManager _tokens;
  final LogService _log;

  /// 用于向预签名 URL 直传的原生客户端（不走 QQBot 鉴权）。
  final http.Client _rawClient;

  /// 上传到单聊。
  Future<UploadOutcome> uploadForC2c({
    required String botId,
    required String userOpenid,
    required String filePath,
    required QqMediaFileType fileType,
    String? fileName,
  }) =>
      _upload(
        botId: botId,
        prepareUrl: QqEndpoints.c2cUploadPrepare(userOpenid),
        partFinishUrl: QqEndpoints.c2cUploadPartFinish(userOpenid),
        mergeUrl: QqEndpoints.c2cFiles(userOpenid),
        filePath: filePath,
        fileType: fileType,
        fileName: fileName,
      );

  /// 上传到群聊。
  Future<UploadOutcome> uploadForGroup({
    required String botId,
    required String groupOpenid,
    required String filePath,
    required QqMediaFileType fileType,
    String? fileName,
  }) =>
      _upload(
        botId: botId,
        prepareUrl: QqEndpoints.groupUploadPrepare(groupOpenid),
        partFinishUrl: QqEndpoints.groupUploadPartFinish(groupOpenid),
        mergeUrl: QqEndpoints.groupFiles(groupOpenid),
        filePath: filePath,
        fileType: fileType,
        fileName: fileName,
      );

  Future<UploadOutcome> _upload({
    required String botId,
    required String prepareUrl,
    required String partFinishUrl,
    required String mergeUrl,
    required String filePath,
    required QqMediaFileType fileType,
    String? fileName,
  }) async {
    // ① 上传前按官方软硬限制本地拦截。
    final file = File(filePath);
    if (!await file.exists()) {
      return UploadOutcome.failure(
        MediaRejectedError(userMessage: '文件不存在或已被移动：$filePath'),
      );
    }
    final size = await file.length();
    if (size > fileType.hardLimitBytes) {
      return UploadOutcome.failure(
        MediaRejectedError(
          userMessage: '文件 ${(size / 1024 / 1024).toStringAsFixed(1)}MB 超过'
              '官方硬限制 ${fileType.hardLimitMb}MB，无法上传。',
        ),
      );
    }
    // 超过软限制时官方会降级为「文件」类型上传，这里显式改类型，
    // 让发送端的展示与实际类型一致。
    final effectiveType =
        size > fileType.softLimitBytes ? QqMediaFileType.file : fileType;

    final token = await _tokens.accessToken(botId);
    if (token == null) {
      return UploadOutcome.failure(
        AuthError(userMessage: '缺少可用的访问凭证，无法上传文件。'),
      );
    }

    final bytes = await file.readAsBytes();
    final name = fileName ?? file.uri.pathSegments.last;

    // ② upload_prepare。官方的 md5 / sha1 / md5_10m 标为必填，
    // 会在读文件时一并算出来，不做「不传也能通过」的侥幸依赖。
    final checksum = MediaChecksum.of(bytes);
    final prepareResponse = await _http.postJson(
      prepareUrl,
      UploadPrepareRequest(
        fileType: effectiveType,
        fileSize: size,
        fileName: name,
        md5: checksum.md5,
        sha1: checksum.sha1,
        md5Prefix: checksum.md5Prefix,
      ).toJson(),
      authToken: token,
    );
    if (!prepareResponse.isSuccess) {
      return UploadOutcome.failure(prepareResponse.failure!);
    }

    final prepared = UploadPrepareResponse.fromJson(prepareResponse.body);
    if (!prepared.isUsable) {
      _log.error(
        LogSource.api,
        'upload_prepare 响应缺少必要字段，无法继续分片上传',
        botId: botId,
        detail: '实际响应：${prepareResponse.body}',
      );
      return UploadOutcome.failure(
        MediaTransferError(
          userMessage: '平台返回的上传信息不完整，请稍后重试。',
          officialMessage: prepareResponse.body.toString(),
        ),
      );
    }

    // ③ 逐片 PUT + upload_part_finish
    //
    // 字节范围按**列表顺序**推出来，而不是用 part.index 去乘分片大小。
    // 官方文档写 index 从 0 开始，实测却出现过 index = 1；两种情况下
    // 「第 n 片的数据在文件里的位置」都是位置 × 分片大小，
    // 而 index 只需原样回传即可。这样无论起点是 0 还是 1 都不会错位。
    final parts = prepared.parts!;
    final uploadConfig = prepared.uploadConfig ?? const UploadConfig();
    final fallbackBlockSize = prepared.effectiveBlockSize;
    var offset = 0;

    for (final part in parts) {
      final chunkSize = part.blockSize ?? fallbackBlockSize;
      if (chunkSize <= 0) {
        return UploadOutcome.failure(
          MediaTransferError(userMessage: '平台返回的分片大小为 0，无法上传。'),
        );
      }
      final end = (offset + chunkSize).clamp(0, bytes.length);
      if (end <= offset) break;
      final chunk = Uint8List.sublistView(bytes, offset, end);
      offset = end;

      final putError = await _putPartWithRetry(
        url: part.presignedUrl,
        chunk: chunk,
        config: uploadConfig,
      );
      if (putError != null) {
        return UploadOutcome.failure(MediaTransferError(
          userMessage: putError,
          cause: 'presigned PUT 到 COS 失败',
        ));
      }

      final finishResponse = await _http.postJson(
        partFinishUrl,
        UploadPartFinishRequest(
          uploadId: prepared.uploadId!,
          partIndex: part.index,
          blockSize: chunk.length,
          md5: MediaChecksum.md5Of(chunk),
        ).toJson(),
        authToken: token,
      );
      if (!finishResponse.isSuccess) {
        return UploadOutcome.failure(finishResponse.failure!);
      }
    }

    // ④ 合并
    final mergeResponse = await _http.postJson(
      mergeUrl,
      {
        'file_type': effectiveType.value,
        'srv_send_msg': false,
        'file_name': name,
        'upload_id': prepared.uploadId,
      },
      authToken: token,
    );
    if (!mergeResponse.isSuccess) {
      return UploadOutcome.failure(mergeResponse.failure!);
    }

    final info = MediaFileInfo.fromJson(
      mergeResponse.body,
      fileType: effectiveType,
    );
    if (!info.isUsable) {
      _log.error(
        LogSource.api,
        '文件合并成功但未返回 file_info',
        botId: botId,
        detail: '实际响应：${mergeResponse.body}',
      );
      return UploadOutcome.failure(
        MediaTransferError(userMessage: '上传完成但未取得文件标识，请重试。'),
      );
    }

    _log.info(
      LogSource.api,
      '文件上传完成（${effectiveType.label}，${(size / 1024).toStringAsFixed(0)}KB，'
      '${parts.length} 个分片'
      '${info.ttl == null ? '' : '，凭证有效期 ${info.ttl} 秒'}）',
      botId: botId,
    );
    return UploadOutcome.success(info);
  }

  /// 带重试地直传一个分片，成功返回 `null`，失败返回给用户看的说明。
  ///
  /// 重试节奏取自官方下发的 `upload_config.retry_delay`（默认 1 秒）。
  /// 官方还给了 `retry_timeout`（默认 300 秒），表示服务端容忍的重试总窗口；
  /// 本项目**不把它用作上限**——真按 5 分钟一直重试，用户会盯着一个转圈的
  /// 发送按钮不知道发生了什么。改为固定 3 次尝试，失败即返回并让用户重发，
  /// 这在移动网络的瞬时抖动场景下已经够用，代价是行为可预期。
  Future<String?> _putPartWithRetry({
    required String url,
    required Uint8List chunk,
    required UploadConfig config,
  }) async {
    const maxAttempts = 3;
    String? lastError;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      lastError = await _putPart(url, chunk);
      if (lastError == null) return null;
      if (attempt == maxAttempts) break;
      await Future<void>.delayed(config.retryDelayDuration);
    }
    return '分片上传失败（已尝试 $maxAttempts 次）：$lastError';
  }

  /// 向预签名地址直传一个分片，成功返回 `null`，失败返回错误说明。
  ///
  /// 这一条请求**不带 QQBot 鉴权头**：鉴权信息已经在预签名 URL 里，
  /// 多带一个 `Authorization` 反而会让 COS 拒绝。
  Future<String?> _putPart(String url, Uint8List chunk) async {
    try {
      final response = await _rawClient
          .put(Uri.parse(url), body: chunk)
          .timeout(const Duration(seconds: 60));
      if (response.statusCode >= 200 && response.statusCode < 300) return null;

      final reason = 'HTTP ${response.statusCode}'
          '${_cosErrorCode(response.body) ?? ''}';
      AppLogger.warn('分片直传被拒绝：$reason', tag: 'media');
      return reason;
    } catch (error, stack) {
      AppLogger.error('分片直传异常', error: error, stackTrace: stack, tag: 'media');
      return '网络异常（${error.runtimeType}）';
    }
  }

  /// 从 COS 的错误响应里抠出错误码。
  ///
  /// COS 返回的是 XML（`<Code>SignatureDoesNotMatch</Code>`），
  /// 直接把整个 XML 塞进用户可见的文案里毫无意义，只保留 Code 那一段。
  /// 预签名 URL 过期时这里会给出 `AccessDenied` / `SignatureDoesNotMatch`,
  /// 是排障时最关键的一条信息。
  static String? _cosErrorCode(String body) {
    final match = RegExp(r'<Code>([^<]{1,64})</Code>').firstMatch(body);
    if (match == null) return null;
    return '（${match.group(1)}）';
  }

  void dispose() => _rawClient.close();
}

/// 上传结果。
@immutable
class UploadOutcome {
  const UploadOutcome({this.info, this.error});

  factory UploadOutcome.success(MediaFileInfo info) => UploadOutcome(info: info);

  factory UploadOutcome.failure(AppError error) => UploadOutcome(error: error);

  final MediaFileInfo? info;
  final AppError? error;

  bool get isSuccess => info != null && error == null;
}
