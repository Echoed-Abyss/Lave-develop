import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/logging/app_logger.dart';
import '../domain/models/plugin_models.dart';

/// 内置解释器释放器：把 assets 里的运行时释放到 [pythonRoot]。
///
/// [abi] 为设备实际的 ABI（从原生库目录名推导），用于在多个 ABI 目录中
/// 选中正确的那一份——不同架构的二进制不能混用。
///
/// 抽成可替换的函数是为了让能力探测能在纯 Dart 测试中验证：
/// 测试注入一个空实现即可模拟「没有内置资源」。
typedef PluginAssetExtractor = Future<void> Function(
  Directory pythonRoot,
  String? abi,
);

/// 内置 Python 运行时的解析结果。
@immutable
class BundledPythonRuntime {
  const BundledPythonRuntime({
    required this.executable,
    required this.environment,
    required this.ensureExtracted,
  });

  /// 可执行文件（启动器或解释器）的绝对路径。
  final String executable;

  /// 启动子进程时需要额外注入的环境变量。
  ///
  /// - `PYTHONHOME`：标准库所在的前缀目录。**不设它解释器会去
  ///   `/usr/lib/python3.x` 找标准库，在 Android 上必然失败**；
  /// - `LD_LIBRARY_PATH`：原生库目录。官方的 `libpython3.14.so` 与它依赖的
  ///   libcrypto / libssl / libsqlite3 都放在那里，不设它动态链接器找不到。
  final Map<String, String> environment;

  /// 确保标准库已释放到磁盘（幂等）。
  ///
  /// **刻意与探测分离**：释放要写 600 多个文件，若放在启动流程里，
  /// 首次安装后的第一次启动会白屏数秒。改为在真正要启动插件时才做，
  /// 用户看到的等待只出现在「点启动插件」这一个动作上。
  final Future<void> Function() ensureExtracted;
}

/// 内置运行时的标准库版本目录名。
///
/// 与 assets 中的 `lib/python3.14/` 对应；升级内置 Python 时同步修改，
/// 以便识别出「已释放的是旧版本」并重新释放。
const String bundledPythonVersionDir = 'python3.14';

/// 从 Flutter assets 释放内置 Python 运行时（默认实现）。
///
/// 为什么必须「释放」而不是直接执行 assets 里的文件：
/// Android 的 assets 位于 APK 内部，没有真实文件路径，也无法设置可执行位。
/// 标准库必须复制到应用私有目录（**读取不受限**），
/// 而可执行文件必须走原生库目录（Android 10 起禁止从数据目录执行文件）。
///
/// 资产布局（由打包流程决定，见 README「内置 Python 运行时」）：
/// ```
/// assets/python/arm64-v8a/lib/python3.14/…      # 标准库（含 ABI 相关的 lib-dynload）
/// ```
Future<void> rootBundleAssetExtractor(Directory pythonRoot, String? abi) async {
  // 顺序即优先级：优先设备实际 ABI，其次常见 ABI，最后不带 ABI 的通用目录。
  final candidates = <String>[
    if (abi != null && abi.isNotEmpty) abi,
    'arm64-v8a',
    'armeabi-v7a',
    'x86_64',
    '',
  ];

  try {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final allKeys = manifest.listAssets();

    for (final candidate in candidates) {
      final prefix = candidate.isEmpty ? 'assets/python/' : 'assets/python/$candidate/';
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

      AppLogger.info(
        '已释放内置 Python 运行时（$prefix，${keys.length} 个文件）',
        tag: 'plugin',
      );
      return;
    }
  } catch (error) {
    // 没有内置资源属于正常情况（例如未打包运行时的构建），因此不算错误。
    AppLogger.info('未发现内置 Python 资源：$error', tag: 'plugin');
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
  PluginRuntime._({required this.capability, this.bundled});

  /// 当前平台能力。
  final PluginRuntimeCapability capability;

  /// 内置运行时（使用内置方案时非空）。
  ///
  /// 非空时 [startProcess] 会注入 `PYTHONHOME` 与 `LD_LIBRARY_PATH` ——
  /// 少了这两个变量，官方的 `libpython3.14.so` 既找不到标准库，
  /// 也找不到同目录下的 libcrypto / libssl / libsqlite3。
  final BundledPythonRuntime? bundled;

  /// 探测当前平台是否可以运行 Python 插件。
  ///
  /// 探测顺序（**先内置，后系统**）：
  /// 1. 原生库目录里的启动器 `libpylauncher.so` + 已释放的标准库（Android 首选）；
  /// 2. assets 中自带的可执行解释器 `python3`（桌面或自带运行时的构建）；
  /// 3. 系统 PATH 中的 `python3` / `python`（桌面平台走这条）。
  ///
  /// 这样做的意义：Android 系统**不内置 Python**，`Process.start('python3')`
  /// 在真机上必然失败。要让 Android 上真正可用，必须把运行时随包分发。
  static Future<PluginRuntime> probe({
    PluginAssetExtractor? assetExtractor,
    Directory? filesDirectory,
    Future<String?> Function()? nativeDirectoryProvider,
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

    // ── ① 内置运行时 ──
    final bundled = await _resolveBundledRuntime(
      assetExtractor: assetExtractor,
      filesDirectory: filesDirectory,
      nativeDirectoryProvider: nativeDirectoryProvider,
    );
    if (bundled != null) {
      AppLogger.info('使用内置 Python：${bundled.executable}', tag: 'plugin');
      return PluginRuntime._(
        capability: PluginRuntimeCapability.available(
          platform: platform,
          pythonExecutable: bundled.executable,
        ),
        bundled: bundled,
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
            ? '未检测到内置 Python 运行时。本应用应在 APK 中内置官方 Android 版 '
                'CPython；出现此提示说明构建产物不完整，或设备架构不在打包范围内'
                '（当前仅内置 arm64-v8a）。'
            : '未在系统中找到可用的 Python 解释器（已尝试 python3 / python），'
                '请先安装 Python 3 后重启应用。',
      ),
    );
  }

  /// 候选可执行文件名。
  static const List<String> _pythonCandidates = ['python3', 'python'];

  /// 解析内置运行时。
  ///
  /// 释放标准库与定位可执行文件是两个独立的动作：
  /// 标准库放在**应用私有目录**（只读即可，Android 不限制读取），
  /// 可执行文件放在**原生库目录**（Android 10 起禁止从数据目录执行文件）。
  static Future<BundledPythonRuntime?> _resolveBundledRuntime({
    PluginAssetExtractor? assetExtractor,
    Directory? filesDirectory,
    Future<String?> Function()? nativeDirectoryProvider,
  }) async {
    try {
      final base = filesDirectory ?? await getApplicationSupportDirectory();
      final root = Directory('${base.path}${Platform.pathSeparator}python');

      // 原生库目录的末级目录名就是设备的 ABI，用它挑对应的 assets 目录。
      String? abi = Platform.isAndroid ? 'arm64-v8a' : null;
      String? nativeDir;
      if (nativeDirectoryProvider != null) {
        final resolved = await nativeDirectoryProvider();
        if (resolved != null && resolved.isNotEmpty) {
          nativeDir = resolved;
          final name = p.basename(resolved);
          if (name.isNotEmpty) abi = name;
        }
      }

      // 标准库只需释放一次。
      //
      // 不设标记的话每次冷启动都要重写 600 多个文件——那是几百毫秒到数秒的
      // 纯 IO，用户会感知为「打开应用特别卡」。
      final stdlibMarker = File(
        '${root.path}${Platform.pathSeparator}lib'
        '${Platform.pathSeparator}$bundledPythonVersionDir'
        '${Platform.pathSeparator}os.py',
      );

      Future<void> ensureExtracted() async {
        if (stdlibMarker.existsSync()) return;
        final extractor = assetExtractor ?? rootBundleAssetExtractor;
        await extractor(root, abi);
      }

      // ── 方案 A：原生库目录里的启动器（Android 内置方案） ──
      //
      // 这里**只检查启动器是否存在，不在这里释放标准库**：
      // 探测发生在应用启动流程中，而释放要写 600 多个文件，
      // 放在这里会让首次启动白屏数秒。真正的释放推迟到启动插件时
      // （见 ensureExtracted）。
      if (nativeDir != null) {
        final launcher = File(
          '$nativeDir${Platform.pathSeparator}libpylauncher.so',
        );
        if (launcher.existsSync()) {
          return BundledPythonRuntime(
            executable: launcher.path,
            environment: {
              'PYTHONHOME': root.path,
              'LD_LIBRARY_PATH': nativeDir,
            },
            ensureExtracted: ensureExtracted,
          );
        }
      }

      // ── 方案 B：assets 里直接带了可执行解释器 ──
      //
      // 这条路必须先释放才能判断解释器是否存在，因此在这里就释放。
      await ensureExtracted();
      final direct = File('${root.path}${Platform.pathSeparator}python3');
      if (direct.existsSync()) {
        // 赋予可执行位。失败时返回 null —— 没有执行位的文件交给
        // Process.start 只会得到一个难以理解的 errno。
        final chmod = await Process.run('chmod', ['755', direct.path]);
        if (chmod.exitCode != 0) {
          AppLogger.warn('内置解释器 chmod 失败：${chmod.stderr}', tag: 'plugin');
          return null;
        }
        return BundledPythonRuntime(
          executable: direct.path,
          environment: {'PYTHONHOME': root.path},
          ensureExtracted: ensureExtracted,
        );
      }

      return null;
    } catch (error) {
      AppLogger.warn('内置运行时解析失败：$error', tag: 'plugin');
      return null;
    }
  }

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

    // 内置运行时：先把标准库释放出来（首次启动一个插件时会花一点时间）。
    await bundled?.ensureExtracted();

    // 入口路径必须**留在插件目录内**。
    //
    // `plugin.json` 是插件包里的文件，`entry` 完全可以被写成
    // `../../main.py` 或一个绝对路径。不校验就等于允许插件包指定
    // 「执行本目录之外的任意 Python 文件」——那是把信任边界直接交了出去。
    final entryPath = _resolveEntry(directory, manifest.entry);
    if (entryPath == null) {
      onDiagnostic('入口路径不合法（必须是插件目录内的相对路径）：${manifest.entry}');
      return null;
    }
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
          // 内置运行时需要 PYTHONHOME 与 LD_LIBRARY_PATH，见 BundledPythonRuntime。
          ...?bundled?.environment,
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

  /// 把 `entry` 解析为插件目录内的绝对路径；越界返回 `null`。
  ///
  /// 拒绝三类输入：绝对路径、含 `..` 的相对路径、以及规范化之后
  /// 仍不在插件目录内的路径。这是「插件包不能指定执行目录外文件」的唯一保障。
  static String? _resolveEntry(String directory, String entry) {
    final trimmed = entry.trim();
    if (trimmed.isEmpty) return null;
    final normalized = p.normalize(trimmed.replaceAll('\\', '/'));
    if (p.isAbsolute(normalized)) return null;
    if (normalized == '.' || normalized.startsWith('..')) return null;
    final root = p.normalize(directory);
    final full = p.normalize(p.join(root, normalized));
    if (!p.isWithin(root, full)) return null;
    return full;
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

  /// 立刻强杀进程（用于握手超时与判定卡死的场景）。
  ///
  /// 与 [stop] 的区别：不发 `shutdown`、不等宽限期。卡死的插件根本处理不了
  /// `shutdown`，等它只是白等三秒，而它在此期间仍占着内存并继续堆积输入。
  void kill() {
    if (_stopping) return;
    _stopping = true;
    try {
      _process.kill(ProcessSignal.sigkill);
    } catch (error) {
      AppLogger.warn('强杀插件进程失败：$error', tag: 'plugin');
    }
  }

  /// 优雅停止（先发 shutdown，再等待，最后强杀）。
  Future<void> stop({Duration grace = const Duration(seconds: 3)}) async {
    if (_stopping) return;

    // **必须先发 shutdown 再把 _stopping 置位。**
    //
    // 早期版本反过来写，而 [send] 会检查 `_stopping` 并直接返回——
    // 于是这条优雅停止消息被自己丢掉了，插件永远收不到 shutdown，
    // 每次停止都只能等满 3 秒宽限期再 SIGKILL。
    // 这里直接写 stdin 而不是走 [send]，就是为了不再依赖那个标志位的时序。
    try {
      _process.stdin.writeln(
        const PluginMessage(type: PluginMessageType.shutdown).toLine(),
      );
      await _process.stdin.flush();
    } catch (_) {
      // 忽略：进程可能已经退出。
    }

    _stopping = true;
    try {
      _process.stdin.close();
    } catch (_) {
      // 同上。
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
