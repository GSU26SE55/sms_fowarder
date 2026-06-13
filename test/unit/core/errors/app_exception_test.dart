import 'package:flutter_test/flutter_test.dart';
import 'package:sms_gateway_app/core/errors/app_exception.dart';

void main() {
  group('AppException', () {
    test('toString includes message', () {
      const e = AppException('boom');
      expect(e.toString(), contains('boom'));
    });

    test('preserves optional cause', () {
      final inner = StateError('inner');
      final e = AppException('outer', inner);
      expect(e.message, 'outer');
      expect(e.cause, inner);
    });
  });

  group('Specialized exceptions', () {
    test('ConfigurationException is AppException', () {
      const e = ConfigurationException('cfg');
      expect(e, isA<AppException>());
      expect(e.message, 'cfg');
    });

    test('PermissionDeniedException is AppException', () {
      const e = PermissionDeniedException('perm');
      expect(e, isA<AppException>());
    });

    test('NetworkException carries statusCode + cause', () {
      final inner = Exception('socket');
      final e = NetworkException('http fail', statusCode: 502, cause: inner);
      expect(e, isA<AppException>());
      expect(e.statusCode, 502);
      expect(e.message, 'http fail');
      expect(e.cause, inner);
    });

    test('NativeSendException carries code', () {
      const e = NativeSendException('NO_SERVICE', 'No cellular service');
      expect(e, isA<AppException>());
      expect(e.code, 'NO_SERVICE');
      expect(e.message, 'No cellular service');
    });
  });
}
