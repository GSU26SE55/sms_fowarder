enum SmsLogLevel { info, success, warning, error }

class SmsLogEntry {
  final DateTime timestamp;
  final SmsLogLevel level;
  final String message;
  final String? smsId;

  const SmsLogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.smsId,
  });

  factory SmsLogEntry.info(String message, {String? smsId}) =>
      SmsLogEntry(timestamp: DateTime.now(), level: SmsLogLevel.info, message: message, smsId: smsId);

  factory SmsLogEntry.success(String message, {String? smsId}) =>
      SmsLogEntry(timestamp: DateTime.now(), level: SmsLogLevel.success, message: message, smsId: smsId);

  factory SmsLogEntry.warning(String message, {String? smsId}) =>
      SmsLogEntry(timestamp: DateTime.now(), level: SmsLogLevel.warning, message: message, smsId: smsId);

  factory SmsLogEntry.error(String message, {String? smsId}) =>
      SmsLogEntry(timestamp: DateTime.now(), level: SmsLogLevel.error, message: message, smsId: smsId);
}
