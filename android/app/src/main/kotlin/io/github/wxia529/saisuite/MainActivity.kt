package io.github.wxia529.saisuite

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import android.app.AlarmManager
import android.app.PendingIntent
import android.app.NotificationManager
import android.content.Intent
import android.net.Uri
import android.content.ActivityNotFoundException
import android.os.Build
import android.Manifest
import android.content.pm.PackageManager

class MainActivity : FlutterActivity() {
    private var sensorService: SensorService? = null
    private var mediaService: MediaService? = null
    private var creativeService: CreativeService? = null
    private var notificationResult: MethodChannel.Result? = null
    private fun timerIntent(label: String = "计时") = PendingIntent.getBroadcast(this, 73,
        Intent(this, TimerReceiver::class.java).putExtra("label", label), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "saisuite/updates").setMethodCallHandler { call, result ->
            when (call.method) {
                "appInfo" -> {
                    @Suppress("DEPRECATION") val info = packageManager.getPackageInfo(packageName, 0)
                    @Suppress("DEPRECATION") val code = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
                    val variant = when (code / 1000) { 1L -> "armeabi-v7a"; 2L -> "arm64-v8a"; 4L -> "x86_64"; else -> "universal" }
                    result.success(mapOf("version" to info.versionName, "versionCode" to code, "variant" to variant))
                }
                "openUrl" -> {
                    val uri = Uri.parse(call.argument<String>("url") ?: "")
                    val path = uri.path ?: ""
                    if (uri.scheme != "https" || uri.host != "github.com" || uri.userInfo != null ||
                        (uri.port != -1 && uri.port != 443) || uri.query != null || uri.fragment != null ||
                        !(path == "/wxia529/SaiSuite/releases" || path.startsWith("/wxia529/SaiSuite/releases/"))) {
                        result.error("INVALID_URL", "仅支持当前 GitHub 仓库的发布地址", null)
                    } else {
                        try {
                            startActivity(Intent(Intent.ACTION_VIEW, uri).addCategory(Intent.CATEGORY_BROWSABLE))
                            result.success(null)
                        } catch (_: ActivityNotFoundException) { result.error("NO_BROWSER", "没有可用的浏览器", null) }
                        catch (_: Exception) { result.error("OPEN_FAILED", "无法打开浏览器", null) }
                    }
                }
                else -> result.notImplemented()
            }
        }
        PdfService(this).register(MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "saisuite/pdf"))
        creativeService = CreativeService(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "saisuite/creative").setMethodCallHandler { call, result -> creativeService!!.handle(call, result) }
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
        if(requestCode==75) creativeService?.cameraSaved(resultCode)
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 73) { notificationResult?.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED); notificationResult = null }
    }
}
