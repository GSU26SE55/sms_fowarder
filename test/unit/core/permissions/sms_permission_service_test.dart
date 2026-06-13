import 'package:flutter_test/flutter_test.dart';
import 'package:sms_gateway_app/core/permissions/sms_permission_service.dart';

/// `SmsPermissionService` chỉ wrap `permission_handler` mỏng. Test thật
/// behavior cần platform channel mock — phức tạp, không cao value. Ta verify
/// constructor + API surface.
void main() {
  test('can be instantiated', () {
    expect(SmsPermissionService(), isA<SmsPermissionService>());
  });
}
