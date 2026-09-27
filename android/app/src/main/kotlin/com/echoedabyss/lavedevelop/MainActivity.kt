package com.echoedabyss.lavedevelop

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 主 Activity。
 *
 * 除承载 Flutter 之外，只额外暴露一件事：**原生库目录的绝对路径**。
 *
 * 为什么 Dart 侧拿不到它：该路径形如
 * `/data/app/~~<hash>/<pkg>-<hash>/lib/arm64-v8a`，其中的哈希由安装过程决定，
 * 应用无法自行推算。而它恰恰是内置 Python 的关键——
 *
 * 1. `libpylauncher.so`（可执行的 Python 启动器）与 `libpython3.14.so`
 *    都随 APK 放在这个目录里。Android 10 起禁止从应用可写数据目录执行文件，
 *    安装后的原生库目录是唯一可执行的落点；
 * 2. 该目录还要设为 `LD_LIBRARY_PATH`，否则启动器找不到 `libpython3.14.so`
 *    以及它依赖的 libcrypto / libssl / libsqlite3。
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "lave/native",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "nativeLibraryDir" -> result.success(applicationInfo.nativeLibraryDir)
                else -> result.notImplemented()
            }
        }
    }
}
