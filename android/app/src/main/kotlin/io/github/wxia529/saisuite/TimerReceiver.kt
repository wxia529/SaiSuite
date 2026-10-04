package io.github.wxia529.saisuite

import android.app.*
import android.content.*
import android.os.Build

class TimerReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val manager = context.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel("pomodoro", "番茄钟提醒", NotificationManager.IMPORTANCE_HIGH))
        val launch = PendingIntent.getActivity(context, 0, Intent(context, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, "pomodoro") else Notification.Builder(context)
        val notification = builder.setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("${intent.getStringExtra("label") ?: "计时"}结束")
            .setContentText("打开赛赛工具箱确认下一阶段")
            .setContentIntent(launch).setAutoCancel(true).build()
        try { manager.notify(73, notification) } catch (_: SecurityException) { }
    }
}
