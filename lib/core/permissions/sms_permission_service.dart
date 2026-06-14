import 'dart:io' show Platform;

import 'package:permission_handler/permission_handler.dart';

import '../../features/sms_gateway/native/native_sms_sender.dart';

class SmsPermissionService {
  SmsPermissionService({NativeSmsSender? nativeSmsSender})
      : _nativeSmsSender = nativeSmsSender ?? NativeSmsSender();

  final NativeSmsSender _nativeSmsSender;

  Future<bool> hasSmsPermission() async {
    // iOS exposes no SEND_SMS permission. Capability is gated by
    // MFMessageComposeViewController.canSendText(), surfaced via the native channel.
    if (Platform.isIOS) {
      return _nativeSmsSender.hasSmsPermission();
    }
    final status = await Permission.sms.status;
    return status.isGranted;
  }

  Future<bool> requestSmsPermission() async {
    if (Platform.isIOS) {
      return _nativeSmsSender.hasSmsPermission();
    }
    final status = await Permission.sms.request();
    return status.isGranted;
  }

  Future<bool> hasNotificationPermission() async {
    final status = await Permission.notification.status;
    return status.isGranted;
  }

  Future<bool> requestNotificationPermission() async {
    final status = await Permission.notification.request();
    return status.isGranted;
  }

  Future<bool> isPermanentlyDenied() async {
    final status = await Permission.sms.status;
    return status.isPermanentlyDenied;
  }

  Future<void> openSettings() async {
    await openAppSettings();
  }
}
