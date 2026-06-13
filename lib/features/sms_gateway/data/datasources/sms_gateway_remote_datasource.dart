import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../models/pending_sms_model.dart';
import '../models/sms_report_request_model.dart';

class SmsGatewayRemoteDatasource {
  final ApiClient apiClient;

  SmsGatewayRemoteDatasource(this.apiClient);

  Future<List<PendingSmsModel>> fetchPendingMessages({int limit = ApiConstants.defaultBatchSize}) async {
    final response = await apiClient.get(
      ApiConstants.pendingMessagesPath,
      queryParameters: {'limit': limit},
    );

    final raw = response.data;
    if (raw == null) return const [];

    // Backend trả về list trực tiếp hoặc dạng { items: [...] }
    final List<dynamic> data = raw is List<dynamic>
        ? raw
        : (raw is Map<String, dynamic> && raw['items'] is List)
            ? raw['items'] as List<dynamic>
            : const [];

    return data
        .map((item) => PendingSmsModel.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<void> reportStatus(SmsReportRequestModel request) async {
    await apiClient.post(ApiConstants.reportPath, data: request.toJson());
  }

  Future<void> heartbeat() async {
    await apiClient.post(ApiConstants.heartbeatPath, data: const {});
  }
}
