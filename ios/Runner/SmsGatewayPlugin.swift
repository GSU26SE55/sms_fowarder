import Flutter
import UIKit
import MessageUI

/// iOS bridge for the `sms_gateway/native_sms` MethodChannel.
///
/// iOS does NOT expose a programmatic SMS-send API. We surface the system
/// `MFMessageComposeViewController` instead — the user must tap Send. Any
/// background-driven send attempt resolves with an `IOS_UNSUPPORTED_BACKGROUND`
/// error so the Dart layer can mark the message accordingly.
final class SmsGatewayPlugin: NSObject, FlutterPlugin, MFMessageComposeViewControllerDelegate {

    private static let channelName = "sms_gateway/native_sms"

    private var pendingResult: FlutterResult?

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
        let instance = SmsGatewayPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "sendSms":
            guard let args = call.arguments as? [String: Any],
                  let phone = args["phoneNumber"] as? String, !phone.isEmpty,
                  let message = args["message"] as? String, !message.isEmpty else {
                result(FlutterError(code: "INVALID_ARGUMENT",
                                    message: "Phone number and message are required",
                                    details: nil))
                return
            }
            presentComposer(phoneNumber: phone, message: message, result: result)

        case "hasSmsPermission":
            // iOS has no SEND_SMS permission. Capability is gated by MFMessageComposeViewController.canSendText().
            result(MFMessageComposeViewController.canSendText())

        case "startForegroundService", "stopForegroundService":
            // No equivalent of Android foreground service on iOS — silently succeed.
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func presentComposer(phoneNumber: String, message: String, result: @escaping FlutterResult) {
        guard MFMessageComposeViewController.canSendText() else {
            result(FlutterError(code: "SMS_NOT_AVAILABLE",
                                message: "This device cannot send SMS",
                                details: nil))
            return
        }

        guard let presenter = Self.topViewController() else {
            result(FlutterError(code: "NO_PRESENTER",
                                message: "No view controller available to present composer",
                                details: nil))
            return
        }

        // If a previous composer is still onscreen, refuse rather than racing.
        if pendingResult != nil {
            result(FlutterError(code: "COMPOSER_BUSY",
                                message: "Another SMS composer is already presented",
                                details: nil))
            return
        }

        pendingResult = result
        let composer = MFMessageComposeViewController()
        composer.messageComposeDelegate = self
        composer.recipients = [phoneNumber]
        composer.body = message
        presenter.present(composer, animated: true, completion: nil)
    }

    // MARK: - MFMessageComposeViewControllerDelegate

    func messageComposeViewController(_ controller: MFMessageComposeViewController,
                                      didFinishWith result: MessageComposeResult) {
        controller.dismiss(animated: true) { [weak self] in
            guard let self = self, let pending = self.pendingResult else { return }
            self.pendingResult = nil
            switch result {
            case .sent:
                pending(true)
            case .cancelled:
                pending(FlutterError(code: "CANCELLED",
                                     message: "User cancelled the SMS composer",
                                     details: nil))
            case .failed:
                pending(FlutterError(code: "SEND_FAILED",
                                     message: "iOS reported SMS send failure",
                                     details: nil))
            @unknown default:
                pending(FlutterError(code: "UNKNOWN",
                                     message: "Unknown MessageComposeResult",
                                     details: nil))
            }
        }
    }

    // MARK: - Helpers

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }

        let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow }
            ?? scenes.flatMap { $0.windows }.first

        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
