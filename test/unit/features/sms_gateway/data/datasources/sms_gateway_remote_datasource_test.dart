import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sms_gateway_app/core/constants/api_constants.dart';
import 'package:sms_gateway_app/core/network/api_client.dart';
import 'package:sms_gateway_app/features/sms_gateway/data/datasources/sms_gateway_remote_datasource.dart';
import 'package:sms_gateway_app/features/sms_gateway/data/models/sms_report_request_model.dart';

class _MockApiClient extends Mock implements ApiClient {}

Response<dynamic> _resp(dynamic data, {int code = 200}) => Response<dynamic>(
      requestOptions: RequestOptions(path: ''),
      statusCode: code,
      data: data,
    );

void main() {
  late _MockApiClient api;
  late SmsGatewayRemoteDatasource ds;

  setUp(() {
    api = _MockApiClient();
    ds = SmsGatewayRemoteDatasource(api);
  });

  group('fetchPendingMessages', () {
    test('passes correct path + query and parses list response', () async {
      when(() => api.get(
            any(),
            queryParameters: any(named: 'queryParameters'),
          )).thenAnswer((_) async => _resp([
            {'id': 'a', 'phoneNumber': '+84900000001', 'message': 'hi'},
            {'id': 'b', 'phoneNumber': '+84900000002', 'message': 'hi 2'},
          ]));
      final list = await ds.fetchPendingMessages(limit: 7);
      expect(list, hasLength(2));
      expect(list.first.id, 'a');
      verify(() => api.get(
            ApiConstants.pendingMessagesPath,
            queryParameters: {'limit': 7},
          )).called(1);
    });

    test('parses { items: [...] } envelope', () async {
      when(() => api.get(any(),
              queryParameters: any(named: 'queryParameters')))
          .thenAnswer((_) async => _resp({
                'items': [
                  {'id': 'x', 'phoneNumber': '+84', 'message': 'm'},
                ]
              }));
      final list = await ds.fetchPendingMessages();
      expect(list, hasLength(1));
      expect(list.first.id, 'x');
    });

    test('returns empty when data is null', () async {
      when(() => api.get(any(),
              queryParameters: any(named: 'queryParameters')))
          .thenAnswer((_) async => _resp(null));
      expect(await ds.fetchPendingMessages(), isEmpty);
    });

    test('returns empty when data is unexpected shape', () async {
      when(() => api.get(any(),
              queryParameters: any(named: 'queryParameters')))
          .thenAnswer((_) async => _resp({'unexpected': true}));
      expect(await ds.fetchPendingMessages(), isEmpty);
    });
  });

  group('reportStatus', () {
    test('POSTs to correct path with serialized payload', () async {
      when(() => api.post(any(), data: any(named: 'data')))
          .thenAnswer((_) async => _resp(null));
      await ds.reportStatus(const SmsReportRequestModel(
        smsId: 'sms-1',
        status: 'Sent',
      ));
      final capt = verify(() => api.post(
            ApiConstants.reportPath,
            data: captureAny(named: 'data'),
          )).captured.single as Map<String, dynamic>;
      expect(capt['smsId'], 'sms-1');
      expect(capt['status'], 'Sent');
    });
  });

  group('heartbeat', () {
    test('POSTs to heartbeat path with empty body', () async {
      when(() => api.post(any(), data: any(named: 'data')))
          .thenAnswer((_) async => _resp(null));
      await ds.heartbeat();
      verify(() => api.post(ApiConstants.heartbeatPath, data: {})).called(1);
    });
  });

  group('fetchPendingMessages — edge cases', () {
    test('default limit when caller omits it', () async {
      when(() => api.get(any(),
              queryParameters: any(named: 'queryParameters')))
          .thenAnswer((_) async => _resp([]));
      await ds.fetchPendingMessages();
      verify(() => api.get(
            ApiConstants.pendingMessagesPath,
            queryParameters: {'limit': ApiConstants.defaultBatchSize},
          )).called(1);
    });

    test('empty list response → empty result', () async {
      when(() => api.get(any(),
              queryParameters: any(named: 'queryParameters')))
          .thenAnswer((_) async => _resp([]));
      expect(await ds.fetchPendingMessages(), isEmpty);
    });

    test('items envelope with empty array', () async {
      when(() => api.get(any(),
              queryParameters: any(named: 'queryParameters')))
          .thenAnswer((_) async => _resp({'items': []}));
      expect(await ds.fetchPendingMessages(), isEmpty);
    });

    test('propagates NetworkException from ApiClient', () async {
      when(() => api.get(any(),
              queryParameters: any(named: 'queryParameters')))
          .thenThrow(Exception('boom'));
      expect(() => ds.fetchPendingMessages(), throwsException);
    });
  });

  group('reportStatus — edge cases', () {
    test('Failed status with multiline errorMessage forwards as-is',
        () async {
      when(() => api.post(any(), data: any(named: 'data')))
          .thenAnswer((_) async => _resp(null));
      await ds.reportStatus(const SmsReportRequestModel(
        smsId: 'sms-x',
        status: 'Failed',
        errorMessage: 'line1\nline2',
      ));
      final capt = verify(() => api.post(
            ApiConstants.reportPath,
            data: captureAny(named: 'data'),
          )).captured.single as Map<String, dynamic>;
      expect(capt['errorMessage'], 'line1\nline2');
    });

    test('Cancelled status accepted (server validates value)', () async {
      when(() => api.post(any(), data: any(named: 'data')))
          .thenAnswer((_) async => _resp(null));
      await ds.reportStatus(
          const SmsReportRequestModel(smsId: 'x', status: 'Cancelled'));
      // No client-side enum check — server returns 400 if invalid; that's
      // surfaced as NetworkException by ApiClient.
      verify(() => api.post(any(), data: any(named: 'data'))).called(1);
    });
  });

  group('heartbeat — edge cases', () {
    test('propagates network error', () async {
      when(() => api.post(any(), data: any(named: 'data')))
          .thenThrow(Exception('disconnected'));
      expect(() => ds.heartbeat(), throwsException);
    });
  });
}
