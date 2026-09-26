import 'package:flutter/foundation.dart';

/// 运行环境判定。
///
/// 环境通过编译期变量 `APP_ENV` 指定，例如：
/// ```bash
/// flutter run --dart-define=APP_ENV=dev
/// flutter build apk --dart-define=APP_ENV=prod
/// ```
/// 未显式指定时，按 Flutter 编译模式推断：Debug 视为调试环境，Release 视为生产环境。
///
/// 注意：这里刻意不用 `kDebugMode` 直接当环境开关，因为「Debug 构建连生产网关」是
/// 排查线上问题的常见需求，需要一个能独立于编译模式切换的开关。
abstract final class AppEnvironment {
  /// 编译期注入的环境标识；未注入时为空字符串。
  static const String _declared = String.fromEnvironment('APP_ENV');

  /// 是否为调试环境。
  static bool get isDev {
    if (_declared == 'prod') return false;
    if (_declared == 'dev') return true;
    // 未声明时：非 Release 构建一律视为调试环境。
    return !kReleaseMode;
  }

  /// 是否为生产环境。
  static bool get isProd => !isDev;

  /// 供日志与界面展示的短标识。
  static String get label => isDev ? 'dev' : 'prod';
}

/// 全局可配置项。
///
/// 三条设计原则：
/// 1. **官方文档给出的固定数值一律不放这里**，它们集中在 `QqLimits`，本类只放
///    「官方未提供、需要自行取值或真机实测收敛」的阈值（心跳超时判据、重连退避、接入点缓存等）。
/// 2. 调试与生产**只在取值上不同，代码路径完全一致**。避免出现「只有生产才会走到」的分支，
///    那类分支永远测不到。
/// 3. 全部字段不可变，通过 [copyWith] 覆盖，便于测试注入极端值（如把超时压到 1 毫秒）。
@immutable
class AppConfig {
  const AppConfig({
    required this.heartbeatTimeoutMultiplier,
    required this.handshakeTimeout,
    required this.reconnectBaseDelay,
    required this.reconnectMaxDelay,
    required this.reconnectJitterRatio,
    required this.endpointCacheTtl,
    required this.httpTimeout,
    required this.maxConcurrentConnections,
    required this.enableNetworkLog,
    required this.enableFrameLog,
    required this.enableForegroundService,
  });

  /// 调试环境：日志全开；心跳判据更保守，便于尽早暴露断链问题。
  static const AppConfig dev = AppConfig(
    // 官方未提供心跳超时阈值，取心跳周期的 2 倍作为死链判据（见架构文档 9/11 章）。
    heartbeatTimeoutMultiplier: 2,
    // 建连后等待 Op10 Hello 的超时。
    handshakeTimeout: Duration(seconds: 15),
    // 重连退避：指数增长 + 抖动，避免集中重连触发官方 4008「发送 payload 过快」。
    reconnectBaseDelay: Duration(seconds: 1),
    reconnectMaxDelay: Duration(seconds: 60),
    reconnectJitterRatio: 0.2,
    // `GET /gateway` 官方限制 2 QPM（burst 10 QPM），因此接入点结果必须缓存复用。
    endpointCacheTtl: Duration(minutes: 5),
    // 官方建议发消息接口 timeout 最低 5 秒，这里留更宽裕的余量。
    httpTimeout: Duration(seconds: 10),
    // 多 Bot 并发上限，超出后按「最近使用」权重让空闲连接转惰性。
    maxConcurrentConnections: 3,
    enableNetworkLog: true,
    enableFrameLog: true,
    // 前台服务：当前版本**尚未实现** Android 原生 Service 与 iOS BGTask，
    // 因此这里保持 false。置 true 会让配置读到的人以为「后台保活已经生效」，
    // 而实际只有 Dart 侧的退避重连在工作。
    enableForegroundService: false,
  );

  /// 生产环境：关闭逐帧日志与网络明细，降低耗电与日志体积；退避上限放宽。
  static const AppConfig prod = AppConfig(
    heartbeatTimeoutMultiplier: 2,
    handshakeTimeout: Duration(seconds: 15),
    reconnectBaseDelay: Duration(seconds: 1),
    reconnectMaxDelay: Duration(seconds: 120),
    reconnectJitterRatio: 0.2,
    endpointCacheTtl: Duration(minutes: 5),
    httpTimeout: Duration(seconds: 10),
    maxConcurrentConnections: 3,
    enableNetworkLog: false,
    enableFrameLog: false,
    // 同上：原生前台服务未实现，保持 false，避免配置误导。
    enableForegroundService: false,
  );

  /// 当前生效配置。
  static AppConfig get current => AppEnvironment.isDev ? dev : prod;

  /// 心跳超时判据的倍数。官方未提供阈值：收到 Op11 视为成功，
  /// 超过 `heartbeat_interval × 本倍数` 仍未收到即判定为死链并主动断开重连。
  final int heartbeatTimeoutMultiplier;

  /// 建连后等待 Op10 Hello 的超时。
  final Duration handshakeTimeout;

  /// 重连退避的起始间隔。
  final Duration reconnectBaseDelay;

  /// 重连退避的上限间隔。
  final Duration reconnectMaxDelay;

  /// 退避抖动比例（0~1），用于打散重连时间点。
  final double reconnectJitterRatio;

  /// WSS 接入点的本地缓存时长。官方 `GET /gateway` 限 2 QPM，
  /// 频繁调用会触发限流，因此缓存是必需项而非优化。
  final Duration endpointCacheTtl;

  /// HTTP 请求超时。
  final Duration httpTimeout;

  /// 允许同时保持的 WSS 连接数上限。
  final int maxConcurrentConnections;

  /// 是否输出 HTTP 请求/响应明细日志（含脱敏后的 URL 与状态码）。
  final bool enableNetworkLog;

  /// 是否输出 WSS 逐帧日志。
  final bool enableFrameLog;

  /// 是否启用 Android 前台服务。
  final bool enableForegroundService;

  /// 心跳超时判据（由 `heartbeat_interval` 换算）。
  Duration heartbeatTimeoutFor(Duration heartbeatInterval) =>
      heartbeatInterval * heartbeatTimeoutMultiplier;

  /// 按退避次数换算等待时长：`base × 2^attempt`，上限 [reconnectMaxDelay]。
  ///
  /// 不含抖动；抖动由调用方叠加随机量，以便测试可断言确定性部分。
  Duration backoffFor(int attempt) {
    if (attempt <= 0) return reconnectBaseDelay;
    final exponential = reconnectBaseDelay * (1 << attempt);
    return exponential > reconnectMaxDelay ? reconnectMaxDelay : exponential;
  }

  AppConfig copyWith({
    int? heartbeatTimeoutMultiplier,
    Duration? handshakeTimeout,
    Duration? reconnectBaseDelay,
    Duration? reconnectMaxDelay,
    double? reconnectJitterRatio,
    Duration? endpointCacheTtl,
    Duration? httpTimeout,
    int? maxConcurrentConnections,
    bool? enableNetworkLog,
    bool? enableFrameLog,
    bool? enableForegroundService,
  }) {
    return AppConfig(
      heartbeatTimeoutMultiplier:
          heartbeatTimeoutMultiplier ?? this.heartbeatTimeoutMultiplier,
      handshakeTimeout: handshakeTimeout ?? this.handshakeTimeout,
      reconnectBaseDelay: reconnectBaseDelay ?? this.reconnectBaseDelay,
      reconnectMaxDelay: reconnectMaxDelay ?? this.reconnectMaxDelay,
      reconnectJitterRatio: reconnectJitterRatio ?? this.reconnectJitterRatio,
      endpointCacheTtl: endpointCacheTtl ?? this.endpointCacheTtl,
      httpTimeout: httpTimeout ?? this.httpTimeout,
      maxConcurrentConnections:
          maxConcurrentConnections ?? this.maxConcurrentConnections,
      enableNetworkLog: enableNetworkLog ?? this.enableNetworkLog,
      enableFrameLog: enableFrameLog ?? this.enableFrameLog,
      enableForegroundService:
          enableForegroundService ?? this.enableForegroundService,
    );
  }
}
