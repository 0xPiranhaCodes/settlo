package app.settlo

import android.Manifest
import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The settle-up awaiting you as an ongoing notification, the Android side of
 * the Live Activity (`app.settlo/live_activity`, ADR 0012). The app shows and
 * ends it from its own state; there is no push in v1.
 */
class SettleUpNotification(private val activity: Activity) : MethodChannel.MethodCallHandler {
    // Lazy: the activity has no context yet when MainActivity constructs this.
    private val manager by lazy { activity.getSystemService(NotificationManager::class.java) }

    /** The last state the app asked for, posted once permission arrives. */
    private var current: Map<*, *>? = null
    private var permissionResult: MethodChannel.Result? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "show" -> {
                current = call.arguments as Map<*, *>
                post()
                result.success(null)
            }
            "end" -> {
                current = null
                manager.cancel(NOTIFICATION_ID)
                result.success(null)
            }
            "requestPermission" -> requestPermission(result)
            else -> result.notImplemented()
        }
    }

    private fun allowed() = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
        activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
        PackageManager.PERMISSION_GRANTED

    // Asked once, from Activity when a settle-up waits (never at launch).
    private fun requestPermission(result: MethodChannel.Result) {
        if (allowed()) return result.success(true)
        val prefs = activity.getSharedPreferences("settlo", Context.MODE_PRIVATE)
        if (permissionResult != null || prefs.getBoolean(ASKED_KEY, false)) {
            return result.success(false)
        }
        prefs.edit().putBoolean(ASKED_KEY, true).apply()
        permissionResult = result
        activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_CODE)
    }

    /** From `MainActivity.onRequestPermissionsResult`; true when it was ours. */
    fun onPermissionResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
        if (granted) post()
        permissionResult?.success(granted)
        permissionResult = null
        return true
    }

    private fun post() {
        val state = current ?: return
        if (!allowed()) return
        manager.createNotificationChannel(
            // Low: it sits in the shade without sound; the app posts it, not a person.
            NotificationChannel(CHANNEL_ID, "Settle-ups waiting for you", NotificationManager.IMPORTANCE_LOW),
        )
        // Explicit, so no other app can send Settlo this link; Flutter routes its path.
        val confirm = PendingIntent.getActivity(
            activity,
            0,
            Intent(Intent.ACTION_VIEW, Uri.parse("settlo://app${state["path"]}"), activity, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val notification = Notification.Builder(activity, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_settlo)
            .setColor(GOLD)
            .setContentTitle("${state["payer"]} paid ${state["amount"]} · confirm you received it")
            .setContentText(state["space"] as String)
            .setWhen((state["recordedAtMs"] as Number).toLong())
            .setShowWhen(true)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_REMINDER)
            .setContentIntent(confirm)
            .addAction(Notification.Action.Builder(null, "Confirm", confirm).build())
            .build()
        manager.notify(NOTIFICATION_ID, notification)
    }

    private companion object {
        const val CHANNEL_ID = "settle_ups"
        const val NOTIFICATION_ID = 1
        const val REQUEST_CODE = 105
        const val ASKED_KEY = "asked_post_notifications"
        const val GOLD = 0xFFD8B36A.toInt()
    }
}
