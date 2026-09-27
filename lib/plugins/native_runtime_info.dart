import 'package:flutter/services.dart';

import '../core/logging/app_logger.dart';

/// 平台原生信息通道。
///
/// 目前只暴露一件事：**安装后的原生库目录绝对路径**。
///
/// 这个路径无法在 Dart 侧推算（含安装时生成的哈希，
/// 形如 `/data/app/~~<hash>/<pkg>-<hash>/lib/arm64-v8a`），
/// 但它是内置 Python 能运行的前提：
///
/// - 可执行启动器 `libpylauncher.so` 与运行时 `libpython3.14.so` 都放在这里；
///   Android 10 起禁止从应用可写数据目录执行文件，原生库目录是唯一可执行落点；
/// - 该目录同时要作为子进程的 `LD_LIBRARY_PATH`。
///
/// 非 Android 平台返回 `null`（桌面平台直接使用系统 Python，不需要这条路径）。
class NativeRuntimeInfo {
  NativeRuntimeInfo({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('lave/native');

  final MethodChannel _channel;

  String? _cachedNativeLibraryDir;
  bool _queried = false;

  /// 取原生库目录；不可用时返回 `null`。
  ///
  /// 结果会缓存：该路径在应用生命周期内不变，而它每次都要走一次平台通道。
  Future<String?> nativeLibraryDir() async {
    if (_queried) return _cachedNativeLibraryDir;
    _queried = true;
    try {
      final result = await _channel.invokeMethod<String>('nativeLibraryDir');
      _cachedNativeLibraryDir = (result == null || result.isEmpty) ? null : result;
    } on MissingPluginException {
      // 非 Android 平台（或未注册通道）属正常情况，不是错误。
      _cachedNativeLibraryDir = null;
    } catch (error) {
      // 通道异常不应导致插件功能整体不可用：返回 null 会退回到
      // 「从 assets 释放解释器」与「系统 Python」两条备选路径。
      AppLogger.warn('获取原生库目录失败：$error', tag: 'plugin');
      _cachedNativeLibraryDir = null;
    }
    if (_cachedNativeLibraryDir != null) {
      AppLogger.info('原生库目录：$_cachedNativeLibraryDir', tag: 'plugin');
    }
    return _cachedNativeLibraryDir;
  }
}
