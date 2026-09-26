import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../api/token_api.dart';
import '../core/constants/app_config.dart';
import '../core/constants/qq_limits.dart';
import '../core/error/app_error.dart';
import '../core/error/error_mapper.dart';
import '../core/logging/app_logger.dart';
import '../core/logging/log_service.dart';
import '../data/repository/bot_repository.dart';
import '../domain/models/connection_status.dart';
import '../domain/models/log_entry.dart';
import 'gateway_api.dart';
import 'gateway_socket.dart';
import 'heartbeat_scheduler.dart';
import 'protocol/events/qq_event.dart';
import 'protocol/gateway_frame.dart';
import 'protocol/qq_opcode.dart';

/// 连接尝试结束时的去向。
enum _CloseOutcome {
  /// 已停止，不再重连。
  stopped,

  /// 可重试 Resume（官方 4008 / 4009，或普通网络断开）。
  resume,

  /// 必须重新 Identify（官方 4006 / 4007 / 4900~4913）。
  identify,

  /// 终态，停止重连（封禁 4915 / 下架 4914 / 参数与权限错误）。
  blocked,
}

/// 单个机器人的 WSS 长连接。
///
/// 完整承担官方要求的连接生命周期（知识库 3.2 节六步）：
/// 取接入点 → 建连 → 收 Hello → Identify → 心跳 → 断线 Resume。
///
/// 三条关键设计：
/// 1. **只暴露两条对外通道**：状态流 `status` 与事件流 `events`。
///    上层（事件分发、UI）不需要知道 WebSocket 的存在；
/// 2. **错误码决定去向**：关闭码一律经 `QqWsCloseInfo.resolve` 折算为
///    「重试 Resume / 改 Identify / 停止」，与官方错误码表的两列严格对应；
/// 3. **seq 的推进由外部确认**：本类只在收到事件时更新内存中的水位供心跳使用，
///    **持久化水位必须由事件分发层在落库成功后调用 [acknowledgeSeq] 推进** ——
///    如果在「收到」时就推进，进程在处理中途被杀会导致这段事件既没落库
///    也不会被 Resume 补发，属于静默丢消息。
class GatewayConnection {
  GatewayConnection({
    required this.botId,
    required GatewayApi gatewayApi,
    required AccessTokenManager tokens,
    required BotRepository bots,
    required LogService log,
    required AppConfig config,
    GatewaySocketFactory? socketFactory,
  })  : _gatewayApi = gatewayApi,
        _tokens = tokens,
        _bots = bots,
        _log = log,
        _config = config,
        _socketFactory = socketFactory ?? defaultGatewaySocketFactory,
        status = ValueNotifier(
          ConnectionSnapshot.idle(botId, DateTime.now()),
        );

  /// 机器人 AppID。
  final String botId;

  final GatewayApi _gatewayApi;
  final AccessTokenManager _tokens;
  final BotRepository _bots;
  final LogService _log;
  final AppConfig _config;
  final GatewaySocketFactory _socketFactory;

  /// 连接状态（不可变快照，UI 直接监听）。
  final ValueNotifier<ConnectionSnapshot> status;

  final StreamController<QqEvent> _events =
      StreamController<QqEvent>.broadcast();

  /// 业务事件流（已排除 READY / RESUMED 这类连接期事件）。
  Stream<QqEvent> get events => _events.stream;

  GatewaySocket? _socket;
  StreamSubscription<String>? _frameSubscription;
  HeartbeatScheduler? _heartbeat;
  Timer? _handshakeTimer;
  Completer<_CloseOutcome>? _closeCompleter;

  Duration _heartbeatInterval = const Duration(milliseconds: 45000);
  bool _stopped = true;
  bool _helloReceived = false;
  int _attempt = 0;
  DateTime? _seqPersistedAt;

  /// 启动连接（幂等：已在运行时不重复启动）。
  Future<void> start() async {
    if (!_stopped) {
      _log.info(LogSource.gateway, '连接已处于运行状态，忽略重复启动', botId: botId);
      return;
    }
    _stopped = false;
    _attempt = 0;
    _log.info(LogSource.gateway, '开始建立 WSS 长连接', botId: botId);
    unawaited(_runLoop());
  }

  /// 停止连接并释放资源。
  Future<void> stop() async {
    _stopped = true;
    _handshakeTimer?.cancel();
    _heartbeat?.stop();
    await _frameSubscription?.cancel();
    _frameSubscription = null;
    final socket = _socket;
    _socket = null;
    if (socket != null && !socket.isClosed) {
      await socket.close(1000, 'client stop');
    }
    _closeCompleter?.complete(_CloseOutcome.stopped);
    _setPhase(ConnectionPhase.idle, clearError: true);
    _log.info(LogSource.gateway, '已断开 WSS 连接', botId: botId);
  }

  /// 手动重连（界面上的「重连」按钮，或终态后用户修正配置再试）。
  Future<void> reconnectNow({bool clearSession = false}) async {
    if (clearSession) {
      await _bots.clearSession(botId);
    }
    await stop();
    await start();
  }

  /// 事件处理完成后推进持久化水位。
  ///
  /// **必须由事件分发层在落库成功后调用**，见类文档第 3 条。
  /// 为避免高频写盘，内部做了节流（默认最多每 5 秒落一次，
  /// 但内存水位每次都更新，保证心跳携带的 `s` 是最新的）。
  Future<void> acknowledgeSeq(int? seq) async {
    if (seq == null) return;
    _heartbeat?.updateSeq(seq);
    status.value = status.value.withSeq(seq);

    final last = _seqPersistedAt;
    final now = DateTime.now();
    if (last != null && now.difference(last) < const Duration(seconds: 5)) {
      return;
    }
    _seqPersistedAt = now;
    await _bots.saveSession(botId, seq: seq);
  }

  /// 释放。
  Future<void> dispose() async {
    await stop();
    await _events.close();
    status.dispose();
  }

  // ───────────────────────── 主循环 ─────────────────────────

  Future<void> _runLoop() async {
    while (!_stopped) {
      final outcome = await _connectOnce();

      if (_stopped || outcome == _CloseOutcome.stopped) return;

      if (outcome == _CloseOutcome.blocked) {
        // 终态：不再重连。官方对封禁 / 下架 / 参数权限错误标注「不可重试」，
        // 无限重连只会表现为耗电与日志刷屏，而用户什么都看不到。
        _setPhase(
          ConnectionPhase.blocked,
          keepError: true,
        );
        _log.error(
          LogSource.gateway,
          '连接已停止，需要人工处理后再重连',
          botId: botId,
          detail: '原因：${status.value.lastError?.userMessage ?? '未知'}',
        );
        return;
      }

      if (outcome == _CloseOutcome.identify) {
        // 官方 4006 / 4007：无效 session，无法继续 resume，必须重新 identify。
        await _bots.clearSession(botId);
        _log.warn(
          LogSource.gateway,
          '会话已失效，将重新鉴权（Identify）',
          botId: botId,
        );
      }

      _attempt++;
      final delay = _nextBackoff(_attempt);
      final nextRetryAt = DateTime.now().add(delay);
      _setPhase(
        ConnectionPhase.backoff,
        attempt: _attempt,
        nextRetryAt: nextRetryAt,
      );
      _log.warn(
        LogSource.gateway,
        '连接断开，${delay.inSeconds} 秒后重连'
        '（第 $_attempt 次，将${outcome == _CloseOutcome.identify ? '重新鉴权' : '尝试恢复会话'}）',
        botId: botId,
      );
      await Future<void>.delayed(delay);
    }
  }

  /// 退避时长：指数增长 + 抖动。
  ///
  /// 抖动是必需的：多机器人同时断开时，若退避完全一致会同时冲击网关，
  /// 触发官方 4008「发送 payload 过快」。
  Duration _nextBackoff(int attempt) {
    final base = _config.backoffFor(attempt);
    final jitterRatio = _config.reconnectJitterRatio;
    if (jitterRatio <= 0) return base;
    final jitter = base * (Random().nextDouble() * jitterRatio);
    return base + jitter;
  }

  /// 建立一次连接并一直等到它结束。
  Future<_CloseOutcome> _connectOnce() async {
    _helloReceived = false;
    _setPhase(ConnectionPhase.fetchingEndpoint, clearError: true);

    // 连续失败多次后强制刷新接入点缓存（可能是网关地址变了）。
    final endpoint = await _gatewayApi.fetch(
      botId,
      forceRefresh: _attempt >= 3,
      cacheTtl: _config.endpointCacheTtl,
    );
    if (endpoint == null) {
      final error = _tokens.hasValidToken(botId)
          ? NetworkError(userMessage: '获取 WSS 接入点失败，请检查网络。')
          : AuthError(userMessage: '缺少可用的访问凭证，请到「设置」页检查机器人密钥。');
      _setPhase(ConnectionPhase.backoff, lastError: error);
      return _tokens.hasValidToken(botId)
          ? _CloseOutcome.resume
          : _CloseOutcome.blocked;
    }

    _setPhase(ConnectionPhase.connecting);

    final socket = _socketFactory();
    _socket = socket;
    final completer = Completer<_CloseOutcome>();
    _closeCompleter = completer;

    _frameSubscription = socket.messages.listen(
      _onFrame,
      onError: (Object error) {
        AppLogger.warn('连接异常：$error', tag: 'wss');
        _completeClose(_outcomeFor(socket, error: error));
      },
      onDone: () => _completeClose(_outcomeFor(socket)),
      cancelOnError: false,
    );

    try {
      await socket.connect(Uri.parse(endpoint.url));
    } catch (error, stack) {
      AppLogger.error('建立 WebSocket 连接失败',
          error: error, stackTrace: stack, tag: 'wss');
      _setPhase(
        ConnectionPhase.backoff,
        lastError: NetworkError(userMessage: '无法连接 QQ 网关，请检查网络。', cause: error),
      );
      await _frameSubscription?.cancel();
      _frameSubscription = null;
      return _CloseOutcome.resume;
    }

    _log.info(
      LogSource.gateway,
      'WebSocket 已连接，等待 Hello'
      '${endpoint.shards == null ? '' : '（官方建议分片 ${endpoint.shards}，本项目不分片）'}',
      botId: botId,
    );

    // 建连后必须收到 Op10 Hello，否则视为握手失败。
    _handshakeTimer = Timer(_config.handshakeTimeout, () {
      if (_helloReceived) return;
      _log.warn(
        LogSource.gateway,
        '等待 Hello 超时（${_config.handshakeTimeout.inSeconds} 秒），将重连',
        botId: botId,
      );
      _setPhase(
        ConnectionPhase.backoff,
        lastError: TimeoutError(userMessage: '网关未下发 Hello，握手超时。'),
      );
      unawaited(socket.close(1000, 'hello timeout'));
      _completeClose(_CloseOutcome.resume);
    });

    return completer.future;
  }

  void _completeClose(_CloseOutcome outcome) {
    final completer = _closeCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete(outcome);
    }
  }

  /// 依据关闭码决定去向。
  ///
  /// 这是官方错误码表「是否可以重试 RESUME / 是否可以重试 IDENTIFY」
  /// 两列在代码中的唯一落点。
  _CloseOutcome _outcomeFor(GatewaySocket socket, {Object? error}) {
    if (_stopped) return _CloseOutcome.stopped;

    final code = socket.closeCode;
    final reason = socket.closeReason;

    if (code == null) {
      // 底层网络异常（官方文档未提供标准关闭码的解释，
      // 因此没有关闭码时一律按网络断开处理）。
      _setPhase(
        ConnectionPhase.backoff,
        lastError: NetworkError(
          userMessage: '网络连接中断，正在重连。',
          cause: error,
        ),
      );
      return _CloseOutcome.resume;
    }

    final appError = ErrorMapper.fromWsClose(code, reason: reason);
    _setPhase(ConnectionPhase.backoff, lastError: appError);
    _log.warn(
      LogSource.gateway,
      '连接被关闭：$code ${socket.closeReason ?? ''}'.trim(),
      botId: botId,
      detail: '判定：${appError.userMessage}',
    );

    if (appError.isTerminalForBot) return _CloseOutcome.blocked;
    if (appError is ProtocolRejectedError) return _CloseOutcome.blocked;
    if (appError is SessionInvalidError) return _CloseOutcome.identify;
    return _CloseOutcome.resume;
  }

  // ───────────────────────── 帧处理 ─────────────────────────

  void _onFrame(String raw) {
    Map<String, dynamic> decoded;
    try {
      final json = jsonDecode(raw);
      if (json is! Map) {
        AppLogger.warn('收到非对象帧，已忽略', tag: 'wss');
        return;
      }
      decoded = json.cast<String, dynamic>();
    } catch (error) {
      AppLogger.warn('帧解析失败，已忽略：$error', tag: 'wss');
      return;
    }

    final frame = GatewayFrame.fromJson(decoded);

    final op = frame.op;
    if (op == null) {
      // 官方未定义 3 / 4 / 5 / 8，遇到时记录原始 op 并忽略，
      // 这样将来官方新增 opcode 也不会让连接崩掉。
      _log.warn(
        LogSource.gateway,
        '收到未知 opcode=${frame.rawOp}，已忽略该帧',
        botId: botId,
      );
      return;
    }

    // 心跳要携带「收到的最新的 s」，因此每帧都更新，与事件类型无关。
    _heartbeat?.updateSeq(frame.seq);

    switch (op) {
      case QqOpCode.hello:
        _handleHello(frame);
      case QqOpCode.heartbeatAck:
        _heartbeat?.ack();
      case QqOpCode.dispatch:
        _handleDispatch(frame);
      case QqOpCode.reconnect:
        _log.warn(
          LogSource.gateway,
          '网关要求客户端重新连接（Op7）',
          botId: botId,
        );
        unawaited(_socket?.close(1000, 'server requested reconnect'));
      case QqOpCode.invalidSession:
        // 官方：identify 或 resume 参数有错时返回本消息。
        _log.warn(
          LogSource.gateway,
          '鉴权参数被网关拒绝（Op9 Invalid Session），将重新鉴权',
          botId: botId,
        );
        unawaited(_bots.clearSession(botId));
        _setPhase(
          ConnectionPhase.backoff,
          lastError: SessionInvalidError(
            userMessage: '鉴权参数被拒绝，正在重新鉴权。',
          ),
        );
        unawaited(_socket?.close(1006, 'invalid session'));
      case QqOpCode.heartbeat:
      case QqOpCode.identify:
      case QqOpCode.resume:
      case QqOpCode.httpCallbackAck:
      case QqOpCode.callbackUrlVerify:
        // 这些 op 只应由客户端发送（或仅用于 HTTP 回调模式）。
        _log.warn(
          LogSource.gateway,
          '收到不应由网关下发的 opcode=${op.value}，已忽略',
          botId: botId,
        );
    }
  }

  void _handleHello(GatewayFrame frame) {
    _helloReceived = true;
    _handshakeTimer?.cancel();
    final data = frame.data is Map
        ? (frame.data! as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final hello = HelloData.fromJson(data);
    _heartbeatInterval = hello.heartbeatInterval;

    _log.info(
      LogSource.gateway,
      '收到 Hello，心跳周期 ${hello.heartbeatIntervalMs} 毫秒',
      botId: botId,
    );

    _setPhase(ConnectionPhase.authenticating, heartbeatInterval: _heartbeatInterval);
    unawaited(_authenticate());
  }

  /// 按官方顺序鉴权：有可用会话则 Resume，否则 Identify。
  Future<void> _authenticate() async {
    final token = await _tokens.buildIdentifyToken(botId);
    if (token == null) {
      _log.error(
        LogSource.gateway,
        '无法生成 Identify 凭证，请检查密钥配置',
        botId: botId,
      );
      _setPhase(
        ConnectionPhase.blocked,
        lastError: ConfigError(
          userMessage: '凭证配置不完整，请到「设置」页填写机器人密钥或 Token。',
        ),
      );
      await _socket?.close(1000, 'no credential');
      return;
    }

    final session = _bots.session(botId);
    if (session.canResume) {
      _sendFrame({
        'op': QqOpCode.resume.value,
        'd': ResumePayload(
          token: token,
          sessionId: session.sessionId!,
          seq: session.seq,
        ).toJson(),
      });
      _log.info(
        LogSource.gateway,
        '已发送 Resume（session=…${_tail(session.sessionId!)}, seq=${session.seq}）',
        botId: botId,
      );
      return;
    }

    _sendFrame({
      'op': QqOpCode.identify.value,
      'd': IdentifyPayload(
        token: token,
        intents: QqIntents.defaultMask,
        // 官方明确：若无需分片，使用 [0, 1] 即可。
        // 本项目的 Gradle 侧不需要分片，但要实测确认 [0,1] 是否被接受。
        shard: const [0, 1],
        properties: {
          r'$os': _platformName(),
          r'$browser': 'Lave',
          r'$device': 'Lave',
        },
      ).toJson(),
    });
    _log.info(
      LogSource.gateway,
      '已发送 Identify（intents=${QqIntents.defaultMask}，'
      '是否含群成员位=${QqIntents.has(QqIntents.defaultMask, QqIntents.groupMemberEvent)}）',
      botId: botId,
    );
  }

  void _handleDispatch(GatewayFrame frame) {
    final type = frame.type;

    if (type == 'READY') {
      final data = frame.data is Map
          ? (frame.data! as Map).cast<String, dynamic>()
          : const <String, dynamic>{};
      final ready = ReadyData.fromJson(data);
      if (!ready.isUsable) {
        _log.error(
          LogSource.gateway,
          'READY 事件缺少 session_id，无法建立可恢复会话',
          botId: botId,
          detail: '实际载荷：$data',
        );
      } else {
        unawaited(
          _bots.saveSession(botId, sessionId: ready.sessionId, seq: frame.seq),
        );
      }
      _attempt = 0;
      _setPhase(
        ConnectionPhase.online,
        sessionId: ready.sessionId,
        seq: frame.seq,
        clearError: true,
      );
      _startHeartbeat();
      unawaited(_bots.markConnected(botId, DateTime.now()));
      _log.info(
        LogSource.gateway,
        '鉴权成功，已进入在线状态'
        '${ready.user?.username == null ? '' : '（${ready.user!.username}）'}',
        botId: botId,
      );
      return;
    }

    if (type == 'RESUMED') {
      _attempt = 0;
      _setPhase(
        ConnectionPhase.online,
        seq: frame.seq,
        clearError: true,
      );
      _startHeartbeat();
      _log.info(
        LogSource.gateway,
        '会话已恢复，网关已完成遗漏事件补发',
        botId: botId,
      );
      return;
    }

    // 业务事件：解码后交给分发层。
    //
    // 这里**不推进持久化 seq** —— 由分发层在落库成功后调用 acknowledgeSeq。
    final event = QqEvent.decode(type, frame.data, id: frame.id, seq: frame.seq);
    if (!_events.isClosed) _events.add(event);
  }

  void _startHeartbeat() {
    _heartbeat?.stop();
    _heartbeat = HeartbeatScheduler(
      interval: _heartbeatInterval,
      timeoutMultiplier: _config.heartbeatTimeoutMultiplier,
      onSend: (seq) {
        // 官方：首次连接 d 传 null，之后传最新收到的 s。
        _sendFrame({'op': QqOpCode.heartbeat.value, 'd': seq});
      },
      onDead: () {
        _log.warn(
          LogSource.gateway,
          '心跳连续 $_heartbeatMissDescription 未收到 ACK，判定为死链并重连',
          botId: botId,
        );
        unawaited(_socket?.close(1000, 'heartbeat timeout'));
        _completeClose(_CloseOutcome.resume);
      },
    );
    _heartbeat!.start();
  }

  String get _heartbeatMissDescription =>
      '${_config.heartbeatTimeoutMultiplier} 次';

  void _sendFrame(Map<String, dynamic> frame) {
    final socket = _socket;
    if (socket == null || socket.isClosed) return;
    socket.send(jsonEncode(frame));
  }

  void _setPhase(
    ConnectionPhase phase, {
    int? attempt,
    String? sessionId,
    int? seq,
    Duration? heartbeatInterval,
    AppError? lastError,
    DateTime? nextRetryAt,
    bool clearError = false,
    bool keepError = false,
  }) {
    final current = status.value;
    status.value = current.transition(
      phase,
      DateTime.now(),
      attempt: attempt,
      sessionId: sessionId,
      seq: seq,
      heartbeatInterval: heartbeatInterval,
      lastError: keepError ? null : lastError,
      nextRetryAt: nextRetryAt,
      clearError: clearError,
    );
  }

  String _platformName() {
    // 官方示例里 $os 填 'linux'；这里填真实平台名，
    // 属于对「官方未提供取值约束」的保守选择（填真实值比留空更安全）。
    return defaultTargetPlatform.name;
  }

  static String _tail(String value) =>
      value.length <= 6 ? value : value.substring(value.length - 6);
}

/// 官方分片建议值的展示助手（本项目不分片，仅用于日志与界面说明）。
String describeShardPolicy() =>
    '不使用分片（官方明确：若无需分片，使用 [0, 1] 即可）'
    '；分片用于多连接水平扩展，移动端单机无收益。'
    '官方错误码 4011 提示「连接需要处理的 guild 过多，请进行合理的分片」。'
    '被动回复窗口：单聊 ${QqLimits.c2cReplyWindow.inMinutes} 分钟 / '
    '群聊 ${QqLimits.groupReplyWindow.inMinutes} 分钟。';
