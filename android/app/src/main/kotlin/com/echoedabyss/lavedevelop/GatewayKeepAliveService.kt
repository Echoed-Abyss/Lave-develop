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
import androidx.annotation.RequiresApi

/**
 * 网关长连接的保活前台服务。
 *
 * ## 为什么必须有它
 *
 * 本应用的全部功能都挂在一条 WSS 长连接上，而心跳必须由**本进程**按周期发出。
 * 应用退到后台后进程进入 cached 状态，Android 的 **cached apps freezer**
 * 会在进入 cached 状态约 10 秒后冻结该进程——被冻结时 Dart 的定时器不再触发，
 * 心跳停发，服务端随即关闭连接（连接存活几十秒到两分钟，约 1~3 个心跳周期）。
 *
 * 官方给出的解药就是把进程**移出 cached 状态**：前台服务的进程属于
 * 「可见进程」，不会被冻结。Dart 侧无法自行改变进程优先级，
 * 因此必须由原生侧起一个真正的前台服务。
 *
 * ## 类型为什么是 specialUse
 *
 * Android 15 起 `dataSync` 类型的前台服务在 24 小时内累计只能跑 6 小时，
 * 到点系统会要求停服，之后除非用户把应用切回前台，否则无法再次启动——
 * 对「应当 24 小时在线」的机器人客户端是致命的。`specialUse` 没有时长限制，
 * 因此 API 34+ 用它；API 31~33 还没有 `specialUse` 类型，退回 `dataSync`。
 *
 * ## 通知能否被用户关掉（如实说明）
 *
 * - Android 12/13：`setOngoing(true)` 已足够，用户划不掉；
 * - **Android 14 起系统改了行为，`setOngoing(true)` 也挡不住用户划掉**
 *   （锁屏界面、「全部清除」等场景除外），这是官方行为变更，应用无法对抗。
 *   通知被划掉**不影响服务运行**，只是用户看不到在线状态了；
 * - 用户在系统里关闭通知渠道或拒绝通知权限，同样只是让通知不可见，服务照常运行；
 * - 真正会终结一切的是「强行停止」与任务管理器里的「停止」——
 *   应用会进入 stopped 状态，任何自动拉起（含开机广播）都会失效，
 *   只能由用户重新打开应用。详见 [KeepAliveScheduler] 的效力表。
 *
 * 本项目刻意**不**用 `CallStyle`（通话样式）或媒体通知来换取「通知不可关闭」：
 * 那是把连接伪装成来电，属于欺骗性 UI，代价是用户信任，不值得。
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

        /**
         * 实际生效的前台服务类型（[ServiceInfo] 的 `FOREGROUND_SERVICE_TYPE_*`）。
         *
         * 必须暴露出来：`specialUse` 与 `dataSync` 的后果完全不同——
         * 后者在 Android 15+ 有「每 24 小时累计 6 小时」的硬上限，
         * 到点会被系统强制停服。用户遇到「开机几小时后掉线」时，
         * 这个字段是唯一能直接定性的证据。
         */
        @Volatile
        var foregroundType: Int = 0
            private set

        /** 供界面直接显示的类型名。 */
        val foregroundTypeName: String
            get() = when (foregroundType) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE -> "specialUse"
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC -> "dataSync"
                0 -> "unknown"
                else -> "other($foregroundType)"
            }

        /** 启动或更新文案。 */
        fun start(context: Context, text: String) = dispatch(context, ACTION_START, text)

        /** 只更新通知文案，不重启服务。 */
        fun update(context: Context, text: String) = dispatch(context, ACTION_UPDATE, text)

        /** 停止保活（用户主动关闭，会同时撤掉看门狗闹钟）。 */
        fun stop(context: Context) = dispatch(context, ACTION_STOP, null)

        private fun dispatch(context: Context, action: String, text: String?) {
            // 先把开关记进原生侧：开机广播到达时 Flutter 引擎还没起来，
            // 只能靠这份记录判断「用户本来是开着保活的」。
            if (action == ACTION_STOP) {
                KeepAliveScheduler.setEnabled(context, false, null)
                KeepAliveScheduler.cancelAll(context)
            } else {
                KeepAliveScheduler.setEnabled(context, true, text)
            }

            val intent = Intent(context, GatewayKeepAliveService::class.java).setAction(action)
            if (text != null) intent.putExtra(EXTRA_TEXT, text)
            try {
                if (action == ACTION_STOP) {
                    // 停止走 startService：不必承担「5 秒内必须 startForeground」的义务。
                    context.startService(intent)
                } else {
                    context.startForegroundService(intent)
                }
            } catch (error: Exception) {
                // 常见于应用处于后台且不满足豁免条件时（Android 12+ 的限制）。
                // 不当致命错误：Dart 侧在回到前台时会重新请求，
                // 看门狗闹钟也会周期性重试。
                Log.w(TAG, "请求启动保活服务失败：$error")
            }
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var currentText: String = DEFAULT_TEXT

    /** 是否是「用户主动关闭」导致的销毁。用于区分该不该安排重启。 */
    private var stopping = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        ensureChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopping = true
            // 开关记录必须一起关掉。
            //
            // 通知栏的「停止保活」按钮直接用 PendingIntent.getService 投递到这里，
            // 不经过 `dispatch`，因此那条路径上的 setEnabled/cancelAll 不会执行。
            // 漏掉这一步的后果很具体：用户点了停止、服务确实停了，
            // 但开关仍记为「开」，15 分钟后看门狗闹钟又会把它拉起来——
            // 用户会觉得「怎么关都关不掉」。
            KeepAliveScheduler.setEnabled(this, false, null)
            KeepAliveScheduler.cancelAll(this)
            releaseWakeLock()
            stopForegroundCompat()
            stopSelf()
            return START_NOT_STICKY
        }

        intent?.getStringExtra(EXTRA_TEXT)?.let { if (it.isNotBlank()) currentText = it }

        // 先进入前台：这样无论后续哪一步失败，进程都已经脱离 cached 状态。
        promoteToForeground()
        acquireWakeLock()
        // 看门狗每次启动都重排：它是一次性闹钟，靠自身续期维持周期性。
        KeepAliveScheduler.scheduleWatchdog(this)

        // START_STICKY：进程被系统回收后尽量把服务拉起来。
        // 这是「尽力而为」，重启回来时是普通后台服务，转前台仍受
        // Android 12+ 的后台启动限制约束——因此还需要看门狗闹钟兜底。
        return START_STICKY
    }

    /**
     * 用户从最近任务里划掉应用时触发。
     *
     * `stopWithTask="false"` 保证服务本身不会因此被停掉，但部分 ROM 会连进程一起清。
     * 这里额外排一个一次性闹钟，把「被清掉」的情况也覆盖上：
     * 精确闹钟在官方豁免清单内，是唯一能凭它在后台重新启动前台服务的定时手段。
     */
    override fun onTaskRemoved(rootIntent: Intent?) {
        Log.i(TAG, "任务被移除，安排重启闹钟")
        if (KeepAliveScheduler.isEnabled(this)) {
            KeepAliveScheduler.scheduleRestart(this)
        }
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        val wasRunning = isRunning
        isRunning = false
        releaseWakeLock()
        super.onDestroy()

        // 非用户主动关闭的销毁（系统回收、ROM 清理）都要安排重启。
        if (!stopping && KeepAliveScheduler.isEnabled(this)) {
            Log.i(TAG, "服务被销毁（wasRunning=$wasRunning），安排重启闹钟")
            KeepAliveScheduler.scheduleRestart(this)
        }
    }

    // ───────────────────────── 通知与前台状态 ─────────────────────────

    /**
     * 尝试进入前台。返回是否成功。
     *
     * 三级降级的原因：几种失败彼此独立（类型权限缺失、后台启动被拒、
     * 系统不支持带类型的重载），任何一步抛异常都不应让服务整体崩掉——
     * 服务本身还在运行，只是暂时没有前台优先级。
     */
    private fun promoteToForeground(): Boolean {
        val notification = buildNotification(currentText)

        if (Build.VERSION.SDK_INT >= 34) {
            if (attemptForeground(
                    "specialUse",
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
                ) {
                    startForeground(
                        NOTIFICATION_ID,
                        notification,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
                    )
                }
            ) {
                return true
            }
        } else if (attemptForeground(
                "dataSync",
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            ) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
                )
            }
        ) {
            return true
        }

        // 最后兜底：不带类型的重载，使用清单里声明的类型。
        // 此时无法确知系统选了什么，`foregroundType` 置 0（unknown）——
        // 界面会如实显示「未知」，而不是假装成 specialUse。
        if (attemptForeground("清单默认类型", 0) {
                startForeground(NOTIFICATION_ID, notification)
            }
        ) {
            return true
        }

        isRunning = false
        foregroundType = 0
        // 连前台都进不去时，至少把通知挂上，让用户知道后台有个服务在跑。
        try {
            getSystemService(NotificationManager::class.java)?.notify(NOTIFICATION_ID, notification)
        } catch (error: Exception) {
            Log.w(TAG, "发送通知失败：$error")
        }
        return false
    }

    private fun attemptForeground(
        label: String,
        type: Int,
        block: () -> Unit,
    ): Boolean = try {
        block()
        isRunning = true
        foregroundType = type
        Log.i(TAG, "已进入前台服务（$label）")
        true
    } catch (error: Exception) {
        Log.w(TAG, "以前台服务方式启动失败（$label）：$error")
        false
    }

    /**
     * 前台服务超时（Android 15 / API 35 起）。
     *
     * 只有 `dataSync` / `mediaProcessing` 会自动收到这个回调，
     * 因为这两类在 Android 15+ 有「每 24 小时累计 6 小时」的上限，
     * 到点系统要求应用停服，否则会 ANR 并丢失前台资格。
     *
     * 本项目在 API 34+ 一律用 `specialUse`（无时限），因此正常情况下
     * 这个回调**永远不会**被触发。仍然实现它有两个理由：
     * 1. 万一 `specialUse` 启动被 ROM 拒绝而退回 `dataSync`，
     *    这里是唯一能获知「被系统掐了」的地方，必须记录下来；
     * 2. 官方明确要求：超时回调里不主动停服会被判 ANR。
     *
     * 处理方式：如实记录被限流的类型，然后停服并由看门狗闹钟在
     * 允许的时机重新拉起——期间保持「如实告知用户」而不是假装还在线。
     */
    @RequiresApi(Build.VERSION_CODES.VANILLA_ICE_CREAM)
    override fun onTimeout(startId: Int, fgsType: Int) {
        val name = when (fgsType) {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC -> "dataSync"
            ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROCESSING -> "mediaProcessing"
            else -> "type=$fgsType"
        }
        Log.w(TAG, "前台服务被系统判定超时（$name，startId=$startId），即将停服并等待重新拉起")
        handleTimeout("系统对前台服务类型 $name 的运行时长配额已用尽")
    }

    /** Android 15 起 `shortService` 使用的单参数重载。 */
    @RequiresApi(Build.VERSION_CODES.VANILLA_ICE_CREAM)
    override fun onTimeout(startId: Int) {
        Log.w(TAG, "前台服务被系统判定超时（startId=$startId），即将停服并等待重新拉起")
        handleTimeout("系统对前台服务的运行时长配额已用尽")
    }

    /**
     * 超时后的统一收尾。
     *
     * `stopSelf()` 是**必须**的：官方规定超时回调内不主动停服会被判 ANR。
     * 重新拉起交给看门狗——从后台启动前台服务受 Android 12+ 限制，
     * 而精确闹钟在豁免清单内，是唯一可靠的重启时机。
     */
    private fun handleTimeout(reason: String) {
        val wasRunning = isRunning
        isRunning = false
        releaseWakeLock()
        stopForegroundCompat()
        stopSelf()
        if (KeepAliveScheduler.isEnabled(this)) {
            KeepAliveScheduler.scheduleRestart(this)
        }
        if (wasRunning) {
            Log.w(TAG, "保活前台服务因超时停止：$reason")
        }
    }

    private fun stopForegroundCompat() {
        stopForeground(STOP_FOREGROUND_REMOVE)
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

        // 「停止」动作按钮。
        //
        // **为什么必须有它**：应用退出后 Dart 与前台服务都会继续跑（这正是保活
        // 的含义），此时用户手上唯一能「真正停下来」的入口就是这条通知。
        // 没有这个按钮，用户就只剩下去系统设置里「强行停止」，那反而更容易
        // 把应用弄进 stopped 状态、连开机自启都失效。
        //
        // 用 getService 而不是 getBroadcast：停止逻辑本来就写在服务的
        // onStartCommand 里（ACTION_STOP），绕一层广播只会多一个可被拦截的环节。
        val stopIntent = Intent(this, GatewayKeepAliveService::class.java).setAction(ACTION_STOP)
        val stopPending = PendingIntent.getService(
            this,
            1,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val builder = Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("Lave 正在维持网关连接")
            .setContentText(text)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pending)
            .addAction(
                Notification.Action.Builder(
                    null,
                    "停止保活",
                    stopPending,
                ).build(),
            )
            // 常驻 + 不可自动清除：Android 13 及以下用户划不掉它。
            // Android 14+ 系统改行为后仍可被划掉，但服务不受影响（见类注释）。
            .setOngoing(true)
            .setAutoCancel(false)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            // 前台服务通知属于「持续状态」，用 LOW 让它静默，不打扰用户。
            .setPriority(Notification.PRIORITY_LOW)
            .setCategory(Notification.CATEGORY_SERVICE)
            // Android 12 起前台服务通知默认延迟 10 秒才显示。
            // 用户切到后台时这条通知是「服务是否真的在跑」的唯一可见证据，
            // 延迟出现会让人以为保活没生效，因此要求立即显示。
            .setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)

        return builder.build()
    }

    private fun ensureChannel() {
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "维持机器人在线所需的常驻通知，可随时在应用内关闭保活"
            setShowBadge(false)
            // 用户若关闭本渠道，只是看不到通知，前台服务照常运行。
            lockscreenVisibility = Notification.VISIBILITY_SECRET
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
