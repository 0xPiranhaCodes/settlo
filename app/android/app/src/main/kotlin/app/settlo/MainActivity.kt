package app.settlo

import android.app.ActivityManager
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val settleUp = SettleUpNotification(this)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, "app.settlo/live_activity").setMethodCallHandler(settleUp)
        // The glass tab bar's flat fallback (canvas note n32, ADR 0012).
        MethodChannel(messenger, "app.settlo/device").setMethodCallHandler { call, result ->
            if (call.method != "prefersFlatChrome") return@setMethodCallHandler result.notImplemented()
            val am = getSystemService(ActivityManager::class.java)
            val memory = ActivityManager.MemoryInfo().also(am::getMemoryInfo)
            // Below 6 GB of RAM (reported as under 5 GiB after OS reservations) the blur costs frames.
            result.success(am.isLowRamDevice || memory.totalMem < 5L * 1024 * 1024 * 1024)
        }
        // Settle up: open upi://pay through the app chooser (ADR 0011).
        MethodChannel(messenger, "app.settlo/upi")
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

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        if (!settleUp.onPermissionResult(requestCode, grantResults)) {
            super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        }
    }
}
