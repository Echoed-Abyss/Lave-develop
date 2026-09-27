package com.echoedabyss.lavedevelop

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 主 Activity。
 *
 * 除承载 Flutter 之外，还通过 `lave/native` 通道暴露两件事：
 *
 * 1. **原生库目录的绝对路径**。
 *    该路径形如 `/data/app/~~<hash>/<pkg>-<hash>/lib/arm64-v8a`，其中的哈希由
 *    安装过程决定，应用无法自行推算。而它恰恰是内置 Python 的关键——
 *    `libpylauncher.so` 与 `libpython3.14.so` 都随 APK 放在这个目录里，
 *    Android 10 起禁止从应用可写数据目录执行文件，安装后的原生库目录
 *    是唯一可执行的落点；该目录还要设为 `LD_LIBRARY_PATH`。
 *
 * 2. **网关保活前台服务的开关**，以及保活所需的两个系统能力
 *    （通知权限、电池优化白名单）。详细理由见 [GatewayKeepAliveService]。
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "lave/native"

        /** 通知权限请求码，任意值即可，只要不与其它请求冲突。 */
        private const val REQUEST_NOTIFICATION = 0x1A01

        private const val DEFAULT_KEEP_ALIVE_TEXT = "正在维持网关长连接"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "nativeLibraryDir" ->
                    result.success(applicationInfo.nativeLibraryDir)

                // ── 网关保活 ──────────────────────────────────────────────
                "keepAliveStart" -> {
                    GatewayKeepAliveService.start(this, keepAliveText(call))
                    result.success(true)
                }

                "keepAliveUpdate" -> {
                    GatewayKeepAliveService.update(this, keepAliveText(call))
                    result.success(true)
                }

                "keepAliveStop" -> {
                    GatewayKeepAliveService.stop(this)
                    result.success(true)
                }

                "keepAliveIsRunning" ->
                    result.success(GatewayKeepAliveService.isRunning)

                // ── 保活的系统前提 ────────────────────────────────────────
                "requestNotificationPermission" -> {
                    requestNotificationPermission()
                    // 授权结果是异步的，这里只表示「已发起请求」。
                    // 前台服务本身不依赖该权限（未授权只是不显示通知），
                    // 因此调用方不需要等待结果。
                    result.success(hasNotificationPermission())
                }

                "isIgnoringBatteryOptimizations" ->
                    result.success(isIgnoringBatteryOptimizations())

                "openBatteryOptimizationSettings" -> {
                    openBatteryOptimizationSettings()
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun keepAliveText(call: MethodCall): String =
        call.argument<String>("text")?.takeIf { it.isNotBlank() } ?: DEFAULT_KEEP_ALIVE_TEXT

    private fun hasNotificationPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (hasNotificationPermission()) return
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            REQUEST_NOTIFICATION,
        )
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val manager = getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return true
        return manager.isIgnoringBatteryOptimizations(packageName)
    }

    /**
     * 打开系统的「电池优化」列表，由用户自行把本应用加入白名单。
     *
     * 刻意**不用** `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` 直接弹窗：
     * 那个动作需要在清单里声明 `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`，
     * 而官方对该权限的用途限制很严——只有「低电耗模式破坏了应用核心功能，
     * 且技术上无法改用 FCM」才被接受，正例里明确写着即时通讯类应当用 FCM。
     * 本项目是自建长连接且不上架应用商店，但没必要为此背上一个受限权限。
     */
    private fun openBatteryOptimizationSettings() {
        val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
        try {
            startActivity(intent)
        } catch (_: Exception) {
            // 少数 ROM 没有这个设置页，退回应用详情页，至少让用户能手动设置。
            startActivity(
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                    .setData(android.net.Uri.fromParts("package", packageName, null)),
            )
        }
    }
}
