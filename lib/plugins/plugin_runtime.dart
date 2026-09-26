import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../core/logging/app_logger.dart';
import '../domain/models/plugin_models.dart';

/// 内置解释器释放器：把 assets 中的 Python 运行时写到 [pythonRoot]，返回可执行文件路径。
///
/// 抽成可替换的函数是为了让能力探测可以在纯 Dart 测试中验证——
/// 测试注入一个「假装释放成功 / 假装没有内置资源」的实现即可。
typedef PluginAssetExtractor = Future<String?> Function(Directory pythonRoot);

/// 从 Flutter assets 释放内置 Python 运行时（默认实现）。
///
/// 为什么必须「释放」而不是直接执行 assets 里的文件：
/// Android 的 assets 位于 APK 内部，没有真实文件路径，也无法设置可执行位。
/// 必须先复制到应用私有目录并 `chmod 755`，才能被 `Process.start` 执行。
///
/// 资产布局（由打包流程决定，见 README「内置 Python 运行时」）：
/// ```
/// android/app/src/main/assets/python/arm64-v8a/python3
/// android/app/src/main/assets/python/arm64-v8a/lib/python3.12/…
/// ```
/// 按 ABI 分目录是因为不同架构的二进制不能混用；
/// 这里按顺序尝试，取第一个真实存在的目录。
Future<String?> rootBundleAssetExtractor(Directory pythonRoot) async {
  // 顺序即优先级：移动端优先 arm64，桌面端用不带 ABI 的目录。
  const abiCandidates = <String>['arm64-v8a', 'armeabi-v7a', 'x86_64', ''];

  try {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final allKeys = manifest.listAssets();

    for (final abi in abiCandidates) {
      final prefix = abi.isEmpty ? 'assets/python/' : 'assets/python/$abi/';
      final keys = allKeys.where((key) => key.startsWith(prefix)).toList();
      if (keys.isEmpty) continue;

      for (final key in keys) {
        final relative = key.substring(prefix.length);
        if (relative.isEmpty) continue;
        final target = File(
          '${pythonRoot.path}${Platform.pathSeparator}'
          '${relative.replaceAll('/', Platform.pathSeparator)}',
        );
        await target.parent.create(recursive: true);
        final data = await rootBundle.load(key);
        await target.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true,
        );
      }

      final executable =
          File('${pythonRoot.path}${Platform.pathSeparator}python3');
      if (await executable.exists()) {
        AppLogger.info(
          '已释放内置 Python 运行时（$prefix，${keys.length} 个文件）',
          tag: 'plugin',
        );
        return executable.path;
      }
      return null;
    }
    return null;
  } catch (error) {
    // 没有内置资源属于正常情况（绝大多数构建都不会带），因此只记 debug。
    AppLogger.info('未发现内置 Python 资源：$error', tag: 'plugin');
    return null;
  }
}

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
  /// 探测顺序（**先看内置解释器，再找系统解释器**）：
  /// 1. 应用私有目录下已释放的内置解释器（`<files>/python/bin/python3`）；
  /// 2. 从 APK 的 assets 释放内置解释器（见 [ensureBundledPython]）；
  /// 3. 系统 PATH 中的 `python3` / `python`。
  ///
  /// 这样做的意义：Android 系统**不内置 Python**，`Process.start('python3')`
  /// 在真机上必然失败。要让 Android 上真正可用，必须把解释器随包分发，
  /// 由本方法负责把它从 assets 释放到可执行位置。
  static Future<PluginRuntime> probe({
    PluginAssetExtractor? assetExtractor,
    Directory? filesDirectory,
  }) async {
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

    // ── ① 已释放的内置解释器 ──
    final bundled = await _resolveBundledInterpreter(
      assetExtractor: assetExtractor,
      filesDirectory: filesDirectory,
    );
    if (bundled != null) {
      AppLogger.info('使用内置 Python：$bundled', tag: 'plugin');
      return PluginRuntime._(
        capability: PluginRuntimeCapability.available(
          platform: platform,
          pythonExecutable: bundled,
        ),
      );
    }

    // ── ② 系统解释器 ──
    for (final candidate in _pythonCandidates) {
      try {
        final result = await Process.run(candidate, const ['-V'])
            .timeout(const Duration(seconds: 10));
        if (result.exitCode == 0) {
          final version = '${result.stdout}${result.stderr}'.trim();
          AppLogger.info('已探测到系统 Python：$candidate（$version）', tag: 'plugin');
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
            ? '未在应用中检测到内置 Python 运行时，且 Android 系统本身不提供 Python。'
                '请把交叉编译好的解释器按 '
                '`android/app/src/main/assets/python/<abi>/python3` 放入 '
                'assets 后重新打包（详见 README「内置 Python 运行时」）。'
            : '未在系统中找到可用的 Python 解释器（已尝试 python3 / python），'
                '请先安装 Python 3 后重启应用。',
      ),
    );
  }

  /// 解析可用的内置解释器，必要时先从 assets 释放。
  ///
  /// 布局约定：`assets/python/<abi>/` 下的全部内容会被释放到
  /// 应用私有目录的 `<files>/python/`，其中解释器可执行文件为
  /// `<files>/python/python3`。保持目录结构是为了让 stdlib
  /// （`lib/python3.x/…`）也能被一起带出来——只放一个裸可执行文件是跑不起来的。
  static Future<String?> _resolveBundledInterpreter({
    PluginAssetExtractor? assetExtractor,
    Directory? filesDirectory,
  }) async {
    try {
      final base = filesDirectory ?? await getApplicationSupportDirectory();
      final root = Directory('${base.path}${Platform.pathSeparator}python');
      final executable = File(
        '${root.path}${Platform.pathSeparator}python3',
      );

      if (executable.existsSync()) return executable.path;

      final extractor = assetExtractor ?? rootBundleAssetExtractor;
      final extracted = await extractor(root);
      if (extracted == null) return null;

      // 赋予可执行权限。失败时直接返回 null —— 没有执行位的文件
      // 交给 Process.start 只会得到一个难以理解的 errno。
      final chmod = await Process.run('chmod', ['755', extracted]);
      if (chmod.exitCode != 0) {
        AppLogger.warn('内置解释器 chmod 失败：${chmod.stderr}', tag: 'plugin');
        return null;
      }
      return extracted;
    } catch (error) {
      AppLogger.warn('内置解释器释放失败：$error', tag: 'plugin');
      return null;
    }
  }

  /// 候选可执行文件名。
  static const List<String> _pythonCandidates = ['python3', 'python'];

  /// 启动一个插件进程。
  ///
  /// 返回 `null` 表示当前平台不支持（调用方应展示 [capability] 的原因）。
  Future<PluginProcess?> startProcess({
    required PluginManifest manifest,
    required String directory,
    required void Function(String line) onDiagnostic,
  }) async {
    if (!capability.supported) return null;
    final executable = capability.pythonExecutable;
    if (executable == null) return null;

    final entryPath = '$directory${Platform.pathSeparator}${manifest.entry}';
    if (!File(entryPath).existsSync()) {
      onDiagnostic('入口文件不存在：$entryPath');
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
        onDiagnostic: onDiagnostic,
      );
    } catch (error, stack) {
      AppLogger.error('启动插件进程失败',
          error: error, stackTrace: stack, tag: 'plugin');
      onDiagnostic('启动失败：$error');
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
    required void Function(String line) onDiagnostic,
  }) : _process = process {
    _init(onDiagnostic);
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

  void _init(void Function(String line) onDiagnostic) {
    _stdoutSub = _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleStdoutLine, onError: (Object e) => onDiagnostic('$e'));

    _stderrSub = _process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
      (line) {
        // 插件的 stderr 只在这里转成一条日志。
        //
        // 早期实现同时调用了 onDiagnostic(line) 与 _logLines.add(...)，
        // 结果是插件的每一行报错都会在「日志」Tab 里出现两次
        // （一次 warn 一次 error），看起来像重复报错。
        // 现在「行内容」只走 logLines，「流级异常」才走 onDiagnostic。
        _logLines.add(
          PluginMessage(
            type: PluginMessageType.log,
            payload: {'level': 'error', 'message': line, 'tag': 'stderr'},
          ),
        );
      },
      onError: (Object e) => onDiagnostic('$e'),
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
