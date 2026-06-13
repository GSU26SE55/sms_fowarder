import '../../../../shared/utils/phone_number_utils.dart';
import '../../../../core/errors/app_exception.dart';
import '../../native/native_sms_sender.dart';

class SendSmsUsecase {
  final NativeSmsSender nativeSmsSender;

  SendSmsUsecase(this.nativeSmsSender);

  Future<void> call({
    required String phoneNumber,
    required String message,
  }) async {
    final normalized = PhoneNumberUtils.normalizeVn(phoneNumber);
    if (!PhoneNumberUtils.isValid(normalized)) {
      throw AppException('Invalid phone number: $phoneNumber');
    }
    if (message.trim().isEmpty) {
      throw const AppException('Message must not be empty');
    }
    await nativeSmsSender.sendSms(phoneNumber: normalized, message: message);
  }
}
