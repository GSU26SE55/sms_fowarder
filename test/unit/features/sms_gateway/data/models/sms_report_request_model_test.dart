import 'package:flutter_test/flutter_test.dart';
import 'package:sms_gateway_app/features/sms_gateway/data/models/sms_report_request_model.dart';

void main() {
  group('SmsReportRequestModel.toJson', () {
    test('Sent without errorMessage', () {
      const r = SmsReportRequestModel(smsId: 'sms-1', status: 'Sent');
      expect(r.toJson(), {
        'smsId': 'sms-1',
        'status': 'Sent',
        'errorMessage': null,
      });
    });

    test('Failed with errorMessage', () {
      const r = SmsReportRequestModel(
        smsId: 'sms-2',
        status: 'Failed',
        errorMessage: 'NO_SERVICE',
      );
      expect(r.toJson(), {
        'smsId': 'sms-2',
        'status': 'Failed',
        'errorMessage': 'NO_SERVICE',
      });
    });

    test('Status with multibyte chars (defensive)', () {
      const r = SmsReportRequestModel(smsId: 'x', status: 'Sent ✓');
      expect(r.toJson()['status'], 'Sent ✓');
    });

    test('errorMessage with newlines preserved', () {
      const r = SmsReportRequestModel(
        smsId: 'x',
        status: 'Failed',
        errorMessage: 'line1\nline2\nline3',
      );
      expect((r.toJson()['errorMessage'] as String).split('\n'), hasLength(3));
    });

    test('Very long errorMessage (1000 chars)', () {
      final long = 'E' * 1000;
      final r = SmsReportRequestModel(
        smsId: 'x',
        status: 'Failed',
        errorMessage: long,
      );
      expect((r.toJson()['errorMessage'] as String).length, 1000);
    });

    test('Empty smsId still serializes', () {
      const r = SmsReportRequestModel(smsId: '', status: 'Sent');
      expect(r.toJson()['smsId'], '');
    });
  });
}
