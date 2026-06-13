# Testing — SMS Gateway App

Tài liệu mô tả 4 loại test có trong repo và cách chạy.

## Tổng quan

Flutter có 4 loại test chính. Repo này có cả 4:

| Loại            | Vị trí                       | Yêu cầu thiết bị                  | Tốc độ      |
| --------------- | ---------------------------- | --------------------------------- | ----------- |
| **Unit**        | `test/unit/`                 | Không — chạy headless trên Dart VM | < 1s/test  |
| **Widget**      | `test/widget/`               | Không — render off-screen          | ~50ms/test |
| **Golden**      | `test/golden/`               | Không — so sánh PNG ref            | ~100ms/test|
| **Integration** | `integration_test/`          | **Có** — Android device/emulator   | ~5-30s/test|

## Cấu trúc thư mục

```
test/
├── helpers/
│   └── test_helpers.dart          # Mock classes + wrappers dùng chung
│
├── unit/                          # Pure-Dart logic, mocked dependencies
│   ├── core/
│   │   ├── errors/app_exception_test.dart
│   │   └── storage/local_storage_service_test.dart
│   ├── shared/utils/
│   │   └── phone_number_utils_test.dart
│   └── features/sms_gateway/
│       ├── data/
│       │   ├── models/
│       │   │   ├── pending_sms_model_test.dart
│       │   │   └── sms_report_request_model_test.dart
│       │   ├── datasources/sms_gateway_remote_datasource_test.dart
│       │   └── repositories/sms_gateway_repository_impl_test.dart
│       ├── domain/usecases/
│       │   ├── send_sms_usecase_test.dart
│       │   └── report_sms_status_usecase_test.dart
│       ├── native/
│       │   └── native_sms_sender_test.dart      # MethodChannel mock
│       └── presentation/controllers/
│           ├── gateway_settings_controller_test.dart
│           └── sms_gateway_controller_test.dart # core controller
│
├── widget/                        # Widget rendering + interaction
│   ├── shared/
│   │   ├── app_button_test.dart
│   │   ├── animated_status_dot_test.dart
│   │   ├── stat_card_test.dart
│   │   ├── section_card_test.dart
│   │   └── empty_state_test.dart
│   └── features/sms_gateway/
│       ├── widgets/
│       │   ├── sms_log_item_test.dart
│       │   └── gateway_status_card_test.dart
│       └── pages/
│           ├── gateway_home_page_test.dart
│           ├── gateway_settings_page_test.dart
│           └── gateway_logs_page_test.dart
│
└── golden/                        # Pixel-perfect snapshot tests
    ├── stat_card_golden_test.dart
    └── goldens/                   # auto-generated PNGs (commit to git)

integration_test/                  # End-to-end on real device
└── app_test.dart
```

## Chạy tests

### Chạy tất cả unit + widget + golden cùng lúc

```bash
flutter test
```

### Chỉ chạy 1 loại

```bash
# Unit
flutter test test/unit/

# Widget
flutter test test/widget/

# Golden
flutter test test/golden/
```

### Chỉ chạy 1 file

```bash
flutter test test/unit/shared/utils/phone_number_utils_test.dart
```

### Lần đầu chạy golden test (hoặc khi UI đổi cố tình)

```bash
flutter test --update-goldens
```

Sau khi update, **commit** thư mục `test/golden/goldens/` vào git để teammates
có baseline so sánh.

### Integration test (cần Android device)

Cắm điện thoại Android USB + bật USB debugging, rồi:

```bash
# Liệt kê device để chắc chắn có máy
flutter devices

# Chạy integration test
flutter test integration_test/app_test.dart
```

Hoặc chạy trên emulator: mở Android Studio → Device Manager → Run emulator,
rồi `flutter test integration_test/`.

### Đo coverage

```bash
flutter test --coverage
# Sinh ra coverage/lcov.info
# Convert sang HTML để xem:
brew install lcov
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html
```

## Conventions

- Tên file: `<source>_test.dart` (vd `phone_number_utils.dart` → `phone_number_utils_test.dart`).
- Mỗi `test()` đặt trong `group()` theo phương thức/feature.
- Dùng **mocktail** (không phải mockito) — null-safety friendly hơn.
- Mock class đặt trong `test/helpers/test_helpers.dart`, không lặp lại trong từng file.
- Wrap widget với `wrapWithApp(...)` hoặc `wrapWithProviders(...)` từ helpers.
- Dùng `setUp` để reset state, `setUpAll(registerCommonFallbacks)` đầu file nếu mock kiểu phức tạp.

## Pattern reference

### Unit test với mocktail

```dart
class MockRepo extends Mock implements MyRepo {}

void main() {
  late MockRepo repo;
  late MyUsecase usecase;

  setUp(() {
    repo = MockRepo();
    usecase = MyUsecase(repo);
  });

  test('returns value from repo', () async {
    when(() => repo.fetch()).thenAnswer((_) async => 'data');
    expect(await usecase.call(), 'data');
    verify(() => repo.fetch()).called(1);
  });
}
```

### Widget test với Provider

```dart
testWidgets('renders xxx', (tester) async {
  final ctrl = MockSmsGatewayController();
  when(() => ctrl.status).thenReturn(GatewayStatus.running);

  await tester.pumpWidget(wrapWithProviders(
    const MyWidget(),
    smsCtrl: ctrl,
  ));
  expect(find.text('Expected'), findsOneWidget);
});
```

### Golden test

```dart
testWidgets('snapshot', (tester) async {
  await tester.pumpWidget(_frame(const MyWidget()));
  await expectLater(
    find.byType(MyWidget),
    matchesGoldenFile('goldens/my_widget.png'),
  );
});
```

### MethodChannel mock (cho native side)

```dart
const channel = MethodChannel('my/channel');

TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
    .setMockMethodCallHandler(channel, (call) async {
  if (call.method == 'sendSms') return true;
  return null;
});
```

## CI

Tham khảo `.github/workflows/test.yml` (nếu có) hoặc đơn giản:

```yaml
- run: flutter test
- run: flutter analyze
- run: flutter test integration_test/  # cần Android emulator
```

## Mở rộng

Khi thêm feature mới, ưu tiên theo thứ tự:

1. **Unit test** cho logic mới (usecase, model, validator) — rẻ + nhanh.
2. **Widget test** cho UI mới (page, widget) — verify render + interaction.
3. **Golden test** cho UI cố định (design system, icon) — bắt regression visual.
4. **Integration test** cho user flow end-to-end mới — chậm nhưng cao impact.

Mục tiêu coverage: **≥ 70%** unit + widget. Golden + integration cho phần
critical UX.
