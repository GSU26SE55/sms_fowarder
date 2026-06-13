import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sms_gateway_app/core/errors/app_exception.dart';
import 'package:sms_gateway_app/features/sms_gateway/domain/usecases/send_sms_usecase.dart';

import '../../../../../helpers/test_helpers.dart';

void main() {
  late MockNativeSmsSender sender;
  late SendSmsUsecase usecase;

  setUp(() {
    sender = MockNativeSmsSender();
    usecase = SendSmsUsecase(sender);
  });

  test('normalizes VN number 0901… to +84901…', () async {
    when(() => sender.sendSms(
        phoneNumber: any(named: 'phoneNumber'),
        message: any(named: 'message'))).thenAnswer((_) async {});

    await usecase(phoneNumber: '0901234567', message: 'hi');

    verify(() => sender.sendSms(
        phoneNumber: '+84901234567', message: 'hi')).called(1);
  });

  test('throws AppException for invalid phone', () async {
    expect(
      () => usecase(phoneNumber: 'abc', message: 'm'),
      throwsA(isA<AppException>()),
    );
    verifyNever(() => sender.sendSms(
        phoneNumber: any(named: 'phoneNumber'),
        message: any(named: 'message')));
  });

  test('throws AppException for empty message', () async {
    expect(
      () => usecase(phoneNumber: '+84901234567', message: '  '),
      throwsA(isA<AppException>()),
    );
  });

  test('propagates NativeSendException from sender', () async {
    when(() => sender.sendSms(
            phoneNumber: any(named: 'phoneNumber'),
            message: any(named: 'message')))
        .thenThrow(const NativeSendException('NO_SERVICE', 'no service'));
    expect(
      () => usecase(phoneNumber: '+84901234567', message: 'hi'),
      throwsA(isA<NativeSendException>()
          .having((e) => e.code, 'code', 'NO_SERVICE')),
    );
  });

  test('rejects 8-digit phone (below min 9)', () {
    expect(
      () => usecase(phoneNumber: '12345678', message: 'm'),
      throwsA(isA<AppException>()),
    );
  });

  test('accepts long international number (15 digits)', () async {
    when(() => sender.sendSms(
            phoneNumber: any(named: 'phoneNumber'),
            message: any(named: 'message')))
        .thenAnswer((_) async {});
    await usecase(phoneNumber: '+123456789012345', message: 'm');
    verify(() => sender.sendSms(
        phoneNumber: '+123456789012345', message: 'm')).called(1);
  });

  test('passes message containing emoji + Vietnamese', () async {
    when(() => sender.sendSms(
            phoneNumber: any(named: 'phoneNumber'),
            message: any(named: 'message')))
        .thenAnswer((_) async {});
    const msg = '🔔 Mã OTP: 654321 (hết hạn sau 5 phút)';
    await usecase(phoneNumber: '0901234567', message: msg);
    verify(() => sender.sendSms(
        phoneNumber: '+84901234567', message: msg)).called(1);
  });

  test('rejects message with just whitespace', () {
    expect(
      () => usecase(phoneNumber: '+84901234567', message: '\t\n  '),
      throwsA(isA<AppException>()),
    );
  });

  test('rejects empty phone after normalize', () {
    expect(
      () => usecase(phoneNumber: '', message: 'm'),
      throwsA(isA<AppException>()),
    );
  });

  test('rejects garbage phone', () {
    expect(
      () => usecase(phoneNumber: 'abc xyz', message: 'm'),
      throwsA(isA<AppException>()),
    );
  });
}
