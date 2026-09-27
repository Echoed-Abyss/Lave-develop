package com.echoedabyss.lavedevelop

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * 保活闹钟接收器。
 *
 * 处理两类由 [KeepAliveScheduler] 排定的闹钟：
 *
 * - `ACTION_WATCHDOG`：周期性巡检。服务若因任何原因不在了就把它拉回来，
 *   并把下一次巡检重新排上（`setExactAndAllowWhileIdle` 是一次性的，
 *   没有循环变体，必须自己续期）；
 * - `ACTION_RESTART`：用户从最近任务里划掉应用后的一次性拉起。
 *
 * 这个接收器**不导出**（`android:exported="false"`）：
 * 闹钟是我们自己用显式 Intent 投递的，不需要也不应该让其它应用触发。
 */
class KeepAliveAlarmReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (!KeepAliveScheduler.isEnabled(context)) {
            // 用户已经关掉保活，残留的闹钟直接作废。
            KeepAliveScheduler.cancelAll(context)
            return
        }

        when (intent.action) {
            KeepAliveScheduler.ACTION_WATCHDOG -> {
                Log.i("LaveKeepAlive", "看门狗巡检")
                KeepAliveScheduler.startServiceIfEnabled(context)
                // 续期下一次巡检。
                KeepAliveScheduler.scheduleWatchdog(context)
            }

            KeepAliveScheduler.ACTION_RESTART -> {
                Log.i("LaveKeepAlive", "任务被移除后的重启闹钟")
                KeepAliveScheduler.startServiceIfEnabled(context)
            }
        }
    }
}
