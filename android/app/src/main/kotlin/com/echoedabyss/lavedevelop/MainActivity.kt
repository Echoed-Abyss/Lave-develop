package com.echoedabyss.lavedevelop

import android.Manifest
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference

/**
 * 主 Activity。
 *
 * 除承载 Flutter 之外，还通过 `lave/native` 通道暴露三件事：
 *
 * 1. **原生库目录的绝对路径**。
 *    该路径形如 `/data/app/~~<hash>/<pkg>-<hash>/lib/arm64-v8a`，其中的哈希由
 *    安装过程决定，应用无法自行推算。而它恰恰是内置 Python 的关键——
 *    `libpylauncher.so` 与 `libpython3.14.so` 都随 APK 放在这个目录里，
 *    Android 10 起禁止从应用可写数据目录执行文件，安装后的原生库目录
 *    是唯一可执行的落点；该目录还要设为 `LD_LIBRARY_PATH`。
 *
 * 2. **网关保活前台服务的开关**，以及保活所需的三个系统能力
 *    （通知权限、电池优化白名单、精确闹钟）。详细理由见 [GatewayKeepAliveService]。
 *
 * 3. **保活诊断快照**。把「前台服务到底有没有真的在跑、跑的是哪种类型、
 *    有没有被 Doze 限制」如实回报给界面——否则用户只能看到「开关是开的、
 *    机器人就是不在线」，完全无从下手。
 *
 * ## 为什么要持有长期存活的 FlutterEngine
 *
 * 本应用的全部业务都跑在 Dart 侧的那条 WSS 长连接上，而 Dart 代码活在
 * `FlutterEngine` 里。**默认情况下引擎与 Activity 同生共死**：
 * `FlutterActivity` 被销毁时会把引擎一起销毁，Dart 的 `main()` 随之结束、
 * 定时器全部停止、socket 被关闭。
 *
 * 这在「应用应当 24 小时在线」的场景下是致命的：用户从最近任务划掉应用、
 * 或系统在内存紧张时回收 Activity，都会让引擎连同连接一起消失——
 * 而保活前台服务此时还活着，进程也还活着，只有 Dart 死了。
 * 表现就是「只要程序不在前台，WSS 就断连」。
 *
 * 因此这里做两件事：
 * - `provideFlutterEngine` 返回**同一个**引擎实例（首次创建后一直复用）；
 * - `shouldDestroyEngineWithHost()` 返回 `false`，Activity 销毁时不动引擎。
 *
 * 于是 Activity 退出后 Dart 继续运行、心跳继续发送、连接保持，
 * 保活前台服务则保证进程不被系统冻结。用户重新打开应用时，
 * 引擎被重新 Attach 到新 Activity，界面直接接上仍在运行的连接。
 *
 * 代价与边界（必须如实说明）：这样一来「退出应用」不再等于「停止机器人」。
 * 想要真正停下来，必须关掉「后台保活」开关，或在常驻通知上点「停止」。
 * 这是「保活」这个功能本身的含义，界面与文档都已按此描述。
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "lave/native"

        /** 通知权限请求码，任意值即可，只要不与其它请求冲突。 */
        private const val REQUEST_NOTIFICATION = 0x1A01

        private const val DEFAULT_KEEP_ALIVE_TEXT = "正在维持网关长连接"

        /**
         * 全程复用的 Flutter 引擎。
         *
         * 用 `@Volatile`：它会同时被主线程与（可能的）其它线程读取。
         */
        @Volatile
        private var cachedEngine: FlutterEngine? = null

        /**
         * 通道是否已注册。
         *
         * **必须去重**：`configureFlutterEngine` 在 Activity 每次重建时都会被调用，
         * 而 `setMethodCallHandler` 是「覆盖式」的——重复注册虽然不会报错，
         * 但会不断创建新的闭包。更关键的是它必须只做一次，
         * 因为复用引擎时 Dart 侧的 `MethodChannel` 已经建立，重复注册没有意义。
         */
        @Volatile
        private var channelRegistered = false

        /**
         * 当前处于前台的 Activity。
         *
         * 用弱引用而不是强引用：引擎生命周期长于 Activity，强引用会把已销毁的
         * Activity（及其整棵 View 树）一直留在内存里。
         *
         * 有些操作（申请运行时权限、弹系统授权页）**必须**有 Activity，
         * 引擎存活期间 Activity 可能为空，这些调用要能优雅降级。
         */
        private var currentActivity: WeakReference<MainActivity>? = null

        /** 取当前可用的 Activity；已进入销毁流程的视为不可用。 */
        fun activityOrNull(): MainActivity? {
            val activity = currentActivity?.get() ?: return null
            return if (activity.isFinishing) null else activity
        }
    }

    override fun provideFlutterEngine(context: Context): FlutterEngine {
        cachedEngine?.let { return it }

        // 用 applicationContext 构造：引擎会比 Activity 活得更久，
        // 持有 Activity 的 Context 会泄漏一整个 Activity。
        val engine = FlutterEngine(context.applicationContext)
        // 复用引擎时必须自己启动 Dart 入口：默认实现只在「由框架创建引擎」时
        // 才会执行 `main()`，手工创建的引擎不启动入口点就永远不会跑 Dart 代码。
        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        cachedEngine = engine
        return engine
    }

    /**
     * Activity 销毁时不销毁引擎。
     *
     * 这是「后台继续跑」的关键开关，理由见类注释。
     */
    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        currentActivity = WeakReference(this)
        super.onCreate(savedInstanceState)
    }

    override fun onResume() {
        super.onResume()
        currentActivity = WeakReference(this)
    }

    override fun onDestroy() {
        // 只在「这个 Activity 就是当前记录的那一个」时清空，
        // 避免「旧 Activity 销毁」把「新 Activity」的引用误清掉。
        if (activityOrNull() === this) currentActivity = null
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        if (channelRegistered) return
        channelRegistered = true

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
            // 处理器**不能捕获 Activity**：引擎比 Activity 活得久，
            // 捕获 `this` 会让所有用到 Activity 的分支在 Activity 销毁后崩掉，
            // 也会阻止 Activity 被回收。需要时用 activityOrNull() 现取。
            when (call.method) {
                "nativeLibraryDir" ->
                    result.success(applicationInfo.nativeLibraryDir)

                // ── 网关保活 ──────────────────────────────────────────────
                "keepAliveStart" -> {
                    GatewayKeepAliveService.start(applicationContext, keepAliveText(call))
                    result.success(true)
                }

                "keepAliveUpdate" -> {
                    GatewayKeepAliveService.update(applicationContext, keepAliveText(call))
                    result.success(true)
                }

                "keepAliveStop" -> {
                    GatewayKeepAliveService.stop(applicationContext)
                    result.success(true)
                }

                "keepAliveIsRunning" ->
                    result.success(GatewayKeepAliveService.isRunning)

                // ── 保活的系统前提 ────────────────────────────────────────
                "requestNotificationPermission" -> {
                    // 授权结果是异步的，这里只表示「已发起请求（或不需要）」。
                    // 前台服务本身不依赖该权限（未授权只是不显示通知），
                    // 因此调用方不需要等待用户的选择结果。
                    val activity = activityOrNull()
                    if (activity != null) requestNotificationPermission(activity)
                    result.success(hasNotificationPermission())
                }

                "isIgnoringBatteryOptimizations" ->
                    result.success(isIgnoringBatteryOptimizations())

                "openBatteryOptimizationSettings" -> {
                    openBatteryOptimizationSettings()
                    result.success(true)
                }

                // 直接弹「是否允许应用在后台运行」的系统对话框。
                // 与 openBatteryOptimizationSettings 的区别：后者只是打开列表页，
                // 要用户自己在几十个应用里找到本应用再手动改，绝大多数人不会做完。
                "requestIgnoreBatteryOptimizations" ->
                    result.success(requestIgnoreBatteryOptimizations())

                "canScheduleExactAlarms" ->
                    result.success(KeepAliveScheduler.canScheduleExactAlarms(applicationContext))

                "openExactAlarmSettings" -> {
                    KeepAliveScheduler.openExactAlarmSettings(applicationContext)
                    result.success(true)
                }

                "keepAliveStatus" ->
                    result.success(keepAliveStatus())

                else -> result.notImplemented()
            }
        }
    }

    private fun keepAliveText(call: MethodCall): String =
        call.argument<String>("text")?.takeIf { it.isNotBlank() } ?: DEFAULT_KEEP_ALIVE_TEXT

    /**
     * 保活诊断快照。
     *
     * 一次性返回界面需要的全部事实，避免多次跨通道往返。
     * 每一项都可能影响「后台是否真的在线」，缺了任何一项，
     * 排查时就只能靠猜。
     */
    private fun keepAliveStatus(): Map<String, Any?> = mapOf(
        // 前台服务是否真的以前台形态在跑（不是「用户开了开关」）。
        "running" to GatewayKeepAliveService.isRunning,
        // 实际生效的前台服务类型名（specialUse / dataSync / unknown）。
        // dataSync 在 Android 15+ 有 6 小时/24 小时上限，必须让用户看得见。
        "foregroundType" to GatewayKeepAliveService.foregroundTypeName,
        "ignoringBatteryOptimizations" to isIgnoringBatteryOptimizations(),
        "canScheduleExactAlarms" to KeepAliveScheduler.canScheduleExactAlarms(applicationContext),
        "notificationPermission" to hasNotificationPermission(),
        // 应用待机分桶。≥ 40（RARE）会限制网络访问，是「息屏久了掉线」的常见原因。
        "standbyBucket" to standbyBucket(),
        "sdkInt" to Build.VERSION.SDK_INT,
    )

    private fun hasNotificationPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun requestNotificationPermission(activity: MainActivity) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (hasNotificationPermission()) return
        activity.requestPermissions(
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
     * 弹系统的「允许应用在后台运行 / 忽略电池优化」对话框。
     *
     * 返回「当前是否已经在白名单里」（弹窗是异步的，返回值不代表用户的选择）。
     *
     * 为什么必须做这件事：**低电耗模式（Doze）会暂停应用的网络访问**，
     * 唤醒锁也一并被忽略。表现在日志里就是连接存活时间越来越短、
     * 息屏十几分钟后必断。加入白名单是唯一能解除这条限制的手段。
     */
    private fun requestIgnoreBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        if (isIgnoringBatteryOptimizations()) return true

        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
            .setData(Uri.fromParts("package", packageName, null))

        val activity = activityOrNull()
        return try {
            if (activity != null) {
                activity.startActivity(intent)
            } else {
                applicationContext.startActivity(
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
            }
            false
        } catch (error: Exception) {
            // 少数 ROM 没有该页面（或厂商改了行为），退回列表页，
            // 至少让用户能手动设置，而不是按下按钮毫无反应。
            Log.w("LaveKeepAlive", "申请忽略电池优化失败，退回设置列表：$error")
            openBatteryOptimizationSettings()
            false
        }
    }

    /**
     * 打开系统的「电池优化」列表，由用户自行把本应用加入白名单。
     *
     * 作为 [requestIgnoreBatteryOptimizations] 的兜底路径保留：
     * 直接弹窗需要清单里声明 `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`
     * （已声明，因为本应用是自建长连接、不上架应用商店），
     * 但个别 ROM 会拦截该动作，那时只能靠这个列表页。
     */
    private fun openBatteryOptimizationSettings() {
        val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
        val activity = activityOrNull()
        try {
            if (activity != null) {
                activity.startActivity(intent)
            } else {
                applicationContext.startActivity(
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
            }
        } catch (error: Exception) {
            Log.w("LaveKeepAlive", "打开电池优化设置失败：$error")
            val fallback = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.fromParts("package", packageName, null))
            try {
                if (activity != null) {
                    activity.startActivity(fallback)
                } else {
                    applicationContext.startActivity(
                        fallback.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                    )
                }
            } catch (inner: Exception) {
                Log.w("LaveKeepAlive", "打开应用详情页失败：$inner")
            }
        }
    }

    /**
     * 应用待机分桶（API 28+）。
     *
     * 取值 10=ACTIVE、20=WORKING_SET、30=FREQUENT、40=RARE、50=RESTRICTED。
     * 进入 RARE 及以上后系统会**限制应用的互联网连接**，
     * 因此这个数字是「后台为什么掉线」的关键证据之一。
     * 查询自己的分桶不需要任何权限。
     */
    private fun standbyBucket(): Int {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return -1
        val manager = getSystemService(UsageStatsManager::class.java) ?: return -1
        return try {
            manager.appStandbyBucket
        } catch (error: Exception) {
            Log.w("LaveKeepAlive", "查询待机分桶失败：$error")
            -1
        }
    }
}
