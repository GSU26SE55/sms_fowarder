import 'package:flutter_test/flutter_test.dart';
import 'package:sms_gateway_app/shared/utils/phone_number_utils.dart';

void main() {
  group('PhoneNumberUtils.normalizeVn', () {
    test('keeps E.164 number unchanged', () {
      expect(PhoneNumberUtils.normalizeVn('+84901234567'), '+84901234567');
    });

    test('converts 84xxxxxxxxx to +84xxxxxxxxx', () {
      expect(PhoneNumberUtils.normalizeVn('84901234567'), '+84901234567');
    });

    test('converts 0xxxxxxxxx (10 digits) to +84xxxxxxxxx', () {
      expect(PhoneNumberUtils.normalizeVn('0901234567'), '+84901234567');
    });

    test('strips spaces, dashes, parens, dots', () {
      expect(PhoneNumberUtils.normalizeVn('090 123-4567'), '+84901234567');
      expect(PhoneNumberUtils.normalizeVn('(090) 123.4567'), '+84901234567');
    });

    test('returns input unchanged when format is unknown', () {
      expect(PhoneNumberUtils.normalizeVn('12345'), '12345');
    });

    test('handles empty input', () {
      expect(PhoneNumberUtils.normalizeVn(''), '');
    });
  });

  group('PhoneNumberUtils.isValid', () {
    test('accepts +84… format', () {
      expect(PhoneNumberUtils.isValid('+84901234567'), isTrue);
    });

    test('accepts 9-digit number without +', () {
      expect(PhoneNumberUtils.isValid('123456789'), isTrue);
    });

    test('accepts up to 15 digits', () {
      expect(PhoneNumberUtils.isValid('+123456789012345'), isTrue);
    });

    test('rejects empty', () {
      expect(PhoneNumberUtils.isValid(''), isFalse);
      expect(PhoneNumberUtils.isValid('   '), isFalse);
    });

    test('rejects fewer than 9 digits', () {
      expect(PhoneNumberUtils.isValid('12345678'), isFalse);
    });

    test('rejects letters', () {
      expect(PhoneNumberUtils.isValid('+84abc1234567'), isFalse);
    });

    test('rejects special chars', () {
      expect(PhoneNumberUtils.isValid('+84-901-234-567'), isFalse);
    });

    test('rejects 16 digits (over max)', () {
      expect(PhoneNumberUtils.isValid('+1234567890123456'), isFalse);
    });

    test('rejects single + only', () {
      expect(PhoneNumberUtils.isValid('+'), isFalse);
    });

    test('rejects only special chars', () {
      expect(PhoneNumberUtils.isValid('++++'), isFalse);
      expect(PhoneNumberUtils.isValid('-/.'), isFalse);
    });

    test('rejects letter in middle', () {
      expect(PhoneNumberUtils.isValid('+849O1234567'), isFalse); // capital O
    });
  });

  group('PhoneNumberUtils.normalizeVn — quốc tế', () {
    test('keeps US E.164 unchanged', () {
      expect(PhoneNumberUtils.normalizeVn('+14155551234'), '+14155551234');
    });

    test('keeps UK E.164 unchanged', () {
      expect(PhoneNumberUtils.normalizeVn('+447911123456'), '+447911123456');
    });

    test('non-VN 10-digit starting with 0 left unchanged-ish', () {
      // Số nội địa của nước khác như '0123456789' (10 ký tự) bị normalize
      // thành +84xxxxxxxxx vì rule chỉ nhận biết 0xxx của VN. Trade-off
      // đã biết — gateway VN nội bộ.
      expect(PhoneNumberUtils.normalizeVn('0123456789'), '+84123456789');
    });
  });

  group('PhoneNumberUtils.normalizeVn — whitespace + special chars', () {
    test('strips tabs', () {
      expect(PhoneNumberUtils.normalizeVn('090\t123\t4567'), '+84901234567');
    });

    test('strips mixed whitespace + parens + dots', () {
      expect(PhoneNumberUtils.normalizeVn('(090).123.4567'), '+84901234567');
    });

    test('keeps + only at start', () {
      // Already has + → returns as-is after stripping junk.
      expect(PhoneNumberUtils.normalizeVn('+84 (90) 1234-567'),
          '+84901234567');
    });
  });

  group('PhoneNumberUtils.normalizeVn — boundary', () {
    test('9-digit input without prefix returned as-is', () {
      // Không match 0xx (10 digits) nor 84xxx (11 digits) nor + → as-is
      expect(PhoneNumberUtils.normalizeVn('123456789'), '123456789');
    });

    test('only whitespace input returns empty', () {
      expect(PhoneNumberUtils.normalizeVn('   '), '');
    });

    test('84 prefix but only 10 digits total (not VN format)', () {
      // 8412345 = 7 chars, không match 11 chars rule
      expect(PhoneNumberUtils.normalizeVn('8412345'), '8412345');
    });

    test('multiple plus signs treated as start with +', () {
      // Bắt đầu bằng + thì giữ nguyên (đã được strip junk khác).
      expect(PhoneNumberUtils.normalizeVn('++84901234567').startsWith('+'),
          isTrue);
    });
  });

  group('PhoneNumberUtils.isValid combined with normalizeVn', () {
    test('round-trip: normalize 0901234567 → +84901234567 → valid', () {
      final n = PhoneNumberUtils.normalizeVn('0901234567');
      expect(PhoneNumberUtils.isValid(n), isTrue);
    });

    test('garbage input normalizes to garbage, fails isValid', () {
      final n = PhoneNumberUtils.normalizeVn('abc xyz');
      expect(PhoneNumberUtils.isValid(n), isFalse);
    });
  });
}
