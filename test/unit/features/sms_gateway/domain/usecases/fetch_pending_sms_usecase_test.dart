import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sms_gateway_app/features/sms_gateway/domain/entities/pending_sms.dart';
import 'package:sms_gateway_app/features/sms_gateway/domain/usecases/fetch_pending_sms_usecase.dart';

import '../../../../../helpers/test_helpers.dart';

void main() {
  late MockSmsGatewayRepository repo;
  late FetchPendingSmsUsecase usecase;

  setUp(() {
    repo = MockSmsGatewayRepository();
    usecase = FetchPendingSmsUsecase(repo);
  });

  test('forwards default limit (5) to repository', () async {
    when(() => repo.fetchPendingMessages(limit: any(named: 'limit')))
        .thenAnswer((_) async => const [
              PendingSms(id: 'a', phoneNumber: '+84', message: 'm'),
            ]);
    final r = await usecase();
    expect(r, hasLength(1));
    verify(() => repo.fetchPendingMessages(limit: 5)).called(1);
  });

  test('forwards custom limit', () async {
    when(() => repo.fetchPendingMessages(limit: any(named: 'limit')))
        .thenAnswer((_) async => const []);
    await usecase(limit: 12);
    verify(() => repo.fetchPendingMessages(limit: 12)).called(1);
  });

  test('returns empty list when repository returns empty', () async {
    when(() => repo.fetchPendingMessages(limit: any(named: 'limit')))
        .thenAnswer((_) async => const []);
    expect(await usecase(), isEmpty);
  });

  test('propagates exception from repository', () async {
    when(() => repo.fetchPendingMessages(limit: any(named: 'limit')))
        .thenThrow(Exception('boom'));
    expect(() => usecase(), throwsException);
  });
}
