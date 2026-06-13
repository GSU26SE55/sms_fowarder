import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sms_gateway_app/features/sms_gateway/domain/usecases/report_sms_status_usecase.dart';

import '../../../../../helpers/test_helpers.dart';

void main() {
  late MockSmsGatewayRepository repo;
  late ReportSmsStatusUsecase usecase;

  setUp(() {
    repo = MockSmsGatewayRepository();
    usecase = ReportSmsStatusUsecase(repo);
  });

  test('sent → reportSent on repository', () async {
    when(() => repo.reportSent(any())).thenAnswer((_) async {});
    await usecase.sent('sms-1');
    verify(() => repo.reportSent('sms-1')).called(1);
  });

  test('failed → reportFailed on repository', () async {
    when(() => repo.reportFailed(any(), any())).thenAnswer((_) async {});
    await usecase.failed('sms-2', 'why');
    verify(() => repo.reportFailed('sms-2', 'why')).called(1);
  });

  test('sent propagates exception from repository', () async {
    when(() => repo.reportSent(any())).thenThrow(Exception('boom'));
    expect(() => usecase.sent('x'), throwsException);
  });

  test('failed propagates exception from repository', () async {
    when(() => repo.reportFailed(any(), any()))
        .thenThrow(Exception('boom'));
    expect(() => usecase.failed('x', 'r'), throwsException);
  });

  test('sent + failed in sequence both forwarded', () async {
    when(() => repo.reportSent(any())).thenAnswer((_) async {});
    when(() => repo.reportFailed(any(), any())).thenAnswer((_) async {});
    await usecase.sent('a');
    await usecase.failed('b', 'why');
    verify(() => repo.reportSent('a')).called(1);
    verify(() => repo.reportFailed('b', 'why')).called(1);
  });
}
