import 'package:flutter/services.dart';

import '../../../core/errors/app_exception.dart';

/// Wrapper Dart cho MethodChannel `sms_gateway/native_sms`.
///
/// `sendSms` resolve khi `SmsManager` đã chấp nhận yêu cầu gửi (đã nhận broadcast
/// `SENT` thành công). Nếu hệ thống báo lỗi, throw [NativeSendException] kèm
/// mã lỗi gốc.
class NativeSmsSender {
  static const MethodChannel _channel = MethodChannel('sms_gateway/native_sms');

  Future<void> sendSms({
    required String phoneNumber,
    required String message,
  }) async {
    try {
      await _channel.invokeMethod<bool>('sendSms', {
        'phoneNumber': phoneNumber,
        'message': message,
      });
    } on PlatformException catch (e) {
      throw NativeSendException(e.code, e.message ?? 'Native SMS send failed');
    }
  }

  Future<bool> hasSmsPermission() async {
    try {
      final result = await _channel.invokeMethod<bool>('hasSmsPermission');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> startForegroundService() async {
    try {
      await _channel.invokeMethod<void>('startForegroundService');
    } on PlatformException catch (e) {
      throw NativeSendException(e.code, e.message ?? 'Failed to start service');
    }
  }

  Future<void> stopForegroundService() async {
    try {
      await _channel.invokeMethod<void>('stopForegroundService');
    } on PlatformException catch (e) {
      throw NativeSendException(e.code, e.message ?? 'Failed to stop service');
    }
  }
}
