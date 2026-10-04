package io.github.wxia529.saisuite

import android.app.Activity
import android.graphics.BitmapFactory
import android.media.ExifInterface
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaCodec
import android.media.MediaMuxer
import android.content.Intent
import android.content.pm.PackageManager
import android.provider.MediaStore
import androidx.core.content.FileProvider
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
import com.google.android.gms.tasks.Tasks
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.Executors

class CreativeService(private val activity: Activity) {
    private var cameraResult: MethodChannel.Result? = null
    private var cameraFile: File? = null
    fun cameraSaved(resultCode: Int) {
        val result = cameraResult ?: return
        cameraResult = null
        val file = cameraFile; cameraFile = null
        if(resultCode == Activity.RESULT_OK && file != null && file.length() > 0) result.success(mapOf("path" to file.path))
        else { file?.delete(); result.success(null) }
    }
    private val worker = Executors.newSingleThreadExecutor()
    private val fields = linkedMapOf("拍摄时间" to ExifInterface.TAG_DATETIME_ORIGINAL,
        "作者" to ExifInterface.TAG_ARTIST, "版权" to ExifInterface.TAG_COPYRIGHT,
        "描述" to ExifInterface.TAG_IMAGE_DESCRIPTION, "相机" to ExifInterface.TAG_MODEL,
        "方向" to ExifInterface.TAG_ORIENTATION, "纬度" to ExifInterface.TAG_GPS_LATITUDE,
        "经度" to ExifInterface.TAG_GPS_LONGITUDE)
    fun handle(call: MethodCall, result: MethodChannel.Result) {
        if(call.method == "camera") {
            if(cameraResult != null) { result.error("BUSY", "相机已打开", null); return }
            val file = File(activity.cacheDir, "saisuite_camera_${System.nanoTime()}.jpg")
            try {
                val uri = FileProvider.getUriForFile(activity, activity.packageName + ".camera.files", file)
                val intent = Intent(MediaStore.ACTION_IMAGE_CAPTURE).putExtra(MediaStore.EXTRA_OUTPUT, uri)
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                activity.packageManager.queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY).forEach {
                    activity.grantUriPermission(it.activityInfo.packageName, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                }
                cameraResult = result; cameraFile = file
                activity.startActivityForResult(intent, 75)
            } catch(e: Exception) { file.delete(); cameraResult = null; cameraFile = null; result.error("CAMERA", "无法打开相机，请使用选择图片", null) }
            return
        }
        worker.execute {
            var generated: File? = null
            try {
                val source = File(call.argument<String>("path")!!)
                require(source.isFile && source.length() <= 524288000) { "输入文件无效或超过 500 MB" }
                val value: Any = when(call.method) {
                    "ocr" -> {
                        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                        BitmapFactory.decodeFile(source.path, bounds)
                        require(bounds.outWidth in 1..4096 && bounds.outHeight in 1..4096 && bounds.outWidth.toLong() * bounds.outHeight <= 16000000) { "识别图片尺寸过大" }
                        val bitmap = requireNotNull(BitmapFactory.decodeFile(source.path)) { "无法读取识别图片" }
                        val recognizer = TextRecognition.getClient(ChineseTextRecognizerOptions.Builder().build())
                        try {
                            val recognized = Tasks.await(recognizer.process(InputImage.fromBitmap(bitmap, 0)))
                            mapOf("text" to recognized.text, "lines" to recognized.textBlocks.flatMap { it.lines }.map { line ->
                                val r = line.boundingBox
                                mapOf("text" to line.text, "box" to listOf(r?.left ?: 0, r?.top ?: 0, r?.right ?: 0, r?.bottom ?: 0))
                            })
                        } finally { bitmap.recycle(); recognizer.close() }
                    }
                    "exifRead", "exifWrite" -> {
                        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                        BitmapFactory.decodeFile(source.path, bounds)
                        require(bounds.outMimeType == "image/jpeg") { "照片信息编辑目前支持 JPEG" }
                        require(source.length() <= 31457280) { "照片超过 30 MB" }
                        if(call.method == "exifRead") {
                            val exif = ExifInterface(source.path)
                            fields.mapValues { exif.getAttribute(it.value) ?: "" }
                        } else {
                            val out = File(activity.cacheDir, "saisuite_exif_${System.nanoTime()}.jpg")
                            generated = out; source.copyTo(out)
                            val exif = ExifInterface(out.path)
                            if(call.argument<Boolean>("clear") == true) {
                                // Keep display orientation; remove metadata without rotating/re-encoding pixels.
                                ExifInterface::class.java.fields.filter { it.name.startsWith("TAG_") && it.type == String::class.java }.forEach {
                                    val tag = it.get(null) as String
                                    if(tag != ExifInterface.TAG_ORIENTATION) exif.setAttribute(tag, null)
                                }
                            } else {
                                val edits = call.argument<Map<String, String>>("fields") ?: emptyMap()
                                edits.forEach { (key, content) ->
                                    require(key in listOf("拍摄时间", "作者", "版权", "描述") && content.length <= 500) { "信息字段无效" }
                                    require(content.all { it.code in 32..126 }) { "为兼容 EXIF 照片软件，文字字段请使用英文、数字和常用半角符号" }
                                    if(key == "拍摄时间" && content.isNotEmpty()) require(Regex("\\d{4}:\\d{2}:\\d{2} \\d{2}:\\d{2}:\\d{2}").matches(content)) { "拍摄时间格式为 YYYY:MM:DD HH:MM:SS" }
                                    exif.setAttribute(fields[key]!!, content.ifEmpty { null })
                                }
                            }
                            exif.saveAttributes()
                            mapOf("path" to out.path)
                        }
                    }
                    "extractAudio" -> {
                        val extractor = MediaExtractor()
                        var muxer: MediaMuxer? = null
                        try {
                            extractor.setDataSource(source.path)
                            val track = (0 until extractor.trackCount).firstOrNull {
                                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
                            } ?: throw IllegalArgumentException("视频没有音轨")
                            val format = extractor.getTrackFormat(track)
                            require(format.getString(MediaFormat.KEY_MIME) == "audio/mp4a-latm") { "目前支持 AAC 音轨直接提取为 M4A；请先用视频工具转换为 MP4" }
                            extractor.selectTrack(track)
                            val out = File(activity.cacheDir, "saisuite_audio_${System.nanoTime()}.m4a")
                            generated = out
                            muxer = MediaMuxer(out.path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
                            val destination = muxer.addTrack(format)
                            muxer.start()
                            val buffer = ByteBuffer.allocate(4 * 1024 * 1024)
                            val info = MediaCodec.BufferInfo()
                            val origin = extractor.sampleTime.coerceAtLeast(0)
                            while(true) {
                                buffer.clear()
                                val size = extractor.readSampleData(buffer, 0)
                                if(size < 0) break
                                require(size <= buffer.capacity()) { "音频帧超出处理上限" }
                                info.set(0, size, (extractor.sampleTime - origin).coerceAtLeast(0), extractor.sampleFlags)
                                muxer.writeSampleData(destination, buffer, info)
                                extractor.advance()
                            }
                            muxer.stop()
                            mapOf("path" to out.path, "bytes" to out.length())
                        } finally { muxer?.release(); extractor.release() }
                    }
                    else -> throw IllegalArgumentException("不支持的操作")
                }
                activity.runOnUiThread { result.success(value) }
            } catch(e: Throwable) {
                generated?.delete()
                activity.runOnUiThread { result.error("CREATIVE", e.message ?: "处理失败", null) }
            }
        }
    }
}
