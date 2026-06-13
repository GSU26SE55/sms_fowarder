import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sms_gateway_app/features/sms_gateway/data/models/pending_sms_model.dart';
import 'package:sms_gateway_app/features/sms_gateway/data/models/sms_report_request_model.dart';
import 'package:sms_gateway_app/features/sms_gateway/data/repositories/sms_gateway_repository_impl.dart';

import '../../../../../helpers/test_helpers.dart';

void main() {
  setUpAll(registerCommonFallbacks);

  late MockSmsGatewayRemoteDatasource ds;
  late SmsGatewayRepositoryImpl repo;

  setUp(() {
    ds = MockSmsGatewayRemoteDatasource();
    repo = SmsGatewayRepositoryImpl(ds);
    registerFallbackValue(
        const SmsReportRequestModel(smsId: 'fallback', status: 'Sent'));
  });

  test('fetchPendingMessages forwards to datasource', () async {
    when(() => ds.fetchPendingMessages(limit: any(named: 'limit')))
        .thenAnswer((_) async => const [
              PendingSmsModel(id: 'a', phoneNumber: '+84', message: 'm'),
            ]);

    final r = await repo.fetchPendingMessages(limit: 3);
    expect(r, hasLength(1));
    verify(() => ds.fetchPendingMessages(limit: 3)).called(1);
  });

  test('reportSent sends status=Sent without errorMessage', () async {
    when(() => ds.reportStatus(any())).thenAnswer((_) async {});
    await repo.reportSent('sms-id-1');
    final captured =
        verify(() => ds.reportStatus(captureAny())).captured.single
            as SmsReportRequestModel;
    expect(captured.smsId, 'sms-id-1');
    expect(captured.status, 'Sent');
    expect(captured.errorMessage, isNull);
  });

  test('reportFailed sends status=Failed with errorMessage', () async {
    when(() => ds.reportStatus(any())).thenAnswer((_) async {});
    await repo.reportFailed('sms-id-2', 'NO_SERVICE');
    final captured =
        verify(() => ds.reportStatus(captureAny())).captured.single
            as SmsReportRequestModel;
    expect(captured.smsId, 'sms-id-2');
    expect(captured.status, 'Failed');
    expect(captured.errorMessage, 'NO_SERVICE');
  });

  test('heartbeat forwards to datasource', () async {
    when(() => ds.heartbeat()).thenAnswer((_) async {});
    await repo.heartbeat();
    verify(() => ds.heartbeat()).called(1);
  });

  test('reportFailed empty errorMessage still forwarded', () async {
    when(() => ds.reportStatus(any())).thenAnswer((_) async {});
    await repo.reportFailed('sms-x', '');
    final captured =
        verify(() => ds.reportStatus(captureAny())).captured.single
            as SmsReportRequestModel;
    expect(captured.errorMessage, '');
  });

  test('multiple sequential reports', () async {
    when(() => ds.reportStatus(any())).thenAnswer((_) async {});
    await repo.reportSent('a');
    await repo.reportSent('b');
    await repo.reportFailed('c', 'why');
    verify(() => ds.reportStatus(any())).called(3);
  });

  test('error from datasource propagates from reportSent', () async {
    when(() => ds.reportStatus(any())).thenThrow(Exception('boom'));
    expect(() => repo.reportSent('x'), throwsException);
  });

  test('fetchPendingMessages: default limit forwarded', () async {
    when(() => ds.fetchPendingMessages(limit: any(named: 'limit')))
        .thenAnswer((_) async => const []);
    await repo.fetchPendingMessages();
    verify(() => ds.fetchPendingMessages(limit: 5)).called(1);
  });
}
