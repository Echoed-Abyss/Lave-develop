import 'package:flutter/foundation.dart';

import '../../core/constants/qq_limits.dart';
import '../../core/utils/qq_json.dart';
import '../../domain/models/qq_enums.dart';

/// 富媒体上传相关实体。
///
/// 字段对照官方文档（知识库 8.3 / 8.4 / 8.5 / 8.6 节）。官方上传是**三段式四步**：
/// 1. `upload_prepare` 拿 `upload_id`、`block_size` 与各分片预签名 URL；
/// 2. 按 `block_size` 分片，逐片 HTTP PUT 到预签名 URL；
/// 3. 每片成功后调用 `upload_part_finish`；
/// 4. 全部分片完成后携带 `upload_id` 调用 `files` 完成合并，拿到 `file_info`。
///
/// 移动端选择分片而非 URL 直传的原因：官方 URL 直传要求提供
/// **平台可下载的公网 URL**，而 `image_picker` 给的是设备本地文件。
///
/// ## 曾经踩过的坑（真机实测才暴露）
///
/// 早期版本把 `parts` 当成「字符串数组」，而它实际是**对象数组**
/// （`{index, presigned_url, block_size}`）。解析后得到空列表，
/// 于是每次上传都停在「响应缺少必要字段」——而响应本身完全正常。
/// 同一个错误还掩盖了三处请求侧不合规：`upload_prepare` 的必填校验值
/// （`md5` / `sha1` / `md5_10m`）从未发送，`upload_part_finish` 的字段名
/// 写成 `part_number`（官方为 `part_index`），以及分片大小被假定为固定 5MB。
@immutable
class UploadPrepareResponse {
  const UploadPrepareResponse({
    this.uploadId,
    this.blockSize,
    this.parts,
    this.uploadConfig,
    this.raw = const {},
  });

  /// 分片上传任务 ID，后续 `files` 合并与 `upload_part_finish` 都要用。
  final String? uploadId;

  /// 顶层分片大小（字节），官方默认 5MB。
  ///
  /// 实测这个值**并不等于** 5MB：小文件时服务端会把整份文件当成一个分片，
  /// 于是 `block_size` 约等于文件大小（例如 605516 / 1728171）。
  /// 所以它只能当作「列表里没给 block_size 时的兜底」，不能当作分片依据。
  final int? blockSize;

  /// 分片列表。按官方描述应从 `index = 0` 开始，但实测出现过 `index = 1`，
  /// 因此上传时按**列表顺序**定位字节偏移，并把服务端给的 `index`
  /// 原样回传给 `upload_part_finish`。
  final List<UploadPart>? parts;

  /// 上传配置（并发、重试超时与延迟）。
  final UploadConfig? uploadConfig;

  /// 原始响应，便于字段名与预期不符时排查。
  final Map<String, dynamic> raw;

  factory UploadPrepareResponse.fromJson(Map<String, dynamic> json) {
    final topBlockSize = _intOf(json['block_size']) ??
        _intOf(json['blockSize']) ??
        _intOf(json['part_size']);

    return UploadPrepareResponse(
      uploadId: QqJson.str(json['upload_id']) ?? QqJson.str(json['uploadId']),
      blockSize: topBlockSize,
      parts: _parseParts(json['parts'], topBlockSize),
      uploadConfig: json['upload_config'] == null
          ? null
          : UploadConfig.fromJson(QqJson.map(json['upload_config'])!),
      raw: json,
    );
  }

  /// 实际生效的顶层分片大小。官方未给出时按默认 5MB。
  int get effectiveBlockSize =>
      blockSize ?? QqLimits.uploadDefaultBlockSizeBytes;

  /// 是否可用于分片上传（必须具备 upload_id 与至少一个可用分片）。
  bool get isUsable =>
      uploadId != null &&
      uploadId!.isNotEmpty &&
      (parts?.isNotEmpty ?? false);

  /// 各分片地址，仅用于日志与兼容旧调用点。
  List<String> get partUrls =>
      parts?.map((e) => e.presignedUrl).toList(growable: false) ?? const [];

  /// 解析 `parts`。
  ///
  /// 官方为对象数组；同时兼容「纯字符串数组」与「单个字符串」这两种
  /// 简化形态——服务端字段形态未在任何文档里承诺过，多兼容一层，
  /// 代价只是几行代码，收益是换一个版本也不会整条链路直接断掉。
  /// 没有 `presigned_url` 的项会被丢弃：缺地址的分片无法上传，
  /// 留着只会在 PUT 时抛出一个更难懂的错误。
  static List<UploadPart>? _parseParts(Object? raw, int? topBlockSize) {
    if (raw is String) {
      return raw.isEmpty
          ? null
          : [UploadPart(index: 0, presignedUrl: raw, blockSize: topBlockSize)];
    }
    if (raw is! List) return null;

    final result = <UploadPart>[];
    for (var position = 0; position < raw.length; position++) {
      final item = raw[position];
      if (item is String) {
        if (item.isEmpty) continue;
        result.add(UploadPart(
          index: position,
          presignedUrl: item,
          blockSize: topBlockSize,
        ));
        continue;
      }
      final map = QqJson.map(item);
      if (map == null) continue;
      final url = QqJson.str(map['presigned_url']) ??
          QqJson.str(map['presignedUrl']) ??
          QqJson.str(map['url']);
      if (url == null || url.isEmpty) continue;
      result.add(UploadPart(
        // 官方未回传 index 时用列表下标兜底，至少保证顺序信息不丢。
        index: _intOf(map['index']) ?? position,
        presignedUrl: url,
        blockSize: _intOf(map['block_size']) ?? _intOf(map['blockSize']),
      ));
    }
    return result.isEmpty ? null : List.unmodifiable(result);
  }

  /// 解析可能是数字、也可能是字符串的整数字段。
  ///
  /// 官方文档把 `block_size` / `file_size` 标为 **string**，实测响应里却是
  /// number。两种都见过，因此两个方向都要认。
  static int? _intOf(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    final text = QqJson.str(raw);
    if (text == null || text.isEmpty) return null;
    return int.tryParse(text);
  }

  /// 按文件总字节数计算需要多少个分片（仅在服务端未给出 parts 时使用）。
  int partCountFor(int totalBytes) {
    final size = effectiveBlockSize;
    if (size <= 0) return 0;
    return (totalBytes + size - 1) ~/ size;
  }
}

/// 一个分片的上传信息（官方 `UploadPart`）。
@immutable
class UploadPart {
  const UploadPart({
    required this.index,
    required this.presignedUrl,
    this.blockSize,
  });

  /// 服务端给的分片序号，`upload_part_finish` 要原样回传。
  final int index;

  /// 预签名上传地址，客户端 PUT 分片数据到这里。
  final String presignedUrl;

  /// 该分片的实际大小（字节）。缺失时按顶层 `block_size` 处理。
  final int? blockSize;
}

/// `upload_prepare` 请求实体。
///
/// 官方把 `md5` / `sha1` / `md5_10m` 都标为必填，实测不传也能拿到响应，
/// 但既然服务端拿它们做完整性校验与秒传判断，就该老实算出来传上去：
/// 缺校验值时服务端只能盲收，出问题也没有依据可查。
@immutable
class UploadPrepareRequest {
  const UploadPrepareRequest({
    required this.fileType,
    required this.fileSize,
    required this.fileName,
    required this.md5,
    required this.sha1,
    required this.md5Prefix,
  });

  /// 业务类型：1=图片, 2=视频, 3=语音, 4=文件。
  final QqMediaFileType fileType;

  /// 文件大小（字节）。官方标为 string，这里按 string 发。
  final int fileSize;

  /// 文件名。
  final String fileName;

  /// 整个文件的 MD5（十六进制小写）。
  final String md5;

  /// 整个文件的 SHA1（十六进制小写）。
  final String sha1;

  /// 文件前 [QqLimits.md5PrefixBytes] 字节的 MD5。
  final String md5Prefix;

  Map<String, dynamic> toJson() => {
        'file_type': fileType.value,
        'file_size': '$fileSize',
        'file_name': fileName,
        'md5': md5,
        'sha1': sha1,
        'md5_10m': md5Prefix,
      };
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

/// `upload_part_finish` 请求实体（官方 8.4 / 8.6 节）。
///
/// 官方四个字段都标「否」，但既然是「通知服务端该分片已上传完成」，
/// 就必须把能标识这片的信息都给全：缺 `part_index` 时服务端只能靠猜。
/// 早期版本把字段名写成 `part_number`（官方为 `part_index`），
/// 服务端收不到分片序号，这类错误不会报错，只会让上传悄无声息地不生效。
@immutable
class UploadPartFinishRequest {
  const UploadPartFinishRequest({
    required this.uploadId,
    required this.partIndex,
    required this.blockSize,
    required this.md5,
  });

  /// 分片上传任务 ID。
  final String uploadId;

  /// 分片序号，对应 `UploadPart.index`。
  ///
  /// **原样回传服务端给的值**，不要自己按 0 起重排：官方文档说从 0 开始，
  /// 而实测响应里出现过 `index = 1`。猜错序号等于告诉服务端「第 0 片好了」
  /// 而实际上传的是别的片。
  final int partIndex;

  /// 该分片的实际大小（字节）。官方标为 string。
  final int blockSize;

  /// 该分片的 MD5（十六进制小写）。
  final String md5;

  Map<String, dynamic> toJson() => {
        'upload_id': uploadId,
        'part_index': partIndex,
        'block_size': '$blockSize',
        'md5': md5,
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
