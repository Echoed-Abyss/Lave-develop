import 'dart:async';

import 'package:web_socket_channel/status.dart' as ws_status;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/logging/app_logger.dart';

/// WebSocket 连接的抽象。
///
/// **独立成接口的唯一理由是测试**：连接状态机里有大量分支
/// （Hello → Identify → READY、断线 → Resume、4006 改 Identify、4915 进终态），
/// 如果不把这层抽出来，这些分支就只能靠真机验证，成本极高。
/// 抽出后测试可以注入一个「按脚本吐帧、按脚本断开」的假实现。
abstract interface class GatewaySocket {
  /// 收到的文本帧流。
  Stream<String> get messages;

  /// 连接已建立。
  Future<void> connect(Uri uri);

  /// 发送一帧。
  void send(String payload);

  /// 关闭连接。
  Future<void> close([int? code, String? reason]);

  /// 服务端或底层给出的关闭码。
  ///
  /// 网关错误码（4001/4006/4008/4915 等）通过它拿到；
  /// 为 `null` 通常表示底层网络异常（如 1006 未正常关闭）。
  int? get closeCode;

  /// 关闭原因文本。
  String? get closeReason;

  /// 是否已关闭。
  bool get isClosed;
}

/// 基于 `web_socket_channel` 的真实实现。
///
/// 选 `web_socket_channel` 而不是其他 WebSocket 包的原因：
/// 它由 Dart 官方团队维护，且暴露了 `closeCode` / `closeReason` ——
/// 官方网关的错误码正是通过关闭码传递的，拿不到它就无法实现
/// 「按错误码分流 Resume / Identify / 停止重连」。
class WebSocketChannelGatewaySocket implements GatewaySocket {
  WebSocketChannelGatewaySocket();

  WebSocketChannel? _channel;
  final StreamController<String> _messages =
      StreamController<String>.broadcast();
  int? _closeCode;
  String? _closeReason;
  bool _closed = false;

  @override
  Stream<String> get messages => _messages.stream;

  @override
  Future<void> connect(Uri uri) async {
    final channel = WebSocketChannel.connect(uri);
    _channel = channel;
    // 3.x 起必须先 await ready，否则写入会抛「未连接」。
    await channel.ready;
    channel.stream.listen(
      (dynamic message) {
        if (message is String) {
          _messages.add(message);
        } else if (message is List<int>) {
          // 官方文档未提供任何压缩传输说明（知识库第 11 章），
          // 因此正常情况下不会收到二进制帧；收到时按 UTF-8 尽力解码并记日志。
          AppLogger.warn('收到二进制帧，按 UTF-8 尝试解码', tag: 'wss');
          _messages.add(String.fromCharCodes(message));
        }
      },
      onError: (Object error, StackTrace stack) {
        AppLogger.warn('WebSocket 错误：$error', tag: 'wss');
        _closeCode ??= ws_status.goingAway;
        _closed = true;
        _messages.addError(error, stack);
      },
      onDone: () {
        _closeCode = channel.closeCode ?? _closeCode;
        _closeReason = channel.closeReason ?? _closeReason;
        _closed = true;
        unawaited(_messages.close());
      },
      cancelOnError: false,
    );
  }

  @override
  void send(String payload) {
    if (_closed) return;
    _channel?.sink.add(payload);
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    if (_closed) return;
    _closed = true;
    _closeCode = code ?? ws_status.normalClosure;
    _closeReason = reason;
    try {
      await _channel?.sink.close(code ?? ws_status.normalClosure, reason);
    } catch (_) {
      // 关闭失败无需上报：连接本来就已经不可用。
    }
    if (!_messages.isClosed) await _messages.close();
  }

  @override
  int? get closeCode => _closeCode;

  @override
  String? get closeReason => _closeReason;

  @override
  bool get isClosed => _closed;
}

/// 连接工厂。测试通过替换它注入假实现。
typedef GatewaySocketFactory = GatewaySocket Function();

/// 默认工厂。
GatewaySocket defaultGatewaySocketFactory() =>
    WebSocketChannelGatewaySocket();
