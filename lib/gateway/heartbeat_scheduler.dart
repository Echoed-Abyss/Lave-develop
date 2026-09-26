import 'dart:async';

import 'package:flutter/foundation.dart';

/// 心跳调度器。
///
/// 官方机制（知识库 3.6 节）：
/// - 心跳周期由连接成功后下发的 **Op10 Hello** 给出，**单位毫秒**；
/// - 「鉴权成功之后，就需要按照周期进行心跳发送」；
/// - 心跳报文是 `op = 1`，`d` 为**客户端收到的最新的消息的 `s`**，
///   首次连接传 `null`；
/// - 发送成功后会收到 **OpCode 11 Heartbeat ACK**。
///
/// **官方未提供心跳丢失的判定阈值**（知识库第 11 章明确列为缺失项），
/// 因此这里用「连续 [timeoutMultiplier] 次未收到 ACK 即判定死链」的保守策略，
/// 倍数可在 `AppConfig` 里调整。
class HeartbeatScheduler {
  HeartbeatScheduler({
    required this.interval,
    required this.timeoutMultiplier,
    required this.onSend,
    required this.onDead,
  });

  /// 心跳周期（来自 Hello）。
  final Duration interval;

  /// 允许的连续丢失次数。
  final int timeoutMultiplier;

  /// 发送心跳。参数为要携带的 `s`（首次连接为 `null`）。
  final void Function(int? seq) onSend;

  /// 判定为死链时回调（调用方应主动断开并重连）。
  final void Function() onDead;

  Timer? _timer;
  int? _lastSeq;
  bool _awaitingAck = false;
  int _missedAcks = 0;

  /// 是否已启动。
  bool get isRunning => _timer != null;

  /// 连续丢失的心跳次数（供界面展示连接质量）。
  int get missedAcks => _missedAcks;

  /// 当前携带的序列号。
  int? get lastSeq => _lastSeq;

  /// 启动心跳。
  void start() {
    stop();
    _missedAcks = 0;
    _awaitingAck = false;
    _timer = Timer.periodic(interval, (_) => _tick());
  }

  /// 更新要携带的 `s`。
  ///
  /// 官方要求携带「客户端收到的最新的 `s`」，因此连接层每收到一帧就更新它。
  void updateSeq(int? seq) {
    if (seq != null) _lastSeq = seq;
  }

  /// 收到 Op11 Heartbeat ACK。
  void ack() {
    _awaitingAck = false;
    _missedAcks = 0;
  }

  /// 停止心跳。
  void stop() {
    _timer?.cancel();
    _timer = null;
    _awaitingAck = false;
  }

  void _tick() {
    if (_awaitingAck) {
      _missedAcks++;
      if (_missedAcks >= timeoutMultiplier) {
        // 判定死链：不在这里主动关闭 socket，交给连接层统一处理，
        // 这样重连与状态迁移只有一条代码路径。
        stop();
        onDead();
        return;
      }
    }
    _awaitingAck = true;
    onSend(_lastSeq);
  }
}

/// 便于测试断言：把 05:03 这样的时间格式化。
@visibleForTesting
String formatClock(DateTime time) {
  final local = time.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}
