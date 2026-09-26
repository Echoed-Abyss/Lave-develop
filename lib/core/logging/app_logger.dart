import 'package:flutter/foundation.dart';

import '../constants/app_config.dart';

/// 分级日志。
///
/// 三条硬要求：
/// 1. **脱敏**：官方接入票据（access_token、clientSecret/AppSecret、token）绝不能进日志。
///    调试环境的网络日志最容易泄露这些值，因此所有输出统一经过 [redact]，
///    而不是靠「注意一下别打出来」。
/// 2. **分级可控**：生产环境关闭逐帧与网络明细，避免耗电与日志膨胀，配置见 [AppConfig]。
/// 3. **必须能带 traceId**：官方提供 `X-Tps-trace-ID` 与响应体 `trace_id`，
///    出问题时靠它找平台协助定位，因此日志接口支持附带该字段。
///
/// 说明：本项目不引入第三方日志库。移动端日志的唯一消费方是开发者在 IDE 里的
/// `debugPrint` 输出与本地诊断导出，多一层依赖不划算；真需要落盘时在此处加 sink 即可。
abstract final class AppLogger {
  AppLogger._();

  static bool _networkEnabled = AppConfig.current.enableNetworkLog;
  static bool _frameEnabled = AppConfig.current.enableFrameLog;

  /// 覆盖日志开关。
  ///
  /// 供测试与运行时设置页使用——[AppConfig] 是编译期常量，
  /// 而用户可能希望在发布包里临时打开逐帧日志来排查连接问题。
  @visibleForTesting
  static void configure({bool? network, bool? frame}) {
    if (network != null) _networkEnabled = network;
    if (frame != null) _frameEnabled = frame;
  }

  /// 通用调试日志。
  static void debug(String message, {String? tag}) =>
      _emit('DEBUG', tag, message);

  /// 关键流程日志（连接建立、会话恢复、消息发送等）。
  static void info(String message, {String? tag}) => _emit('INFO', tag, message);

  /// 警告（可自愈的异常：重连、降级、重试）。
  static void warn(String message, {String? tag}) => _emit('WARN', tag, message);

  /// 错误。携带原始异常与堆栈，便于定位。
  static void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String? tag,
  }) {
    _emit('ERROR', tag, message);
    if (error != null) _emit('ERROR', tag, '  cause: $error');
    if (stackTrace != null) _emit('ERROR', tag, '  stack: $stackTrace');
  }

  /// 网络明细日志（HTTP 请求 / 响应）。生产环境默认关闭。
  static void network(String message, {String? tag}) {
    if (!_networkEnabled) return;
    _emit('NET', tag ?? 'http', message);
  }

  /// WSS 逐帧日志。生产环境默认关闭——高频帧日志会显著增加耗电。
  static void frame(String message, {String? tag}) {
    if (!_frameEnabled) return;
    _emit('FRAME', tag ?? 'wss', message);
  }

  /// 把输入中的敏感字段值替换为 `***`。
  ///
  /// 分三遍处理，顺序不可颠倒：
  /// 1. `Authorization` 请求头：**必须吃掉整行的值**。格式为 `QQBot {ACCESS_TOKEN}`，
  ///    若按普通键值对只吃掉 `QQBot`，token 本身仍会留在日志里；
  /// 2. 引号包裹的值（JSON 形态）：`{"access_token":"xxx"}`；
  /// 3. 未加引号的值（query string 形态）：`token=xxx`。
  ///
  /// 键名匹配大小写不敏感，因此 `appSecret` / `app_secret` / `AppSecret` 都能命中。
  /// 只会匹配「键 + 冒号或等号 + 值」的形态，因此自然语言里的
  /// 「本次 token 已刷新」不会被误伤。
  static String redact(String input) {
    if (input.isEmpty) return input;
    var result = input;
    result = result.replaceAllMapped(_authorizationPattern, (m) {
      return '${m.group(1)}***';
    });
    result = result.replaceAllMapped(_quotedValuePattern, (m) {
      return '${m.group(1)}***${m.group(3)}';
    });
    result = result.replaceAllMapped(_bareValuePattern, (m) {
      return '${m.group(1)}***';
    });
    return result;
  }

  /// `Authorization: QQBot xxxxx` —— 值吃到行尾 / 引号 / 逗号 / 右花括号为止。
  static final RegExp _authorizationPattern = RegExp(
    r'''(authorization["']?\s*[:=]\s*)([^"'\r\n,}]+)''',
    caseSensitive: false,
  );

  /// `"access_token": "xxx"` 形态：保留引号，只替换引号内的值。
  static final RegExp _quotedValuePattern = RegExp(
    '''(["']?(?:access_token|client_secret|clientsecret|app_secret|appsecret'''
    '''|app_token|apptoken|authorization|token|secret|password)["']?\\s*[:=]\\s*")([^"]*)(")''',
    caseSensitive: false,
  );

  /// `token=xxx` 形态：值吃到引号 / 空白 / 逗号 / 右花括号为止。
  static final RegExp _bareValuePattern = RegExp(
    '''(["']?(?:access_token|client_secret|clientsecret|app_secret|appsecret'''
    '''|app_token|apptoken|authorization|token|secret|password)["']?\\s*[:=]\\s*)'''
    '''([^"'\\s,}]+)''',
    caseSensitive: false,
  );

  static void _emit(String level, String? tag, String message) {
    final prefix = tag == null ? '[$level]' : '[$level][$tag]';
    // 所有输出统一脱敏，包括调用方传入的原始报文。
    debugPrint('$prefix ${redact(message)}');
  }
}