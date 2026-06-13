# SMS Gateway App (Flutter + Native Android)

Ứng dụng Android viết bằng Flutter, biến điện thoại có SIM thành **SMS Gateway nội bộ**
cho backend `.NET`. Theo guide gốc ở `../flutter_android_sms_gateway_guide.md`.

## Kiến trúc

```
.NET backend  →  sms_messages (Pending)  ←─ poll ─  Flutter App  →  MethodChannel  →  Kotlin  →  SmsManager  →  SIM
```

- **Dart (Flutter)**: UI, lưu config, polling backend, điều phối gửi/report, log.
- **Kotlin native**: kiểm quyền `SEND_SMS`, gọi `SmsManager`, BroadcastReceiver bắt
  kết quả `SENT` rồi trả về Flutter qua `MethodChannel.Result`.
- **Foreground Service**: `SmsGatewayService` giữ app sống khi màn hình tắt
  (notification thường trực + partial wake lock).

## Cấu trúc

```
lib/
├── main.dart                     # Entry point, init storage rồi run app
├── app.dart                      # MultiProvider + MaterialApp
├── core/
│   ├── constants/                # API paths + storage keys
│   ├── errors/                   # AppException hierarchy
│   ├── network/                  # Dio ApiClient + ApiResult
│   ├── permissions/              # SmsPermissionService (SEND_SMS, notification)
│   └── storage/                  # SharedPreferences config
├── features/sms_gateway/
│   ├── data/                     # datasource + models + repository impl
│   ├── domain/                   # entities + repositories + usecases
│   ├── native/                   # MethodChannel wrapper
│   └── presentation/             # controllers + pages + widgets
└── shared/                       # phone utils + common widgets

android/app/src/main/kotlin/com/example/sms_gateway_app/
├── MainActivity.kt               # MethodChannel handler
├── SmsGatewayService.kt          # Foreground service + wake lock
├── SmsSentReceiver.kt
└── SmsDeliveredReceiver.kt
```

## Chạy thử

```bash
flutter pub get
flutter run                # cắm điện thoại Android thật
```

App khởi động vào **Gateway Home**, bấm biểu tượng ⚙ để cấu hình:

| Trường              | Ý nghĩa                                                |
| ------------------- | ------------------------------------------------------ |
| Backend URL         | `https://api.example.com` (không có dấu `/` cuối)     |
| Gateway token       | Plain text token do admin backend cấp.                 |
| Device code         | Mã device đăng ký trên backend (`android-gateway-001`).|
| Polling interval    | Giây giữa các lần poll, 5–600.                         |
| Auto start          | Tự bắt đầu khi mở app.                                 |

Bấm **Start gateway**:
1. Xin `SEND_SMS` (và `POST_NOTIFICATIONS` trên Android 13+).
2. Khởi động `SmsGatewayService` (foreground notification).
3. `Timer.periodic` poll `GET /api/sms-gateway/messages/pending` mỗi N giây.
4. Với mỗi SMS lấy được:
   - Gọi `MethodChannel('sms_gateway/native_sms').invokeMethod('sendSms', …)`.
   - Native gửi qua `SmsManager.sendTextMessage` (hoặc `sendMultipartTextMessage`).
   - Đợi BroadcastReceiver bắt `SENT` rồi resolve Future.
   - `POST /api/sms-gateway/messages/report` với `Sent` hoặc `Failed`.
5. Mỗi 1 phút gửi `POST /api/sms-gateway/heartbeat`.

## API contract (backend phải khớp)

Xem `../backend-sms-fowarder.md`.

Headers Flutter gửi:

```
Authorization: Bearer <gateway-token>
X-Device-Code: <device-code>
Content-Type: application/json
```

Endpoints:

```
GET  /api/sms-gateway/messages/pending?limit=5
POST /api/sms-gateway/messages/report     { smsId, status, errorMessage }
POST /api/sms-gateway/heartbeat
```

## Build APK

```bash
flutter build apk --release
# APK ở build/app/outputs/flutter-apk/app-release.apk
```

> Không publish lên Google Play vì `SEND_SMS` thuộc nhóm permission bị Google Play
> hạn chế. Cài trực tiếp `adb install` hoặc gửi APK cho điện thoại gateway.

## Lưu ý

- App chỉ gửi SMS bằng SIM mặc định. Muốn chọn SIM (dual-SIM), cần `READ_PHONE_STATE`
  + `SubscriptionManager.getActiveSubscriptionInfoList()` ở Kotlin (chưa triển khai).
- Timeout `SENT` broadcast = 30 giây trong `MainActivity.kt`.
- Số điện thoại được chuẩn hoá về dạng E.164 Việt Nam (`+84xxxxxxxxx`) trước khi gửi.
- Daily limit / rate limit nằm phía backend.
