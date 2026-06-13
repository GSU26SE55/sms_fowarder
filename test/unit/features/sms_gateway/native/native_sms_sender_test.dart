import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sms_gateway_app/core/errors/app_exception.dart';
import 'package:sms_gateway_app/features/sms_gateway/native/native_sms_sender.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('sms_gateway/native_sms');

  late NativeSmsSender sender;

  setUp(() {
    sender = NativeSmsSender();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  void mockChannel(Future<dynamic> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
  }

  group('sendSms', () {
    test('invokes sendSms with phoneNumber + message', () async {
      MethodCall? captured;
      mockChannel((call) async {
        captured = call;
        return true;
      });

      await sender.sendSms(phoneNumber: '+84901234567', message: 'hi');

      expect(captured?.method, 'sendSms');
      expect(captured?.arguments,
          {'phoneNumber': '+84901234567', 'message': 'hi'});
    });

    test('wraps PlatformException into NativeSendException', () async {
      mockChannel((call) async {
        throw PlatformException(code: 'NO_SERVICE', message: 'no signal');
      });

      expect(
        () => sender.sendSms(phoneNumber: '+84', message: 'm'),
        throwsA(isA<NativeSendException>()
            .having((e) => e.code, 'code', 'NO_SERVICE')
            .having((e) => e.message, 'message', 'no signal')),
      );
    });
  });

  group('hasSmsPermission', () {
    test('returns native true', () async {
      mockChannel((call) async => true);
      expect(await sender.hasSmsPermission(), isTrue);
    });

    test('returns false on PlatformException', () async {
      mockChannel((call) async {
        throw PlatformException(code: 'X');
      });
      expect(await sender.hasSmsPermission(), isFalse);
    });
  });

  group('startForegroundService / stopForegroundService', () {
    test('start invokes correct method', () async {
      String? lastMethod;
      mockChannel((call) async {
        lastMethod = call.method;
        return null;
      });
      await sender.startForegroundService();
      expect(lastMethod, 'startForegroundService');
    });

    test('stop wraps error', () async {
      mockChannel((call) async {
        throw PlatformException(code: 'X', message: 'boom');
      });
      expect(
        () => sender.stopForegroundService(),
        throwsA(isA<NativeSendException>()),
      );
    });
  });

  group('sendSms — all known PlatformException codes', () {
    final codes = [
      ('GENERIC_FAILURE', 'SMS generic failure'),
      ('NO_SERVICE', 'No cellular service'),
      ('NULL_PDU', 'Null PDU'),
      ('RADIO_OFF', 'Radio off (airplane mode?)'),
      ('TIMEOUT', 'No SENT broadcast within 30s'),
      ('MISSING_PERMISSION', 'SEND_SMS permission is not granted'),
      ('INVALID_ARGUMENT', 'Phone number and message are required'),
      ('UNKNOWN', 'SMS failed with resultCode=42'),
    ];

    for (final (code, msg) in codes) {
      test('code $code maps to NativeSendException', () async {
        mockChannel((call) async {
          throw PlatformException(code: code, message: msg);
        });
        expect(
          () => sender.sendSms(phoneNumber: '+84', message: 'm'),
          throwsA(isA<NativeSendException>()
              .having((e) => e.code, 'code', code)
              .having((e) => e.message, 'message', msg)),
        );
      });
    }
  });

  group('sendSms — null platform message', () {
    test('falls back to default message when native message is null',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('sms_gateway/native_sms'), (call) async {
        throw PlatformException(code: 'X');
      });
      try {
        await sender.sendSms(phoneNumber: '+84', message: 'm');
        fail('expected throw');
      } catch (e) {
        expect(e, isA<NativeSendException>());
        final n = e as NativeSendException;
        expect(n.message, isNotEmpty);
      }
    });
  });

  group('hasSmsPermission — null result handled', () {
    test('returns false when native returns null', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('sms_gateway/native_sms'),
              (call) async => null);
      expect(await sender.hasSmsPermission(), isFalse);
    });
  });

  group('start/stop foreground — success returns null', () {
    test('start completes without throwing', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('sms_gateway/native_sms'),
              (call) async => null);
      expect(() => sender.startForegroundService(), returnsNormally);
    });

    test('stop completes without throwing', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('sms_gateway/native_sms'),
              (call) async => null);
      expect(() => sender.stopForegroundService(), returnsNormally);
    });
  });
}
