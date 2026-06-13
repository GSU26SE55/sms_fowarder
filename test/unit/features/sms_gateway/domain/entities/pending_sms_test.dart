import 'package:flutter_test/flutter_test.dart';
import 'package:sms_gateway_app/features/sms_gateway/domain/entities/pending_sms.dart';

void main() {
  test('PendingSms holds id/phoneNumber/message', () {
    const sms = PendingSms(
      id: 'sms-1',
      phoneNumber: '+84901234567',
      message: 'hello',
    );
    expect(sms.id, 'sms-1');
    expect(sms.phoneNumber, '+84901234567');
    expect(sms.message, 'hello');
  });

  test('PendingSms is a const value type', () {
    const a = PendingSms(id: 'a', phoneNumber: 'p', message: 'm');
    const b = PendingSms(id: 'a', phoneNumber: 'p', message: 'm');
    // Đây là entity giá trị; với const dart sẽ canonicalize cùng instance.
    expect(identical(a, b), isTrue);
  });
}
