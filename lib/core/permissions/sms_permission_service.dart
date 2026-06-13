import 'package:permission_handler/permission_handler.dart';

class SmsPermissionService {
  Future<bool> hasSmsPermission() async {
    final status = await Permission.sms.status;
    return status.isGranted;
  }

  Future<bool> requestSmsPermission() async {
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
