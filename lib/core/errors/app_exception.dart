class AppException implements Exception {
  final String message;
  final Object? cause;

  const AppException(this.message, [this.cause]);

  @override
  String toString() => 'AppException: $message';
}

class ConfigurationException extends AppException {
  const ConfigurationException(super.message);
}

class PermissionDeniedException extends AppException {
  const PermissionDeniedException(super.message);
}

class NetworkException extends AppException {
  final int? statusCode;
  const NetworkException(String message, {this.statusCode, Object? cause})
      : super(message, cause);
}

class NativeSendException extends AppException {
  final String code;
  const NativeSendException(this.code, String message) : super(message);
}
