package io.github.wxia529.saisuite

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        PdfService(this).register(MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "saisuite/pdf"))
    }
}
