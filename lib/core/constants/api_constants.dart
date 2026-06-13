class ApiConstants {
  ApiConstants._();

  static const String pendingMessagesPath = '/api/sms-gateway/messages/pending';
  static const String reportPath = '/api/sms-gateway/messages/report';
  static const String heartbeatPath = '/api/sms-gateway/heartbeat';

  /// SignalR Hub path (mount qua `MapHub<SmsGatewayHub>` ở backend).
  static const String hubPath = '/hubs/sms-gateway';

  /// Khi realtime active, polling chỉ là safety net với interval dài hơn.
  static const Duration realtimeFallbackPollInterval = Duration(seconds: 60);

  static const int defaultBatchSize = 5;
  static const Duration defaultPollingInterval = Duration(seconds: 10);
  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 10);
}
