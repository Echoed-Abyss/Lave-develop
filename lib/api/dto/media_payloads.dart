import 'package:flutter/foundation.dart';

import '../../core/constants/qq_limits.dart';
import '../../core/utils/qq_json.dart';
import '../../domain/models/qq_enums.dart';

/// 富媒体上传相关实体。
///
/// 字段对照官方文档（知识库 7.4 节）。官方上传是**三段式四步**：
/// 1. `upload_prepare` 拿 `upload_id`、`block_size` 与各分片预签名 URL；
/// 2. 按 `block_size` 分片，逐片 HTTP PUT 到预签名 URL；
/// 3. 每片成功后调用 `upload_part_finish`；
/// 4. 全部分片完成后携带 `upload_id` 调用 `files` 完成合并，拿到 `file_info`。
///
/// 移动端选择分片而非 URL 直传的原因：官方 URL 直传要求提供
/// **平台可下载的公网 URL**，而 `image_picker` 给的是设备本地文件。
///
/// 注意（知识库第 9 章待实测清单第 8 项）：官方文档未给出
/// `upload_prepare` 响应的完整字段名，本文件的字段命名以「官方文字描述 +
/// 常见约定」为准，**首次真机上传时必须按实际响应核对**，
/// 因此所有字段都做了多重键名兼容。
@immutable
class UploadPrepareResponse {
  const UploadPrepareResponse({
    this.uploadId,
    this.blockSize,
    this.partUrls,
    this.uploadConfig,
    this.raw = const {},
  });

  /// 分片上传任务 ID，后续 `files` 合并与 `upload_part_finish` 都要用。
  final String? uploadId;

  /// 分片大小（字节）。官方默认 5MB，示例中出现过 10485760（10MB）。
  final int? blockSize;

  /// 各分片的预签名上传地址（按顺序 PUT）。
  final List<String>? partUrls;

  /// 上传配置（并发、重试超时与延迟）。
  final UploadConfig? uploadConfig;

  /// 原始响应，便于字段名不确定时排查与兜底。
  final Map<String, dynamic> raw;

  factory UploadPrepareResponse.fromJson(Map<String, dynamic> json) {
    // 字段名多重兼容：官方文字描述为「upload_id / block_size / 各分片预签名 URL」，
    // 但未给出确切的数组字段名，因此对常见候选逐一尝试。
    final rawBlockSize = QqJson.integer(json['block_size']) ??
        QqJson.integer(json['blockSize']) ??
        QqJson.integer(json['part_size']);
    final rawParts = json['part_urls'] ??
        json['partUrls'] ??
        json['urls'] ??
        json['presigned_urls'] ??
        json['parts'];

    return UploadPrepareResponse(
      uploadId: QqJson.str(json['upload_id']) ?? QqJson.str(json['uploadId']),
      blockSize: rawBlockSize,
      partUrls: _stringList(rawParts),
      uploadConfig: json['upload_config'] == null
          ? null
          : UploadConfig.fromJson(QqJson.map(json['upload_config'])!),
      raw: json,
    );
  }

  /// 实际生效的分片大小。官方未给出时按默认 5MB。
  int get effectiveBlockSize =>
      blockSize ?? QqLimits.uploadDefaultBlockSizeBytes;

  /// 是否可用于分片上传（必须具备 upload_id 与至少一个分片地址）。
  bool get isUsable =>
      uploadId != null &&
      uploadId!.isNotEmpty &&
      (partUrls?.isNotEmpty ?? false);

  /// 按文件总字节数计算需要多少个分片。
  int partCountFor(int totalBytes) {
    final size = effectiveBlockSize;
    if (size <= 0) return 0;
    return (totalBytes + size - 1) ~/ size;
  }

  static List<String>? _stringList(Object? raw) {
    if (raw is! List) return null;
    return raw
        .map((e) => QqJson.str(e))
        .whereType<String>()
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }
}

/// 官方 `upload_config`。
///
/// 官方默认值：`concurrency = 1`、`retry_timeout = 300` 秒、`retry_delay = 1` 秒。
@immutable
class UploadConfig {
  const UploadConfig({
    this.concurrency = 1,
    this.retryTimeout = 300,
    this.retryDelay = 1,
  });

  /// 并发数，官方默认 1。
  final int concurrency;

  /// 重试超时（秒），官方默认 300。
  final int retryTimeout;

  /// 重试延迟（秒），官方默认 1。
  final int retryDelay;

  factory UploadConfig.fromJson(Map<String, dynamic> json) => UploadConfig(
        concurrency: QqJson.integer(json['concurrency']) ?? 1,
        retryTimeout: QqJson.integer(json['retry_timeout']) ?? 300,
        retryDelay: QqJson.integer(json['retry_delay']) ?? 1,
      );

  Duration get retryTimeoutDuration => Duration(seconds: retryTimeout);

  Duration get retryDelayDuration => Duration(seconds: retryDelay);
}

/// `upload_part_finish` 请求实体。
///
/// 官方未给出该接口的完整请求体字段名，这里按官方文字描述
/// 「每片 PUT 成功后调用 upload_part_finish 通知服务端该分片完成」建模，
/// 并为可能的字段名差异保留了 [extra] 透传位。
@immutable
class UploadPartFinishRequest {
  const UploadPartFinishRequest({
    required this.uploadId,
    required this.partNumber,
    this.etag,
    this.extra = const {},
  });

  /// 分片上传任务 ID。
  final String uploadId;

  /// 分片序号。官方未明确从 0 还是 1 开始，
  /// 本项目按「与预上传返回的分片地址列表下标一致」使用 0 起。
  final int partNumber;

  /// PUT 响应中返回的 ETag（若存储侧返回）。
  final String? etag;

  /// 额外字段透传位，用于应对官方字段名与本地建模不一致的情况。
  final Map<String, dynamic> extra;

  Map<String, dynamic> toJson() => {
        'upload_id': uploadId,
        'part_number': partNumber,
        if (etag != null) 'etag': etag,
        ...extra,
      };
}

/// `files` 接口响应实体 —— 富媒体上传的最终产物。
@immutable
class MediaFileInfo {
  const MediaFileInfo({
    this.fileUuid,
    this.fileInfo,
    this.ttl,
    this.id,
    this.rawUrl,
    this.fileType,
  });

  /// 文件唯一 ID。
  final String? fileUuid;

  /// 用于发消息接口的 `media.file_info` 字段。
  ///
  /// 官方明确：内部为序列化的二进制数据，**开发者无需解析，直接透传即可**。
  /// 因此这里保持字符串形态，任何「解析一下看看里面是什么」的尝试都是错的。
  final String? fileInfo;

  /// `file_info` 有效期（秒）。**0 表示可长期使用**，到期后需重新上传。
  final int? ttl;

  /// 发送消息的唯一 ID。**仅 `srv_send_msg = true` 时返回**。
  final String? id;

  /// 文件下载链接（COS 预签名 GET URL），有效期与 `ttl` 一致。
  ///
  /// 官方：仅分片上传合并（`upload_id` 路径）且 `file_type` 为
  /// 图片/视频/语音时返回；URL 直传和文件类型（`file_type = 4`）不返回此字段。
  final String? rawUrl;

  /// 本地记录的上传文件类型（官方响应未回传，由请求侧带入以便缓存管理）。
  final QqMediaFileType? fileType;

  factory MediaFileInfo.fromJson(
    Map<String, dynamic> json, {
    QqMediaFileType? fileType,
  }) =>
      MediaFileInfo(
        fileUuid: QqJson.str(json['file_uuid']),
        fileInfo: QqJson.str(json['file_info']),
        ttl: QqJson.integer(json['ttl']),
        id: QqJson.str(json['id']),
        rawUrl: QqJson.str(json['raw_url']),
        fileType: fileType,
      );

  /// 是否可用于发送（必须有 `file_info`）。
  bool get isUsable => fileInfo != null && fileInfo!.isNotEmpty;

  /// `file_info` 的过期时刻。`ttl` 为 0 或缺失时返回 `null` 表示长期有效。
  DateTime? expiryAt(DateTime now) {
    final seconds = ttl;
    if (seconds == null || seconds == 0) return null;
    return now.add(Duration(seconds: seconds));
  }

  /// 在给定时刻是否已过期。
  ///
  /// 用途：本地缓存 `file_info` 复用时必须先判断有效期，
  /// 否则会用过期数据发送消息并以 304080（文件信息无效）失败。
  bool isExpiredAt(DateTime now) {
    final expiry = expiryAt(now);
    if (expiry == null) return false;
    return !now.isBefore(expiry);
  }
}
