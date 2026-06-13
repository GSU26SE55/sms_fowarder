import 'package:flutter_test/flutter_test.dart';
import 'package:sms_gateway_app/features/sms_gateway/data/datasources/sms_gateway_realtime_datasource.dart';

void main() {
  group('RealtimeConnectionState enum', () {
    test('has 5 states', () {
      expect(RealtimeConnectionState.values, hasLength(5));
    });

    test('contains expected values', () {
      expect(RealtimeConnectionState.values,
          contains(RealtimeConnectionState.connected));
      expect(RealtimeConnectionState.values,
          contains(RealtimeConnectionState.disconnected));
      expect(RealtimeConnectionState.values,
          contains(RealtimeConnectionState.connecting));
      expect(RealtimeConnectionState.values,
          contains(RealtimeConnectionState.reconnecting));
      expect(RealtimeConnectionState.values,
          contains(RealtimeConnectionState.failed));
    });
  });

  group('SmsGatewayRealtimeDatasource constructor', () {
    test('stores params', () {
      final ds = SmsGatewayRealtimeDatasource(
        backendUrl: 'https://b.test',
        hubPath: '/hubs/sms-gateway',
        accessToken: 'tok',
        deviceCode: 'dev-1',
      );
      expect(ds.backendUrl, 'https://b.test');
      expect(ds.hubPath, '/hubs/sms-gateway');
      expect(ds.accessToken, 'tok');
      expect(ds.deviceCode, 'dev-1');
    });

    test('isConnected is false before connect', () {
      final ds = SmsGatewayRealtimeDatasource(
        backendUrl: 'https://b.test',
        hubPath: '/h',
        accessToken: 't',
        deviceCode: 'd',
      );
      expect(ds.isConnected, isFalse);
    });
  });

  group('disconnect — no-op when never connected', () {
    test('does not throw when called fresh', () async {
      final ds = SmsGatewayRealtimeDatasource(
        backendUrl: 'https://b.test',
        hubPath: '/h',
        accessToken: 't',
        deviceCode: 'd',
      );
      // Just verify no exception.
      await ds.disconnect();
      expect(true, isTrue);
    });

    test('idempotent — multiple disconnects safe', () async {
      final ds = SmsGatewayRealtimeDatasource(
        backendUrl: 'https://b.test',
        hubPath: '/h',
        accessToken: 't',
        deviceCode: 'd',
      );
      await ds.disconnect();
      await ds.disconnect();
      await ds.disconnect();
      expect(true, isTrue);
    });
  });

  // NOTE: live `connect()` test against an unreachable host is omitted —
  // negotiation does real DNS + TCP work that varies between CI environments
  // (some machines block port 80 outbound; DNS timeout 30s). Coverage of
  // connect-failure handling is provided indirectly via
  // SmsGatewayController integration where realtime is allowed to fail.
}
