import '../entities/pending_sms.dart';

abstract class SmsGatewayRepository {
  Future<List<PendingSms>> fetchPendingMessages({int limit});

  Future<void> reportSent(String smsId);

  Future<void> reportFailed(String smsId, String errorMessage);

  Future<void> heartbeat();
}
