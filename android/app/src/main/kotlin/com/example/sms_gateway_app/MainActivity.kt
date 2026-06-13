package com.example.sms_gateway_app

import android.Manifest
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.telephony.SmsManager
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL_NAME = "sms_gateway/native_sms"
        private const val ACTION_SENT = "com.example.sms_gateway_app.SMS_SENT"
        const val EXTRA_REQUEST_ID = "request_id"
    }

    private val mainHandler by lazy { android.os.Handler(android.os.Looper.getMainLooper()) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "sendSms" -> {
                    val phoneNumber = call.argument<String>("phoneNumber")
                    val message = call.argument<String>("message")
                    if (phoneNumber.isNullOrBlank() || message.isNullOrBlank()) {
                        result.error("INVALID_ARGUMENT", "Phone number and message are required", null)
                        return@setMethodCallHandler
                    }
                    sendSms(phoneNumber, message, result)
                }
                "hasSmsPermission" -> result.success(hasSmsPermission())
                "startForegroundService" -> {
                    SmsGatewayService.start(applicationContext)
                    result.success(null)
                }
                "stopForegroundService" -> {
                    SmsGatewayService.stop(applicationContext)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun hasSmsPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.SEND_SMS
        ) == PackageManager.PERMISSION_GRANTED
    }

    /**
     * Gửi SMS qua SmsManager. Đăng ký một BroadcastReceiver dynamic để bắt
     * kết quả SENT và chuyển về Flutter qua MethodChannel.Result.
     *
     * Nhờ vậy `Future.sendSms()` ở Dart chỉ resolve khi radio đã thật sự chấp
     * nhận, thay vì chỉ "đã gọi API gửi".
     */
    private fun sendSms(
        phoneNumber: String,
        message: String,
        result: MethodChannel.Result
    ) {
        if (!hasSmsPermission()) {
            result.error("MISSING_PERMISSION", "SEND_SMS permission is not granted", null)
            return
        }

        val smsManager: SmsManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            getSystemService(SmsManager::class.java)
        } else {
            @Suppress("DEPRECATION")
            SmsManager.getDefault()
        }

        val parts = smsManager.divideMessage(message)
        val requestId = UUID.randomUUID().toString()

        val sentIntent = Intent(ACTION_SENT).apply {
            setPackage(packageName)
            putExtra(EXTRA_REQUEST_ID, requestId)
        }
        val piFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val sentPending = PendingIntent.getBroadcast(
            this, requestId.hashCode(), sentIntent, piFlags
        )

        // Counter giảm dần khi mỗi part trả về RESULT_OK; chỉ resolve khi == 0
        // hoặc khi có part đầu tiên fail. Đảm bảo MethodChannel.Result được
        // complete đúng MỘT lần với trạng thái phản ánh toàn bộ multipart.
        val remaining = AtomicInteger(parts.size)
        val resolved = AtomicBoolean(false)
        lateinit var timeoutRunnable: Runnable
        lateinit var receiver: BroadcastReceiver

        fun finishOk() {
            if (!resolved.compareAndSet(false, true)) return
            mainHandler.removeCallbacks(timeoutRunnable)
            try { unregisterReceiver(receiver) } catch (_: Exception) {}
            result.success(true)
        }

        fun finishError(code: String, message: String) {
            if (!resolved.compareAndSet(false, true)) return
            mainHandler.removeCallbacks(timeoutRunnable)
            try { unregisterReceiver(receiver) } catch (_: Exception) {}
            result.error(code, message, null)
        }

        receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (intent.getStringExtra(EXTRA_REQUEST_ID) != requestId) return
                if (resolved.get()) return
                when (resultCode) {
                    android.app.Activity.RESULT_OK -> {
                        if (remaining.decrementAndGet() == 0) finishOk()
                    }
                    SmsManager.RESULT_ERROR_GENERIC_FAILURE ->
                        finishError("GENERIC_FAILURE", "SMS generic failure")
                    SmsManager.RESULT_ERROR_NO_SERVICE ->
                        finishError("NO_SERVICE", "No cellular service")
                    SmsManager.RESULT_ERROR_NULL_PDU ->
                        finishError("NULL_PDU", "Null PDU")
                    SmsManager.RESULT_ERROR_RADIO_OFF ->
                        finishError("RADIO_OFF", "Radio off (airplane mode?)")
                    else ->
                        finishError("UNKNOWN", "SMS failed with resultCode=$resultCode")
                }
            }
        }

        val filter = IntentFilter(ACTION_SENT)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(receiver, filter)
        }

        // Safety net: 30 giây không nhận đủ broadcast → coi như fail.
        timeoutRunnable = Runnable {
            finishError("TIMEOUT", "No SENT broadcast within 30s")
        }
        mainHandler.postDelayed(timeoutRunnable, 30_000)

        try {
            if (parts.size > 1) {
                val sentList = ArrayList<PendingIntent>(parts.size).apply {
                    repeat(parts.size) { add(sentPending) }
                }
                smsManager.sendMultipartTextMessage(
                    phoneNumber, null, parts, sentList, null
                )
            } else {
                smsManager.sendTextMessage(
                    phoneNumber, null, message, sentPending, null
                )
            }
        } catch (ex: Exception) {
            finishError("SEND_SMS_FAILED", ex.message ?: "SMS send failed")
        }
    }
}
