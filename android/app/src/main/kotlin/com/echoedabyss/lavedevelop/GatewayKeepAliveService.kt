package com.echoedabyss.lavedevelop

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log

/**
 * 网关长连接的保活前台服务。
 *
 * ## 为什么必须有它
 *
 * 本应用的全部功能都挂在一条 WSS 长连接上，而心跳必须由**本进程**按周期发出。
 * 应用退到后台后进程进入 cached 状态，Android 的 **cached apps freezer**
 * 会在进入 cached 状态约 10 秒后冻结该进程——被冻结时 Dart 的定时器不再触发，
 * 心跳停发，服务端随即关闭连接。
 *
 * 这与日志里观察到的现象吻合：连接存活时间总是几十秒到两分钟
 * （约 1~3 个心跳周期 41.25 秒），关闭码是 WSS 层的 1002，
 * 且断连时应用正好处于后台。
 *
 * 官方给出的解药就是把进程**移出 cached 状态**：前台服务的进程属于
 * 「可见进程」，不会被冻结。Dart 侧无法自行改变进程优先级，
 * 因此必须由原生侧起一个真正的前台服务（只 `startService` 不算，
 * 必须走 `startForeground`）。
 *
 * ## 为什么不选 dataSync 作为主类型
 *
 * Android 15 起 `dataSync` 类型的前台服务在 24 小时内累计只能跑 6 小时，
 * 到点系统会调用超时回调并要求停服，之后除非用户把应用切回前台，
 * 否则无法再次启动——对「应当 24 小时在线」的机器人客户端是致命的。
 * `specialUse` 没有时长限制，因此 API 34+ 优先用它；
 * `dataSync` 只作为 API 29~33 的兜底（那时还没有 specialUse 这个类型）。
 *
 * ## 为什么还要 WakeLock
 *
 * 前台服务只改变进程优先级，**不会**阻止设备息屏后 CPU 停止调度。
 * 心跳是定时任务，没有 CPU 就发不出去，因此额外持一把 `PARTIAL_WAKE_LOCK`。
 * 注意低电耗模式（Doze）会忽略唤醒锁，彻底解决需要用户把应用加入
 * 电池优化白名单——这一步只能由用户手动完成，应用侧只提供跳转入口。
 */
class GatewayKeepAliveService : Service() {

    companion object {
        private const val TAG = "LaveKeepAlive"
        private const val CHANNEL_ID = "lave_gateway"
        private const val CHANNEL_NAME = "网关连接保活"
        private const val NOTIFICATION_ID = 10086
        private const val DEFAULT_TEXT = "正在维持网关长连接"

        private const val ACTION_START = "com.echoedabyss.lavedevelop.KEEPALIVE_START"
        private const val ACTION_UPDATE = "com.echoedabyss.lavedevelop.KEEPALIVE_UPDATE"
        private const val ACTION_STOP = "com.echoedabyss.lavedevelop.KEEPALIVE_STOP"
        private const val EXTRA_TEXT = "text"

        /**
         * 服务当前是否以前台服务形态运行。
         *
         * 只用于让界面区分「用户希望保活」与「保活真的生效了」——
         * 两者会因为通知权限缺失、后台启动被拒等原因不一致。
         */
        @Volatile
        var isRunning: Boolean = false
            private set

        /** 启动或更新文案。 */
        fun start(context: Context, text: String) = dispatch(context, ACTION_START, text)

        /** 只更新通知文案，不重启服务。 */
        fun update(context: Context, text: String) = dispatch(context, ACTION_UPDATE, text)

        /** 停止保活。 */
        fun stop(context: Context) = dispatch(context, ACTION_STOP, null)

        private fun dispatch(context: Context, action: String, text: String?) {
            val intent = Intent(context, GatewayKeepAliveService::class.java).setAction(action)
            if (text != null) intent.putExtra(EXTRA_TEXT, text)
            try {
                if (action == ACTION_STOP) {
                    // 停止走 startService：不必承担「5 秒内必须 startForeground」的义务。
                    context.startService(intent)
                } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (error: Exception) {
                // 常见于应用处于后台时触发（Android 12+ 禁止后台启动前台服务）。
                // 不能把这里当致命错误：Dart 侧在应用回到前台后会重新请求启动。
                Log.w(TAG, "请求启动保活服务失败：$error")
            }
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var currentText: String = DEFAULT_TEXT

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        ensureChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            releaseWakeLock()
            stopForegroundCompat()
            stopSelf()
            return START_NOT_STICKY
        }

        intent?.getStringExtra(EXTRA_TEXT)?.let { if (it.isNotBlank()) currentText = it }

        // 先进入前台：这样无论后续哪一步失败，进程都已经脱离 cached 状态。
        promoteToForeground()
        acquireWakeLock()

        // START_STICKY：进程被系统回收后尽量把服务拉起来。
        // 这只是「尽力而为」——重启回来时是**普通后台服务**，
        // 而 Android 12 起禁止从后台启动前台服务，因此 promoteToForeground
        // 的失败不能当致命错误处理（见该方法的说明）。
        return START_STICKY
    }

    override fun onDestroy() {
        isRunning = false
        releaseWakeLock()
        super.onDestroy()
    }

    // ───────────────────────── 通知与前台状态 ─────────────────────────

    /**
     * 尝试进入前台。返回是否成功。
     *
     * 三级降级的原因：三种失败彼此独立（类型权限缺失、后台启动被拒、
     * 系统不支持带类型的重载），任何一步抛异常都不应让服务整体崩掉——
     * 服务本身还在运行，只是暂时没有前台优先级。
     */
    private fun promoteToForeground(): Boolean {
        val notification = buildNotification(currentText)

        if (Build.VERSION.SDK_INT >= 34) {
            if (attemptForeground("specialUse") {
                    startForeground(
                        NOTIFICATION_ID,
                        notification,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
                    )
                }
            ) {
                return true
            }
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            if (attemptForeground("dataSync") {
                    startForeground(
                        NOTIFICATION_ID,
                        notification,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
                    )
                }
            ) {
                return true
            }
        }

        // 最后兜底：不带类型的重载，使用清单里声明的类型。
        if (attemptForeground("清单默认类型") {
                startForeground(NOTIFICATION_ID, notification)
            }
        ) {
            return true
        }

        isRunning = false
        // 连前台都进不去时，至少把通知挂上，让用户知道后台有个服务在跑。
        try {
            getSystemService(NotificationManager::class.java)?.notify(NOTIFICATION_ID, notification)
        } catch (error: Exception) {
            Log.w(TAG, "发送通知失败：$error")
        }
        return false
    }

    private fun attemptForeground(label: String, block: () -> Unit): Boolean = try {
        block()
        isRunning = true
        Log.i(TAG, "已进入前台服务（$label）")
        true
    } catch (error: Exception) {
        Log.w(TAG, "以前台服务方式启动失败（$label）：$error")
        false
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    private fun buildNotification(text: String): Notification {
        val launch = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pending = PendingIntent.getActivity(
            this,
            0,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        return builder
            .setContentTitle("Lave 正在维持网关连接")
            .setContentText(text)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pending)
            .setOngoing(true)
            .setShowWhen(false)
            // 前台服务通知属于「持续状态」，用 LOW 让它静默，不打扰用户。
            .setPriority(Notification.PRIORITY_LOW)
            .build()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "维持机器人在线所需的常驻通知，可随时在应用内关闭保活"
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    // ───────────────────────── 唤醒锁 ─────────────────────────

    private fun acquireWakeLock() {
        if (wakeLock != null) return
        val manager = getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return
        val lock = manager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "$packageName:gateway",
        )
        // 不设超时：超时后系统会自动释放，而应用在后台期间没有人会去续期，
        // 结果是心跳悄悄停发。服务的生命周期就是这把锁的生命周期。
        lock.setReferenceCounted(false)
        try {
            lock.acquire()
            wakeLock = lock
        } catch (error: Exception) {
            Log.w(TAG, "获取唤醒锁失败：$error")
        }
    }

    private fun releaseWakeLock() {
        val lock = wakeLock ?: return
        wakeLock = null
        try {
            if (lock.isHeld) lock.release()
        } catch (error: Exception) {
            Log.w(TAG, "释放唤醒锁失败：$error")
        }
    }
}
