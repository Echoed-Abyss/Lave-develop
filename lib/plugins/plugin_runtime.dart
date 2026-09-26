import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/logging/app_logger.dart';
import '../domain/models/plugin_models.dart';

/// Python 插件运行时（进程型）。
///
/// ## 平台能力（必须先读这段）
///
/// 需求里的「启动 Python 子进程 + stdin/stdout JSON 通信」有一个无法回避的
/// 平台限制：
/// - **iOS 根本无法创建子进程**：`dart:io` 的 `Process.start` 不支持 iOS。
///   这是 Dart 运行平台限制，不是权限问题，改配置也无法绕开。
///   若要在 iOS 上运行 Python，只能改为**进程内嵌解释器**（FFI 加载静态链接的
///   CPython），届时 stdin/stdout 的概念不复存在，需换成内存管道——
///   那是另一个量级的工程量，需要单独评估。
/// - **Android 系统未内置 Python**：`Process.start('python3')` 在真机上会失败
///   （`No such file or directory`）。要跑起来必须先把 Python 运行时打进 APK
///   （Chaquopy 或 `python-for-android` 自编译）。
/// - **Windows / macOS / Linux** 上可直接工作（依赖系统 Python）。
///
/// 因此本实现**先探测能力再启动**，并把结论上报到界面：
/// 不支持的平台会明确显示原因与建议，而不是假装启动成功、在用户点击时静默失败。
///
/// ## 协议
///
/// 一行一条 JSON（JSON Lines）。选它的原因是 `stdout` 天然按行分帧：
/// 不需要额外的长度头或分隔协议，插件作者用 `print` 就能调试。
class PluginRuntime {
  PluginRuntime._({required this.capability});

  /// 当前平台能力。
  final PluginRuntimeCapability capability;

  /// 探测当前平台是否可以运行 Python 插件。
  ///
  /// 探测方式：实际执行 `python3 -V` / `python -V`，能拿到版本号才算可用——
  /// **不做「按平台猜测」**，因为 Android 上装了 Python 的定制系统确实存在，
  /// 而桌面环境也可能没装 Python。
  static Future<PluginRuntime> probe() async {
    final platform = _platformName();

    if (Platform.isIOS) {
      return PluginRuntime._(
        capability: PluginRuntimeCapability.unsupported(
          platform: platform,
          reason: 'iOS 不允许应用创建子进程（Dart 的 Process.start 不支持 iOS），'
              '因此无法以子进程方式运行 Python 插件。'
              '如需在 iOS 上支持插件，需改为内嵌解释器方案。',
        ),
      );
    }

    for (final candidate in _pythonCandidates) {
      try {
        final result = await Process.run(candidate, const ['-V'])
            .timeout(const Duration(seconds: 10));
        if (result.exitCode == 0) {
          final version = '${result.stdout}${result.stderr}'.trim();
          AppLogger.info('已探测到 Python：$candidate（$version）', tag: 'plugin');
          return PluginRuntime._(
            capability: PluginRuntimeCapability.available(
              platform: platform,
              pythonExecutable: candidate,
            ),
          );
        }
      } catch (_) {
        // 该候选不可用，继续尝试下一个。
      }
    }

    return PluginRuntime._(
      capability: PluginRuntimeCapability.unsupported(
        platform: platform,
        reason: Platform.isAndroid
            ? 'Android 系统未内置 Python 解释器，需要先把 Python 运行时'
                '打包进 APK（Chaquopy 或自编译 CPython）才能运行插件。'
            : '未在系统中找到可用的 Python 解释器（已尝试 python3 / python），'
                '请先安装 Python 3 后重启应用。',
      ),
    );
  }

  /// 候选可执行文件名。
  static const List<String> _pythonCandidates = ['python3', 'python'];

  /// 启动一个插件进程。
  ///
  /// 返回 `null` 表示当前平台不支持（调用方应展示 [capability] 的原因）。
  Future<PluginProcess?> startProcess({
    required PluginManifest manifest,
    required String directory,
    required void Function(String line) onStderr,
  }) async {
    if (!capability.supported) return null;
    final executable = capability.pythonExecutable;
    if (executable == null) return null;

    final entryPath = '$directory${Platform.pathSeparator}${manifest.entry}';
    if (!File(entryPath).existsSync()) {
      onStderr('入口文件不存在：$entryPath');
      return null;
    }

    try {
      final process = await Process.start(
        executable,
        ['-u', entryPath],
        workingDirectory: directory,
        environment: {
          // `-u` 与 PYTHONUNBUFFERED 都是必需的：
          // Python 默认对管道 stdout 做块缓冲，不加就会导致
          // 「插件明明 print 了但主程序收不到」，且现象是长时间静默。
          'PYTHONUNBUFFERED': '1',
          'PYTHONIOENCODING': 'utf-8',
        },
        runInShell: false,
      );
      return PluginProcess(
        manifest: manifest,
        process: process,
        onStderr: onStderr,
      );
    } catch (error, stack) {
      AppLogger.error('启动插件进程失败',
          error: error, stackTrace: stack, tag: 'plugin');
      onStderr('启动失败：$error');
      return null;
    }
  }

  static String _platformName() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }
}

/// 一个正在运行的插件进程。
class PluginProcess {
  PluginProcess({
    required this.manifest,
    required Process process,
    required void Function(String line) onStderr,
  }) : _process = process {
    _init(onStderr);
  }

  final PluginManifest manifest;
  final Process _process;

  final StreamController<PluginMessage> _messages =
      StreamController<PluginMessage>.broadcast();
  final StreamController<PluginMessage> _logLines =
      StreamController<PluginMessage>.broadcast();
  final StreamController<int> _exits = StreamController<int>.broadcast();

  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;
  bool _stopping = false;

  /// 插件发来的协议消息（不含纯日志行）。
  Stream<PluginMessage> get messages => _messages.stream;

  /// 插件产生的日志（含 stdout 的 print 与 stderr）。
  Stream<PluginMessage> get logLines => _logLines.stream;

  /// 进程退出事件（携带退出码）。
  Stream<int> get exits => _exits.stream;

  /// 进程 PID。
  int get pid => _process.pid;

  /// 是否仍在运行。
  bool get isRunning => !_stopping;

  void _init(void Function(String line) onStderr) {
    _stdoutSub = _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleStdoutLine, onError: (Object e) => onStderr('$e'));

    _stderrSub = _process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
      (line) {
        // 插件的 stderr 直接进日志：这是插件报错的主要出口，
        // 吞掉它等于让插件作者完全看不见问题。
        onStderr(line);
        _logLines.add(
          PluginMessage(
            type: PluginMessageType.log,
            payload: {'level': 'error', 'message': line, 'tag': 'stderr'},
          ),
        );
      },
      onError: (Object e) => onStderr('$e'),
    );

    unawaited(_process.exitCode.then((code) {
      _stopping = true;
      // 崩溃隔离的关键点：进程退出只影响这一个插件，
      // 主程序与其它插件不受影响，只把崩溃原因记录出来。
      _exits.add(code);
      if (!_messages.isClosed) unawaited(_messages.close());
      if (!_logLines.isClosed) unawaited(_logLines.close());
    }));
  }

  /// 处理一行 stdout。
  ///
  /// **容错原则**：非 JSON 行不当作错误丢弃。插件作者习惯用 `print('调试')`，
  /// 若把这些行直接扔掉，最常见的排查手段就失效了。因此非 JSON 一律按
  /// 「插件日志」处理。
  void _handleStdoutLine(String line) {
    final text = line.trim();
    if (text.isEmpty) return;
    if (!text.startsWith('{')) {
      _logLines.add(
        PluginMessage(
          type: PluginMessageType.log,
          payload: {'level': 'info', 'message': text, 'tag': 'stdout'},
        ),
      );
      return;
    }
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) {
        _logLines.add(
          PluginMessage(
            type: PluginMessageType.log,
            payload: {'level': 'info', 'message': text, 'tag': 'stdout'},
          ),
        );
        return;
      }
      final message = PluginMessage.fromJson(decoded.cast<String, dynamic>());
      if (message.type == PluginMessageType.log) {
        _logLines.add(message);
      } else {
        _messages.add(message);
      }
    } catch (_) {
      _logLines.add(
        PluginMessage(
          type: PluginMessageType.log,
          payload: {'level': 'warn', 'message': '无法解析的协议行：$text'},
        ),
      );
    }
  }

  /// 向插件发送一条协议消息。
  void send(PluginMessage message) {
    if (_stopping) return;
    try {
      _process.stdin.writeln(message.toLine());
    } catch (error) {
      AppLogger.warn('向插件写入失败：$error', tag: 'plugin');
    }
  }

  /// 优雅停止（先发 shutdown，再等待，最后强杀）。
  Future<void> stop({Duration grace = const Duration(seconds: 3)}) async {
    if (_stopping) return;
    _stopping = true;
    try {
      send(const PluginMessage(type: PluginMessageType.shutdown));
      await _process.stdin.flush();
      _process.stdin.close();
    } catch (_) {
      // 忽略：进程可能已经退出。
    }

    final exited = await _process.exitCode
        .timeout(grace, onTimeout: () => -1);
    if (exited == -1) {
      // 超时未退出则强杀，避免留下僵尸进程占内存。
      _process.kill(ProcessSignal.sigkill);
    }

    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    if (!_messages.isClosed) await _messages.close();
    if (!_logLines.isClosed) await _logLines.close();
    if (!_exits.isClosed) await _exits.close();
  }
}
