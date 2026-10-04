package io.github.wxia529.saisuite

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import android.app.AlarmManager
import android.app.PendingIntent
import android.app.NotificationManager
import android.content.Intent
import android.os.Build
import android.Manifest
import android.content.pm.PackageManager

class MainActivity : FlutterActivity() {
    private var sensorService: SensorService? = null
    private var mediaService: MediaService? = null
    private var notificationResult: MethodChannel.Result? = null
    private fun timerIntent(label: String = "计时") = PendingIntent.getBroadcast(this, 73,
        Intent(this, TimerReceiver::class.java).putExtra("label", label), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        PdfService(this).register(MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "saisuite/pdf"))
        mediaService = MediaService(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "saisuite/media").setMethodCallHandler { call, result -> mediaService!!.handle(call, result) }
        sensorService = SensorService(this)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "saisuite/sensors").setStreamHandler(sensorService)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "saisuite/device").setMethodCallHandler { call, result ->
            when (call.method) {
                "sensors" -> result.success(sensorService!!.inventory())
                "displayMetrics" -> { val metrics = resources.displayMetrics; result.success(mapOf("xdpi" to metrics.xdpi, "ydpi" to metrics.ydpi, "density" to metrics.density)) }
                "timerSchedule" -> {
                    val deadline = call.argument<Number>("deadline")!!.toLong()
                    getSystemService(AlarmManager::class.java).setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, deadline, timerIntent(call.argument<String>("label") ?: "计时"))
                    if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                        if (notificationResult != null) result.error("BUSY", "正在请求通知权限", null)
                        else { notificationResult = result; requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 73) }
                    } else result.success(getSystemService(NotificationManager::class.java).areNotificationsEnabled())
                }
                "timerCancel" -> { getSystemService(AlarmManager::class.java).cancel(timerIntent()); getSystemService(NotificationManager::class.java).cancel(73); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }
    override fun onPause() { sensorService?.onCancel(null); super.onPause() }
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if(requestCode==74) mediaService?.saved(resultCode,data)
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 73) { notificationResult?.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED); notificationResult = null }
    }
}
