# Hướng dẫn xây dựng tính năng gửi SMS bằng SIM điện thoại Android với .NET Backend và Flutter

> Mục tiêu: xây dựng một hệ thống cho phép backend .NET của dự án tạo yêu cầu gửi SMS, sau đó một ứng dụng Flutter chạy trên điện thoại Android của bạn sẽ lấy yêu cầu đó và gửi SMS bằng SIM thật trong điện thoại.

---

## 1. Tổng quan ý tưởng

Bạn đang có:

- Backend dự án viết bằng .NET.
- Trong backend đã có hoặc sẽ có `SmsService`.
- Một điện thoại Android có gắn SIM.
- Muốn dùng chính SIM đó để gửi SMS tự động.
- Muốn phần app gateway làm bằng Flutter.

Cách làm đúng là **không để backend .NET gửi SMS trực tiếp**, vì backend không có quyền truy cập SIM của điện thoại. Thay vào đó, ta biến điện thoại Android thành một **SMS Gateway nội bộ**.

Mô hình tổng quát:

```text
.NET Backend
   ↓
SmsService
   ↓
Database SMS Queue
   ↓
Flutter Android SMS Gateway App
   ↓
Native Android SmsManager
   ↓
SIM trên điện thoại Android
   ↓
Người nhận SMS
```

Backend chỉ tạo lệnh gửi SMS và lưu vào database. Flutter app trên Android sẽ lấy lệnh đó, xin quyền `SEND_SMS`, gọi native Android để gửi SMS bằng SIM, rồi báo trạng thái gửi lại cho backend.

---

## 2. Vì sao cần Flutter + Native Android?

Flutter tự nó không trực tiếp gửi SMS bằng SIM ở tầng Dart thuần. Có 2 hướng:

### Hướng 1: Dùng package Flutter có sẵn

Một số package trên pub.dev có hỗ trợ gửi SMS như:

- `flutter_send_sms`
- `telephony`
- `telephony_sms`
- `sms_sender`
- `another_telephony`
- `flutter_native_sms`

Tuy nhiên, với tính năng gateway nội bộ, nên cẩn thận vì:

- Một số package có thể không còn được maintain tốt.
- Có package chỉ mở màn hình soạn SMS, không gửi nền.
- Có package hoạt động khác nhau giữa các phiên bản Android.
- Có package không hỗ trợ tốt dual SIM hoặc trạng thái gửi.

### Hướng 2: Flutter gọi native Android qua MethodChannel

Đây là hướng nên dùng cho dự án của bạn.

Flutter phụ trách:

- UI.
- Lưu cấu hình gateway token.
- Gọi API backend.
- Hiển thị log gửi SMS.
- Điều phối service polling.

Native Android Kotlin phụ trách:

- Kiểm tra quyền `SEND_SMS`.
- Gửi SMS thật bằng `SmsManager`.
- Trả kết quả về Flutter.

Flutter chính thức hỗ trợ Platform Channels/MethodChannel để gọi code platform-specific như Android Kotlin hoặc Java từ Dart.

---

## 3. Kiến trúc tổng thể hệ thống

### 3.1. Các thành phần chính

```text
Backend .NET
├── SmsService
├── SmsController
├── SmsGatewayController
├── SmsMessage Entity
├── SmsGatewayDevice Entity
└── Database

Flutter Android App
├── Presentation Layer
├── Application Layer
├── Data Layer
├── Domain Layer
├── Native Android MethodChannel
└── Foreground/Polling Worker

Android Phone
├── SIM
├── SMS permission
└── Native SmsManager
```

---

## 4. Flow nghiệp vụ tổng quát

### 4.1. Flow gửi SMS thông thường

```text
User hoặc hệ thống cần gửi SMS
        ↓
.NET Backend gọi SmsService.QueueSmsAsync(...)
        ↓
Backend lưu SMS vào bảng sms_messages với status = Pending
        ↓
Flutter Android Gateway App polling API /api/sms-gateway/messages/pending
        ↓
Backend trả về danh sách SMS đang chờ gửi
        ↓
Flutter gọi native Android qua MethodChannel
        ↓
Native Android dùng SmsManager gửi SMS bằng SIM
        ↓
Native Android trả kết quả về Flutter
        ↓
Flutter gọi API report về backend
        ↓
Backend cập nhật trạng thái Sent hoặc Failed
```

### 4.2. Flow gửi OTP

```text
User nhập số điện thoại
        ↓
Backend tạo OTP
        ↓
Backend lưu OTP dạng hash
        ↓
Backend queue SMS chứa mã OTP
        ↓
Flutter Android Gateway gửi SMS
        ↓
User nhập OTP
        ↓
Backend kiểm tra OTP
```

Lưu ý: OTP nên có bảng riêng, không nên chỉ phụ thuộc vào bảng SMS.

---

## 5. Phần Backend .NET

## 5.1. Entity `SmsMessage`

```csharp
public class SmsMessage
{
    public Guid Id { get; set; }

    public string PhoneNumber { get; set; } = default!;
    public string Message { get; set; } = default!;

    public SmsStatus Status { get; set; } = SmsStatus.Pending;

    public int RetryCount { get; set; } = 0;
    public int MaxRetryCount { get; set; } = 3;

    public string? ErrorMessage { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? PickedAt { get; set; }
    public DateTime? SentAt { get; set; }
    public DateTime? FailedAt { get; set; }

    public string? GatewayDeviceId { get; set; }
}
```

## 5.2. Enum `SmsStatus`

```csharp
public enum SmsStatus
{
    Pending = 0,
    Sending = 1,
    Sent = 2,
    Failed = 3,
    Cancelled = 4
}
```

## 5.3. Entity `SmsGatewayDevice`

Dùng để quản lý điện thoại Android nào được phép lấy SMS để gửi.

```csharp
public class SmsGatewayDevice
{
    public Guid Id { get; set; }
    public string DeviceName { get; set; } = default!;
    public string DeviceCode { get; set; } = default!;
    public string ApiKeyHash { get; set; } = default!;
    public bool IsActive { get; set; } = true;

    public int DailyLimit { get; set; } = 100;
    public int SentToday { get; set; } = 0;

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? LastSeenAt { get; set; }
}
```

Không nên lưu API key plain text trong database. Nên hash giống cách lưu token.

---

## 6. SmsService trong .NET

`SmsService` chỉ nên làm nhiệm vụ queue SMS, không nên phụ thuộc trực tiếp vào việc điện thoại Android đang online hay không.

## 6.1. Interface

```csharp
public interface ISmsService
{
    Task<Guid> QueueSmsAsync(string phoneNumber, string message, CancellationToken cancellationToken = default);
}
```

## 6.2. Implementation

```csharp
public class SmsService : ISmsService
{
    private readonly AppDbContext _dbContext;

    public SmsService(AppDbContext dbContext)
    {
        _dbContext = dbContext;
    }

    public async Task<Guid> QueueSmsAsync(
        string phoneNumber,
        string message,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(phoneNumber))
            throw new ArgumentException("Phone number is required", nameof(phoneNumber));

        if (string.IsNullOrWhiteSpace(message))
            throw new ArgumentException("Message is required", nameof(message));

        var sms = new SmsMessage
        {
            Id = Guid.NewGuid(),
            PhoneNumber = phoneNumber.Trim(),
            Message = message.Trim(),
            Status = SmsStatus.Pending,
            CreatedAt = DateTime.UtcNow
        };

        _dbContext.SmsMessages.Add(sms);
        await _dbContext.SaveChangesAsync(cancellationToken);

        return sms.Id;
    }
}
```

---

## 7. API cho hệ thống gọi gửi SMS

API này dành cho frontend/admin/backend nội bộ gọi để tạo yêu cầu gửi SMS.

```http
POST /api/sms/send
```

Request:

```json
{
  "phoneNumber": "0901234567",
  "message": "Ma OTP cua ban la 123456"
}
```

Response:

```json
{
  "smsId": "5d6e7fd6-8e56-4db2-9316-55fbf7e01234",
  "status": "Pending"
}
```

Ví dụ controller:

```csharp
[ApiController]
[Route("api/sms")]
public class SmsController : ControllerBase
{
    private readonly ISmsService _smsService;

    public SmsController(ISmsService smsService)
    {
        _smsService = smsService;
    }

    [HttpPost("send")]
    public async Task<IActionResult> Send([FromBody] QueueSmsRequest request)
    {
        var smsId = await _smsService.QueueSmsAsync(
            request.PhoneNumber,
            request.Message
        );

        return Ok(new
        {
            smsId,
            status = "Pending"
        });
    }
}

public class QueueSmsRequest
{
    public string PhoneNumber { get; set; } = default!;
    public string Message { get; set; } = default!;
}
```

---

## 8. API cho Flutter Android Gateway App

Đây là nhóm API chỉ dành cho điện thoại Android gateway.

### 8.1. Lấy danh sách SMS pending

```http
GET /api/sms-gateway/messages/pending?limit=5
Authorization: Bearer <gateway-token>
X-Device-Code: android-gateway-001
```

Response:

```json
[
  {
    "id": "5d6e7fd6-8e56-4db2-9316-55fbf7e01234",
    "phoneNumber": "0901234567",
    "message": "Ma OTP cua ban la 123456"
  }
]
```

### 8.2. Report trạng thái gửi SMS

```http
POST /api/sms-gateway/messages/report
Authorization: Bearer <gateway-token>
X-Device-Code: android-gateway-001
```

Request khi gửi thành công:

```json
{
  "smsId": "5d6e7fd6-8e56-4db2-9316-55fbf7e01234",
  "status": "Sent",
  "errorMessage": null
}
```

Request khi gửi lỗi:

```json
{
  "smsId": "5d6e7fd6-8e56-4db2-9316-55fbf7e01234",
  "status": "Failed",
  "errorMessage": "Missing SEND_SMS permission"
}
```

---

## 9. Logic lấy SMS pending trong backend

Khi Android lấy SMS pending, backend nên chuyển trạng thái từ `Pending` sang `Sending` để tránh nhiều thiết bị cùng lấy một SMS.

Ví dụ:

```csharp
[HttpGet("messages/pending")]
public async Task<IActionResult> GetPendingMessages([FromQuery] int limit = 5)
{
    limit = Math.Clamp(limit, 1, 20);

    var messages = await _dbContext.SmsMessages
        .Where(x => x.Status == SmsStatus.Pending)
        .OrderBy(x => x.CreatedAt)
        .Take(limit)
        .ToListAsync();

    foreach (var message in messages)
    {
        message.Status = SmsStatus.Sending;
        message.PickedAt = DateTime.UtcNow;
        message.GatewayDeviceId = GetCurrentDeviceCode();
    }

    await _dbContext.SaveChangesAsync();

    return Ok(messages.Select(x => new
    {
        id = x.Id,
        phoneNumber = x.PhoneNumber,
        message = x.Message
    }));
}
```

Trong production, nên dùng transaction hoặc row lock để tránh race condition nếu có nhiều gateway device.

---

## 10. Logic report trạng thái trong backend

```csharp
[HttpPost("messages/report")]
public async Task<IActionResult> Report([FromBody] SmsReportRequest request)
{
    var sms = await _dbContext.SmsMessages
        .FirstOrDefaultAsync(x => x.Id == request.SmsId);

    if (sms == null)
        return NotFound();

    if (request.Status == "Sent")
    {
        sms.Status = SmsStatus.Sent;
        sms.SentAt = DateTime.UtcNow;
        sms.ErrorMessage = null;
    }
    else if (request.Status == "Failed")
    {
        sms.RetryCount += 1;
        sms.ErrorMessage = request.ErrorMessage;

        if (sms.RetryCount < sms.MaxRetryCount)
        {
            sms.Status = SmsStatus.Pending;
        }
        else
        {
            sms.Status = SmsStatus.Failed;
            sms.FailedAt = DateTime.UtcNow;
        }
    }
    else
    {
        return BadRequest("Invalid status");
    }

    await _dbContext.SaveChangesAsync();

    return Ok();
}

public class SmsReportRequest
{
    public Guid SmsId { get; set; }
    public string Status { get; set; } = default!;
    public string? ErrorMessage { get; set; }
}
```

---

# 11. Phần Flutter Android SMS Gateway App

## 11.1. Vai trò của Flutter app

Flutter app sẽ làm các việc sau:

- Màn hình nhập backend URL.
- Màn hình nhập gateway token.
- Xin quyền gửi SMS.
- Kiểm tra trạng thái quyền SMS.
- Polling backend để lấy SMS pending.
- Gọi native Android để gửi SMS.
- Report kết quả gửi về backend.
- Hiển thị lịch sử/log gửi SMS.
- Cho phép bật/tắt gateway.

---

## 12. Cấu trúc thư mục Flutter đề xuất

Dự án nên tổ chức theo kiểu clean architecture đơn giản.

```text
sms_gateway_app/
├── android/
│   └── app/
│       └── src/
│           └── main/
│               ├── AndroidManifest.xml
│               └── kotlin/
│                   └── com/example/sms_gateway_app/
│                       └── MainActivity.kt
│
├── ios/
│
├── lib/
│   ├── main.dart
│   ├── app.dart
│   │
│   ├── core/
│   │   ├── constants/
│   │   │   ├── api_constants.dart
│   │   │   └── storage_keys.dart
│   │   ├── errors/
│   │   │   └── app_exception.dart
│   │   ├── network/
│   │   │   ├── api_client.dart
│   │   │   └── api_result.dart
│   │   ├── permissions/
│   │   │   └── sms_permission_service.dart
│   │   └── storage/
│   │       └── local_storage_service.dart
│   │
│   ├── features/
│   │   └── sms_gateway/
│   │       ├── data/
│   │       │   ├── datasources/
│   │       │   │   └── sms_gateway_remote_datasource.dart
│   │       │   ├── models/
│   │       │   │   ├── pending_sms_model.dart
│   │       │   │   └── sms_report_request_model.dart
│   │       │   └── repositories/
│   │       │       └── sms_gateway_repository_impl.dart
│   │       │
│   │       ├── domain/
│   │       │   ├── entities/
│   │       │   │   └── pending_sms.dart
│   │       │   ├── repositories/
│   │       │   │   └── sms_gateway_repository.dart
│   │       │   └── usecases/
│   │       │       ├── fetch_pending_sms_usecase.dart
│   │       │       ├── report_sms_status_usecase.dart
│   │       │       └── send_sms_usecase.dart
│   │       │
│   │       ├── presentation/
│   │       │   ├── controllers/
│   │       │   │   └── sms_gateway_controller.dart
│   │       │   ├── pages/
│   │       │   │   ├── gateway_home_page.dart
│   │       │   │   ├── gateway_settings_page.dart
│   │       │   │   └── gateway_logs_page.dart
│   │       │   └── widgets/
│   │       │       ├── gateway_status_card.dart
│   │       │       └── sms_log_item.dart
│   │       │
│   │       └── native/
│   │           └── native_sms_sender.dart
│   │
│   └── shared/
│       ├── widgets/
│       │   └── app_button.dart
│       └── utils/
│           └── phone_number_utils.dart
│
├── pubspec.yaml
└── README.md
```

---

## 13. Các package Flutter nên dùng

Trong `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter

  dio: ^5.0.0
  shared_preferences: ^2.0.0
  permission_handler: ^12.0.0
  uuid: ^4.0.0

  # Nếu dùng state management đơn giản
  provider: ^6.0.0

  # Hoặc nếu dự án của bạn quen Riverpod
  # flutter_riverpod: ^2.0.0
```

Gợi ý:

- `dio`: gọi API backend.
- `shared_preferences`: lưu backend URL, token, device code.
- `permission_handler`: xin quyền SMS.
- `provider` hoặc `riverpod`: quản lý state app.

Với phần gửi SMS thật, tài liệu này ưu tiên dùng `MethodChannel` thay vì phụ thuộc package SMS gửi nền.

---

## 14. Xin quyền SEND_SMS trong Flutter

### 14.1. Khai báo trong AndroidManifest.xml

File:

```text
android/app/src/main/AndroidManifest.xml
```

Thêm quyền này bên ngoài thẻ `<application>`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-permission android:name="android.permission.SEND_SMS" />
    <uses-permission android:name="android.permission.READ_PHONE_STATE" />

    <application
        android:label="SMS Gateway"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher">

        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">

            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>

    </application>
</manifest>
```

`READ_PHONE_STATE` không bắt buộc nếu bạn chỉ gửi SMS bằng SIM mặc định. Nếu muốn đọc thông tin SIM hoặc chọn SIM, có thể cần thêm quyền và logic native nâng cao.

### 14.2. Service xin quyền trong Flutter

File:

```text
lib/core/permissions/sms_permission_service.dart
```

```dart
import 'package:permission_handler/permission_handler.dart';

class SmsPermissionService {
  Future<bool> hasSmsPermission() async {
    final status = await Permission.sms.status;
    return status.isGranted;
  }

  Future<bool> requestSmsPermission() async {
    final status = await Permission.sms.request();
    return status.isGranted;
  }

  Future<void> openSettings() async {
    await openAppSettings();
  }
}
```

### 14.3. Sử dụng trong UI

```dart
final permissionService = SmsPermissionService();

Future<void> enableGateway() async {
  final hasPermission = await permissionService.hasSmsPermission();

  if (!hasPermission) {
    final granted = await permissionService.requestSmsPermission();

    if (!granted) {
      // Hiển thị dialog: cần cấp quyền SMS để gateway hoạt động
      return;
    }
  }

  // Bắt đầu polling backend
}
```

---

## 15. Gửi SMS bằng MethodChannel

## 15.1. Dart side: `NativeSmsSender`

File:

```text
lib/features/sms_gateway/native/native_sms_sender.dart
```

```dart
import 'package:flutter/services.dart';

class NativeSmsSender {
  static const MethodChannel _channel = MethodChannel('sms_gateway/native_sms');

  Future<void> sendSms({
    required String phoneNumber,
    required String message,
  }) async {
    await _channel.invokeMethod('sendSms', {
      'phoneNumber': phoneNumber,
      'message': message,
    });
  }
}
```

---

## 15.2. Android side: `MainActivity.kt`

File:

```text
android/app/src/main/kotlin/com/example/sms_gateway_app/MainActivity.kt
```

Ví dụ Kotlin:

```kotlin
package com.example.sms_gateway_app

import android.Manifest
import android.content.pm.PackageManager
import android.telephony.SmsManager
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "sms_gateway/native_sms"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "sendSms" -> {
                    val phoneNumber = call.argument<String>("phoneNumber")
                    val message = call.argument<String>("message")

                    if (phoneNumber.isNullOrBlank() || message.isNullOrBlank()) {
                        result.error("INVALID_ARGUMENT", "Phone number and message are required", null)
                        return@setMethodCallHandler
                    }

                    sendSms(phoneNumber, message, result)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun sendSms(
        phoneNumber: String,
        message: String,
        result: MethodChannel.Result
    ) {
        val permission = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.SEND_SMS
        )

        if (permission != PackageManager.PERMISSION_GRANTED) {
            result.error("MISSING_PERMISSION", "SEND_SMS permission is not granted", null)
            return
        }

        try {
            val smsManager = SmsManager.getDefault()
            val parts = smsManager.divideMessage(message)

            if (parts.size > 1) {
                smsManager.sendMultipartTextMessage(
                    phoneNumber,
                    null,
                    parts,
                    null,
                    null
                )
            } else {
                smsManager.sendTextMessage(
                    phoneNumber,
                    null,
                    message,
                    null,
                    null
                )
            }

            result.success(true)
        } catch (ex: Exception) {
            result.error("SEND_SMS_FAILED", ex.message, null)
        }
    }
}
```

Lưu ý: đoạn code trên trả `success` khi đã gọi API gửi SMS thành công. Nếu muốn biết chắc SMS đã được gửi bởi hệ thống hay chưa, bạn cần nâng cấp thêm `PendingIntent` và BroadcastReceiver để nhận trạng thái `SENT`/`DELIVERED`.

---

## 16. Model Flutter

## 16.1. Entity `PendingSms`

File:

```text
lib/features/sms_gateway/domain/entities/pending_sms.dart
```

```dart
class PendingSms {
  final String id;
  final String phoneNumber;
  final String message;

  const PendingSms({
    required this.id,
    required this.phoneNumber,
    required this.message,
  });
}
```

## 16.2. Model `PendingSmsModel`

File:

```text
lib/features/sms_gateway/data/models/pending_sms_model.dart
```

```dart
import '../../domain/entities/pending_sms.dart';

class PendingSmsModel extends PendingSms {
  const PendingSmsModel({
    required super.id,
    required super.phoneNumber,
    required super.message,
  });

  factory PendingSmsModel.fromJson(Map<String, dynamic> json) {
    return PendingSmsModel(
      id: json['id'] as String,
      phoneNumber: json['phoneNumber'] as String,
      message: json['message'] as String,
    );
  }
}
```

## 16.3. Report request model

File:

```text
lib/features/sms_gateway/data/models/sms_report_request_model.dart
```

```dart
class SmsReportRequestModel {
  final String smsId;
  final String status;
  final String? errorMessage;

  const SmsReportRequestModel({
    required this.smsId,
    required this.status,
    this.errorMessage,
  });

  Map<String, dynamic> toJson() {
    return {
      'smsId': smsId,
      'status': status,
      'errorMessage': errorMessage,
    };
  }
}
```

---

## 17. API Client Flutter

File:

```text
lib/core/network/api_client.dart
```

```dart
import 'package:dio/dio.dart';

class ApiClient {
  final Dio _dio;

  ApiClient({
    required String baseUrl,
    required String gatewayToken,
    required String deviceCode,
  }) : _dio = Dio(
          BaseOptions(
            baseUrl: baseUrl,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 10),
            headers: {
              'Authorization': 'Bearer $gatewayToken',
              'X-Device-Code': deviceCode,
            },
          ),
        );

  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) {
    return _dio.get(path, queryParameters: queryParameters);
  }

  Future<Response<dynamic>> post(
    String path, {
    Object? data,
  }) {
    return _dio.post(path, data: data);
  }
}
```

---

## 18. Remote datasource

File:

```text
lib/features/sms_gateway/data/datasources/sms_gateway_remote_datasource.dart
```

```dart
import '../../../../core/network/api_client.dart';
import '../models/pending_sms_model.dart';
import '../models/sms_report_request_model.dart';

class SmsGatewayRemoteDatasource {
  final ApiClient apiClient;

  SmsGatewayRemoteDatasource(this.apiClient);

  Future<List<PendingSmsModel>> fetchPendingMessages({int limit = 5}) async {
    final response = await apiClient.get(
      '/api/sms-gateway/messages/pending',
      queryParameters: {'limit': limit},
    );

    final data = response.data as List<dynamic>;

    return data
        .map((item) => PendingSmsModel.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> reportStatus(SmsReportRequestModel request) async {
    await apiClient.post(
      '/api/sms-gateway/messages/report',
      data: request.toJson(),
    );
  }
}
```

---

## 19. Repository Flutter

## 19.1. Domain repository

File:

```text
lib/features/sms_gateway/domain/repositories/sms_gateway_repository.dart
```

```dart
import '../entities/pending_sms.dart';

abstract class SmsGatewayRepository {
  Future<List<PendingSms>> fetchPendingMessages({int limit});

  Future<void> reportSent(String smsId);

  Future<void> reportFailed(String smsId, String errorMessage);
}
```

## 19.2. Repository implementation

File:

```text
lib/features/sms_gateway/data/repositories/sms_gateway_repository_impl.dart
```

```dart
import '../../domain/entities/pending_sms.dart';
import '../../domain/repositories/sms_gateway_repository.dart';
import '../datasources/sms_gateway_remote_datasource.dart';
import '../models/sms_report_request_model.dart';

class SmsGatewayRepositoryImpl implements SmsGatewayRepository {
  final SmsGatewayRemoteDatasource remoteDatasource;

  SmsGatewayRepositoryImpl(this.remoteDatasource);

  @override
  Future<List<PendingSms>> fetchPendingMessages({int limit = 5}) {
    return remoteDatasource.fetchPendingMessages(limit: limit);
  }

  @override
  Future<void> reportSent(String smsId) {
    return remoteDatasource.reportStatus(
      SmsReportRequestModel(
        smsId: smsId,
        status: 'Sent',
      ),
    );
  }

  @override
  Future<void> reportFailed(String smsId, String errorMessage) {
    return remoteDatasource.reportStatus(
      SmsReportRequestModel(
        smsId: smsId,
        status: 'Failed',
        errorMessage: errorMessage,
      ),
    );
  }
}
```

---

## 20. Usecase gửi SMS

File:

```text
lib/features/sms_gateway/domain/usecases/send_sms_usecase.dart
```

```dart
import '../../native/native_sms_sender.dart';

class SendSmsUsecase {
  final NativeSmsSender nativeSmsSender;

  SendSmsUsecase(this.nativeSmsSender);

  Future<void> call({
    required String phoneNumber,
    required String message,
  }) {
    return nativeSmsSender.sendSms(
      phoneNumber: phoneNumber,
      message: message,
    );
  }
}
```

---

## 21. Controller Flutter xử lý polling

File:

```text
lib/features/sms_gateway/presentation/controllers/sms_gateway_controller.dart
```

```dart
import 'dart:async';

import '../../domain/repositories/sms_gateway_repository.dart';
import '../../domain/usecases/send_sms_usecase.dart';

class SmsGatewayController {
  final SmsGatewayRepository repository;
  final SendSmsUsecase sendSmsUsecase;

  Timer? _timer;
  bool _isRunning = false;
  bool _isProcessing = false;

  SmsGatewayController({
    required this.repository,
    required this.sendSmsUsecase,
  });

  bool get isRunning => _isRunning;

  void start() {
    if (_isRunning) return;

    _isRunning = true;

    _timer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => processPendingMessages(),
    );

    processPendingMessages();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
  }

  Future<void> processPendingMessages() async {
    if (_isProcessing) return;

    _isProcessing = true;

    try {
      final messages = await repository.fetchPendingMessages(limit: 5);

      for (final sms in messages) {
        try {
          await sendSmsUsecase(
            phoneNumber: sms.phoneNumber,
            message: sms.message,
          );

          await repository.reportSent(sms.id);
        } catch (error) {
          await repository.reportFailed(sms.id, error.toString());
        }
      }
    } finally {
      _isProcessing = false;
    }
  }
}
```

Đây là bản polling đơn giản chạy khi app đang mở. Nếu muốn app hoạt động ổn định lâu dài, nên nâng cấp thành Foreground Service ở native Android.

---

## 22. UI Flutter cơ bản

## 22.1. Gateway Home Page

File:

```text
lib/features/sms_gateway/presentation/pages/gateway_home_page.dart
```

```dart
import 'package:flutter/material.dart';

import '../../../../core/permissions/sms_permission_service.dart';
import '../controllers/sms_gateway_controller.dart';

class GatewayHomePage extends StatefulWidget {
  final SmsGatewayController controller;
  final SmsPermissionService permissionService;

  const GatewayHomePage({
    super.key,
    required this.controller,
    required this.permissionService,
  });

  @override
  State<GatewayHomePage> createState() => _GatewayHomePageState();
}

class _GatewayHomePageState extends State<GatewayHomePage> {
  bool _isRunning = false;
  String _statusText = 'Gateway stopped';

  Future<void> _toggleGateway() async {
    if (_isRunning) {
      widget.controller.stop();
      setState(() {
        _isRunning = false;
        _statusText = 'Gateway stopped';
      });
      return;
    }

    final hasPermission = await widget.permissionService.hasSmsPermission();
    final granted = hasPermission || await widget.permissionService.requestSmsPermission();

    if (!granted) {
      setState(() {
        _statusText = 'SMS permission denied';
      });
      return;
    }

    widget.controller.start();

    setState(() {
      _isRunning = true;
      _statusText = 'Gateway running';
    });
  }

  @override
  void dispose() {
    widget.controller.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SMS Gateway'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _statusText,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _toggleGateway,
              child: Text(_isRunning ? 'Stop Gateway' : 'Start Gateway'),
            ),
          ],
        ),
      ),
    );
  }
}
```

---

## 23. Chạy app nền như thế nào?

Có 3 mức triển khai:

### Mức 1: MVP đơn giản

App chỉ polling khi đang mở.

Phù hợp để test nhanh:

```text
Mở app → Bấm Start Gateway → App lấy SMS pending → Gửi SMS
```

Ưu điểm:

- Dễ làm.
- Dễ debug.
- Ít lỗi nền.

Nhược điểm:

- Nếu tắt app thì không gửi nữa.

### Mức 2: Foreground Service

App chạy một service có notification thường trực.

```text
SMS Gateway is running
```

Ưu điểm:

- Ổn định hơn.
- Ít bị Android kill.
- Phù hợp gateway nội bộ.

Nhược điểm:

- Cần viết thêm native Android code.
- Cần notification permission với Android mới.

### Mức 3: Firebase Cloud Messaging + Foreground Service

Backend push thông báo khi có SMS mới, Android thức dậy lấy SMS.

Ưu điểm:

- Real-time hơn.
- Giảm polling.

Nhược điểm:

- Phức tạp hơn.
- Cần Firebase.
- Vẫn cần xử lý background restriction.

Khuyến nghị cho bạn:

```text
Giai đoạn 1: Làm MVP polling khi app mở.
Giai đoạn 2: Nâng cấp Foreground Service.
Giai đoạn 3: Nếu cần real-time mới thêm Firebase.
```

---

## 24. Bảo mật bắt buộc phải có

Vì gateway này có thể gửi SMS bằng SIM thật của bạn, nên bảo mật rất quan trọng.

Nên có:

- Gateway token riêng.
- Device code riêng cho từng điện thoại.
- Hash token trong database.
- Rate limit số SMS/phút.
- Daily limit số SMS/ngày.
- Log toàn bộ SMS đã gửi.
- Chỉ cho phép gửi tới số điện thoại hợp lệ.
- Không public API gateway ra ngoài nếu không cần.
- Nên dùng HTTPS.
- Có nút disable gateway device từ admin.

Ví dụ header bắt buộc:

```http
Authorization: Bearer <gateway-token>
X-Device-Code: android-gateway-001
```

---

## 25. Rate limit đề xuất

Vì dùng SIM cá nhân, không nên gửi quá nhiều.

Gợi ý:

```text
MVP/demo: 5 SMS/phút
Nội bộ nhỏ: 30-50 SMS/ngày
OTP test: 3 OTP/số điện thoại/10 phút
```

Không nên dùng SIM cá nhân để gửi hàng trăm hoặc hàng nghìn SMS/ngày vì dễ bị nhà mạng chặn hoặc đánh dấu spam.

---

## 26. Retry logic đề xuất

Trạng thái:

```text
Pending → Sending → Sent
Pending → Sending → Failed → Pending retry
Pending → Sending → Failed final
```

Khi Android report failed:

```text
Nếu retryCount < maxRetryCount:
    status = Pending
Nếu retryCount >= maxRetryCount:
    status = Failed
```

Các lỗi thường gặp:

- Chưa cấp quyền `SEND_SMS`.
- SIM hết tiền.
- Điện thoại mất sóng.
- Airplane mode.
- App bị kill.
- Backend không kết nối được.
- Số điện thoại sai định dạng.
- Tin nhắn quá dài.
- Nhà mạng chặn do gửi nhiều.

---

## 27. Logging trong Flutter app

Nên có màn hình logs:

```text
[10:01:02] Gateway started
[10:01:10] Fetched 2 pending SMS
[10:01:11] Sending SMS to 0901234567
[10:01:12] Sent SMS id=xxx
[10:01:22] No pending SMS
```

Có thể lưu local logs bằng:

- `shared_preferences` nếu log ít.
- `sqflite` nếu muốn log nhiều và query tốt.

MVP thì chỉ cần hiển thị log trong memory là đủ.

---

## 28. Xử lý số điện thoại Việt Nam

Nên chuẩn hóa trước khi gửi.

Ví dụ:

```text
0901234567      → 0901234567 hoặc +84901234567
+84901234567    → +84901234567
84901234567     → +84901234567
```

Trong backend nên validate:

```text
- Không rỗng.
- Chỉ chứa số và dấu +.
- Độ dài hợp lệ.
- Với Việt Nam: 10 số dạng 0xxxxxxxxx hoặc quốc tế +84xxxxxxxxx.
```

---

## 29. Những điểm cần lưu ý về Android permission

`SEND_SMS` là quyền nhạy cảm/dangerous permission. Android yêu cầu app phải khai báo quyền trong `AndroidManifest.xml` và với Android 6.0 trở lên phải xin quyền runtime khi app chạy.

Nếu đưa app lên Google Play, nhóm quyền SMS/Call Log bị Google Play hạn chế mạnh. Với gateway nội bộ, nên build APK và cài trực tiếp vào điện thoại Android của bạn thay vì publish lên Play Store.

---

## 30. Checklist triển khai MVP

### Backend .NET

- [ ] Tạo enum `SmsStatus`.
- [ ] Tạo entity `SmsMessage`.
- [ ] Tạo entity `SmsGatewayDevice`.
- [ ] Tạo migration database.
- [ ] Tạo `ISmsService`.
- [ ] Tạo `SmsService.QueueSmsAsync()`.
- [ ] Tạo `POST /api/sms/send`.
- [ ] Tạo `GET /api/sms-gateway/messages/pending`.
- [ ] Tạo `POST /api/sms-gateway/messages/report`.
- [ ] Thêm authentication cho gateway API.
- [ ] Thêm rate limit cơ bản.

### Flutter Android App

- [ ] Tạo Flutter project.
- [ ] Tổ chức thư mục theo structure ở trên.
- [ ] Thêm package `dio`, `permission_handler`, `shared_preferences`.
- [ ] Khai báo `SEND_SMS` trong `AndroidManifest.xml`.
- [ ] Tạo `SmsPermissionService`.
- [ ] Tạo `NativeSmsSender` dùng MethodChannel.
- [ ] Viết Kotlin code trong `MainActivity.kt` để gửi SMS.
- [ ] Tạo API client.
- [ ] Tạo datasource/repository/usecase.
- [ ] Tạo màn hình Start/Stop Gateway.
- [ ] Polling backend mỗi 10 giây.
- [ ] Report Sent/Failed về backend.
- [ ] Test với số điện thoại thật.

---

## 31. Roadmap triển khai theo giai đoạn

### Giai đoạn 1: MVP gửi SMS khi app đang mở

Mục tiêu:

- Backend queue SMS.
- Flutter app lấy SMS pending.
- Android gửi SMS bằng SIM.
- Backend nhận trạng thái.

Hoàn thành giai đoạn này là bạn đã chứng minh được tính năng hoạt động.

### Giai đoạn 2: Làm app ổn định hơn

Thêm:

- Log màn hình.
- Retry tốt hơn.
- Rate limit.
- Device management.
- Validate số điện thoại.
- Cảnh báo khi mất quyền SMS.
- Cảnh báo khi gateway offline.

### Giai đoạn 3: Chạy nền ổn định

Thêm:

- Foreground Service Android.
- Notification thường trực.
- Tự khởi động lại gateway khi app mở.
- Kiểm tra mạng.
- Kiểm tra last seen device.

### Giai đoạn 4: Production nội bộ

Thêm:

- HTTPS.
- Token rotation.
- Admin dashboard xem SMS logs.
- Cấu hình daily limit.
- Cảnh báo SIM lỗi/mất sóng.
- Có nhiều gateway phones nếu cần.

---

## 32. Khi nào không nên dùng cách này?

Không nên dùng Android SIM Gateway nếu:

- Cần gửi số lượng lớn SMS.
- Cần gửi OTP cho production nghiêm túc.
- Cần cam kết tin nhắn đến nhanh và ổn định.
- Cần gửi SMS brandname.
- Cần báo cáo delivery chính xác từ nhà mạng.

Khi đó nên dùng SMS Gateway chính thức:

- Viettel SMS Brandname.
- VNPT SMS.
- FPT SMS.
- eSMS.vn.
- SpeedSMS.
- Twilio.
- Vonage.
- Infobip.

---

## 33. Kết luận kiến trúc nên làm

Với dự án của bạn, kiến trúc phù hợp nhất là:

```text
.NET Backend
    ↓
SmsService.QueueSmsAsync()
    ↓
sms_messages table
    ↓
SmsGatewayController
    ↓
Flutter Android Gateway App
    ↓
MethodChannel
    ↓
Kotlin Native SmsManager
    ↓
SIM điện thoại Android
    ↓
Người nhận SMS
```

Điểm cốt lõi:

- Backend không gửi SMS trực tiếp.
- Backend chỉ queue SMS.
- Flutter app là gateway.
- Native Android mới gửi SMS bằng SIM.
- Cần xin quyền `SEND_SMS`.
- Nên bắt đầu bằng polling đơn giản.
- Sau đó mới nâng cấp Foreground Service.

---

## 34. Tài liệu tham khảo

- Android `Manifest.permission.SEND_SMS`: https://developer.android.com/reference/android/Manifest.permission
- Android runtime permissions: https://developer.android.com/training/permissions/requesting
- Flutter Platform Channels: https://docs.flutter.dev/platform-integration/platform-channels
- permission_handler package: https://pub.dev/packages/permission_handler
- Google Play SMS/Call Log policy: https://support.google.com/googleplay/android-developer/answer/10208820

