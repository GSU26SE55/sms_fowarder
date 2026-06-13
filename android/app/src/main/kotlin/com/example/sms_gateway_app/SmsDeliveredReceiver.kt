package com.example.sms_gateway_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class SmsDeliveredReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Log.d("SmsDeliveredReceiver", "SMS_DELIVERED received, resultCode=$resultCode")
    }
}
