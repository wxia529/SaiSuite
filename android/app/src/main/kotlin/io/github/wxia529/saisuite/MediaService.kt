package io.github.wxia529.saisuite

import android.app.*
import android.content.*
import android.graphics.*
import android.media.ExifInterface
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.*
import android.widget.*
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.effect.Presentation
import androidx.media3.transformer.*

class MediaService(private val activity: Activity) {
    private val worker = Executors.newSingleThreadExecutor()
    private var transformer: Transformer? = null
    private var pendingVideo: MethodChannel.Result? = null
    private var outputVideo: File? = null
    private var pendingSave: MethodChannel.Result? = null
    private var saveSource: File? = null
    private val owned = java.util.Collections.synchronizedSet(mutableSetOf<File>())
    private fun output(extension: String): File = File(activity.cacheDir, "saisuite_media_${System.nanoTime()}.$extension").also { owned.add(it) }
    private fun input(path: String): File = File(path).also { require(it.isFile && it.length() <= 524288000) { "文件不存在或超过 500 MB" } }
    private fun background(result: MethodChannel.Result, block: () -> Any?) {
        worker.execute {
            try { val value = block(); activity.runOnUiThread { result.success(value) } }
            catch (e: Exception) { activity.runOnUiThread { result.error("MEDIA", e.message ?: "媒体处理失败", null) } }
            catch (e: OutOfMemoryError) { activity.runOnUiThread { result.error("MEMORY", "内存不足，请缩小文件或分辨率", null) } }
        }
    }
    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "imageInfo" -> background(result) {
                val source=input(call.argument<String>("path")!!)
                val options=BitmapFactory.Options().apply { inJustDecodeBounds=true }
                BitmapFactory.decodeFile(source.path,options)
                require(options.outWidth>0 && options.outHeight>0) { "图片格式无法识别" }
                val orientation=try { ExifInterface(source.path).getAttributeInt(ExifInterface.TAG_ORIENTATION,ExifInterface.ORIENTATION_NORMAL) } catch(_:Exception) { ExifInterface.ORIENTATION_NORMAL }
                mapOf("width" to options.outWidth,"height" to options.outHeight,"mime" to (options.outMimeType ?: "未知"),"orientation" to orientation,"bytes" to source.length())
            }
            "imageProcess" -> background(result) { processImage(call) }
            "imagePrepareEditor" -> background(result) {
                val path = call.argument<String>("path")!!
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeFile(input(path).path, bounds)
                require(bounds.outMimeType in listOf("image/jpeg", "image/png", "image/webp")) { "请选择 JPEG、PNG 或 WebP 图片" }
                require(bounds.outWidth.toLong() * bounds.outHeight <= 40_000_000) { "图片超过 4000 万像素，请先缩小尺寸" }
                val bitmap = decoded(path)
                try {
                    val out = output("png")
                    out.outputStream().use { require(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)) { "图片准备失败" } }
                    mapOf("path" to out.path, "width" to bitmap.width, "height" to bitmap.height)
                } finally { bitmap.recycle() }
            }
            "imageEditorExport" -> background(result) {
                val path = call.argument<String>("path")!!
                val edge = call.argument<Number>("maxEdge")!!.toInt()
                val quality = call.argument<Number>("quality")!!.toInt()
                val format = call.argument<String>("format")!!
                require(edge in 1..4096 && quality in 50..100 && format in listOf("JPEG", "PNG")) { "导出设置无效" }
                val bitmaps = mutableListOf<Bitmap>()
                try {
                    // Generated editor PNGs can exceed the import file limit.
                    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                    BitmapFactory.decodeFile(input(path).path, bounds)
                    require(bounds.outMimeType == "image/png" && bounds.outWidth in 1..4098 && bounds.outHeight in 1..4098) { "编辑结果格式或尺寸无效" }
                    var bitmap = requireNotNull(BitmapFactory.decodeFile(path)) { "无法读取编辑结果" }
                    bitmaps.add(bitmap)
                    val scale = minOf(1.0, edge.toDouble() / maxOf(bitmap.width, bitmap.height))
                    if (scale < 1) {
                        bitmap = Bitmap.createScaledBitmap(bitmap, maxOf(1, (bitmap.width * scale).toInt()), maxOf(1, (bitmap.height * scale).toInt()), true)
                        bitmaps.add(bitmap)
                    }
                    if (format == "JPEG" && bitmap.hasAlpha()) {
                        val opaque = Bitmap.createBitmap(bitmap.width, bitmap.height, Bitmap.Config.ARGB_8888)
                        bitmaps.add(opaque)
                        Canvas(opaque).apply { drawColor(Color.WHITE); drawBitmap(bitmap, 0f, 0f, null) }
                        bitmap = opaque
                    }
                    val out = output(if (format == "PNG") "png" else "jpg")
                    out.outputStream().use { require(bitmap.compress(if (format == "PNG") Bitmap.CompressFormat.PNG else Bitmap.CompressFormat.JPEG, quality, it)) { "图片导出失败" } }
                    mapOf("path" to out.path, "width" to bitmap.width, "height" to bitmap.height, "bytes" to out.length())
                } finally { bitmaps.distinct().forEach { it.recycle() } }
            }
            "videoInfo" -> background(result) { videoInfo(input(call.argument<String>("path")!!)) }
            "videoFrame" -> background(result) {
                val source = input(call.argument<String>("path")!!)
                val time = call.argument<Number>("seconds")!!.toDouble()
                val retriever = MediaMetadataRetriever()
                try {
                    retriever.setDataSource(source.path)
                    val duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)!!.toDouble()/1000
                    require(time.isFinite() && time >= 0 && time < duration) { "截帧时间须在视频时长内" }
                    val bitmap = if (Build.VERSION.SDK_INT >= 27) retriever.getScaledFrameAtTime((time*1000000).toLong(), MediaMetadataRetriever.OPTION_CLOSEST, 1920, 1080) else retriever.getFrameAtTime((time*1000000).toLong(), MediaMetadataRetriever.OPTION_CLOSEST)
                    requireNotNull(bitmap) { "无法解码视频帧" }
                    val file = output("png")
                    try { file.outputStream().use { check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)) } } finally { bitmap.recycle() }
                    mapOf("path" to file.path, "bytes" to file.length())
                } finally { retriever.release() }
            }
            "videoThumbnail" -> background(result) {
                val retriever = MediaMetadataRetriever()
                try {
                    retriever.setDataSource(input(call.argument<String>("path")!!).path)
                    val time = call.argument<Number>("seconds")!!.toDouble()
                    val duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)!!.toDouble() / 1000
                    require(time.isFinite() && time >= 0 && time < duration) { "缩略图时间须在视频时长内" }
                    var frame = if (Build.VERSION.SDK_INT >= 27) retriever.getScaledFrameAtTime((time * 1000000).toLong(), MediaMetadataRetriever.OPTION_CLOSEST_SYNC, 320, 180) else retriever.getFrameAtTime((time * 1000000).toLong(), MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                    requireNotNull(frame) { "无法生成视频缩略图" }
                    val scale = minOf(1.0, 320.0 / maxOf(frame.width, frame.height))
                    if (scale < 1) { val smaller = Bitmap.createScaledBitmap(frame, maxOf(1, (frame.width * scale).toInt()), maxOf(1, (frame.height * scale).toInt()), true); frame.recycle(); frame = smaller }
                    val file = output("jpg")
                    try { file.outputStream().use { check(frame.compress(Bitmap.CompressFormat.JPEG, 70, it)) } } finally { frame.recycle() }
                    mapOf("path" to file.path, "bytes" to file.length())
                } finally { retriever.release() }
            }
            "videoPreview" -> {
                try {
                    val path = input(call.argument<String>("path")!!).path
                    val view = VideoView(activity)
                    view.setVideoPath(path)
                    val controller = MediaController(activity); view.setMediaController(controller); controller.setAnchorView(view)
                    val dialog = AlertDialog.Builder(activity).setTitle("视频预览").setView(view).setPositiveButton("关闭", null).create()
                    dialog.setOnDismissListener { view.stopPlayback() }
                    view.setOnErrorListener { _, _, _ -> Toast.makeText(activity, "设备无法播放此视频格式", Toast.LENGTH_LONG).show(); true }
                    dialog.show(); view.start(); result.success(null)
                } catch (e: Exception) { result.error("VIDEO", e.message, null) }
            }
            "videoProcess" -> startVideo(call, result)
            "videoProgress" -> { val holder = ProgressHolder(); val status = transformer?.getProgress(holder); result.success(if (status == Transformer.PROGRESS_STATE_AVAILABLE) holder.progress else -1) }
            "videoCancel" -> { transformer?.cancel(); transformer=null; outputVideo?.delete(); pendingVideo?.error("CANCELLED", "已取消视频处理", null); pendingVideo=null; result.success(null) }
            "saveOutput" -> {
                try {
                    check(pendingSave == null) { "另存为正在进行" }
                    val source = File(call.argument<String>("path")!!)
                    require(owned.contains(source) && source.isFile) { "只可导出本工具生成的文件" }
                    pendingSave=result; saveSource=source
                    activity.startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply { addCategory(Intent.CATEGORY_OPENABLE); type=call.argument<String>("mime") ?: "application/octet-stream"; putExtra(Intent.EXTRA_TITLE,call.argument<String>("name") ?: source.name) },74)
                } catch (e: Exception) { pendingSave=null; saveSource=null; result.error("SAVE",e.message,null) }
            }
            "mediaCleanup" -> { val paths = call.argument<List<String>>("paths") ?: emptyList(); worker.execute { for(path in paths) { val file=File(path); if(owned.remove(file)) file.delete() } }; result.success(null) }
            else -> result.notImplemented()
        }
    }
    fun saved(code: Int, data: Intent?) {
        val result=pendingSave ?: return; val source=saveSource
        pendingSave=null; saveSource=null
        if(code != Activity.RESULT_OK || data?.data == null || source == null) { result.success(null); return }
        val uri=data.data!!
        background(result) {
            try {
                activity.contentResolver.openOutputStream(uri,"wt").use { stream ->
                    requireNotNull(stream) { "无法打开目标文件" }
                    source.inputStream().use { it.copyTo(stream) }; stream.flush()
                }
                uri.toString()
            } catch(e: Exception) { try { android.provider.DocumentsContract.deleteDocument(activity.contentResolver,uri) } catch(_:Exception) { }; throw e }
        }
    }
    private fun decoded(path: String, maxEdge: Int = 4096): Bitmap {
        val file=input(path); require(file.length()<=31457280) { "图片文件上限 30 MB" }
        val bounds=BitmapFactory.Options().apply { inJustDecodeBounds=true }; BitmapFactory.decodeFile(path,bounds)
        require(bounds.outWidth>0 && bounds.outHeight>0) { "无法解码图片，请使用 JPEG 或 PNG" }
        val opts=BitmapFactory.Options(); var sample=1
        while (bounds.outWidth/sample>maxEdge || bounds.outHeight/sample>maxEdge) sample*=2
        opts.inSampleSize=sample
        val original=requireNotNull(BitmapFactory.decodeFile(path,opts)) { "无法解码图片" }
        val matrix=Matrix()
        val orientation=try { ExifInterface(path).getAttributeInt(ExifInterface.TAG_ORIENTATION,ExifInterface.ORIENTATION_NORMAL) } catch(_:Exception) { ExifInterface.ORIENTATION_NORMAL }
        when (orientation) {
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.setScale(-1f,1f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.setRotate(180f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.setScale(1f,-1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> { matrix.setRotate(90f); matrix.postScale(-1f,1f) }
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.setRotate(90f)
            ExifInterface.ORIENTATION_TRANSVERSE -> { matrix.setRotate(270f); matrix.postScale(-1f,1f) }
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.setRotate(270f)
        }
        if(matrix.isIdentity) return original
        val oriented=Bitmap.createBitmap(original,0,0,original.width,original.height,matrix,true); if(oriented!==original) original.recycle(); return oriented
    }
    private fun processImage(call: MethodCall): Map<String,Any> {
        val paths=call.argument<List<String>>("paths")!!; require(paths.isNotEmpty() && paths.size<=9) { "请选择 1—9 张图片" }
        val pictures=mutableListOf<Bitmap>()
        var bitmap: Bitmap? = null
        try {
            for(path in paths) pictures.add(decoded(path,if(paths.size>1) 1024 else 4096))
            if(pictures.size==1) {
                val original=pictures[0]
                val rect=call.argument<List<Number>>("crop")!!.map { it.toDouble() }
                require(rect.size==4 && rect.all { it.isFinite() } && rect[0]>=0 && rect[1]>=0 && rect[2]>0 && rect[3]>0 && rect[0]+rect[2]<=100.000001 && rect[1]+rect[3]<=100.000001) { "裁剪区域须在 0—100% 图像范围内" }
                val x=(original.width*rect[0]/100).toInt().coerceIn(0,original.width-1); val y=(original.height*rect[1]/100).toInt().coerceIn(0,original.height-1)
                val w=(original.width*rect[2]/100).toInt().coerceIn(1,original.width-x); val h=(original.height*rect[3]/100).toInt().coerceIn(1,original.height-y)
                val matrix=Matrix().apply { postRotate((call.argument<Number>("rotation")?.toFloat() ?: 0f)); if(call.argument<Boolean>("flip")==true) postScale(-1f,1f) }
                bitmap=Bitmap.createBitmap(original,x,y,w,h,matrix,true)
                if(bitmap===original) bitmap=original.copy(Bitmap.Config.ARGB_8888,true)
            } else {
                val layout=call.argument<String>("layout") ?: "网格"
                val columns=if(layout=="横向") pictures.size else if(layout=="竖向") 1 else kotlin.math.ceil(kotlin.math.sqrt(pictures.size.toDouble())).toInt()
                val rows=(pictures.size+columns-1)/columns
                val side=4096/kotlin.math.max(columns,rows)
                bitmap=Bitmap.createBitmap(columns*side,rows*side,Bitmap.Config.ARGB_8888)
                val canvas=Canvas(bitmap!!);canvas.drawColor(Color.WHITE)
                pictures.forEachIndexed { i,b ->
                    val factor=kotlin.math.min(side.toFloat()/b.width,side.toFloat()/b.height)
                    val left=(i%columns)*side+(side-b.width*factor)/2; val top=(i/columns)*side+(side-b.height*factor)/2
                    canvas.drawBitmap(b,null,RectF(left,top,left+b.width*factor,top+b.height*factor),Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG))
                }
            }
            val target=call.argument<Number>("width")!!.toInt();require(target in 16..4096) { "输出宽度须为 16—4096 px" }
            val current=bitmap!!;val height=(current.height.toDouble()/current.width*target).toInt().coerceAtLeast(1)
            require(height<=4096) { "输出高度超过 4096 px，请减小宽度" }
            val scaled=Bitmap.createScaledBitmap(current,target,height,true);if(scaled!==current) current.recycle();bitmap=scaled
            val watermark=call.argument<String>("watermark") ?: "";require(watermark.length<=128) { "水印最多 128 字符" }
            if(watermark.isNotBlank()) {
                val mutable=bitmap!!.copy(Bitmap.Config.ARGB_8888,true);bitmap!!.recycle();bitmap=mutable
                val paint=Paint(Paint.ANTI_ALIAS_FLAG).apply { color=Color.WHITE; textSize=(target/28f).coerceAtLeast(12f);setShadowLayer(2f,1f,1f,Color.BLACK) }
                Canvas(bitmap!!).drawText(watermark,12f,(height-12).toFloat(),paint)
            }
            val jpeg=call.argument<String>("format")=="JPEG"; val quality=call.argument<Number>("quality")!!.toInt();require(quality in 1..100) { "质量范围 1—100" }
            if(jpeg) {
                val white=Bitmap.createBitmap(target,height,Bitmap.Config.ARGB_8888);val canvas=Canvas(white);canvas.drawColor(Color.WHITE);canvas.drawBitmap(bitmap!!,0f,0f,null);bitmap!!.recycle();bitmap=white
            }
            val out=output(if(jpeg) "jpg" else "png")
            out.outputStream().use { check(bitmap!!.compress(if(jpeg) Bitmap.CompressFormat.JPEG else Bitmap.CompressFormat.PNG,quality,it)) }
            return mapOf("path" to out.path,"width" to target,"height" to height,"bytes" to out.length(),"inputs" to paths.size)
        } finally { pictures.forEach { if(!it.isRecycled) it.recycle() }; bitmap?.let { if(!it.isRecycled) it.recycle() } }
    }
    private fun videoInfo(source: File): Map<String,Any> {
        val r=MediaMetadataRetriever()
        try {
            r.setDataSource(source.path)
            return mapOf("duration" to (r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toDouble()?.div(1000) ?: 0.0),"width" to (r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH) ?: "未知"),"height" to (r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT) ?: "未知"),"rotation" to (r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION) ?: "0"),"bitrate" to (r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_BITRATE) ?: "未知"),"mime" to (r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_MIMETYPE) ?: "未知"),"bytes" to source.length(),"hasAudio" to (r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO)=="yes"))
        } finally { r.release() }
    }
    private fun startVideo(call: MethodCall, result: MethodChannel.Result) {
        if(pendingVideo!=null) { result.error("BUSY","视频处理中，请先取消或等待完成",null); return }
        try {
            check(pendingVideo==null) { "视频处理中，请先取消或等待完成" }
            val source=input(call.argument<String>("path")!!)
            val start=call.argument<Number>("start")!!.toDouble(); val end=call.argument<Number>("end")!!.toDouble()
            require(start.isFinite() && end.isFinite() && start>=0 && end>start) { "请输入有效的起止时间" }
            val height=call.argument<Number>("height")!!.toInt(); val bitrate=call.argument<Number>("bitrate")!!.toInt()
            require(height in listOf(0,360,480,720,1080) && bitrate in 128000..20000000) { "分辨率或码率超出范围" }
            val inputItem=MediaItem.Builder().setUri(Uri.fromFile(source)).setClippingConfiguration(MediaItem.ClippingConfiguration.Builder().setStartPositionMs((start*1000).toLong()).setEndPositionMs((end*1000).toLong()).build()).build()
            val edited=EditedMediaItem.Builder(inputItem).setRemoveAudio(call.argument<Boolean>("mute")==true)
            if(height>0) edited.setEffects(Effects(emptyList(),listOf(Presentation.createForHeight(height))))
            val out=output("mp4");outputVideo=out;pendingVideo=result
            transformer=Transformer.Builder(activity).setVideoMimeType(MimeTypes.VIDEO_H264).setAudioMimeType(MimeTypes.AUDIO_AAC)
                .setEncoderFactory(DefaultEncoderFactory.Builder(activity).setRequestedVideoEncoderSettings(VideoEncoderSettings.Builder().setBitrate(bitrate).build()).build())
                .addListener(object: Transformer.Listener {
                    override fun onCompleted(composition: Composition, exportResult: ExportResult) { if(pendingVideo!==result) return; transformer=null;pendingVideo=null;result.success(mapOf("path" to out.path,"bytes" to out.length(),"duration" to exportResult.durationMs/1000.0,"bitrate" to exportResult.averageVideoBitrate)) }
                    override fun onError(composition: Composition, exportResult: ExportResult, exception: ExportException) { if(pendingVideo!==result) return; transformer=null;pendingVideo=null;out.delete();result.error("VIDEO",exception.message ?: "设备编码器不支持此次处理",null) }
                }).build()
            transformer!!.start(edited.build(),out.path)
        } catch(e:Exception) { transformer?.cancel();transformer=null;pendingVideo=null;outputVideo?.delete();result.error("VIDEO",e.message,null) }
    }
}
