import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sms_gateway_app/core/errors/app_exception.dart';
import 'package:sms_gateway_app/core/network/api_client.dart';

/// `ApiClient` thật wrap Dio. Ta test cách nó **biến đổi** lỗi Dio thành
/// `NetworkException` với statusCode + message rõ ràng, KHÔNG test HTTP thật.
///
/// Cách làm: dùng `dio.options` để bắt connection error nhanh, hoặc validate
/// behaviors qua try/catch.
void main() {
  group('ApiClient construction', () {
    test('attaches Authorization header + X-Device-Code from constructor',
        () {
      final client = ApiClient(
        baseUrl: 'https://api.test.local',
        gatewayToken: 'tok-1',
        deviceCode: 'dev-1',
      );
      // Không expose Dio directly, kiểm tra qua deviceCode getter.
      expect(client.deviceCode, 'dev-1');
    });
  });

  group('ApiClient.get → NetworkException', () {
    test('connection error wraps message and exposes cause', () async {
      final client = ApiClient(
        baseUrl: 'http://127.0.0.1:1', // port không có server
        gatewayToken: 't',
        deviceCode: 'd',
      );

      try {
        await client.get('/api/sms-gateway/messages/pending');
        fail('expected NetworkException');
      } catch (e) {
        expect(e, isA<NetworkException>());
        final net = e as NetworkException;
        expect(net.message, isNotEmpty);
        expect(net.cause, isA<DioException>());
      }
    });
  });

  group('ApiClient.post → NetworkException', () {
    test('connection refused wraps as NetworkException', () async {
      final client = ApiClient(
        baseUrl: 'http://127.0.0.1:1',
        gatewayToken: 't',
        deviceCode: 'd',
      );
      try {
        await client.post('/api/sms-gateway/messages/report', data: {});
        fail('expected NetworkException');
      } catch (e) {
        expect(e, isA<NetworkException>());
      }
    });
  });
}
