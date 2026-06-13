import 'package:dio/dio.dart';

import '../constants/api_constants.dart';
import '../errors/app_exception.dart';

class ApiClient {
  final Dio _dio;
  final String deviceCode;

  ApiClient({
    required String baseUrl,
    required String gatewayToken,
    required this.deviceCode,
  }) : _dio = Dio(
          BaseOptions(
            baseUrl: baseUrl,
            connectTimeout: ApiConstants.connectTimeout,
            receiveTimeout: ApiConstants.receiveTimeout,
            sendTimeout: ApiConstants.connectTimeout,
            headers: {
              'Authorization': 'Bearer $gatewayToken',
              'X-Device-Code': deviceCode,
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            validateStatus: (status) => status != null && status < 500,
          ),
        );

  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final response = await _dio.get<dynamic>(path, queryParameters: queryParameters);
      _ensureSuccess(response);
      return response;
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  Future<Response<dynamic>> post(String path, {Object? data}) async {
    try {
      final response = await _dio.post<dynamic>(path, data: data);
      _ensureSuccess(response);
      return response;
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  void _ensureSuccess(Response<dynamic> response) {
    final code = response.statusCode ?? 0;
    if (code < 200 || code >= 300) {
      throw NetworkException(
        'HTTP $code: ${response.statusMessage ?? 'request failed'}',
        statusCode: code,
      );
    }
  }

  NetworkException _wrap(DioException e) {
    final code = e.response?.statusCode;
    final msg = switch (e.type) {
      DioExceptionType.connectionTimeout => 'Connection timeout',
      DioExceptionType.sendTimeout => 'Send timeout',
      DioExceptionType.receiveTimeout => 'Receive timeout',
      DioExceptionType.connectionError => 'Cannot reach backend (${e.message})',
      DioExceptionType.badCertificate => 'Bad TLS certificate',
      DioExceptionType.cancel => 'Request cancelled',
      DioExceptionType.badResponse => 'HTTP $code: ${e.response?.statusMessage ?? e.message}',
      DioExceptionType.unknown => e.message ?? 'Unknown network error',
    };
    return NetworkException(msg, statusCode: code, cause: e);
  }
}
