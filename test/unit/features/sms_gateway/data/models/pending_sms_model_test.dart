import 'package:flutter_test/flutter_test.dart';
import 'package:sms_gateway_app/features/sms_gateway/data/models/pending_sms_model.dart';
import 'package:sms_gateway_app/features/sms_gateway/domain/entities/pending_sms.dart';

void main() {
  group('PendingSmsModel.fromJson', () {
    test('parses standard string id payload', () {
      final m = PendingSmsModel.fromJson({
        'id': '5d6e7fd6-8e56-4db2-9316-55fbf7e01234',
        'phoneNumber': '+84901234567',
        'message': 'Hello',
      });
      expect(m, isA<PendingSms>());
      expect(m.id, '5d6e7fd6-8e56-4db2-9316-55fbf7e01234');
      expect(m.phoneNumber, '+84901234567');
      expect(m.message, 'Hello');
    });

    test('coerces numeric id to string', () {
      final m = PendingSmsModel.fromJson({
        'id': 123,
        'phoneNumber': '+84901234567',
        'message': 'm',
      });
      expect(m.id, '123');
    });

    test('coerces double id to string', () {
      final m = PendingSmsModel.fromJson({
        'id': 99.5,
        'phoneNumber': '+84',
        'message': 'm',
      });
      expect(m.id, '99.5');
    });

    test('handles unicode message body (emoji + tiếng Việt)', () {
      final m = PendingSmsModel.fromJson({
        'id': 'sms-1',
        'phoneNumber': '+84901234567',
        'message': '🎉 Mã OTP của bạn: 123456 (đã gửi)',
      });
      expect(m.message, contains('🎉'));
      expect(m.message, contains('Mã OTP'));
    });

    test('handles long message (>160 chars, multipart)', () {
      final longMsg = 'A' * 500;
      final m = PendingSmsModel.fromJson({
        'id': 'sms-1',
        'phoneNumber': '+84',
        'message': longMsg,
      });
      expect(m.message.length, 500);
    });

    test('handles empty message string', () {
      final m = PendingSmsModel.fromJson({
        'id': 'sms-1',
        'phoneNumber': '+84',
        'message': '',
      });
      expect(m.message, isEmpty);
    });

    test('missing id key produces "null.toString()" = "null" (defensive)', () {
      // json['id'] returns null; .toString() yields 'null'. Defensive — we
      // expect upstream to enforce id presence, but here just verify behavior
      // is deterministic (no throw).
      final m = PendingSmsModel.fromJson(
          {'phoneNumber': '+84', 'message': 'm'});
      expect(m.id, 'null');
    });

    test('throws when phoneNumber is wrong type (int)', () {
      expect(
        () => PendingSmsModel.fromJson(
            {'id': 'x', 'phoneNumber': 12345, 'message': 'm'}),
        throwsA(isA<TypeError>()),
      );
    });

    test('throws when message is null', () {
      expect(
        () => PendingSmsModel.fromJson({
          'id': 'x',
          'phoneNumber': '+84',
          'message': null,
        }),
        throwsA(isA<TypeError>()),
      );
    });

    test('PendingSmsModel is a PendingSms subtype', () {
      final m = PendingSmsModel.fromJson({
        'id': '1',
        'phoneNumber': '+84',
        'message': 'm',
      });
      expect(m.id, isA<String>());
      expect(m.phoneNumber, isA<String>());
      expect(m.message, isA<String>());
    });
  });
}
