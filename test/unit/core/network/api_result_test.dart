import 'package:flutter_test/flutter_test.dart';
import 'package:sms_gateway_app/core/network/api_result.dart';

void main() {
  group('ApiResult.when', () {
    test('success branch returns mapped value', () {
      final result = ApiSuccess<int>(42);
      final mapped = result.when(
        success: (data) => 'ok=$data',
        failure: (msg, code) => 'fail',
      );
      expect(mapped, 'ok=42');
    });

    test('failure branch passes message + status code', () {
      final result = ApiFailure<int>('boom', statusCode: 502);
      final mapped = result.when(
        success: (_) => 'ok',
        failure: (msg, code) => 'fail=$msg/$code',
      );
      expect(mapped, 'fail=boom/502');
    });

    test('failure with null status code', () {
      final result = ApiFailure<String>('no network');
      final out = result.when(
        success: (_) => 'ok',
        failure: (msg, code) => '$msg|${code ?? 'no-code'}',
      );
      expect(out, 'no network|no-code');
    });
  });

  test('sealed pattern matching via instance check', () {
    final results = <ApiResult<int>>[
      ApiSuccess<int>(1),
      ApiFailure<int>('x'),
    ];
    expect(results.whereType<ApiSuccess<int>>(), hasLength(1));
    expect(results.whereType<ApiFailure<int>>(), hasLength(1));
  });
}
