import '../../domain/entities/pending_sms.dart';
import '../../domain/repositories/sms_gateway_repository.dart';
import '../datasources/sms_gateway_remote_datasource.dart';
import '../models/sms_report_request_model.dart';

class SmsGatewayRepositoryImpl implements SmsGatewayRepository {
  final SmsGatewayRemoteDatasource remoteDatasource;

  SmsGatewayRepositoryImpl(this.remoteDatasource);

  @override
  Future<List<PendingSms>> fetchPendingMessages({int limit = 5}) {
    return remoteDatasource.fetchPendingMessages(limit: limit);
  }

  @override
  Future<void> reportSent(String smsId) {
    return remoteDatasource.reportStatus(
      SmsReportRequestModel(smsId: smsId, status: 'Sent'),
    );
  }

  @override
  Future<void> reportFailed(String smsId, String errorMessage) {
    return remoteDatasource.reportStatus(
      SmsReportRequestModel(
        smsId: smsId,
        status: 'Failed',
        errorMessage: errorMessage,
      ),
    );
  }

  @override
  Future<void> heartbeat() => remoteDatasource.heartbeat();
}
