package io.github.wxia529.saisuite

import android.app.Activity
import android.hardware.*
import android.view.Surface
import io.flutter.plugin.common.EventChannel

class SensorService(private val activity: Activity) : EventChannel.StreamHandler, SensorEventListener {
    private val manager = activity.getSystemService(SensorManager::class.java)
    private var sink: EventChannel.EventSink? = null
    private val values = mutableMapOf<Int, FloatArray>()
    private val accuracies = mutableMapOf<Int, Int>()
    private var last = 0L
    private var interval = 100L
    private val types = listOf(Sensor.TYPE_ACCELEROMETER, Sensor.TYPE_MAGNETIC_FIELD, Sensor.TYPE_GYROSCOPE, Sensor.TYPE_LIGHT, Sensor.TYPE_PRESSURE, Sensor.TYPE_GRAVITY, Sensor.TYPE_ROTATION_VECTOR)
    fun inventory(): List<Map<String, Any>> = types.map { type ->
        val sensor = manager.getDefaultSensor(type)
        mapOf("type" to type, "available" to (sensor != null), "name" to (sensor?.name ?: "设备未提供"), "resolution" to (sensor?.resolution ?: 0f))
    }
    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        onCancel(null); sink = events; values.clear(); accuracies.clear()
        last = 0L
        val mode = (arguments as? Map<*, *>)?.get("mode") as? String
        interval = when (mode) { "compass" -> 33L; "level" -> 50L; else -> 100L }
        val selected = when (mode) {
            "compass" -> listOf(Sensor.TYPE_MAGNETIC_FIELD, if (manager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR) != null) Sensor.TYPE_ROTATION_VECTOR else Sensor.TYPE_ACCELEROMETER)
            "level" -> listOf(if (manager.getDefaultSensor(Sensor.TYPE_GRAVITY) != null) Sensor.TYPE_GRAVITY else Sensor.TYPE_ACCELEROMETER)
            else -> types
        }
        val delay = if (mode == "compass" || mode == "level") SensorManager.SENSOR_DELAY_GAME else SensorManager.SENSOR_DELAY_UI
        for (type in selected) manager.getDefaultSensor(type)?.let { manager.registerListener(this, it, delay) }
    }
    override fun onCancel(arguments: Any?) { manager.unregisterListener(this); sink = null }
    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) { sensor?.let { accuracies[it.type] = accuracy } }
    override fun onSensorChanged(event: SensorEvent) {
        values[event.sensor.type] = event.values.clone(); accuracies[event.sensor.type] = event.accuracy
        val now = android.os.SystemClock.elapsedRealtime()
        if (now - last < interval) return
        last = now
        val data = mutableMapOf<String, Any>("values" to values.mapKeys { it.key.toString() }.mapValues { it.value.toList() }, "accuracy" to accuracies.mapKeys { it.key.toString() })
        val rotation = FloatArray(9)
        var hasOrientation = false
        val a = values[Sensor.TYPE_ACCELEROMETER]; val m = values[Sensor.TYPE_MAGNETIC_FIELD]
        val rv = values[Sensor.TYPE_ROTATION_VECTOR]
        if (rv != null) { SensorManager.getRotationMatrixFromVector(rotation, rv); hasOrientation = true }
        else if (a != null && m != null) hasOrientation = SensorManager.getRotationMatrix(rotation, null, a, m)
        @Suppress("DEPRECATION") val screenRotation = activity.windowManager.defaultDisplay.rotation
        if (hasOrientation) {
            val transformed = FloatArray(9)
            val axes = when (screenRotation) {
                Surface.ROTATION_90 -> Pair(SensorManager.AXIS_Y, SensorManager.AXIS_MINUS_X)
                Surface.ROTATION_180 -> Pair(SensorManager.AXIS_MINUS_X, SensorManager.AXIS_MINUS_Y)
                Surface.ROTATION_270 -> Pair(SensorManager.AXIS_MINUS_Y, SensorManager.AXIS_X)
                else -> Pair(SensorManager.AXIS_X, SensorManager.AXIS_Y)
            }
            SensorManager.remapCoordinateSystem(rotation, axes.first, axes.second, transformed)
            val orientation = SensorManager.getOrientation(transformed, FloatArray(3))
            data["azimuth"] = ((Math.toDegrees(orientation[0].toDouble()) + 360) % 360)
        }
        val gravity = values[Sensor.TYPE_GRAVITY] ?: a
        if (gravity != null && gravity.size >= 3) {
            val x: Double; val y: Double; val z = gravity[2].toDouble()
            when (screenRotation) {
                Surface.ROTATION_90 -> { x = -gravity[1].toDouble(); y = gravity[0].toDouble() }
                Surface.ROTATION_180 -> { x = -gravity[0].toDouble(); y = -gravity[1].toDouble() }
                Surface.ROTATION_270 -> { x = gravity[1].toDouble(); y = -gravity[0].toDouble() }
                else -> { x = gravity[0].toDouble(); y = gravity[1].toDouble() }
            }
            data["tiltX"] = Math.toDegrees(kotlin.math.atan2(x, kotlin.math.sqrt(y*y+z*z)))
            data["tiltY"] = Math.toDegrees(kotlin.math.atan2(y, kotlin.math.sqrt(x*x+z*z)))
        }
        sink?.success(data)
    }
}
