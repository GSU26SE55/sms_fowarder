import 'package:flutter_test/flutter_test.dart';
import 'package:sms_gateway_app/features/sms_gateway/domain/entities/sms_log_entry.dart';

void main() {
  group('SmsLogEntry factory constructors', () {
    test('info() sets level to info', () {
      final e = SmsLogEntry.info('hello');
      expect(e.level, SmsLogLevel.info);
      expect(e.message, 'hello');
      expect(e.smsId, isNull);
    });

    test('success() sets level + smsId', () {
      final e = SmsLogEntry.success('sent', smsId: 'sms-1');
      expect(e.level, SmsLogLevel.success);
      expect(e.smsId, 'sms-1');
    });

    test('warning() sets level', () {
      final e = SmsLogEntry.warning('careful');
      expect(e.level, SmsLogLevel.warning);
    });

    test('error() sets level', () {
      final e = SmsLogEntry.error('failed');
      expect(e.level, SmsLogLevel.error);
    });

    test('timestamp is set at construction time', () {
      final before = DateTime.now();
      final e = SmsLogEntry.info('m');
      final after = DateTime.now();
      expect(e.timestamp.isAfter(before.subtract(const Duration(seconds: 1))),
          isTrue);
      expect(e.timestamp.isBefore(after.add(const Duration(seconds: 1))),
          isTrue);
    });

    test('direct constructor accepts explicit fields', () {
      final ts = DateTime(2026, 1, 15, 10, 30);
      final e = SmsLogEntry(
        timestamp: ts,
        level: SmsLogLevel.warning,
        message: 'x',
        smsId: 's',
      );
      expect(e.timestamp, ts);
      expect(e.level, SmsLogLevel.warning);
    });
  });

  test('all SmsLogLevel values are unique', () {
    expect(SmsLogLevel.values.toSet().length, SmsLogLevel.values.length);
  });
}
