class SmsReportRequestModel {
  final String smsId;
  final String status;
  final String? errorMessage;

  const SmsReportRequestModel({
    required this.smsId,
    required this.status,
    this.errorMessage,
  });

  Map<String, dynamic> toJson() => {
        'smsId': smsId,
        'status': status,
        'errorMessage': errorMessage,
      };
}
