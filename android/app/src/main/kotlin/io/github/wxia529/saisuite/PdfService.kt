package io.github.wxia529.saisuite

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.os.Handler
import android.os.Looper
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.PDPage
import com.tom_roush.pdfbox.pdmodel.PDPageContentStream
import com.tom_roush.pdfbox.pdmodel.common.PDRectangle
import com.tom_roush.pdfbox.pdmodel.encryption.AccessPermission
import com.tom_roush.pdfbox.pdmodel.encryption.InvalidPasswordException
import com.tom_roush.pdfbox.pdmodel.encryption.StandardProtectionPolicy
import com.tom_roush.pdfbox.pdmodel.font.PDType1Font
import com.tom_roush.pdfbox.pdmodel.graphics.image.LosslessFactory
import com.tom_roush.pdfbox.pdmodel.graphics.state.PDExtendedGraphicsState
import com.tom_roush.pdfbox.rendering.PDFRenderer
import com.tom_roush.pdfbox.text.PDFTextStripper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.min

/** Android-only, offline PDF operations. All generated files belong to the app cache. */
class PdfService(private val context: Context) {
    private val executor = Executors.newSingleThreadExecutor()
    private val handler = Handler(Looper.getMainLooper())
    private val cancelled = AtomicBoolean(false)
    init {
        PDFBoxResourceLoader.init(context.applicationContext)
        context.cacheDir.listFiles()?.filter { it.name.startsWith("saisuite_") && System.currentTimeMillis() - it.lastModified() > 86_400_000 }?.forEach { if (it.isFile) it.delete() }
    }
    fun register(channel: MethodChannel) {
        channel.setMethodCallHandler { call, result ->
            if (call.method == "cancel") { cancelled.set(true); result.success(null); return@setMethodCallHandler }
            executor.execute {
                cancelled.set(false)
                try { val output = execute(call); handler.post { result.success(output) } }
                catch (e: InvalidPasswordException) { handler.post { result.error("PASSWORD", "PDF 密码错误或需要打开密码", null) } }
                catch (e: Exception) { handler.post { result.error("PDF_ERROR", e.message ?: "PDF 处理失败", null) } }
                catch (e: OutOfMemoryError) { handler.post { result.error("PDF_MEMORY", "内存不足，请减少图片数量；原图未修改", null) } }
            }
        }
    }
    private fun check() { check(!cancelled.get()) { "操作已取消" } }
    private fun output(ext: String): File = File(context.cacheDir, "saisuite_${UUID.randomUUID()}.$ext")
    private fun path(call: MethodCall): String = requireNotNull(call.argument<String>("path"))
    private fun open(path: String, password: String = ""): PDDocument {
        val file = File(path)
        require(file.isFile && file.length() in 1..104857600) { "PDF 不能为空，且需小于 100 MB" }
        val document = PDDocument.load(file, password)
        if (document.numberOfPages !in 1..500) { document.close(); error("支持 1—500 页 PDF") }
        return document
    }
    private fun pages(call: MethodCall, doc: PDDocument): List<Int> {
        val selected = call.argument<List<Int>>("pages") ?: (0 until doc.numberOfPages).toList()
        require(selected.isNotEmpty() && selected.all { it in 0 until doc.numberOfPages } && selected.size <= 500) { "页面选择无效或超过 500 页" }
        return selected
    }
    private fun save(document: PDDocument): String {
        check()
        val file = output("pdf")
        try { document.save(file); check(); return file.path }
        catch (e: Exception) { file.delete(); throw e }
    }
    private fun boundedImage(path: String): Bitmap {
        val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, options)
        require(options.outWidth > 0 && options.outHeight > 0) { "图片格式不支持" }
        options.inJustDecodeBounds = false
        options.inSampleSize = 1
        while (options.outWidth / options.inSampleSize > 4096 || options.outHeight / options.inSampleSize > 4096) options.inSampleSize *= 2
        return requireNotNull(BitmapFactory.decodeFile(path, options)) { "无法解码图片" }
    }
    private fun originalImage(path: String): Bitmap {
        val file = File(path)
        require(file.isFile && file.length() in 1..104857600) { "图片不能为空，且需小于 100 MB" }
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        require(bounds.outWidth > 0 && bounds.outHeight > 0 && bounds.outMimeType in listOf("image/jpeg", "image/png")) { "请选择 JPEG 或 PNG 图片" }
        require(bounds.outWidth.toLong() * bounds.outHeight <= 16_000_000 && maxOf(bounds.outWidth, bounds.outHeight) <= 14400) { "按图片尺寸支持单张最多 1600 万像素、长边最多 14400 px；未自动缩小图片" }
        val original = requireNotNull(BitmapFactory.decodeFile(path, BitmapFactory.Options().apply { inSampleSize = 1; inScaled = false })) { "无法解码图片" }
        try {
            val orientation = try { ExifInterface(path).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL) } catch (_: Exception) { ExifInterface.ORIENTATION_NORMAL }
            val matrix = Matrix()
            when (orientation) {
                ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.setScale(-1f, 1f)
                ExifInterface.ORIENTATION_ROTATE_180 -> matrix.setRotate(180f)
                ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.setScale(1f, -1f)
                ExifInterface.ORIENTATION_TRANSPOSE -> { matrix.setRotate(90f); matrix.postScale(-1f, 1f) }
                ExifInterface.ORIENTATION_ROTATE_90 -> matrix.setRotate(90f)
                ExifInterface.ORIENTATION_TRANSVERSE -> { matrix.setRotate(270f); matrix.postScale(-1f, 1f) }
                ExifInterface.ORIENTATION_ROTATE_270 -> matrix.setRotate(270f)
            }
            if (matrix.isIdentity) return original
            val oriented = Bitmap.createBitmap(original, 0, 0, original.width, original.height, matrix, false)
            if (oriented !== original) original.recycle()
            return oriented
        } catch (e: Throwable) { original.recycle(); throw e }
    }
    private fun execute(call: MethodCall): Any? {
        when (call.method) {
            "inspect" -> open(path(call), call.argument<String>("password") ?: "").use { doc ->
                return mapOf("count" to doc.numberOfPages, "bytes" to File(path(call)).length(), "encrypted" to doc.isEncrypted,
                    "title" to (doc.documentInformation.title ?: ""), "author" to (doc.documentInformation.author ?: ""),
                    "subject" to (doc.documentInformation.subject ?: ""), "producer" to (doc.documentInformation.producer ?: ""),
                    "pages" to (0 until doc.numberOfPages).map { val p = doc.getPage(it); mapOf("width" to p.cropBox.width.toDouble(), "height" to p.cropBox.height.toDouble(), "rotation" to p.rotation) },
                    "signed" to doc.signatureDictionaries.isNotEmpty(), "forms" to (doc.documentCatalog.acroForm != null))
            }
            "render" -> open(path(call), call.argument<String>("password") ?: "").use { doc ->
                val page = call.argument<Int>("page") ?: 0
                require(page in 0 until doc.numberOfPages) { "页面不存在" }
                val dpi = (call.argument<Number>("dpi")?.toFloat() ?: 100f).coerceIn(36f, 300f)
                val box = doc.getPage(page).cropBox
                val scale = min(dpi / 72f, min(4096f / box.width, 4096f / box.height))
                val bitmap = PDFRenderer(doc).renderImage(page, scale)
                val jpeg = call.argument<String>("format") == "JPEG"
                val file = output(if (jpeg) "jpg" else "png")
                try { check(); file.outputStream().use { bitmap.compress(if (jpeg) Bitmap.CompressFormat.JPEG else Bitmap.CompressFormat.PNG, 90, it) }; check(); return file.path }
                catch (e: Exception) { file.delete(); throw e }
                finally { bitmap.recycle() }
            }
            "transform", "merge" -> {
                val sources = call.argument<List<Map<String, Any?>>>("sources") ?: listOf(mapOf("path" to path(call), "password" to (call.argument<String>("password") ?: ""), "pages" to call.argument<List<Int>>("pages")))
                require(sources.isNotEmpty() && sources.size <= 30) { "每次合并支持 1—30 份文件" }
                val opened = mutableListOf<PDDocument>()
                val out = PDDocument()
                try {
                    for (source in sources) {
                        check()
                        val doc = open(source["path"] as String, source["password"] as? String ?: "")
                        opened.add(doc)
                        @Suppress("UNCHECKED_CAST")
                        val indices = (source["pages"] as? List<Number>)?.map { it.toInt() } ?: (0 until doc.numberOfPages).toList()
                        require(indices.isNotEmpty() && indices.all { it in 0 until doc.numberOfPages }) { "页面序列无效" }
                        for (index in indices) {
                            check(); require(out.numberOfPages < 500) { "导出最多 500 页" }
                            val original = doc.getPage(index)
                            val imported = out.importPage(original)
                            imported.resources = original.resources
                            imported.mediaBox = original.mediaBox
                            imported.cropBox = original.cropBox
                            val rotate = call.argument<Int>("rotation") ?: 0
                            val rotationPages = call.argument<List<Int>>("rotationPages")
                            imported.rotation = (original.rotation + if (rotationPages == null || rotationPages.contains(index)) rotate else 0) % 360
                        }
                    }
                    return save(out)
                } finally { out.close(); opened.forEach { it.close() } }
            }
            "images" -> {
                val paths = requireNotNull(call.argument<List<String>>("images"))
                require(paths.isNotEmpty() && paths.size <= 100) { "每次支持 1—100 张图片" }
                val originalSize = call.argument<String>("paper") == "按图片尺寸"
                if (originalSize) {
                    require(paths.sumOf { File(it).length() } <= 104857600) { "按图片尺寸的输入文件总量需小于 100 MB，请分批转换" }
                }
                val out = PDDocument()
                var totalPixels = 0L
                try {
                    for (path in paths) {
                        check()
                        val bitmap = if (originalSize) originalImage(path) else boundedImage(path)
                        try {
                            if (originalSize) {
                                totalPixels += bitmap.width.toLong() * bitmap.height
                                require(totalPixels <= 64_000_000) { "按图片尺寸每批最多 6400 万像素，请分批转换；未自动缩小图片" }
                            }
                            val size = if (call.argument<String>("paper") == "Letter") PDRectangle.LETTER else PDRectangle.A4
                            val landscape = call.argument<Boolean>("landscape") ?: false
                            val rectangle = if (originalSize) PDRectangle(bitmap.width.toFloat(), bitmap.height.toFloat()) else if (landscape) PDRectangle(size.height, size.width) else size
                            val page = PDPage(rectangle); out.addPage(page)
                            val margin = if (originalSize) 0f else (call.argument<Number>("margin")?.toFloat() ?: 20f) * 72f / 25.4f
                            require(margin >= 0 && margin * 2 < min(rectangle.width, rectangle.height)) { "边距过大" }
                            val image = LosslessFactory.createFromImage(out, bitmap)
                            val scale = min((rectangle.width - 2 * margin) / bitmap.width, (rectangle.height - 2 * margin) / bitmap.height)
                            val w = bitmap.width * scale; val h = bitmap.height * scale
                            PDPageContentStream(out, page).use { it.drawImage(image, (rectangle.width - w) / 2, (rectangle.height - h) / 2, w, h) }
                        } finally { bitmap.recycle() }
                    }
                    return save(out)
                } finally { out.close() }
            }
            "watermark", "encrypt", "decrypt", "text" -> open(path(call), call.argument<String>("password") ?: "").use { doc ->
                when (call.method) {
                    "text" -> {
                        val stripper = PDFTextStripper().apply { sortByPosition = true }
                        val output = StringBuilder()
                        for (index in pages(call, doc)) { check(); stripper.startPage = index + 1; stripper.endPage = index + 1; output.append("--- 第 ${index + 1} 页 ---\n").append(stripper.getText(doc)).append('\n') }
                        return output.toString()
                    }
                    "encrypt" -> {
                        val password = call.argument<String>("newPassword") ?: ""
                        require(password.isNotEmpty() && password.toByteArray(Charsets.UTF_8).size <= 127) { "密码需为 1—127 个 UTF-8 字节" }
                        doc.isAllSecurityToBeRemoved = true
                        val policy = StandardProtectionPolicy(password, password, AccessPermission())
                        policy.encryptionKeyLength = 256
                        doc.isAllSecurityToBeRemoved = false
                        doc.protect(policy)
                    }
                    "decrypt" -> doc.isAllSecurityToBeRemoved = true
                    "watermark" -> {
                        val imagePath = call.argument<String>("image")
                        val text = call.argument<String>("text") ?: ""
                        require(imagePath != null || text.isNotBlank()) { "请输入文字或选择水印图片" }
                        val opacity = (call.argument<Number>("opacity")?.toFloat() ?: 0.25f).coerceIn(0f,1f)
                        val textSize = (call.argument<Number>("size")?.toFloat() ?: 24f).coerceIn(8f,144f)
                        require(text.length <= 128) { "文字水印最多 128 字符" }
                        val bitmap = if (imagePath != null) boundedImage(imagePath) else {
                            val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.BLACK; this.textSize = 72f; typeface = Typeface.create("sans-serif", Typeface.NORMAL) }
                            val w = paint.measureText(text).toInt().coerceIn(1,8192)
                            Bitmap.createBitmap(w,100,Bitmap.Config.ARGB_8888).also { Canvas(it).drawText(text,0f,75f,paint) }
                        }
                        if (imagePath != null) require(bitmap != null) { "水印图片无法读取" }
                        try {
                            val image = bitmap?.let { LosslessFactory.createFromImage(doc,it) }
                            for (index in pages(call,doc)) {
                                check(); val page = doc.getPage(index); val box = page.cropBox
                                val markWidth = if (image != null) min(box.width * 0.9f, if(imagePath != null) textSize * 8 else image.width * textSize / 72f) else 0f
                                val markHeight = if (image != null) markWidth * image.height / image.width else textSize
                                val position = call.argument<String>("position") ?: "center"
                                val x = box.lowerLeftX + (box.width - markWidth) / 2
                                val y = box.lowerLeftY + when(position) { "top" -> box.height - markHeight - 24; "bottom" -> 24f; else -> (box.height - markHeight) / 2 }
                                PDPageContentStream(doc, page, PDPageContentStream.AppendMode.APPEND, true, true).use { stream ->
                                    val state = PDExtendedGraphicsState(); state.nonStrokingAlphaConstant = opacity
                                    stream.setGraphicsStateParameters(state)
                                    if(image != null) stream.drawImage(image,x,y,markWidth,markHeight)
                                }
                            }
                        } finally { bitmap?.recycle() }
                    }
                }
                if (call.method != "encrypt") doc.isAllSecurityToBeRemoved = true
                return save(doc)
            }
            "fixture" -> {
                PDDocument().use { doc ->
                    val count = (call.argument<Int>("count") ?: 3).coerceIn(1,501)
                    for (index in 1..count) { val page=PDPage(if(index==2) PDRectangle.LETTER else PDRectangle.A4);doc.addPage(page);if(index==3)page.rotation=90;PDPageContentStream(doc,page).use { stream->stream.beginText();stream.setFont(PDType1Font.HELVETICA,24f);stream.newLineAtOffset(50f,700f);stream.showText("SaiSuite Test Page $index");stream.endText() } }
                    doc.documentInformation.title="SaiSuite test fixture";return save(doc)
                }
            }
            "cleanup" -> {
                val paths = call.argument<List<String>>("paths") ?: emptyList()
                for (path in paths) { val f=File(path); if(f.parentFile?.canonicalFile==context.cacheDir.canonicalFile && f.name.startsWith("saisuite_") && f.isFile) f.delete() }
                return null
            }
            else -> error("不支持的 PDF 操作")
        }
    }
}
