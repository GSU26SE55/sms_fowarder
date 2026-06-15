import '../../../../core/constants/api_constants.dart';
import '../../../../core/errors/app_exception.dart';
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

    // Backend SmsService trả CommonResponse<T>: { isSuccess, statusCode, message, data: [...] }
    // Defensive check: trong production backend chỉ trả isSuccess=false kèm HTTP 4xx (đã được
    // ApiClient._ensureSuccess throw trước khi tới đây) — nhưng nếu có bug server trả 200+isSuccess=false,
    // throw NetworkException để controller xử lý đúng như 401/403 (xem _PendingPollWorker).
    if (raw is Map<String, dynamic> && raw.containsKey('isSuccess')) {
      final isSuccess = raw['isSuccess'] as bool? ?? false;
      if (!isSuccess) {
        final statusCode = raw['statusCode'] as int?;
        throw NetworkException(
          'Backend rejected pending fetch: ${raw['message'] ?? 'unknown error'}',
          statusCode: statusCode,
        );
      }
    }

    final List<dynamic> data;
    if (raw is Map<String, dynamic> && raw['data'] is List) {
      // 🆕 CommonResponse<List<T>> shape — backend SmsService chuẩn
      data = raw['data'] as List<dynamic>;
    } else if (raw is List<dynamic>) {
      // Legacy fallback (backend cũ chưa wrap response)
      data = raw;
    } else if (raw is Map<String, dynamic> && raw['items'] is List) {
      // Legacy fallback (backend cũ dùng key `items`)
      data = raw['items'] as List<dynamic>;
    } else {
      data = const [];
    }

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
