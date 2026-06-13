import '../entities/pending_sms.dart';
import '../repositories/sms_gateway_repository.dart';

class FetchPendingSmsUsecase {
  final SmsGatewayRepository repository;

  FetchPendingSmsUsecase(this.repository);

  Future<List<PendingSms>> call({int limit = 5}) {
    return repository.fetchPendingMessages(limit: limit);
  }
}
