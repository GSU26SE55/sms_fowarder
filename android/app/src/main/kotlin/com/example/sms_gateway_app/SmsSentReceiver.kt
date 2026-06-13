package com.example.sms_gateway_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Receiver dự phòng cho broadcast SMS_SENT (được khai báo trong AndroidManifest).
 *
 * Trong MainActivity chúng ta đã đăng ký receiver động (in-process) để chuyển
 * kết quả gửi về Flutter. Receiver tĩnh này chỉ log để debug khi cần.
 */
class SmsSentReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Log.d("SmsSentReceiver", "SMS_SENT received, resultCode=$resultCode")
    }
}
