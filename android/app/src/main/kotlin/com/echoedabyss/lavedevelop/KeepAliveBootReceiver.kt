package com.echoedabyss.lavedevelop

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * 开机 / 应用更新后的自启接收器。
 *
 * 这几条广播是官方豁免清单里明确列出的「可以在后台启动前台服务」的场景，
 * 也是手机重启后让机器人自动恢复在线的唯一手段。
 *
 * 为什么这些动作**必须**由原生侧处理：开机广播到达时 Flutter 引擎尚未启动，
 * 甚至用户从未打开过应用（`MY_PACKAGE_REPLACED` 覆盖升级场景），
 * Dart 侧根本没有机会介入。因此这里读取的是
 * [KeepAliveScheduler] 里那份原生侧的开关记录，而不是 Dart 的 JSON 存储。
 *
 * 另注：Android 15 起，开机广播**不允许**启动
 * `dataSync / camera / mediaPlayback / phoneCall / mediaProjection / microphone`
 * 类型的前台服务（会抛异常）。本项目的服务声明的是 `specialUse`，不在禁列内。
 */
class KeepAliveBootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        when (action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_LOCKED_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            // 部分 ROM 用的非标准开机广播，官方未定义但真实存在。
            "android.intent.action.QUICKBOOT_POWERON",
            "com.htc.intent.action.QUICKBOOT_POWERON",
            -> {
                Log.i("LaveKeepAlive", "收到 $action，尝试恢复保活服务")
                KeepAliveScheduler.startServiceIfEnabled(context)
                // 看门狗闹钟在重启后会被系统清空，这里补上。
                KeepAliveScheduler.scheduleWatchdog(context)
            }
        }
    }
}
