package app.settlo

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Settle up: open upi://pay through the app chooser (ADR 0011).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.settlo/upi")
            .setMethodCallHandler { call, result ->
                if (call.method != "openWithChooser") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val intent = Intent(Intent.ACTION_VIEW, Uri.parse(call.argument<String>("uri")))
                // Sees UPI apps on Android 11+ only through the upi <queries> entry.
                if (intent.resolveActivity(packageManager) == null) {
                    result.success(false)
                    return@setMethodCallHandler
                }
                try {
                    startActivity(Intent.createChooser(intent, call.argument<String>("title")))
                    result.success(true)
                } catch (e: ActivityNotFoundException) {
                    result.success(false)
                }
            }
    }
}
