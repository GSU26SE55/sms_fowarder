package com.example.sms_gateway_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat

/**
 * Foreground service giữ tiến trình Dart/Flutter của ứng dụng sống lâu hơn khi
 * gateway đang chạy.
 *
 * Service KHÔNG tự chạy polling — polling vẫn nằm ở SmsGatewayController phía
 * Dart. Vai trò của service là:
 *
 *  1. Hiển thị notification thường trực để Android không kill app.
 *  2. Giữ một partial wake lock nhẹ giúp Timer Dart không bị tạm dừng khi
 *     màn hình tắt thời gian dài.
 *  3. Tạo entry-point để (sau này) có thể nâng cấp polling sang native nếu cần.
 */
class SmsGatewayService : Service() {

    private var wakeLock: PowerManager.WakeLock? = null

    companion object {
        private const val CHANNEL_ID = "sms_gateway_channel"
        private const val CHANNEL_NAME = "SMS Gateway"
        private const val NOTIFICATION_ID = 1001

        fun start(context: Context) {
            val intent = Intent(context, SmsGatewayService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            // Dùng stopService trực tiếp thay vì startService(ACTION_STOP) để
            // không bị ForegroundServiceStartNotAllowedException trên Android 12+
            // khi app đang background.
            try {
                context.stopService(Intent(context, SmsGatewayService::class.java))
            } catch (_: Exception) {
                // Service có thể đã bị Android kill — bỏ qua.
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startInForeground()
        acquireWakeLock()
        return START_STICKY
    }

    private fun startInForeground() {
        val tapIntent = packageManager.getLaunchIntentForPackage(packageName)
        val tapPending = tapIntent?.let {
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
            PendingIntent.getActivity(this, 0, it, flags)
        }

        val notification: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("SMS Gateway")
            .setContentText("Forwarding queued SMS from backend")
            // Vector drawable monochrome → render đúng silhouette trắng trên status bar.
            // Fallback launcher icon nếu drawable không tồn tại (defensive — sẽ tồn tại
            // vì ic_stat_sms.xml đã ship trong res/drawable/).
            .setSmallIcon(R.drawable.ic_stat_sms)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(tapPending)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "sms_gateway:polling"
        ).apply {
            setReferenceCounted(false)
            acquire(10 * 60 * 60 * 1000L /* 10 hours */)
        }
    }

    private fun releaseWakeLock() {
        try {
            if (wakeLock?.isHeld == true) wakeLock?.release()
        } catch (_: Exception) { }
        wakeLock = null
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Foreground notification for SMS gateway polling"
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    override fun onDestroy() {
        releaseWakeLock()
        super.onDestroy()
    }
}
