import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/constants/qq_endpoints.dart';
import '../core/error/app_error.dart';
import '../core/logging/app_logger.dart';
import '../core/logging/log_service.dart';
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

    // ② upload_prepare
    final prepareResponse = await _http.postJson(
      prepareUrl,
      {
        'file_type': effectiveType.value,
        'file_name': fileName ?? file.uri.pathSegments.last,
        'file_size': size,
      },
      authToken: token,
    );
    if (!prepareResponse.isSuccess) {
      return UploadOutcome.failure(prepareResponse.failure!);
    }

    final prepared = UploadPrepareResponse.fromJson(prepareResponse.body);
    if (!prepared.isUsable) {
      // 官方未给出该响应的完整字段名（知识库第 9 章待实测第 8 项），
      // 因此把原始响应写进日志，方便真机核对字段名后调整解析。
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
    final bytes = await file.readAsBytes();
    final blockSize = prepared.effectiveBlockSize;
    final partUrls = prepared.partUrls!;

    for (var index = 0; index < partUrls.length; index++) {
      final start = index * blockSize;
      if (start >= bytes.length && index > 0) break;
      final end = (start + blockSize).clamp(0, bytes.length);
      final chunk = Uint8List.sublistView(bytes, start, end);

      final putResult = await _putPart(partUrls[index], chunk);
      if (!putResult.isSuccess) {
        return UploadOutcome.failure(
          putResult.error ?? MediaTransferError(userMessage: '分片上传失败。'),
        );
      }

      final finishResponse = await _http.postJson(
        partFinishUrl,
        UploadPartFinishRequest(
          uploadId: prepared.uploadId!,
          partNumber: index,
          etag: putResult.etag,
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
        'file_name': fileName ?? file.uri.pathSegments.last,
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
      '${partUrls.length} 个分片'
      '${info.ttl == null ? '' : '，凭证有效期 ${info.ttl} 秒'}）',
      botId: botId,
    );
    return UploadOutcome.success(info);
  }

  /// 向预签名地址直传一个分片。
  Future<PartPutResult> _putPart(String url, Uint8List chunk) async {
    try {
      final response = await _rawClient
          .put(Uri.parse(url), body: chunk)
          .timeout(const Duration(seconds: 60));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return PartPutResult.success(response.headers['etag']);
      }
      return PartPutResult.failure(
        MediaTransferError(
          userMessage: '分片上传失败（HTTP ${response.statusCode}），正在重试。',
        ),
      );
    } catch (error, stack) {
      AppLogger.error('分片直传异常', error: error, stackTrace: stack, tag: 'media');
      return PartPutResult.failure(
        MediaTransferError(userMessage: '分片上传网络异常，正在重试。', cause: error),
      );
    }
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

/// 分片直传结果。
@immutable
class PartPutResult {
  const PartPutResult({this.etag, this.error});

  factory PartPutResult.success(String? etag) => PartPutResult(etag: etag);

  factory PartPutResult.failure(AppError error) => PartPutResult(error: error);

  final String? etag;
  final AppError? error;

  bool get isSuccess => error == null;
}
