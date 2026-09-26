import '../core/error/app_error.dart';
import '../domain/models/qq_enums.dart';
import 'dto/send_message_request.dart';
import 'message_api.dart';
import 'media_api.dart';
import 'qq_http_client.dart';

/// 机器人侧的消息发送能力。
///
/// 抽成接口的目的：指令引擎与插件系统都只需要「把一段文本发出去」，
/// 不应该知道 HTTP、`msg_seq`、被动回复窗口这些细节。
/// 测试时注入一个记录调用参数的假实现即可验证指令行为。
abstract interface class MessageSender {
  /// 发送文本。
  ///
  /// [passive] 为 `true` 时走被动回复（携带 `msg_id` / `event_id`），
  /// 这是唯一不受主动消息频控约束的方式；官方给的窗口是
  /// 单聊 60 分钟 / 群聊 5 分钟。
  Future<ApiResponse> sendText({
    required String conversationId,
    required ConversationScope scope,
    required String text,
    bool passive = true,
    String? msgId,
    String? eventId,
    int? msgSeq,
  });

  /// 发送本地图片（内部完成分片上传后再发富媒体消息）。
  Future<ApiResponse> sendImage({
    required String conversationId,
    required ConversationScope scope,
    required String filePath,
    bool passive = true,
    String? msgId,
    String? eventId,
    int? msgSeq,
  });
}

/// [MessageSender] 的正式实现。
///
/// 被动回复的关键细节：
/// - `msg_id` 取自消息事件的 `d.id`，`event_id` 取自**最外层** payload 的 `id`；
/// - 对同一条消息多次回复必须**递增 `msg_seq`**，
///   否则会被官方以 40054005（消息被去重）拒绝；
/// - 被动回复一旦超时（群 5 分钟 / 单聊 60 分钟）就只能改发主动消息，
///   而主动消息受独立频控约束。
class BotMessageService implements MessageSender {
  BotMessageService({
    required this.botId,
    required MessageApi messageApi,
    required MediaApi mediaApi,
  })  : _messageApi = messageApi,
        _mediaApi = mediaApi;

  final String botId;
  final MessageApi _messageApi;
  final MediaApi _mediaApi;

  /// 每条原始消息已用掉的 `msg_seq`，用于自动递增。
  ///
  /// 用 `msg_id` 作键的原因：官方去重规则是「相同的 msg_id + msg_seq
  /// 重复发送会失败」，因此递增必须按 msg_id 独立计数。
  final Map<String, int> _seqUsage = {};

  @override
  Future<ApiResponse> sendText({
    required String conversationId,
    required ConversationScope scope,
    required String text,
    bool passive = true,
    String? msgId,
    String? eventId,
    int? msgSeq,
  }) {
    final request = SendMessageRequest.text(
      text,
      msgId: passive ? msgId : null,
      eventId: passive ? eventId : null,
      msgSeq: passive ? (msgSeq ?? _nextSeq(msgId)) : null,
    );
    return _dispatch(scope: scope, conversationId: conversationId, request: request);
  }

  @override
  Future<ApiResponse> sendImage({
    required String conversationId,
    required ConversationScope scope,
    required String filePath,
    bool passive = true,
    String? msgId,
    String? eventId,
    int? msgSeq,
  }) async {
    // 官方要求：单聊与群聊的文件上传接口相互独立，同一文件不能跨场景复用。
    final upload = scope == ConversationScope.group
        ? await _mediaApi.uploadForGroup(
            botId: botId,
            groupOpenid: conversationId,
            filePath: filePath,
            fileType: _mediaTypeForPath(filePath),
          )
        : await _mediaApi.uploadForC2c(
            botId: botId,
            userOpenid: conversationId,
            filePath: filePath,
            fileType: _mediaTypeForPath(filePath),
          );

    if (!upload.isSuccess) {
      return ApiResponse.failure(
        upload.error ?? MediaTransferError(userMessage: '图片上传失败。'),
      );
    }

    final request = SendMessageRequest.media(
      upload.info!.fileInfo!,
      msgId: passive ? msgId : null,
      eventId: passive ? eventId : null,
      msgSeq: passive ? (msgSeq ?? _nextSeq(msgId)) : null,
    );
    return _dispatch(scope: scope, conversationId: conversationId, request: request);
  }

  Future<ApiResponse> _dispatch({
    required ConversationScope scope,
    required String conversationId,
    required SendMessageRequest request,
  }) {
    if (scope == ConversationScope.group) {
      return _messageApi.sendGroup(
        botId: botId,
        groupOpenid: conversationId,
        request: request,
      );
    }
    return _messageApi.sendC2c(
      botId: botId,
      userOpenid: conversationId,
      request: request,
    );
  }

  /// 取下一条 `msg_seq`。
  ///
  /// 官方：不填默认是 1。首次回复用 1，第二次用 2，以此类推。
  int _nextSeq(String? msgId) {
    if (msgId == null || msgId.isEmpty) return 1;
    final used = (_seqUsage[msgId] ?? 0) + 1;
    _seqUsage[msgId] = used;
    // 控制内存：只保留最近的记录。
    if (_seqUsage.length > 200) {
      _seqUsage.remove(_seqUsage.keys.first);
    }
    return used;
  }

  /// 依据扩展名推断官方 `file_type`。
  ///
  /// 官方只支持图片 png / jpg、视频 mp4、语音 silk；其余一律按「文件」处理。
  static QqFileTypeGuess guessFileType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png') || lower.endsWith('.jpg')) {
      return QqFileTypeGuess.image;
    }
    if (lower.endsWith('.mp4')) return QqFileTypeGuess.video;
    if (lower.endsWith('.silk')) return QqFileTypeGuess.audio;
    return QqFileTypeGuess.file;
  }

  static QqMediaFileType _mediaTypeForPath(String path) {
    switch (guessFileType(path)) {
      case QqFileTypeGuess.image:
        return QqMediaFileType.image;
      case QqFileTypeGuess.video:
        return QqMediaFileType.video;
      case QqFileTypeGuess.audio:
        return QqMediaFileType.audio;
      case QqFileTypeGuess.file:
        return QqMediaFileType.file;
    }
  }
}

/// 扩展名推断结果。
enum QqFileTypeGuess { image, video, audio, file }

/// 便捷判定：错误是否值得自动重试。
extension ApiResponseRetry on ApiResponse {
  bool get isRetryable => failure?.retryable ?? false;
}
