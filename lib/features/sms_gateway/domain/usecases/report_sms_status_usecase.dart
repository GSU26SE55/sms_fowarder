import '../repositories/sms_gateway_repository.dart';

class ReportSmsStatusUsecase {
  final SmsGatewayRepository repository;

  ReportSmsStatusUsecase(this.repository);

  Future<void> sent(String smsId) => repository.reportSent(smsId);

  Future<void> failed(String smsId, String errorMessage) =>
      repository.reportFailed(smsId, errorMessage);
}
