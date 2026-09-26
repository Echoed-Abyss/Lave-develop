import 'package:flutter/foundation.dart';

import '../../../core/utils/qq_json.dart';

/// 官方 `MessageAttachment` —— C2C / 群聊事件体系的附件对象。
///
/// 字段逐字对照官方文档（知识库 5.1 节），共 8 个。
///
/// **重要：这不是频道体系的附件**。官方频道体系的 `MessageAttachment` 只列出
/// `url` 一个字段（见知识库 6.3 节），两套结构不同名同形。
/// 本项目以单聊/群聊为主，频道事件走独立的降级解析路径，
/// 不要把这个类复用到频道事件上。
@immutable
class MessageAttachment {
  const MessageAttachment({
    this.url,
    this.filename,
    this.width,
    this.height,
    this.size,
    this.contentType,
    this.voiceWavUrl,
    this.asrReferText,
  });

  /// 附件下载 URL。
  final String? url;

  /// 文件名。
  final String? filename;

  /// 图片宽度（像素）。官方标注：**非图片附件无此字段**。
  final int? width;

  /// 图片高度（像素）。官方标注：**非图片附件无此字段**。
  final int? height;

  /// 文件大小（字节）。
  final int? size;

  /// 附件内容类型（MIME）。
  ///
  /// 官方取值：`voice`（语音）、`image/jpeg`、`image/png`、`image/gif`、
  /// `video/mp4`、`file`（群文件）。
  ///
  /// 注意：`voice` 与 `file` **不是标准 MIME 类型**，
  /// 因此判断类型时不能用 MIME 解析库，只能按字符串精确匹配。
  final String? contentType;

  /// 语音消息 SILK 等转换后的 WAV 文件 URL。
  final String? voiceWavUrl;

  /// 语音消息 ASR 参考结果（语音转文字的参考文本）。
  final String? asrReferText;

  factory MessageAttachment.fromJson(Map<String, dynamic> json) =>
      MessageAttachment(
        url: QqJson.str(json['url']),
        filename: QqJson.str(json['filename']),
        width: QqJson.integer(json['width']),
        height: QqJson.integer(json['height']),
        size: QqJson.integer(json['size']),
        contentType: QqJson.str(json['content_type']),
        voiceWavUrl: QqJson.str(json['voice_wav_url']),
        asrReferText: QqJson.str(json['asr_refer_text']),
      );

  /// 是否为图片（三种官方图片 MIME）。
  bool get isImage =>
      contentType == 'image/jpeg' ||
      contentType == 'image/png' ||
      contentType == 'image/gif';

  /// 是否为语音。
  bool get isVoice => contentType == 'voice';

  /// 是否为视频。
  bool get isVideo => contentType == 'video/mp4';

  /// 是否为文件。
  bool get isFile => contentType == 'file';

  /// 是否为官方已知的附件类型。
  ///
  /// 用于 UI 降级：未知类型的附件只展示文件名，不做内容预览。
  bool get isKnownType =>
      isImage || isVoice || isVideo || isFile;

  /// 语音附件的可展示文本：优先 ASR 结果。
  ///
  /// 官方提供 `asr_refer_text` 且明确标注为「参考结果」，
  /// 因此界面上应标注为机器识别文本而非用户原话。
  String? get voiceDisplayText =>
      (asrReferText != null && asrReferText!.isNotEmpty) ? asrReferText : null;
}
