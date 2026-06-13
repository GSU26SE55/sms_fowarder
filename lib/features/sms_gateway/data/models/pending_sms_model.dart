import '../../domain/entities/pending_sms.dart';

class PendingSmsModel extends PendingSms {
  const PendingSmsModel({
    required super.id,
    required super.phoneNumber,
    required super.message,
  });

  factory PendingSmsModel.fromJson(Map<String, dynamic> json) {
    return PendingSmsModel(
      id: json['id'].toString(),
      phoneNumber: json['phoneNumber'] as String,
      message: json['message'] as String,
    );
  }
}
