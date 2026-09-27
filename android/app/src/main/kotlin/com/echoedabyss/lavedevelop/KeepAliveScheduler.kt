package com.echoedabyss.lavedevelop

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.util.Log

/**
 * 保活相关的系统调度：开机自启、看门狗闹钟、被划掉任务后的拉起。
 *
 * ## 为什么这些手段是必要的
 *
 * 前台服务解决的是「进程被 cached apps freezer 冻结」，但它并不保证进程不被杀。
 * Android 12（API 31）起「禁止从后台启动前台服务」生效，因此**任何自动拉起都必须
 * 落在官方豁免清单内**，否则 `startForegroundService` 会直接抛
 * `ForegroundServiceStartNotAllowedException`。官方豁免清单里与本项目相关的三条是：
 *
 * 1. 收到 `ACTION_BOOT_COMPLETED` / `ACTION_LOCKED_BOOT_COMPLETED` /
 *    `ACTION_MY_PACKAGE_REPLACED` 广播；
 * 2. **精确闹钟**（exact alarm）到点；
 * 3. 用户为应用关闭了电池优化。
 *
 * 注意 JobScheduler **不在**豁免清单内 —— 它是常见的误解，
 * 作业执行期间系统给的临时许可名单并不覆盖「启动前台服务」这件事。
 *
 * ## 各手段的实际效力（务必照实告知使用者）
 *
 * | 场景 | 能否自动恢复 |
 * | --- | --- |
 * | 系统因内存压力回收进程 | 能（START_STICKY + 看门狗闹钟） |
 * | 用户从最近任务里划掉应用 | 能（`onTaskRemoved` + 精确闹钟拉起） |
 * | 手机重启 | 能（开机广播） |
 * | 应用被「强行停止」 | **不能**。应用进入 stopped 状态，
 *   清单广播与显式广播都不会再送达，只能由用户重新打开应用 |
 * | 用户在任务管理器里点「停止」 | **不能**（同上，且系统会移除整个应用） |
 *
 * 最后两行不是实现缺陷，是 Android 的既定行为，任何应用都无法绕过。
 */
internal object KeepAliveScheduler {

    private const val TAG = "LaveKeepAlive"

    /** 重启服务用的闹钟动作（显式广播给本项目自己的接收器）。 */
    const val ACTION_RESTART = "com.echoedabyss.lavedevelop.KEEPALIVE_RESTART"

    /** 周期性看门狗动作。 */
    const val ACTION_WATCHDOG = "com.echoedabyss.lavedevelop.KEEPALIVE_WATCHDOG"

    private const val PREFS = "lave_keep_alive"
    private const val KEY_ENABLED = "enabled"
    private const val KEY_TEXT = "last_text"

    private const val REQUEST_RESTART = 1001
    private const val REQUEST_WATCHDOG = 1002

    /**
     * 看门狗周期。
     *
     * 取 15 分钟：精确闹钟在低电耗模式（Doze）下最快也只能约 9~15 分钟响一次，
     * 比这更短的周期不会真的更频繁，只会多耗电。
     */
    private const val WATCHDOG_INTERVAL_MS = 15L * 60L * 1000L

    /** 划掉任务后延迟拉起的时间，留一点余量让系统先完成清理。 */
    private const val RESTART_DELAY_MS = 1500L

    // ───────────────────────── 开关状态 ─────────────────────────

    /**
     * 记录用户的保活意图。
     *
     * 必须存在原生侧：开机广播到达时 Flutter 引擎还没起来，
     * 读不到 Dart 那边存在 JSON 文件里的开关，只能靠这份轻量记录判断
     * 「用户本来是开着保活的」。
     */
    fun setEnabled(context: Context, enabled: Boolean, text: String?) {
        val editor = prefs(context).edit().putBoolean(KEY_ENABLED, enabled)
        if (text != null) editor.putString(KEY_TEXT, text)
        editor.apply()
    }

    fun isEnabled(context: Context): Boolean =
        prefs(context).getBoolean(KEY_ENABLED, false)

    fun lastText(context: Context): String? =
        prefs(context).getString(KEY_TEXT, null)

    // ───────────────────────── 拉起服务 ─────────────────────────

    /**
     * 若用户开着保活，就把前台服务拉起来。
     *
     * 由开机广播、看门狗闹钟、划掉任务后的重启闹钟共同调用。
     * 启动失败（例如当前处于后台且不满足豁免）只记日志：
     * 下一次闹钟或用户切回前台时还会再试，不必打扰用户。
     */
    fun startServiceIfEnabled(context: Context) {
        if (!isEnabled(context)) return
        try {
            GatewayKeepAliveService.start(
                context,
                lastText(context) ?: "正在维持网关长连接",
            )
        } catch (error: Exception) {
            Log.w(TAG, "自动拉起保活服务失败：$error")
        }
    }

    // ───────────────────────── 闹钟 ─────────────────────────

    /** 安排（或重排）周期性看门狗。 */
    fun scheduleWatchdog(context: Context) {
        setAlarm(
            context = context,
            action = ACTION_WATCHDOG,
            requestCode = REQUEST_WATCHDOG,
            triggerAtMs = System.currentTimeMillis() + WATCHDOG_INTERVAL_MS,
        )
    }

    /** 安排一次性的重启闹钟（用于划掉任务、服务被销毁后拉起）。 */
    fun scheduleRestart(context: Context, delayMs: Long = RESTART_DELAY_MS) {
        setAlarm(
            context = context,
            action = ACTION_RESTART,
            requestCode = REQUEST_RESTART,
            triggerAtMs = System.currentTimeMillis() + delayMs,
        )
    }

    /** 撤销全部保活闹钟（用户关闭保活时调用）。 */
    fun cancelAll(context: Context) {
        val manager = context.getSystemService(AlarmManager::class.java) ?: return
        for ((action, code) in listOf(
            ACTION_WATCHDOG to REQUEST_WATCHDOG,
            ACTION_RESTART to REQUEST_RESTART,
        )) {
            manager.cancel(pendingIntent(context, action, code))
        }
    }

    private fun setAlarm(
        context: Context,
        action: String,
        requestCode: Int,
        triggerAtMs: Long,
    ) {
        val manager = context.getSystemService(AlarmManager::class.java) ?: return
        val pending = pendingIntent(context, action, requestCode)

        // 优先精确闹钟：它是官方豁免清单里唯一「凭它能从后台启动前台服务」的
        // 定时手段。拿不到 SCHEDULE_EXACT_ALARM 时退回不精确闹钟——
        // 仍然会响，但系统会按省电策略推迟，因此不能指望它准时。
        val exact = canScheduleExactAlarms(context)
        try {
            if (exact) {
                manager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    triggerAtMs,
                    pending,
                )
            } else {
                manager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    triggerAtMs,
                    pending,
                )
            }
        } catch (error: SecurityException) {
            // 权限在运行中被用户撤销时会走到这里。
            Log.w(TAG, "设置精确闹钟被拒，退回不精确闹钟：$error")
            try {
                manager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    triggerAtMs,
                    pending,
                )
            } catch (inner: Exception) {
                Log.w(TAG, "设置闹钟失败：$inner")
            }
        }
    }

    private fun pendingIntent(
        context: Context,
        action: String,
        requestCode: Int,
    ): PendingIntent {
        val intent = Intent(context, KeepAliveAlarmReceiver::class.java).setAction(action)
        return PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    // ───────────────────────── 精确闹钟权限 ─────────────────────────

    /**
     * 是否已获得精确闹钟权限。
     *
     * Android 14（API 34）起，以 33+ 为目标的新安装应用**默认被拒绝**该权限，
     * 必须由用户在系统设置里手动开启；未授权时 `setExact*` 会抛 `SecurityException`。
     */
    fun canScheduleExactAlarms(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        val manager = context.getSystemService(AlarmManager::class.java) ?: return false
        return manager.canScheduleExactAlarms()
    }

    /**
     * 打开系统的「闹钟和提醒」授权页，让用户为本应用开启精确闹钟。
     *
     * 用 `ACTION_REQUEST_SCHEDULE_EXACT_ALARM` 直接跳到本应用的授权项，
     * 而不是让用户自己去设置里翻。该动作只是跳转，不申请任何额外权限。
     */
    fun openExactAlarmSettings(context: Context) {
        val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
            .setData(android.net.Uri.fromParts("package", context.packageName, null))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            context.startActivity(intent)
        } catch (_: Exception) {
            // 少数 ROM 没有这个页面，退回应用的详情页。
            try {
                context.startActivity(
                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                        .setData(
                            android.net.Uri.fromParts("package", context.packageName, null),
                        )
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
            } catch (error: Exception) {
                Log.w(TAG, "打开精确闹钟设置失败：$error")
            }
        }
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
