# Backend `SmsService` — SMS Forwarder Gateway

> Tài liệu này mô tả **đầy đủ và đồng bộ với codebase** `capstone/backend` cách
> biến **`SmsService`** thành **SMS Gateway Hub trung tâm**:
>
> - Nhận yêu cầu gửi SMS từ các service khác (`AuthService`, `BatteryService`,
>   `TicketService`, …) qua **RabbitMQ + MassTransit** (consumer + Inbox).
> - Cung cấp **REST + SignalR Hub** cho app Flutter `sms_fowarder` (gateway thực thi
>   gửi SMS bằng SIM thật trên Android).
> - Báo kết quả `Sent`/`Failed` ngược lại các service qua **RabbitMQ** (Outbox pattern).
> - Quản lý device gateway (cấp/thu hồi API key, daily limit, rate limit, audit log).
>
> Tài liệu này **thay thế hoàn toàn** mọi giả định monolith/`YourApp.*` ở phiên bản
> cũ. Mọi snippet code đã được căn chỉnh chính xác theo stack thật:
>
> - .NET 8.0
> - PostgreSQL + Npgsql + EF Core 8.0.2
> - MassTransit 8.5.9 (RabbitMQ + EF + Quartz)
> - MediatR 12.2.0
> - BCrypt.Net-Next 4.0.3
> - Redis (StackExchange.Redis 2.9.17) cho Inbox
> - SignalR (`Microsoft.AspNetCore.SignalR`, built-in)
>
> **Kiến trúc Outbox/Inbox tái sử dụng nguyên pattern hiện có**:
>
> - **Outbox**: custom (`OutboxMessage` entity + `OutboxMessagePublisher` viết vào
>   DbContext + `OutboxRelayBackgroundService` poll → bus) — copy nguyên pattern từ
>   `AuthService.Infrastructure.BackgroundJobs.OutboxRelayBackgroundService`.
> - **Inbox**: `IInboxStore` (Redis) qua `IdempotentConsumerExtensions.ProcessOnceAsync`
>   — đã có trong `SharedInfrastructure.Idempotency`.

---

## 0. Mục lục

| Mục | Nội dung |
| ---- | -------- |
| 1   | Vai trò `SmsService` trong microservices |
| 2   | Hợp đồng API với app Flutter |
| 3   | Hợp đồng RabbitMQ liên service (`SharedContracts`) |
| 4   | Các quyết định kiến trúc (đã chốt) |
| 5   | Sơ đồ thư mục mới của `SmsService` |
| 6   | `SmsService.Domain` — enum + entity + domain event + value object |
| 7   | `SmsService.Infrastructure.Persistence` — DbContext + configuration + repository + xmin |
| 8   | `SharedContracts.Events` — bổ sung 3 message contract |
| 9   | `SmsService.Application` — CQRS command/query/handler/validator |
| 10  | `SmsService.Application.Consumers` — RabbitMQ consumer + Inbox |
| 11  | `SmsService.Api` — controllers (Flutter + Admin) |
| 12  | `SmsService.Infrastructure.Realtime` — SignalR Hub + Notifier |
| 13  | Authentication: `GatewayApiKey` scheme (BCrypt) |
| 14  | Outbox: reuse AuthService pattern |
| 15  | Inbox: reuse Redis `IInboxStore` |
| 16  | Rate limiting + daily limit |
| 17  | Background services: `StaleSmsReaper` + `SmsMessageRedactor` |
| 18  | Idempotency cho REST report |
| 19  | Configuration (`appsettings`, env vars) |
| 20  | `Program.cs` — wiring đầy đủ |
| 21  | Migration & schema |
| 22  | Tích hợp với service khác (AuthService migrate `SendPhoneOtpEvent`) |
| 23  | Phase triển khai chi tiết |
| 24  | Checklist trước khi merge |
| 25  | Test end-to-end với app Flutter |
| 26  | Bảo mật |
| 27  | ApiGateway routing (đã setup) — checklist verify |
| 28  | Monitoring & troubleshooting |

---

## 1. Vai trò `SmsService` trong microservices

### 1.1. Trước & sau

**TRƯỚC** (hiện tại trong repo):

```text
SmsService.Api/Program.cs
└── AddMessageBus(typeof(SendPhoneOtpConsumer).Assembly)
└── AddInboxIdempotency
└── SingletonISmsSender → FakeSmsSender (log console)

SmsService.Infrastructure/
├── Consumers/SendPhoneOtpConsumer.cs   (chỉ log)
├── Services/FakeSmsSender.cs
└── Options/SmsOptions.cs
```

Không có Domain/Application. Không có DB. Không có endpoint REST. Không gửi SMS thật.

**SAU**:

```text
                 ┌─ AuthService (OTP)         ─┐
                 ├─ BatteryService (alert)    ─┤  publish SendSmsCommand
                 ├─ TicketService  (notify)   ─┤  (qua Outbox của họ)
                 └─ NotificationService       ─┘
                                │
                                ▼
                  ════ RabbitMQ "SendSmsCommand" ════
                                │
                                ▼
                   ┌───────── SmsService ─────────┐
                   │                              │
                   │  Consumer (Inbox dedup)      │
                   │       │                      │
                   │       ▼                      │
                   │  QueueSmsCommandHandler      │
                   │       │                      │
                   │       ▼                      │
                   │  SmsDbContext                │
                   │  (sms_messages: Pending)     │
                   │       │                      │
                   │       ▼                      │
                   │  ISmsGatewayNotifier         │
                   │  (SignalR push)              │
                   │       │                      │
                   └───────▲──────────────────────┘
                           │
                           │ (internal — ApiGateway forward)
                           │
                   ┌───────┴──────────────────────┐
                   │         ApiGateway           │
                   │   (YARP — entry point duy    │
                   │    nhất cho mobile app)      │
                   │                              │
                   │ Routes:                      │
                   │  /api/sms-gateway/* → SmsService │
                   │  /api/admin/sms-gateway/* → SmsService │
                   │  /hubs/sms-gateway → SmsService │
                   │  (WebSocket upgrade forward) │
                   └───────▲──────────────────────┘
                           │
            REST polling   │   SignalR push (primary)
             (fallback)    │
                           │
                  Flutter app `sms_fowarder`
                           │ baseUrl = ApiGateway URL
                           │
                           │ GET /api/sms-gateway/messages/pending
                           │ POST /api/sms-gateway/messages/report
                           │ POST /api/sms-gateway/heartbeat
                           │ WSS /hubs/sms-gateway
                           ▼
                   (ApiGateway forwards → SmsService)
                           │
                           ▼
                  ClaimPending / ReportSms /
                  Heartbeat command handlers
                           │
                           ▼
                  SmsDbContext + OutboxMessage
                           │
                           ▼
                   ═══ RabbitMQ "SmsDeliveryReportEvent" /
                          "SmsFailedEvent" ═══
                           │
              ┌────────────┼────────────┐
              ▼            ▼            ▼
        AuthService  BatteryService  TicketService
        (callback)   (mark sent)     (update ticket)
```

> 📍 **Mobile app CHỈ kết nối qua ApiGateway** (đã setup ở `services/ApiGateway`).
> Không expose SmsService trực tiếp ra internet. SmsService chỉ chấp nhận traffic
> internal từ ApiGateway (qua docker network / internal VPC).

### 1.2. Nguyên tắc

- **`SmsService` là single owner** của: bảng `sms_messages`, `sms_gateway_devices`,
  `sms_audit_logs`, `outbox_messages` (của riêng SmsService).
- **Service khác không truy cập DB của SmsService**. Mọi giao tiếp qua RabbitMQ.
- **`SmsService` không biết business** (OTP / alert / ticket). Chỉ nhận
  `(phoneNumber, message, correlationId, sourceService)` và chuyển xuống Flutter.
- **Idempotency**:
  - Inbound RabbitMQ: `IInboxStore` (Redis) qua `ProcessOnceAsync`.
  - Inbound REST `/report`: state-machine check (`Status` hiện tại) — xem mục 18.
- **Atomicity**: handler publish event qua `IMessageProducerService` (Outbox) **trước**
  `_unitOfWork.SaveChangesAsync()` → INSERT outbox row cùng transaction với business
  data. `OutboxRelayBackgroundService` poll → publish RabbitMQ thật.

---

## 2. Hợp đồng API với app Flutter

App Flutter trỏ `baseUrl` về **ApiGateway** (KHÔNG phải SmsService trực tiếp).
ApiGateway forward toàn bộ traffic về SmsService internal.

```
baseUrl examples:
  Local dev: https://localhost:5000        (ApiGateway local)
  Staging:   https://api-staging.example.com
  Prod:      https://api.example.com
```

App Flutter ở repo `sms_fowarder` gọi các path sau (`lib/core/constants/api_constants.dart`):

| Kind     | Path                                  | Mục đích                                         |
| -------- | ------------------------------------- | ------------------------------------------------ |
| REST GET | `/api/sms-gateway/messages/pending`   | Claim batch SMS Pending (Pending → Sending).     |
| REST POST| `/api/sms-gateway/messages/report`    | Báo `Sent` hoặc `Failed`.                        |
| REST POST| `/api/sms-gateway/heartbeat`          | Heartbeat 60s/lần.                               |
| Hub      | `/hubs/sms-gateway`                   | Realtime push `NewPendingSms` / `BatchRevoked`.  |

ApiGateway match các prefix `/api/sms-gateway/*` và `/hubs/sms-gateway` rồi forward
nguyên path + body + headers + WebSocket upgrade về SmsService. SmsService thấy
request như đến trực tiếp — không có thay đổi controller logic.

Headers REST (Flutter app gửi, ApiGateway forward nguyên):

```http
Authorization: Bearer <api-key-plaintext>
X-Device-Code: <device-code>
Content-Type: application/json
Accept: application/json
```

SignalR negotiate query string (qua ApiGateway):

```
{apiGatewayBaseUrl}/hubs/sms-gateway?deviceCode={code}&access_token={apiKey}
```

ApiGateway forward WebSocket upgrade về `http://sms-service:8080/hubs/sms-gateway?...`.
`access_token` chỉ dùng khi upgrade WebSocket — handler đã xử lý cả 2 path: xem mục 13.

> ⚠️ **Flutter side cần 1 patch nhỏ**: vì backend trả `CommonResponse<T>` wrapper
> (`{ isSuccess, statusCode, message, data }`) cho mọi REST endpoint, datasource
> `fetchPendingMessages()` của Flutter (`lib/features/sms_gateway/data/datasources/
> sms_gateway_remote_datasource.dart`) phải đọc `raw['data']` thay vì raw list. Chi
> tiết xem **Phụ lục C**. Không đụng SignalR, headers, hay endpoint khác.

---

## 3. Hợp đồng RabbitMQ liên service

Đặt trong `shared/src/SharedContracts/Events/`. Mọi event đều kế thừa
`IntegrationEvent` (đã có sẵn):

```csharp
// shared/src/SharedContracts/Events/Root/IntegrationEvent.cs
namespace SharedContracts.Events.Root;

public abstract record IntegrationEvent
{
    public Guid Id { get; private set; } = Guid.NewGuid();
    public DateTime OccurredAt { get; private set; } = DateTime.UtcNow;
}
```

### 3.1. Inbound — service khác gửi tới `SmsService`

**`SendSmsCommand`** — contract chuẩn (mới):

```csharp
// shared/src/SharedContracts/Events/SendSmsCommand.cs
using SharedContracts.Events.Root;

namespace SharedContracts.Events;

/// <summary>
/// Mọi service muốn gửi SMS qua gateway publish event này.
/// `CorrelationId` để service yêu cầu nhận callback `SmsDeliveryReportEvent`.
/// `SourceService` = "auth" / "battery" / "ticket" / "notification" — dùng cho audit + rate limit per source.
/// `TargetDeviceCode` = null → broadcast tới group "gateway:all" (mọi device đua claim).
/// </summary>
public record SendSmsCommand(
    string PhoneNumber,
    string Message,
    string SourceService,
    Guid CorrelationId,
    string? Category = null,
    string? TargetDeviceCode = null
) : IntegrationEvent;
```

**`SendPhoneOtpEvent`** — *giữ nguyên* để backward-compat (AuthService chưa migrate
xong). `SmsService` có consumer riêng cho event này, chuyển thành `QueueSmsCommand` nội bộ.

### 3.2. Outbound — `SmsService` publish ra cho ai quan tâm

```csharp
// shared/src/SharedContracts/Events/SmsDeliveryReportEvent.cs
using SharedContracts.Events.Root;

namespace SharedContracts.Events;

public record SmsDeliveryReportEvent(
    Guid SmsId,
    Guid CorrelationId,
    string PhoneNumber,
    string SourceService,
    DateTime SentAt,
    string GatewayDeviceCode
) : IntegrationEvent;

public record SmsFailedEvent(
    Guid SmsId,
    Guid CorrelationId,
    string PhoneNumber,
    string SourceService,
    string? ErrorMessage,
    DateTime FailedAt,
    bool FinalFailure
) : IntegrationEvent;
```

Service muốn nhận kết quả (vd: AuthService log audit OTP sent) đăng ký
`IConsumer<SmsDeliveryReportEvent>` trong assembly của họ và `AddMessageBus(...)` sẽ
tự gắn endpoint.

---

## 4. Các quyết định kiến trúc (đã chốt)

| # | Mục | Chốt | Lý do |
|---|-----|------|-------|
| 1 | **Service ownership** | SMS = `SmsService` (refactor: thêm Domain + Application + DbContext) | Tách bạch trách nhiệm; không pollute service khác |
| 2 | **Database** | PostgreSQL riêng `sms_service_db` (connection string key `SmsDb`) | Đồng pattern với `AuthDb`, `BatteryDb`, `TicketDb` |
| 3 | **Concurrency token** | `xmin` (Postgres native) | Đồng pattern với `TicketService.AlertTicketSagaState` |
| 4 | **Entity base** | `AuditableEntity` (`SharedKernels.Domain`) | Có sẵn `CreatedAt`/`UpdatedAt`/`CreatedBy`/`IsDeleted`/`DeletedAt` |
| 5 | **Hash API key gateway** | **BCrypt** (`BCrypt.Net-Next 4.0.3`) | Đã có trong backend, không thêm dependency mới |
| 6 | **CQRS** | MediatR 12.2.0 | Đồng pattern toàn bộ backend |
| 7 | **Inbox** | `IInboxStore` (Redis) qua `ProcessOnceAsync` | Đã có `SharedInfrastructure.Idempotency` |
| 8 | **Outbox** | Custom pattern, copy nguyên xi từ AuthService | Đã chiến đấu thực tế ở 2 service, ổn định |
| 9 | **Message bus** | MassTransit 8.5.9 qua `AddMessageBus(...)` helper | Đã chuẩn hóa |
| 10 | **SignalR backplane** | Chưa cần Redis backplane (single instance MVP) | Thêm khi scale-out |
| 11 | **Auth scheme cho Flutter** | Scheme custom `"GatewayApiKey"` (`AuthenticationHandler`) | Không trộn JWT user |
| 12 | **Auth scheme cho Admin endpoint** | JWT (`JwtBearerDefaults.AuthenticationScheme`) qua `AddJwtAuthentication(...)` | Tái dùng AuthService |
| 13 | **Snake_case** | Manual `HasColumnName(...)` trong từng configuration | Đồng pattern (không dùng convention package) |
| 14 | **Stale claim timeout** | **5 phút** đồng nhất ở cả `ClaimPending` lẫn `StaleSmsReaper` | Tránh khoảng race 2–5 phút |
| 15 | **Daily limit** | Có (theo `SmsGatewayDevice.DailyLimit`) | Chống lạm dụng |
| 16 | **Lưu plaintext message** | Có, **kèm TTL redactor** xóa cột `message` sau 24h khi `Sent` | Cần cho Android render, hạn chế phơi nhiễm |
| 17 | **REST report idempotency** | State-machine check: chỉ accept khi `Status == Sending` AND `GatewayDeviceCode` khớp | Xem mục 18 |
| 18 | **MediatR response shape** | `CommonResponse<T>` (`SharedContracts.Common.Responses`) | Đồng pattern AuthService/BatteryService |
| 19 | **Validation** | `IValidatable<TResponse>` (đã có `ValidationBehavior` trong `SharedInfrastructure`) | Không thêm FluentValidation mới |
| 20 | **Phone normalize** | Helper `PhoneNumberNormalizer.NormalizeVn(...)` → E.164 | Không tạo value object phức tạp |

> ⚠️ **PBKDF2** đã bỏ. **`RowVersion`** đã bỏ. **`YourApp.*`** đã bỏ. Mọi mâu thuẫn
> ở phiên bản trước đã được giải quyết theo bảng trên.

---

## 5. Sơ đồ thư mục mới của `SmsService`

```text
services/SmsService/
├── src/
│   ├── SmsService.Domain/                              🆕 (project mới)
│   │   ├── SmsService.Domain.csproj
│   │   ├── Entities/
│   │   │   ├── SmsMessage.cs
│   │   │   ├── SmsGatewayDevice.cs
│   │   │   ├── SmsAuditLog.cs
│   │   │   └── OutboxMessage.cs
│   │   └── Enums/
│   │       ├── SmsStatus.cs
│   │       └── SmsAuditEvent.cs
│   │
│   ├── SmsService.Application/                         🆕 (project mới)
│   │   ├── SmsService.Application.csproj
│   │   ├── DependencyInjection/
│   │   │   └── ManageDependencyInjection.cs
│   │   ├── Abstractions/
│   │   │   ├── ISmsGatewayNotifier.cs                  (SignalR abstraction — KHÔNG reference SignalR ở Application)
│   │   │   ├── ISmsUnitOfWork.cs
│   │   │   └── IGatewayApiKeyHasher.cs
│   │   ├── Common/
│   │   │   └── PhoneNumberNormalizer.cs
│   │   ├── CQRS/
│   │   │   ├── Commands/
│   │   │   │   ├── QueueSms/
│   │   │   │   │   ├── QueueSmsCommand.cs
│   │   │   │   │   └── QueueSmsCommandHandler.cs
│   │   │   │   ├── ClaimPendingMessages/
│   │   │   │   │   ├── ClaimPendingMessagesCommand.cs
│   │   │   │   │   └── ClaimPendingMessagesCommandHandler.cs
│   │   │   │   ├── ReportSmsResult/
│   │   │   │   │   ├── ReportSmsResultCommand.cs
│   │   │   │   │   └── ReportSmsResultCommandHandler.cs
│   │   │   │   ├── Heartbeat/
│   │   │   │   │   ├── HeartbeatCommand.cs
│   │   │   │   │   └── HeartbeatCommandHandler.cs
│   │   │   │   ├── CancelSms/
│   │   │   │   │   ├── CancelSmsCommand.cs
│   │   │   │   │   └── CancelSmsCommandHandler.cs
│   │   │   │   ├── CreateGatewayDevice/
│   │   │   │   │   ├── CreateGatewayDeviceCommand.cs
│   │   │   │   │   └── CreateGatewayDeviceCommandHandler.cs
│   │   │   │   └── RevokeGatewayDevice/
│   │   │   │       ├── RevokeGatewayDeviceCommand.cs
│   │   │   │       └── RevokeGatewayDeviceCommandHandler.cs
│   │   │   └── Queries/
│   │   │       ├── GetSmsById/
│   │   │       │   ├── GetSmsByIdQuery.cs
│   │   │       │   └── GetSmsByIdQueryHandler.cs
│   │   │       └── ListGatewayDevices/
│   │   │           ├── ListGatewayDevicesQuery.cs
│   │   │           └── ListGatewayDevicesQueryHandler.cs
│   │   ├── Dto/
│   │   │   ├── PendingSmsDto.cs
│   │   │   ├── CreateGatewayDeviceResponseDto.cs
│   │   │   └── GatewayDeviceDto.cs
│   │   └── Consumers/
│   │       ├── SendSmsCommandConsumer.cs               (contract mới)
│   │       └── SendPhoneOtpConsumer.cs                 ♻️ moved from Infrastructure, rewrite
│   │
│   ├── SmsService.Infrastructure/                      ♻️ refactor
│   │   ├── SmsService.Infrastructure.csproj            (thêm dependency + ProjectReference Domain/Application)
│   │   ├── DependencyInjection/
│   │   │   └── ManageDependencyInjection.cs
│   │   ├── Persistence/
│   │   │   ├── SmsDbContext.cs
│   │   │   ├── SmsDbContextFactory.cs                  (IDesignTimeDbContextFactory)
│   │   │   ├── Configurations/
│   │   │   │   ├── SmsMessageConfiguration.cs
│   │   │   │   ├── SmsGatewayDeviceConfiguration.cs
│   │   │   │   ├── SmsAuditLogConfiguration.cs
│   │   │   │   └── OutboxMessageConfiguration.cs
│   │   │   ├── Repositories/
│   │   │   │   └── SmsUnitOfWork.cs
│   │   │   └── Migrations/                             (sẽ sinh ra)
│   │   ├── Security/
│   │   │   ├── BcryptGatewayApiKeyHasher.cs
│   │   │   └── GatewayApiKeyAuthenticationHandler.cs
│   │   ├── Realtime/
│   │   │   ├── SmsGatewayHub.cs                        🆕 (Hub đặt ở Infrastructure để tránh circular Api↔Infrastructure)
│   │   │   └── SignalRSmsGatewayNotifier.cs
│   │   ├── BackgroundJobs/
│   │   │   ├── OutboxRelayBackgroundService.cs         (copy từ AuthService)
│   │   │   ├── StaleSmsReaperBackgroundService.cs
│   │   │   └── SmsMessageRedactorBackgroundService.cs  (TTL xóa cột message sau 24h)
│   │   ├── Services/
│   │   │   └── OutboxMessagePublisher.cs               (IMessageProducerService impl, copy AuthService)
│   │   │       ❌ XÓA `FakeSmsSender.cs` + `ISmsSender` — obsolete (gateway architecture
│   │   │       không gửi SMS trực tiếp; Flutter app gửi qua SIM thật, SmsService chỉ
│   │   │       queue vào DB).
│   │   └── Options/
│   │       ├── SmsOptions.cs                           ♻️ mở rộng
│   │       ├── OutboxOptions.cs
│   │       ├── GatewayAuthOptions.cs
│   │       └── SmsMessageRetentionOptions.cs
│   │
│   └── SmsService.Api/                                 ♻️ refactor
│       ├── SmsService.Api.csproj                       (thêm SignalR — built-in nên không cần package)
│       ├── Program.cs                                  ♻️ wire lại
│       └── Controllers/
│           ├── SmsGatewayController.cs                 (Flutter)
│           └── AdminGatewayDevicesController.cs        (Admin)
│
└── tests/
    ├── SmsService.UnitTests/                           🆕 (chưa có)
    └── SmsService.IntegrationTests/                    🆕 (chưa có)
```

**Cập nhật `SolarBatteryMaintainance.slnx`** thêm 4 project mới:

```xml
<Folder Name="/Services/SmsService/">
    <Project Path="services/SmsService/src/SmsService.Api/SmsService.Api.csproj" />
    <Project Path="services/SmsService/src/SmsService.Application/SmsService.Application.csproj" />
    <Project Path="services/SmsService/src/SmsService.Domain/SmsService.Domain.csproj" />
    <Project Path="services/SmsService/src/SmsService.Infrastructure/SmsService.Infrastructure.csproj" />
    <Project Path="services/SmsService/tests/SmsService.UnitTests/SmsService.UnitTests.csproj" />
    <Project Path="services/SmsService/tests/SmsService.IntegrationTests/SmsService.IntegrationTests.csproj" />
</Folder>
```

---

## 6. `SmsService.Domain`

### 6.1. `SmsStatus`

```csharp
// services/SmsService/src/SmsService.Domain/Enums/SmsStatus.cs
namespace SmsService.Domain.Enums;

public enum SmsStatus
{
    Pending   = 0,
    Sending   = 1,
    Sent      = 2,
    Failed    = 3,
    Cancelled = 4
}
```

Quy tắc chuyển trạng thái:

```text
Pending  → Sending → Sent
Pending  → Sending → Failed (retry < max → quay về Pending; >= max → Failed final)
Pending  → Cancelled (admin huỷ thủ công)
Sending  → Pending (StaleSmsReaper revert sau 5 phút)
```

### 6.2. `SmsAuditEvent`

```csharp
// services/SmsService/src/SmsService.Domain/Enums/SmsAuditEvent.cs
namespace SmsService.Domain.Enums;

public enum SmsAuditEvent
{
    Queued       = 0,
    Picked       = 1,
    Sent         = 2,
    Failed       = 3,
    Retry        = 4,
    Cancelled    = 5,
    Reaped       = 6,
    Redacted     = 7
}
```

### 6.3. `SmsMessage`

```csharp
// services/SmsService/src/SmsService.Domain/Entities/SmsMessage.cs
using SharedKernels.Domain;
using SmsService.Domain.Enums;

namespace SmsService.Domain.Entities;

public class SmsMessage : AuditableEntity
{
    public string PhoneNumber { get; set; } = default!;
    public string? Message { get; set; } // nullable vì Redactor có thể xóa sau khi Sent.

    // Cleanup: domain methods KHÔNG raise DomainEvent (xem comment trong MarkSent).

    public SmsStatus Status { get; set; } = SmsStatus.Pending;

    public int RetryCount    { get; set; }
    public int MaxRetryCount { get; set; } = 3;

    public string? ErrorMessage { get; set; }

    public string? Category      { get; set; }
    public string  SourceService { get; set; } = default!;
    public Guid    CorrelationId { get; set; }
    public string? TargetDeviceCode { get; set; }

    public string? GatewayDeviceCode { get; set; }
    public Guid?   GatewayDeviceId   { get; set; }

    public DateTime? PickedAt { get; set; }
    public DateTime? SentAt   { get; set; }
    public DateTime? FailedAt { get; set; }
    public DateTime? RedactedAt { get; set; }

    // --- Domain methods ---

    public void Claim(string deviceCode, Guid deviceId, DateTime now)
    {
        Status            = SmsStatus.Sending;
        PickedAt          = now;
        GatewayDeviceCode = deviceCode;
        GatewayDeviceId   = deviceId;
        UpdatedAt         = now;
    }

    public void MarkSent(DateTime now)
    {
        Status       = SmsStatus.Sent;
        SentAt       = now;
        ErrorMessage = null;
        UpdatedAt    = now;
        // Side-effect cross-service đi qua Outbox (`SmsDeliveryReportEvent` —
        // IntegrationEvent ở mục 9.5). KHÔNG dùng DomainEvent vì backend không có
        // dispatcher (verified: tất cả entity ở AuthService chỉ `Ignore(DomainEvents)`).
    }

    public void MarkRetry(string? error, DateTime now)
    {
        RetryCount++;
        ErrorMessage      = error;
        Status            = SmsStatus.Pending;
        GatewayDeviceCode = null;
        GatewayDeviceId   = null;
        PickedAt          = null;
        UpdatedAt         = now;
    }

    public void MarkFailedFinal(string? error, DateTime now)
    {
        // Bump RetryCount để cuối luồng RetryCount == MaxRetryCount (semantic nhất quán
        // với MarkRetry — mỗi lần Failed đều +1, dù retry hay final).
        RetryCount++;
        Status       = SmsStatus.Failed;
        FailedAt     = now;
        ErrorMessage = error;
        UpdatedAt    = now;
        // Outbox publish `SmsFailedEvent` ở ReportSmsResultCommandHandler (mục 9.5).
    }

    public void Cancel(DateTime now)
    {
        Status    = SmsStatus.Cancelled;
        UpdatedAt = now;
    }

    /// <summary>
    /// StaleSmsReaper gọi để revert Sending → Pending khi vượt timeout 5 phút mà device
    /// chưa report. Không bump RetryCount (không tính là attempt thất bại từ phía device).
    /// </summary>
    public void ReapStaleClaim(DateTime now)
    {
        Status            = SmsStatus.Pending;
        GatewayDeviceCode = null;
        GatewayDeviceId   = null;
        PickedAt          = null;
        UpdatedAt         = now;
    }

    public void Redact(DateTime now)
    {
        Message    = null;
        RedactedAt = now;
        UpdatedAt  = now;
    }
}
```

### 6.4. `SmsGatewayDevice`

```csharp
// services/SmsService/src/SmsService.Domain/Entities/SmsGatewayDevice.cs
using SharedKernels.Domain;

namespace SmsService.Domain.Entities;

public class SmsGatewayDevice : AuditableEntity
{
    public string DeviceName { get; set; } = default!;
    public string DeviceCode { get; set; } = default!;
    public string ApiKeyHash { get; set; } = default!; // BCrypt hash

    public bool IsActive { get; set; } = true;
    public DateTime? RevokedAt { get; set; }

    public int DailyLimit { get; set; } = 100;
    public int SentToday  { get; set; }
    public DateOnly? SentTodayDate { get; set; }

    public DateTime? LastSeenAt { get; set; }
    public string?   LastSeenIp { get; set; }

    public void Touch(string? ip, DateTime now)
    {
        LastSeenAt = now;
        LastSeenIp = ip;
        UpdatedAt  = now;
    }

    public void ResetDailyCounterIfNeeded(DateTime now)
    {
        var today = DateOnly.FromDateTime(now);
        if (SentTodayDate != today)
        {
            SentTodayDate = today;
            SentToday     = 0;
        }
    }

    public void IncrementSent(DateTime now)
    {
        ResetDailyCounterIfNeeded(now);
        SentToday++;
        UpdatedAt = now;
    }

    public void Revoke(DateTime now)
    {
        IsActive  = false;
        RevokedAt = now;
        UpdatedAt = now;
    }
}
```

### 6.5. `SmsAuditLog`

```csharp
// services/SmsService/src/SmsService.Domain/Entities/SmsAuditLog.cs
using SharedKernels.Domain;
using SmsService.Domain.Enums;

namespace SmsService.Domain.Entities;

/// <summary>
/// Append-only — kế thừa BaseEntity (chỉ Id + DomainEvents) thay vì AuditableEntity
/// vì audit log không có khái niệm "update" hay "soft delete".
/// </summary>
public class SmsAuditLog : BaseEntity
{
    public Guid SmsMessageId { get; set; }
    public SmsAuditEvent Event { get; set; }
    public string? DeviceCode { get; set; }
    public string? Detail { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}
```

### 6.6. `OutboxMessage`

```csharp
// services/SmsService/src/SmsService.Domain/Entities/OutboxMessage.cs
using SharedKernels.Domain;

namespace SmsService.Domain.Entities;

public class OutboxMessage : AuditableEntity
{
    public string EventType { get; set; } = string.Empty;
    public string Payload { get; set; } = string.Empty;
    public DateTime OccurredAt { get; set; }
    public DateTime? ProcessedAt { get; set; }
    public int RetryCount { get; set; }
    public string? LastError { get; set; }
}
```

### 6.7. (Đã bỏ Domain events scaffolding)

Backend hiện tại **không có domain event dispatcher** — verified bằng grep
`SharedInfrastructure`, AuthService, BatteryService: tất cả entities chỉ
`builder.Ignore(x => x.DomainEvents)` trong configuration và không có MediatR
`INotification` hay `IDomainEventDispatcher`. Side-effect cross-service đi qua
**IntegrationEvent + Outbox** (mục 9.5, 14.1).

Vì vậy:

- KHÔNG tạo folder `SmsService.Domain/Events/`.
- KHÔNG có records `SmsSentDomainEvent` / `SmsFailedDomainEvent` / `SmsRetriedDomainEvent`.
- Domain methods (`MarkSent`, `MarkRetry`, `MarkFailedFinal`) chỉ mutate state — KHÔNG gọi `AddDomainEvent(...)`.

Nếu sau này cần in-process dispatch (vd: invalidate cache, gửi notification ngay
trong service), wire MediatR `INotification` + custom interceptor `DispatchDomainEventsInterceptor`.

### 6.8. `SmsService.Domain.csproj`

```xml
<Project Sdk="Microsoft.NET.Sdk">
    <PropertyGroup>
        <TargetFramework>net8.0</TargetFramework>
        <Nullable>enable</Nullable>
        <ImplicitUsings>enable</ImplicitUsings>
    </PropertyGroup>
    <ItemGroup>
        <ProjectReference Include="..\..\..\..\shared\src\SharedKernels\SharedKernels.csproj" />
    </ItemGroup>
</Project>
```

---

## 7. `SmsService.Infrastructure.Persistence`

### 7.1. `SmsDbContext`

```csharp
// services/SmsService/src/SmsService.Infrastructure/Persistence/SmsDbContext.cs
using Microsoft.EntityFrameworkCore;
using SharedInfrastructure.Persistence.Interceptors;
using SmsService.Domain.Entities;

namespace SmsService.Infrastructure.Persistence;

public class SmsDbContext : DbContext
{
    private readonly AuditableEntityInterceptor? _auditableEntityInterceptor;

    /// <summary>
    /// Constructor cho design-time (dotnet ef migrations) — không có DI, interceptor null.
    /// </summary>
    public SmsDbContext(DbContextOptions<SmsDbContext> options) : base(options) { }

    /// <summary>
    /// Constructor runtime — DI inject AuditableEntityInterceptor để auto-set CreatedAt,
    /// CreatedBy (từ JWT), UpdatedAt, và convert Delete → soft-delete (IsDeleted=true).
    /// </summary>
    public SmsDbContext(
        DbContextOptions<SmsDbContext> options,
        AuditableEntityInterceptor auditableEntityInterceptor) : base(options)
    {
        _auditableEntityInterceptor = auditableEntityInterceptor;
    }

    public DbSet<SmsMessage>        SmsMessages       => Set<SmsMessage>();
    public DbSet<SmsGatewayDevice>  SmsGatewayDevices => Set<SmsGatewayDevice>();
    public DbSet<SmsAuditLog>       SmsAuditLogs      => Set<SmsAuditLog>();
    public DbSet<OutboxMessage>     OutboxMessages    => Set<OutboxMessage>();

    protected override void OnConfiguring(DbContextOptionsBuilder optionsBuilder)
    {
        if (_auditableEntityInterceptor is not null)
            optionsBuilder.AddInterceptors(_auditableEntityInterceptor);
        base.OnConfiguring(optionsBuilder);
    }

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.ApplyConfigurationsFromAssembly(typeof(SmsDbContext).Assembly);

        if (Database.IsNpgsql())
        {
            // PostgreSQL xmin optimistic concurrency token cho sms_messages
            // — nhiều device cùng poll claim, RowVersion không native trên PG nên dùng xmin.
            modelBuilder.Entity<SmsMessage>()
                .Property<uint>("xmin")
                .HasColumnType("xid")
                .ValueGeneratedOnAddOrUpdate()
                .IsConcurrencyToken();

            // Daily counter trên SmsGatewayDevice cần concurrency token để tránh over-claim
            // khi 2 request ClaimPending/Report đồng thời cùng tăng SentToday.
            modelBuilder.Entity<SmsGatewayDevice>()
                .Property<uint>("xmin")
                .HasColumnType("xid")
                .ValueGeneratedOnAddOrUpdate()
                .IsConcurrencyToken();
        }

        base.OnModelCreating(modelBuilder);
    }
}
```

> 📝 **Tương tác giữa interceptor và handler manual assignment**:
> - Handler set `sms.CreatedAt = now` → interceptor (on `Added`) **override** thành
>   `DateTime.UtcNow`. Sai lệch vài microsecond, harmless.
> - Handler set `sms.UpdatedAt = now` → interceptor (on `Modified`) **override** thành
>   `DateTime.UtcNow`. Cũng harmless.
> - `SmsAuditLog : BaseEntity` (KHÔNG phải `AuditableEntity`) → interceptor **bỏ qua**
>   → handler set `CreatedAt = now` là source of truth. Đây là lý do `SmsAuditLog`
>   có `CreatedAt` thuộc class (không inherit).
> - `CreatedBy` chỉ được set bởi interceptor (lấy từ `ICurrentUserService.UserId`
>   parsed từ JWT). Trong BG service / Hub không có user context → Guid.Empty.

### 7.2. `SmsDbContextFactory` (design-time để chạy `dotnet ef`)

> ⚠️ **Pattern khớp AuthService.Infrastructure.ApplicationDbContextFactory** — path
> giả định `dotnet ef` chạy từ **REPO ROOT** (`capstone/backend/`), KHÔNG phải từ
> `services/SmsService/`. Đồng nhất với migration command ở mục 21.

```csharp
// services/SmsService/src/SmsService.Infrastructure/Persistence/SmsDbContextFactory.cs
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;
using Microsoft.Extensions.Configuration;
using SharedInfrastructure.Extensions;
using SharedInfrastructure.Persistence.Interceptors;
using SharedInfrastructure.Services;

namespace SmsService.Infrastructure.Persistence;

public class SmsDbContextFactory : IDesignTimeDbContextFactory<SmsDbContext>
{
    public SmsDbContext CreateDbContext(string[] args)
    {
        EnvFileLoader.LoadIfExists();

        var configuration = new ConfigurationBuilder()
            .SetBasePath(Directory.GetCurrentDirectory())
            .AddJsonFile("services/SmsService/src/SmsService.Api/appsettings.json", optional: true)
            .AddJsonFile("services/SmsService/src/SmsService.Api/appsettings.Development.json", optional: true)
            .AddEnvironmentVariables()
            .Build();

        var connectionString = configuration.GetConnectionString("SmsDb")
                               ?? configuration["SmsDb"]
                               ?? configuration["Sms_Db"]
                               ?? configuration["SMS_DB"]
                               ?? "Host=localhost;Port=5432;Database=sms_service_db;Username=postgres;Password=postgres";

        var options = new DbContextOptionsBuilder<SmsDbContext>()
            .UseNpgsql(connectionString)
            .Options;

        // Attach interceptor để giữ consistency — migrations không invoke SaveChanges,
        // nhưng có interceptor đảm bảo design-time model match runtime model.
        return new SmsDbContext(
            options,
            new AuditableEntityInterceptor(new DesignTimeCurrentUserService()));
    }

    /// <summary>Fake ICurrentUserService cho design-time — không có HTTP context.</summary>
    private sealed class DesignTimeCurrentUserService : ICurrentUserService
    {
        public string? UserId => null;
    }
}
```

### 7.3. Configurations (snake_case)

```csharp
// services/SmsService/src/SmsService.Infrastructure/Persistence/Configurations/SmsMessageConfiguration.cs
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using SmsService.Domain.Entities;

namespace SmsService.Infrastructure.Persistence.Configurations;

public class SmsMessageConfiguration : IEntityTypeConfiguration<SmsMessage>
{
    public void Configure(EntityTypeBuilder<SmsMessage> b)
    {
        b.ToTable("sms_messages");
        b.HasKey(x => x.Id);

        b.Property(x => x.Id).HasColumnName("id").ValueGeneratedNever();
        b.Property(x => x.PhoneNumber).HasColumnName("phone_number").HasMaxLength(20).IsRequired();
        b.Property(x => x.Message).HasColumnName("message").HasMaxLength(1600);
        b.Property(x => x.Status).HasColumnName("status").HasConversion<int>().IsRequired();

        b.Property(x => x.RetryCount).HasColumnName("retry_count").HasDefaultValue(0);
        b.Property(x => x.MaxRetryCount).HasColumnName("max_retry_count").HasDefaultValue(3);
        b.Property(x => x.ErrorMessage).HasColumnName("error_message").HasMaxLength(500);

        b.Property(x => x.Category).HasColumnName("category").HasMaxLength(32);
        b.Property(x => x.SourceService).HasColumnName("source_service").HasMaxLength(32).IsRequired();
        b.Property(x => x.CorrelationId).HasColumnName("correlation_id").IsRequired();
        b.Property(x => x.TargetDeviceCode).HasColumnName("target_device_code").HasMaxLength(64);

        b.Property(x => x.GatewayDeviceCode).HasColumnName("gateway_device_code").HasMaxLength(64);
        b.Property(x => x.GatewayDeviceId).HasColumnName("gateway_device_id");

        b.Property(x => x.PickedAt).HasColumnName("picked_at");
        b.Property(x => x.SentAt).HasColumnName("sent_at");
        b.Property(x => x.FailedAt).HasColumnName("failed_at");
        b.Property(x => x.RedactedAt).HasColumnName("redacted_at");

        b.Property(x => x.CreatedAt).HasColumnName("created_at").IsRequired();
        b.Property(x => x.CreatedBy).HasColumnName("created_by");
        b.Property(x => x.UpdatedAt).HasColumnName("updated_at");
        b.Property(x => x.IsDeleted).HasColumnName("is_deleted").HasDefaultValue(false);
        b.Property(x => x.DeletedAt).HasColumnName("deleted_at");

        b.HasIndex(x => new { x.Status, x.CreatedAt })
            .HasDatabaseName("ix_sms_messages_status_created_at");
        b.HasIndex(x => x.PhoneNumber).HasDatabaseName("ix_sms_messages_phone_number");
        b.HasIndex(x => x.CorrelationId).HasDatabaseName("ix_sms_messages_correlation_id");
        b.HasIndex(x => new { x.Status, x.SentAt })
            .HasDatabaseName("ix_sms_messages_status_sent_at"); // dùng cho redactor TTL
        b.HasIndex(x => new { x.TargetDeviceCode, x.Status, x.CreatedAt })
            .HasDatabaseName("ix_sms_messages_target_status_created_at"); // tối ưu ClaimPending khi route theo device

        b.Ignore(x => x.DomainEvents);
    }
}
```

```csharp
// services/SmsService/src/SmsService.Infrastructure/Persistence/Configurations/SmsGatewayDeviceConfiguration.cs
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using SmsService.Domain.Entities;

namespace SmsService.Infrastructure.Persistence.Configurations;

public class SmsGatewayDeviceConfiguration : IEntityTypeConfiguration<SmsGatewayDevice>
{
    public void Configure(EntityTypeBuilder<SmsGatewayDevice> b)
    {
        b.ToTable("sms_gateway_devices");
        b.HasKey(x => x.Id);

        b.Property(x => x.Id).HasColumnName("id").ValueGeneratedNever();
        b.Property(x => x.DeviceName).HasColumnName("device_name").HasMaxLength(64).IsRequired();
        b.Property(x => x.DeviceCode).HasColumnName("device_code").HasMaxLength(64).IsRequired();
        b.Property(x => x.ApiKeyHash).HasColumnName("api_key_hash").HasMaxLength(256).IsRequired();
        b.Property(x => x.IsActive).HasColumnName("is_active").HasDefaultValue(true);
        b.Property(x => x.RevokedAt).HasColumnName("revoked_at");
        b.Property(x => x.DailyLimit).HasColumnName("daily_limit").HasDefaultValue(100);
        b.Property(x => x.SentToday).HasColumnName("sent_today").HasDefaultValue(0);
        b.Property(x => x.SentTodayDate).HasColumnName("sent_today_date").HasColumnType("date");
        b.Property(x => x.LastSeenAt).HasColumnName("last_seen_at");
        b.Property(x => x.LastSeenIp).HasColumnName("last_seen_ip").HasMaxLength(64);

        b.Property(x => x.CreatedAt).HasColumnName("created_at").IsRequired();
        b.Property(x => x.CreatedBy).HasColumnName("created_by");
        b.Property(x => x.UpdatedAt).HasColumnName("updated_at");
        b.Property(x => x.IsDeleted).HasColumnName("is_deleted").HasDefaultValue(false);
        b.Property(x => x.DeletedAt).HasColumnName("deleted_at");

        b.HasIndex(x => x.DeviceCode).IsUnique().HasDatabaseName("ux_sms_gateway_devices_device_code");

        b.Ignore(x => x.DomainEvents);
    }
}
```

```csharp
// services/SmsService/src/SmsService.Infrastructure/Persistence/Configurations/SmsAuditLogConfiguration.cs
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using SmsService.Domain.Entities;

namespace SmsService.Infrastructure.Persistence.Configurations;

public class SmsAuditLogConfiguration : IEntityTypeConfiguration<SmsAuditLog>
{
    public void Configure(EntityTypeBuilder<SmsAuditLog> b)
    {
        b.ToTable("sms_audit_logs");
        b.HasKey(x => x.Id);

        b.Property(x => x.Id).HasColumnName("id").ValueGeneratedNever();
        b.Property(x => x.SmsMessageId).HasColumnName("sms_message_id").IsRequired();
        b.Property(x => x.Event).HasColumnName("event").HasConversion<int>().IsRequired();
        b.Property(x => x.DeviceCode).HasColumnName("device_code").HasMaxLength(64);
        b.Property(x => x.Detail).HasColumnName("detail").HasMaxLength(1000);
        b.Property(x => x.CreatedAt).HasColumnName("created_at").IsRequired();

        b.HasIndex(x => x.SmsMessageId).HasDatabaseName("ix_sms_audit_logs_sms_message_id");
        b.HasIndex(x => new { x.SmsMessageId, x.CreatedAt })
            .HasDatabaseName("ix_sms_audit_logs_sms_message_id_created_at");

        b.Ignore(x => x.DomainEvents);
    }
}
```

```csharp
// services/SmsService/src/SmsService.Infrastructure/Persistence/Configurations/OutboxMessageConfiguration.cs
// Copy nguyên xi từ AuthService.Infrastructure.Persistence.Configurations.OutboxMessageConfiguration
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using SmsService.Domain.Entities;

namespace SmsService.Infrastructure.Persistence.Configurations;

public class OutboxMessageConfiguration : IEntityTypeConfiguration<OutboxMessage>
{
    public void Configure(EntityTypeBuilder<OutboxMessage> b)
    {
        b.ToTable("outbox_messages");
        b.HasKey(o => o.Id);

        b.Property(o => o.Id).HasColumnName("id").ValueGeneratedNever();
        b.Property(o => o.EventType).HasColumnName("event_type").HasMaxLength(500).IsRequired();
        b.Property(o => o.Payload).HasColumnName("payload").HasColumnType("text").IsRequired();
        b.Property(o => o.OccurredAt).HasColumnName("occurred_at").IsRequired();
        b.Property(o => o.ProcessedAt).HasColumnName("processed_at");
        b.Property(o => o.RetryCount).HasColumnName("retry_count").HasDefaultValue(0);
        b.Property(o => o.LastError).HasColumnName("last_error").HasMaxLength(2000);
        b.Property(o => o.CreatedAt).HasColumnName("created_at").IsRequired();
        b.Property(o => o.CreatedBy).HasColumnName("created_by");
        b.Property(o => o.UpdatedAt).HasColumnName("updated_at");
        b.Property(o => o.IsDeleted).HasColumnName("is_deleted").HasDefaultValue(false);
        b.Property(o => o.DeletedAt).HasColumnName("deleted_at");

        b.HasIndex(o => new { o.ProcessedAt, o.OccurredAt })
            .HasDatabaseName("ix_outbox_messages_processed_at_occurred_at");

        b.Ignore(o => o.DomainEvents);
    }
}
```

### 7.4. `ISmsUnitOfWork` + impl

```csharp
// services/SmsService/src/SmsService.Application/Abstractions/ISmsUnitOfWork.cs
using SharedKernels.Interfaces;
using SmsService.Domain.Entities;

namespace SmsService.Application.Abstractions;

public interface ISmsUnitOfWork : IUnitOfWork
{
    IGenericRepository<SmsMessage>       SmsMessages       { get; }
    IGenericRepository<SmsGatewayDevice> SmsGatewayDevices { get; }
    IGenericRepository<SmsAuditLog>      SmsAuditLogs      { get; }
    IGenericRepository<OutboxMessage>    OutboxMessages    { get; }
}
```

```csharp
// services/SmsService/src/SmsService.Infrastructure/Persistence/Repositories/SmsUnitOfWork.cs
using Microsoft.EntityFrameworkCore.Storage;
using SharedInfrastructure.Persistence.Repositories;
using SharedKernels.Interfaces;
using SmsService.Application.Abstractions;
using SmsService.Domain.Entities;

namespace SmsService.Infrastructure.Persistence.Repositories;

public class SmsUnitOfWork : ISmsUnitOfWork
{
    private readonly SmsDbContext _context;
    private IDbContextTransaction? _currentTransaction;

    public SmsUnitOfWork(SmsDbContext context) => _context = context;

    public IGenericRepository<SmsMessage>       SmsMessages       => new GenericRepository<SmsMessage>(_context);
    public IGenericRepository<SmsGatewayDevice> SmsGatewayDevices => new GenericRepository<SmsGatewayDevice>(_context);
    public IGenericRepository<SmsAuditLog>      SmsAuditLogs      => new GenericRepository<SmsAuditLog>(_context);
    public IGenericRepository<OutboxMessage>    OutboxMessages    => new GenericRepository<OutboxMessage>(_context);

    public async Task BeginTransactionAsync()
    {
        if (_currentTransaction is not null) return;
        _currentTransaction = await _context.Database.BeginTransactionAsync();
    }

    public async Task CommitTransactionAsync()
    {
        try
        {
            await _context.SaveChangesAsync();
            if (_currentTransaction is not null) await _currentTransaction.CommitAsync();
        }
        catch { await RollbackTransactionAsync(); throw; }
        finally
        {
            if (_currentTransaction is not null)
            {
                await _currentTransaction.DisposeAsync();
                _currentTransaction = null;
            }
        }
    }

    public async Task RollbackTransactionAsync()
    {
        try
        {
            if (_currentTransaction is not null) await _currentTransaction.RollbackAsync();
        }
        finally
        {
            if (_currentTransaction is not null)
            {
                await _currentTransaction.DisposeAsync();
                _currentTransaction = null;
            }
        }
    }

    public Task<int> SaveChangesAsync(CancellationToken cancellationToken = default)
        => _context.SaveChangesAsync(cancellationToken);

    public void Dispose() => _context.Dispose();
}
```

---

## 8. `SharedContracts.Events` — bổ sung 3 contract

Đã viết ở mục 3. Hành động cụ thể: **tạo 3 file** trong `shared/src/SharedContracts/Events/`:

- `SendSmsCommand.cs`
- `SmsDeliveryReportEvent.cs`
- `SmsFailedEvent.cs`

Không cần đổi `IntegrationEvent` cũ.

---

## 9. `SmsService.Application` — CQRS

Mọi handler trả `CommonResponse<T>` (đã có ở `SharedContracts.Common.Responses`).

### 9.1. `PhoneNumberNormalizer`

```csharp
// services/SmsService/src/SmsService.Application/Common/PhoneNumberNormalizer.cs
using System.Text.RegularExpressions;

namespace SmsService.Application.Common;

public static class PhoneNumberNormalizer
{
    private static readonly Regex Cleanup = new(@"[\s\-\(\)\.]", RegexOptions.Compiled);
    private static readonly Regex E164    = new(@"^\+?[0-9]{9,15}$", RegexOptions.Compiled);

    public static string? NormalizeVn(string raw)
    {
        if (string.IsNullOrWhiteSpace(raw)) return null;
        var s = Cleanup.Replace(raw.Trim(), "");
        if (s.StartsWith("0") && s.Length == 10) s = "+84" + s[1..];
        else if (s.StartsWith("84") && s.Length == 11) s = "+" + s;
        return E164.IsMatch(s) ? s : null;
    }
}
```

### 9.2. `ISmsGatewayNotifier` (abstraction)

```csharp
// services/SmsService/src/SmsService.Application/Abstractions/ISmsGatewayNotifier.cs
namespace SmsService.Application.Abstractions;

/// <summary>
/// Application không reference Microsoft.AspNetCore.SignalR. Infrastructure implement bằng SignalRSmsGatewayNotifier.
/// Khi chưa cần SignalR (test) dùng NullSmsGatewayNotifier.
/// </summary>
public interface ISmsGatewayNotifier
{
    Task NotifyNewPendingSmsAsync(Guid smsId, string phoneNumber, string? targetDeviceCode, CancellationToken cancellationToken = default);
    Task NotifyBatchRevokedAsync(IEnumerable<Guid> smsIds, string? targetDeviceCode, CancellationToken cancellationToken = default);
}
```

### 9.3. `QueueSmsCommand`

```csharp
// services/SmsService/src/SmsService.Application/CQRS/Commands/QueueSms/QueueSmsCommand.cs
using MediatR;
using SharedContracts.Common.Responses;

namespace SmsService.Application.CQRS.Commands.QueueSms;

public record QueueSmsCommand(
    string PhoneNumber,
    string Message,
    string SourceService,
    Guid CorrelationId,
    string? Category = null,
    string? TargetDeviceCode = null
) : IRequest<CommonResponse<Guid>>;
```

```csharp
// services/SmsService/src/SmsService.Application/CQRS/Commands/QueueSms/QueueSmsCommandHandler.cs
using MediatR;
using Microsoft.Extensions.Logging;
using SharedContracts.Common.Responses;
using SmsService.Application.Abstractions;
using SmsService.Application.Common;
using SmsService.Domain.Entities;
using SmsService.Domain.Enums;

namespace SmsService.Application.CQRS.Commands.QueueSms;

public class QueueSmsCommandHandler : IRequestHandler<QueueSmsCommand, CommonResponse<Guid>>
{
    private readonly ISmsUnitOfWork _unitOfWork;
    private readonly ISmsGatewayNotifier _notifier;
    private readonly ILogger<QueueSmsCommandHandler> _logger;

    public QueueSmsCommandHandler(
        ISmsUnitOfWork unitOfWork,
        ISmsGatewayNotifier notifier,
        ILogger<QueueSmsCommandHandler> logger)
    {
        _unitOfWork = unitOfWork;
        _notifier = notifier;
        _logger = logger;
    }

    public async Task<CommonResponse<Guid>> Handle(QueueSmsCommand request, CancellationToken cancellationToken)
    {
        var normalized = PhoneNumberNormalizer.NormalizeVn(request.PhoneNumber);
        if (normalized is null)
            return new CommonResponse<Guid>
            {
                IsSuccess = false, StatusCode = 400,
                Message = "Số điện thoại không hợp lệ (E.164 / VN).",
                Data = Guid.Empty
            };

        if (string.IsNullOrWhiteSpace(request.Message))
            return new CommonResponse<Guid>
            {
                IsSuccess = false, StatusCode = 400, Message = "Nội dung SMS rỗng.", Data = Guid.Empty
            };

        if (request.Message.Length > 1600)
            return new CommonResponse<Guid>
            {
                IsSuccess = false, StatusCode = 400, Message = "Nội dung SMS vượt quá 1600 ký tự.", Data = Guid.Empty
            };

        var now = DateTime.UtcNow;
        var sms = new SmsMessage
        {
            Id               = Guid.NewGuid(),
            PhoneNumber      = normalized,
            Message          = request.Message.Trim(),
            Status           = SmsStatus.Pending,
            Category         = request.Category,
            SourceService    = request.SourceService,
            CorrelationId    = request.CorrelationId,
            TargetDeviceCode = request.TargetDeviceCode,
            CreatedAt        = now
        };
        await _unitOfWork.SmsMessages.AddAsync(sms);

        await _unitOfWork.SmsAuditLogs.AddAsync(new SmsAuditLog
        {
            Id           = Guid.NewGuid(),
            SmsMessageId = sms.Id,
            Event        = SmsAuditEvent.Queued,
            Detail       = $"source={request.SourceService}, category={request.Category}",
            CreatedAt    = now
        });

        await _unitOfWork.SaveChangesAsync(cancellationToken);

        try
        {
            await _notifier.NotifyNewPendingSmsAsync(sms.Id, sms.PhoneNumber, request.TargetDeviceCode, cancellationToken);
        }
        catch (Exception ex)
        {
            // Polling REST sẽ là fallback. Log để debug.
            _logger.LogWarning(ex, "SignalR notify failed for SMS {SmsId}; will fall back to polling.", sms.Id);
        }

        return new CommonResponse<Guid>
        {
            IsSuccess = true, StatusCode = 200, Message = "Queued.", Data = sms.Id
        };
    }
}
```

### 9.4. `ClaimPendingMessagesCommand`

```csharp
// services/SmsService/src/SmsService.Application/CQRS/Commands/ClaimPendingMessages/ClaimPendingMessagesCommand.cs
using MediatR;
using SharedContracts.Common.Responses;
using SmsService.Application.Dto;

namespace SmsService.Application.CQRS.Commands.ClaimPendingMessages;

public record ClaimPendingMessagesCommand(Guid DeviceId, string DeviceCode, int Limit)
    : IRequest<CommonResponse<List<PendingSmsDto>>>;
```

```csharp
// services/SmsService/src/SmsService.Application/Dto/PendingSmsDto.cs
namespace SmsService.Application.Dto;
public record PendingSmsDto(Guid Id, string PhoneNumber, string Message);
```

```csharp
// services/SmsService/src/SmsService.Application/CQRS/Commands/ClaimPendingMessages/ClaimPendingMessagesCommandHandler.cs
using MediatR;
using Microsoft.EntityFrameworkCore;
using SharedContracts.Common.Responses;
using SmsService.Application.Abstractions;
using SmsService.Application.Dto;
using SmsService.Domain.Entities;
using SmsService.Domain.Enums;

namespace SmsService.Application.CQRS.Commands.ClaimPendingMessages;

public class ClaimPendingMessagesCommandHandler
    : IRequestHandler<ClaimPendingMessagesCommand, CommonResponse<List<PendingSmsDto>>>
{
    private static readonly TimeSpan PickStaleAfter = TimeSpan.FromMinutes(5);

    private readonly ISmsUnitOfWork _unitOfWork;

    public ClaimPendingMessagesCommandHandler(ISmsUnitOfWork unitOfWork) => _unitOfWork = unitOfWork;

    public async Task<CommonResponse<List<PendingSmsDto>>> Handle(
        ClaimPendingMessagesCommand request, CancellationToken cancellationToken)
    {
        var limit = Math.Clamp(request.Limit, 1, 20);
        var now = DateTime.UtcNow;
        var staleBefore = now - PickStaleAfter;

        var device = await _unitOfWork.SmsGatewayDevices.GetByIdAsync(request.DeviceId);
        if (device is null || !device.IsActive)
            return new CommonResponse<List<PendingSmsDto>>
            {
                IsSuccess = false, StatusCode = 403,
                Message = "Device không tồn tại hoặc đã bị thu hồi.",
                Data = new List<PendingSmsDto>()
            };

        device.ResetDailyCounterIfNeeded(now);
        if (device.SentToday >= device.DailyLimit)
        {
            // im lặng trả rỗng — không gửi nữa hôm nay
            return new CommonResponse<List<PendingSmsDto>>
            {
                IsSuccess = true, StatusCode = 200,
                Message = "Daily limit reached.",
                Data = new List<PendingSmsDto>()
            };
        }

        var allowance = device.DailyLimit - device.SentToday;
        var take = Math.Min(limit, allowance);

        var candidates = await _unitOfWork.SmsMessages
            .GetAllAsync()
            .Where(x => !x.IsDeleted)
            .Where(x =>
                (x.Status == SmsStatus.Pending && (x.TargetDeviceCode == null || x.TargetDeviceCode == request.DeviceCode))
                || (x.Status == SmsStatus.Sending && x.PickedAt != null && x.PickedAt < staleBefore))
            .OrderBy(x => x.CreatedAt)
            .Take(take)
            .ToListAsync(cancellationToken);

        foreach (var m in candidates)
        {
            m.Claim(request.DeviceCode, request.DeviceId, now);
            await _unitOfWork.SmsAuditLogs.AddAsync(new SmsAuditLog
            {
                Id = Guid.NewGuid(),
                SmsMessageId = m.Id,
                Event = SmsAuditEvent.Picked,
                DeviceCode = request.DeviceCode,
                CreatedAt = now
            });
        }

        try
        {
            await _unitOfWork.SaveChangesAsync(cancellationToken);
        }
        catch (DbUpdateConcurrencyException)
        {
            // 2 nguồn race xảy ra ở 1 trong 2 chỗ:
            // 1. Device khác claim cùng row sms_messages (xmin trên sms_messages).
            // 2. Request khác cùng device đã update SentToday (xmin trên sms_gateway_devices).
            // Cả 2 đều trả rỗng — lần poll tiếp sẽ retry với state mới nhất.
            return new CommonResponse<List<PendingSmsDto>>
            {
                IsSuccess = true, StatusCode = 200,
                Message = "Concurrent claim, retry next poll.",
                Data = new List<PendingSmsDto>()
            };
        }

        return new CommonResponse<List<PendingSmsDto>>
        {
            IsSuccess = true, StatusCode = 200, Message = "OK",
            Data = candidates.Select(m => new PendingSmsDto(m.Id, m.PhoneNumber, m.Message ?? string.Empty)).ToList()
        };
    }
}
```

### 9.5. `ReportSmsResultCommand` (kèm idempotency)

```csharp
// services/SmsService/src/SmsService.Application/CQRS/Commands/ReportSmsResult/ReportSmsResultCommand.cs
using MediatR;
using SharedContracts.Common.Responses;

namespace SmsService.Application.CQRS.Commands.ReportSmsResult;

public record ReportSmsResultCommand(
    Guid DeviceId,
    string DeviceCode,
    Guid SmsId,
    string Status,         // "Sent" | "Failed"
    string? ErrorMessage
) : IRequest<CommonResponse<string>>;
```

```csharp
// services/SmsService/src/SmsService.Application/CQRS/Commands/ReportSmsResult/ReportSmsResultCommandHandler.cs
using MediatR;
using Microsoft.EntityFrameworkCore;
using SharedContracts.Common.Responses;
using SharedContracts.Events;
using SharedContracts.Interfaces;
using SmsService.Application.Abstractions;
using SmsService.Domain.Entities;
using SmsService.Domain.Enums;

namespace SmsService.Application.CQRS.Commands.ReportSmsResult;

public class ReportSmsResultCommandHandler : IRequestHandler<ReportSmsResultCommand, CommonResponse<string>>
{
    private readonly ISmsUnitOfWork _unitOfWork;
    private readonly IMessageProducerService _messageProducer; // Outbox publisher

    public ReportSmsResultCommandHandler(ISmsUnitOfWork unitOfWork, IMessageProducerService messageProducer)
    {
        _unitOfWork = unitOfWork;
        _messageProducer = messageProducer;
    }

    public async Task<CommonResponse<string>> Handle(ReportSmsResultCommand request, CancellationToken cancellationToken)
    {
        var sms = await _unitOfWork.SmsMessages
            .GetAllAsync()
            .FirstOrDefaultAsync(x => x.Id == request.SmsId && !x.IsDeleted, cancellationToken);

        if (sms is null)
            return Fail(404, "SMS không tồn tại.");

        if (!string.Equals(sms.GatewayDeviceCode, request.DeviceCode, StringComparison.Ordinal))
            return Fail(403, "Device này không giữ SMS đó.");

        // ===== IDEMPOTENCY =====
        // Chỉ chấp nhận report khi đang ở trạng thái Sending. Nếu đã Sent/Failed/Pending/Cancelled,
        // coi như duplicate (mạng chập, app retry). Trả 200 no-op để Flutter dừng retry.
        if (sms.Status != SmsStatus.Sending)
            return new CommonResponse<string>
            {
                IsSuccess = true, StatusCode = 200,
                Message = $"Report ignored: current status is {sms.Status}.",
                Data = sms.Status.ToString()
            };

        var now = DateTime.UtcNow;
        var status = request.Status?.Trim() ?? string.Empty;

        if (string.Equals(status, "Sent", StringComparison.OrdinalIgnoreCase))
        {
            sms.MarkSent(now);

            var device = await _unitOfWork.SmsGatewayDevices.GetByIdAsync(request.DeviceId);
            if (device is not null) device.IncrementSent(now);

            await _unitOfWork.SmsAuditLogs.AddAsync(new SmsAuditLog
            {
                Id = Guid.NewGuid(), SmsMessageId = sms.Id,
                Event = SmsAuditEvent.Sent, DeviceCode = request.DeviceCode,
                CreatedAt = now
            });

            // Outbox: publish TRƯỚC SaveChanges. OutboxPublisher viết outbox_messages cùng DbContext.
            await _messageProducer.PublishAsync(new SmsDeliveryReportEvent(
                sms.Id, sms.CorrelationId, sms.PhoneNumber, sms.SourceService,
                now, request.DeviceCode), cancellationToken);
        }
        else if (string.Equals(status, "Failed", StringComparison.OrdinalIgnoreCase))
        {
            // RetryCount + 1 < MaxRetryCount → còn cơ hội retry (lần thứ N tới = RetryCount + 1).
            // Khi == MaxRetryCount thì final: MarkFailedFinal cũng ++RetryCount để cuối luồng
            // RetryCount == MaxRetryCount (nhất quán semantics).
            if (sms.RetryCount + 1 < sms.MaxRetryCount)
            {
                sms.MarkRetry(request.ErrorMessage, now);
                await _unitOfWork.SmsAuditLogs.AddAsync(new SmsAuditLog
                {
                    Id = Guid.NewGuid(), SmsMessageId = sms.Id,
                    Event = SmsAuditEvent.Retry, DeviceCode = request.DeviceCode,
                    Detail = request.ErrorMessage, CreatedAt = now
                });
            }
            else
            {
                sms.MarkFailedFinal(request.ErrorMessage, now);
                await _unitOfWork.SmsAuditLogs.AddAsync(new SmsAuditLog
                {
                    Id = Guid.NewGuid(), SmsMessageId = sms.Id,
                    Event = SmsAuditEvent.Failed, DeviceCode = request.DeviceCode,
                    Detail = request.ErrorMessage, CreatedAt = now
                });

                await _messageProducer.PublishAsync(new SmsFailedEvent(
                    sms.Id, sms.CorrelationId, sms.PhoneNumber, sms.SourceService,
                    request.ErrorMessage, now, FinalFailure: true), cancellationToken);
            }
        }
        else
        {
            return Fail(400, "Invalid status. Expected 'Sent' or 'Failed' (case-insensitive).");
        }

        try
        {
            await _unitOfWork.SaveChangesAsync(cancellationToken);
        }
        catch (DbUpdateConcurrencyException)
        {
            // Race: xmin trên sms_messages (2 device đồng thời report cùng SMS) HOẶC
            // xmin trên sms_gateway_devices (IncrementSent concurrent với ClaimPending).
            // Trả 200 — Flutter đã idempotent (mục 18), không retry.
            return new CommonResponse<string>
            {
                IsSuccess = true, StatusCode = 200,
                Message = "Concurrent report; treated as duplicate.",
                Data = sms.Status.ToString()
            };
        }

        return new CommonResponse<string>
        {
            IsSuccess = true, StatusCode = 200, Message = "OK", Data = sms.Status.ToString()
        };
    }

    private static CommonResponse<string> Fail(int code, string msg) => new()
    {
        IsSuccess = false, StatusCode = code, Message = msg, Data = string.Empty
    };
}
```

### 9.6. `HeartbeatCommand`

```csharp
// services/SmsService/src/SmsService.Application/CQRS/Commands/Heartbeat/HeartbeatCommand.cs
using MediatR;
using SharedContracts.Common.Responses;

namespace SmsService.Application.CQRS.Commands.Heartbeat;

public record HeartbeatCommand(Guid DeviceId, string? Ip) : IRequest<CommonResponse<string>>;
```

```csharp
// services/SmsService/src/SmsService.Application/CQRS/Commands/Heartbeat/HeartbeatCommandHandler.cs
using MediatR;
using SharedContracts.Common.Responses;
using SmsService.Application.Abstractions;
using SmsService.Domain.Entities;

namespace SmsService.Application.CQRS.Commands.Heartbeat;

public class HeartbeatCommandHandler : IRequestHandler<HeartbeatCommand, CommonResponse<string>>
{
    private readonly ISmsUnitOfWork _unitOfWork;
    public HeartbeatCommandHandler(ISmsUnitOfWork unitOfWork) => _unitOfWork = unitOfWork;

    public async Task<CommonResponse<string>> Handle(HeartbeatCommand request, CancellationToken cancellationToken)
    {
        var device = await _unitOfWork.SmsGatewayDevices.GetByIdAsync(request.DeviceId);
        if (device is null)
            return new CommonResponse<string> { IsSuccess = false, StatusCode = 404, Message = "Device không tồn tại.", Data = string.Empty };

        device.Touch(request.Ip, DateTime.UtcNow);
        await _unitOfWork.SaveChangesAsync(cancellationToken);
        return new CommonResponse<string> { IsSuccess = true, StatusCode = 200, Message = "OK", Data = "pong" };
    }
}
```

### 9.7. `CancelSmsCommand`

```csharp
// services/SmsService/src/SmsService.Application/CQRS/Commands/CancelSms/CancelSmsCommand.cs
public record CancelSmsCommand(Guid SmsId) : IRequest<CommonResponse<string>>;
```

Handler: load message, nếu `Sent/Failed/Cancelled` → return 409. Nếu OK → `Cancel(now)`,
append audit `Cancelled`, save, try notify `BatchRevoked`. Tương tự `QueueSms`.

### 9.8. `CreateGatewayDeviceCommand` (admin)

```csharp
// services/SmsService/src/SmsService.Application/CQRS/Commands/CreateGatewayDevice/CreateGatewayDeviceCommand.cs
using MediatR;
using SharedContracts.Common.Responses;
using SmsService.Application.Dto;

namespace SmsService.Application.CQRS.Commands.CreateGatewayDevice;

public record CreateGatewayDeviceCommand(string DeviceName, string DeviceCode, int DailyLimit = 100)
    : IRequest<CommonResponse<CreateGatewayDeviceResponseDto>>;
```

```csharp
// services/SmsService/src/SmsService.Application/Dto/CreateGatewayDeviceResponseDto.cs
namespace SmsService.Application.Dto;
public record CreateGatewayDeviceResponseDto(Guid Id, string DeviceCode, string ApiKey);
```

```csharp
// services/SmsService/src/SmsService.Application/CQRS/Commands/CreateGatewayDevice/CreateGatewayDeviceCommandHandler.cs
using System.Security.Cryptography;
using MediatR;
using SharedContracts.Common.Responses;
using SmsService.Application.Abstractions;
using SmsService.Application.Dto;
using SmsService.Domain.Entities;

namespace SmsService.Application.CQRS.Commands.CreateGatewayDevice;

public class CreateGatewayDeviceCommandHandler
    : IRequestHandler<CreateGatewayDeviceCommand, CommonResponse<CreateGatewayDeviceResponseDto>>
{
    private readonly ISmsUnitOfWork _unitOfWork;
    private readonly IGatewayApiKeyHasher _hasher;

    public CreateGatewayDeviceCommandHandler(ISmsUnitOfWork unitOfWork, IGatewayApiKeyHasher hasher)
    {
        _unitOfWork = unitOfWork;
        _hasher = hasher;
    }

    public async Task<CommonResponse<CreateGatewayDeviceResponseDto>> Handle(
        CreateGatewayDeviceCommand request, CancellationToken cancellationToken)
    {
        var exists = await _unitOfWork.SmsGatewayDevices.AnyAsync(x => x.DeviceCode == request.DeviceCode);
        if (exists)
            return new CommonResponse<CreateGatewayDeviceResponseDto>
            {
                IsSuccess = false, StatusCode = 409,
                Message = "DeviceCode đã tồn tại.",
                Data = new CreateGatewayDeviceResponseDto(Guid.Empty, request.DeviceCode, string.Empty)
            };

        var apiKey = Convert.ToBase64String(RandomNumberGenerator.GetBytes(32));
        var device = new SmsGatewayDevice
        {
            Id = Guid.NewGuid(),
            DeviceName = request.DeviceName,
            DeviceCode = request.DeviceCode,
            ApiKeyHash = _hasher.Hash(apiKey),
            DailyLimit = request.DailyLimit,
            CreatedAt  = DateTime.UtcNow
        };
        await _unitOfWork.SmsGatewayDevices.AddAsync(device);
        await _unitOfWork.SaveChangesAsync(cancellationToken);

        return new CommonResponse<CreateGatewayDeviceResponseDto>
        {
            IsSuccess = true, StatusCode = 200, Message = "Created.",
            Data = new CreateGatewayDeviceResponseDto(device.Id, device.DeviceCode, apiKey)
        };
    }
}
```

### 9.9. `IGatewayApiKeyHasher`

```csharp
// services/SmsService/src/SmsService.Application/Abstractions/IGatewayApiKeyHasher.cs
namespace SmsService.Application.Abstractions;

public interface IGatewayApiKeyHasher
{
    string Hash(string apiKey);
    bool Verify(string apiKey, string hash);
}
```

### 9.10. `ManageDependencyInjection` (Application)

```csharp
// services/SmsService/src/SmsService.Application/DependencyInjection/ManageDependencyInjection.cs
using System.Reflection;

namespace SmsService.Application.DependencyInjection;

/// <summary>
/// Chỉ giữ marker class để expose ApplicationAssembly cho MassTransit
/// (AddMessageBus(...consumerAssemblies)).
/// KHÔNG gọi AddMediatR ở đây — AddSharedInfrastructure (mục 20 step 3) đã quét
/// SmsService.Application assembly qua assemblyName="SmsService.Application". Double-register
/// MediatR sẽ tạo "Multiple handlers registered" exception lúc Send().
/// </summary>
public static class ManageDependencyInjection
{
    public static Assembly ApplicationAssembly => typeof(ManageDependencyInjection).Assembly;
}
```

### 9.11. `SmsService.Application.csproj`

> ⚠️ **Pattern khớp AuthService.Application**: cần đầy đủ 4 package + 4 project ref.
> Thiếu bất kỳ sẽ compile fail:
> - **`MassTransit`** (KHÔNG phải `.RabbitMQ` — Application chỉ dùng `IConsumer<T>` + `ConsumeContext<T>`, transport là Infrastructure concern)
> - **`Microsoft.EntityFrameworkCore`** — handlers catch `DbUpdateConcurrencyException`
>   (xmin race) trong `ClaimPendingMessages` và `ReportSmsResult`
> - **`Microsoft.Extensions.Logging.Abstractions`** — `ILogger<T>` trong handlers + consumers
> - **`SharedInfrastructure`** project — `IInboxStore` + `IdempotentConsumerExtensions.ProcessOnceAsync`
>   trong consumers (mục 10)

```xml
<Project Sdk="Microsoft.NET.Sdk">
    <PropertyGroup>
        <TargetFramework>net8.0</TargetFramework>
        <Nullable>enable</Nullable>
        <ImplicitUsings>enable</ImplicitUsings>
    </PropertyGroup>
    <ItemGroup>
        <PackageReference Include="MassTransit" Version="8.5.9" />
        <PackageReference Include="MediatR" Version="12.2.0" />
        <PackageReference Include="Microsoft.EntityFrameworkCore" Version="8.0.2" />
        <PackageReference Include="Microsoft.Extensions.Logging.Abstractions" Version="8.0.2" />
    </ItemGroup>
    <ItemGroup>
        <ProjectReference Include="..\SmsService.Domain\SmsService.Domain.csproj" />
        <ProjectReference Include="..\..\..\..\shared\src\SharedKernels\SharedKernels.csproj" />
        <ProjectReference Include="..\..\..\..\shared\src\SharedContracts\SharedContracts.csproj" />
        <ProjectReference Include="..\..\..\..\shared\src\SharedInfrastructure\SharedInfrastructure.csproj" />
    </ItemGroup>
</Project>
```

---

## 10. RabbitMQ Consumers + Inbox

### 10.1. `SendSmsCommandConsumer` (contract mới)

```csharp
// services/SmsService/src/SmsService.Application/Consumers/SendSmsCommandConsumer.cs
using MassTransit;
using MediatR;
using Microsoft.Extensions.Logging;
using SharedContracts.Events;
using SharedInfrastructure.Idempotency;
using SmsService.Application.CQRS.Commands.QueueSms;

namespace SmsService.Application.Consumers;

public class SendSmsCommandConsumer : IConsumer<SendSmsCommand>
{
    private readonly IMediator _mediator;
    private readonly IInboxStore _inboxStore;
    private readonly ILogger<SendSmsCommandConsumer> _logger;

    public SendSmsCommandConsumer(IMediator mediator, IInboxStore inboxStore, ILogger<SendSmsCommandConsumer> logger)
    {
        _mediator = mediator;
        _inboxStore = inboxStore;
        _logger = logger;
    }

    public async Task Consume(ConsumeContext<SendSmsCommand> context)
    {
        var msg = context.Message;

        await context.ProcessOnceAsync(_inboxStore, nameof(SendSmsCommandConsumer), async () =>
        {
            var result = await _mediator.Send(new QueueSmsCommand(
                PhoneNumber:      msg.PhoneNumber,
                Message:          msg.Message,
                SourceService:    msg.SourceService,
                CorrelationId:    msg.CorrelationId,
                Category:         msg.Category,
                TargetDeviceCode: msg.TargetDeviceCode
            ), context.CancellationToken);

            if (!result.IsSuccess)
            {
                _logger.LogWarning("QueueSms rejected: {Message} (corr={Corr}, source={Source})",
                    result.Message, msg.CorrelationId, msg.SourceService);
            }
            else
            {
                _logger.LogInformation("SMS queued id={SmsId} corr={Corr} source={Source}",
                    result.Data, msg.CorrelationId, msg.SourceService);
            }
        });
    }
}
```

### 10.2. `SendPhoneOtpConsumer` (backward-compat — rewrite)

> Hiện tại consumer này nằm trong `SmsService.Infrastructure/Consumers`. **Di chuyển**
> sang `SmsService.Application/Consumers` để dùng được `IMediator`.

```csharp
// services/SmsService/src/SmsService.Application/Consumers/SendPhoneOtpConsumer.cs
using MassTransit;
using MediatR;
using Microsoft.Extensions.Logging;
using SharedContracts.Events;
using SharedInfrastructure.Idempotency;
using SmsService.Application.CQRS.Commands.QueueSms;

namespace SmsService.Application.Consumers;

/// <summary>
/// Backward-compat: AuthService cũ publish SendPhoneOtpEvent. Consumer này render template
/// rồi forward sang QueueSmsCommand. Sau khi AuthService migrate sang SendSmsCommand, xóa class này.
/// </summary>
public class SendPhoneOtpConsumer : IConsumer<SendPhoneOtpEvent>
{
    private readonly IMediator _mediator;
    private readonly IInboxStore _inboxStore;
    private readonly ILogger<SendPhoneOtpConsumer> _logger;

    public SendPhoneOtpConsumer(IMediator mediator, IInboxStore inboxStore, ILogger<SendPhoneOtpConsumer> logger)
    {
        _mediator = mediator;
        _inboxStore = inboxStore;
        _logger = logger;
    }

    public async Task Consume(ConsumeContext<SendPhoneOtpEvent> context)
    {
        var msg = context.Message;
        await context.ProcessOnceAsync(_inboxStore, nameof(SendPhoneOtpConsumer), async () =>
        {
            var body = $"Ma OTP cua ban la {msg.Otp}. Vui long khong chia se ma nay.";
            var result = await _mediator.Send(new QueueSmsCommand(
                PhoneNumber:   msg.PhoneNumber,
                Message:       body,
                SourceService: "auth",
                CorrelationId: msg.Id,                // dùng IntegrationEvent.Id làm correlation
                Category:      "otp"
            ), context.CancellationToken);

            _logger.LogInformation("PhoneOtp consumed → QueueSms result={Success} smsId={SmsId}",
                result.IsSuccess, result.Data);
        });
    }
}
```

> ⚠️ **XÓA** file cũ `services/SmsService/src/SmsService.Infrastructure/Consumers/SendPhoneOtpConsumer.cs`
> sau khi đã chuyển sang `Application`. `Program.cs` đăng ký consumer theo assembly mới (mục 20).

---

## 11. Controllers

### 11.1. `SmsGatewayController` (cho app Flutter)

```csharp
// services/SmsService/src/SmsService.Api/Controllers/SmsGatewayController.cs
using MediatR;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using SmsService.Application.CQRS.Commands.ClaimPendingMessages;
using SmsService.Application.CQRS.Commands.Heartbeat;
using SmsService.Application.CQRS.Commands.ReportSmsResult;

namespace SmsService.Api.Controllers;

public record ReportSmsRequest(Guid SmsId, string Status, string? ErrorMessage);

[ApiController]
[Route("api/sms-gateway")]
[Authorize(AuthenticationSchemes = "GatewayApiKey")]
[EnableRateLimiting("gateway")]
public class SmsGatewayController : ControllerBase
{
    private readonly IMediator _mediator;
    public SmsGatewayController(IMediator mediator) => _mediator = mediator;

    private string DeviceCode => User.FindFirst("device_code")?.Value
        ?? throw new InvalidOperationException("Missing device_code claim.");
    private Guid DeviceId => Guid.Parse(User.FindFirst("device_id")!.Value);

    [HttpGet("messages/pending")]
    public async Task<IActionResult> GetPending([FromQuery] int limit = 5, CancellationToken ct = default)
    {
        var resp = await _mediator.Send(new ClaimPendingMessagesCommand(DeviceId, DeviceCode, limit), ct);
        return StatusCode(resp.StatusCode, resp);
    }

    [HttpPost("messages/report")]
    public async Task<IActionResult> Report([FromBody] ReportSmsRequest req, CancellationToken ct)
    {
        var resp = await _mediator.Send(new ReportSmsResultCommand(
            DeviceId, DeviceCode, req.SmsId, req.Status, req.ErrorMessage), ct);
        return StatusCode(resp.StatusCode, resp);
    }

    [HttpPost("heartbeat")]
    public async Task<IActionResult> Heartbeat(CancellationToken ct)
    {
        var ip = HttpContext.Connection.RemoteIpAddress?.ToString();
        var resp = await _mediator.Send(new HeartbeatCommand(DeviceId, ip), ct);
        return StatusCode(resp.StatusCode, resp);
    }
}
```

### 11.2. `AdminGatewayDevicesController` (admin nội bộ qua JWT)

```csharp
// services/SmsService/src/SmsService.Api/Controllers/AdminGatewayDevicesController.cs
using MediatR;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using SmsService.Application.CQRS.Commands.CancelSms;
using SmsService.Application.CQRS.Commands.CreateGatewayDevice;
using SmsService.Application.CQRS.Commands.RevokeGatewayDevice;
using SmsService.Application.CQRS.Queries.ListGatewayDevices;

namespace SmsService.Api.Controllers;

[ApiController]
[Route("api/admin/sms-gateway")]
// Chỉ định explicit JWT scheme — tránh nhầm với scheme "GatewayApiKey" sau này nếu thay default.
[Authorize(AuthenticationSchemes = JwtBearerDefaults.AuthenticationScheme, Roles = "Admin")]
public class AdminGatewayDevicesController : ControllerBase
{
    private readonly IMediator _mediator;
    public AdminGatewayDevicesController(IMediator mediator) => _mediator = mediator;

    [HttpPost("devices")]
    public async Task<IActionResult> Create([FromBody] CreateGatewayDeviceCommand cmd, CancellationToken ct)
    {
        var resp = await _mediator.Send(cmd, ct);
        return StatusCode(resp.StatusCode, resp);
    }

    [HttpGet("devices")]
    public async Task<IActionResult> List(CancellationToken ct)
    {
        var resp = await _mediator.Send(new ListGatewayDevicesQuery(), ct);
        return StatusCode(resp.StatusCode, resp);
    }

    [HttpDelete("devices/{id:guid}")]
    public async Task<IActionResult> Revoke(Guid id, CancellationToken ct)
    {
        var resp = await _mediator.Send(new RevokeGatewayDeviceCommand(id), ct);
        return StatusCode(resp.StatusCode, resp);
    }

    [HttpPost("messages/{id:guid}/cancel")]
    public async Task<IActionResult> Cancel(Guid id, CancellationToken ct)
    {
        var resp = await _mediator.Send(new CancelSmsCommand(id), ct);
        return StatusCode(resp.StatusCode, resp);
    }
}
```

> 📌 **Handlers còn lại** (`CancelSmsCommandHandler`, `RevokeGatewayDeviceCommandHandler`,
> `ListGatewayDevicesQueryHandler`, `GetSmsByIdQueryHandler`) là CRUD đơn giản theo
> pattern `QueueSmsCommandHandler` ở mục 9.3. Mỗi handler:
> - Load entity qua `_unitOfWork.<repo>.GetByIdAsync(id)` (hoặc `GetAllAsync().Where(...)` cho list).
> - Mutate / select.
> - Return `CommonResponse<T>`.
>
> Không cần Outbox event cho admin actions (Cancel publish `NotifyBatchRevoked` qua
> SignalR đã đủ).

---

## 12. SignalR Hub

### 12.1. `SmsGatewayHub`

```csharp
// services/SmsService/src/SmsService.Infrastructure/Realtime/SmsGatewayHub.cs
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using SmsService.Domain.Entities;
using SmsService.Infrastructure.Persistence;

namespace SmsService.Infrastructure.Realtime;

[Authorize(AuthenticationSchemes = "GatewayApiKey")]
public class SmsGatewayHub : Hub
{
    public static string DeviceGroup(string code) => $"device:{code}";
    public const string AllDevicesGroup = "gateway:all";

    private readonly IServiceScopeFactory _scopeFactory;
    private readonly ILogger<SmsGatewayHub> _logger;

    public SmsGatewayHub(IServiceScopeFactory scopeFactory, ILogger<SmsGatewayHub> logger)
    {
        _scopeFactory = scopeFactory;
        _logger = logger;
    }

    public override async Task OnConnectedAsync()
    {
        var deviceCode = Context.User?.FindFirst("device_code")?.Value;
        var deviceIdStr = Context.User?.FindFirst("device_id")?.Value;

        if (string.IsNullOrEmpty(deviceCode) || !Guid.TryParse(deviceIdStr, out var deviceId))
        {
            Context.Abort();
            return;
        }

        await Groups.AddToGroupAsync(Context.ConnectionId, DeviceGroup(deviceCode));
        await Groups.AddToGroupAsync(Context.ConnectionId, AllDevicesGroup);

        // Update LastSeenAt trong scope mới (Hub là transient nhưng connection sống lâu).
        await using var scope = _scopeFactory.CreateAsyncScope();
        var db = scope.ServiceProvider.GetRequiredService<SmsDbContext>();
        var device = await db.SmsGatewayDevices.FirstOrDefaultAsync(x => x.Id == deviceId);
        if (device is not null)
        {
            device.Touch(Context.GetHttpContext()?.Connection.RemoteIpAddress?.ToString(), DateTime.UtcNow);
            await db.SaveChangesAsync();
        }

        _logger.LogInformation("Gateway connected {DeviceCode} ({ConnId})", deviceCode, Context.ConnectionId);
        await base.OnConnectedAsync();
    }

    public override Task OnDisconnectedAsync(Exception? exception)
    {
        var deviceCode = Context.User?.FindFirst("device_code")?.Value;
        _logger.LogInformation("Gateway disconnected {DeviceCode} ({ConnId}) reason={Reason}",
            deviceCode, Context.ConnectionId, exception?.Message ?? "client close");
        return base.OnDisconnectedAsync(exception);
    }

    public Task<string> Ping() => Task.FromResult("pong");
}
```

### 12.2. `SignalRSmsGatewayNotifier`

```csharp
// services/SmsService/src/SmsService.Infrastructure/Realtime/SignalRSmsGatewayNotifier.cs
using Microsoft.AspNetCore.SignalR;
using SmsService.Application.Abstractions;

namespace SmsService.Infrastructure.Realtime;

public class SignalRSmsGatewayNotifier : ISmsGatewayNotifier
{
    private readonly IHubContext<SmsGatewayHub> _hub;
    public SignalRSmsGatewayNotifier(IHubContext<SmsGatewayHub> hub) => _hub = hub;

    public Task NotifyNewPendingSmsAsync(Guid smsId, string phoneNumber, string? targetDeviceCode, CancellationToken cancellationToken = default)
    {
        var payload = new { smsId, phoneNumber, ts = DateTimeOffset.UtcNow };
        return targetDeviceCode is null
            ? _hub.Clients.Group(SmsGatewayHub.AllDevicesGroup).SendAsync("NewPendingSms", payload, cancellationToken)
            : _hub.Clients.Group(SmsGatewayHub.DeviceGroup(targetDeviceCode)).SendAsync("NewPendingSms", payload, cancellationToken);
    }

    public Task NotifyBatchRevokedAsync(IEnumerable<Guid> smsIds, string? targetDeviceCode, CancellationToken cancellationToken = default)
    {
        var payload = new { smsIds = smsIds.ToArray(), ts = DateTimeOffset.UtcNow };
        return targetDeviceCode is null
            ? _hub.Clients.Group(SmsGatewayHub.AllDevicesGroup).SendAsync("BatchRevoked", payload, cancellationToken)
            : _hub.Clients.Group(SmsGatewayHub.DeviceGroup(targetDeviceCode)).SendAsync("BatchRevoked", payload, cancellationToken);
    }
}
```

> 📝 Hub đặt ở `SmsService.Infrastructure.Realtime` (cùng namespace với Notifier) để
> tránh circular reference Api → Infrastructure → Api. `Program.cs` ở Api map hub
> bằng `app.MapHub<SmsService.Infrastructure.Realtime.SmsGatewayHub>("/hubs/sms-gateway")`
> — nhờ `SmsService.Api.csproj` reference `SmsService.Infrastructure.csproj` (xem
> Phụ lục A + B).

---

## 13. Authentication `GatewayApiKey` (BCrypt)

### 13.1. Hasher (BCrypt)

```csharp
// services/SmsService/src/SmsService.Infrastructure/Security/BcryptGatewayApiKeyHasher.cs
using SmsService.Application.Abstractions;

namespace SmsService.Infrastructure.Security;

public class BcryptGatewayApiKeyHasher : IGatewayApiKeyHasher
{
    private const int WorkFactor = 11;

    public string Hash(string apiKey) => BCrypt.Net.BCrypt.HashPassword(apiKey, WorkFactor);

    public bool Verify(string apiKey, string hash)
    {
        try { return BCrypt.Net.BCrypt.Verify(apiKey, hash); }
        catch { return false; }
    }
}
```

### 13.2. AuthenticationHandler

```csharp
// services/SmsService/src/SmsService.Infrastructure/Security/GatewayApiKeyAuthenticationHandler.cs
using System.Security.Claims;
using System.Text.Encodings.Web;
using Microsoft.AspNetCore.Authentication;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using SmsService.Application.Abstractions;
using SmsService.Infrastructure.Persistence;

namespace SmsService.Infrastructure.Security;

public class GatewayAuthOptions : AuthenticationSchemeOptions { }

public class GatewayApiKeyAuthenticationHandler : AuthenticationHandler<GatewayAuthOptions>
{
    private readonly SmsDbContext _db;
    private readonly IGatewayApiKeyHasher _hasher;

    public GatewayApiKeyAuthenticationHandler(
        IOptionsMonitor<GatewayAuthOptions> options,
        ILoggerFactory logger,
        UrlEncoder encoder,
        SmsDbContext db,
        IGatewayApiKeyHasher hasher) : base(options, logger, encoder)
    {
        _db = db;
        _hasher = hasher;
    }

    protected override async Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        // X-Device-Code: header (REST) hoặc deviceCode query (SignalR WebSocket).
        var deviceCode = Request.Headers["X-Device-Code"].ToString();
        if (string.IsNullOrWhiteSpace(deviceCode))
            deviceCode = Request.Query["deviceCode"].ToString();
        if (string.IsNullOrWhiteSpace(deviceCode))
            return AuthenticateResult.Fail("Missing X-Device-Code / deviceCode.");

        // Token: Authorization Bearer (REST) hoặc access_token query (SignalR WebSocket).
        string apiKey;
        var auth = Request.Headers.Authorization.ToString();
        if (auth.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase))
            apiKey = auth["Bearer ".Length..].Trim();
        else
        {
            apiKey = Request.Query["access_token"].ToString();
            if (string.IsNullOrWhiteSpace(apiKey))
                return AuthenticateResult.Fail("Missing Bearer token / access_token.");
        }

        var device = await _db.SmsGatewayDevices
            .AsNoTracking()
            .FirstOrDefaultAsync(x => x.DeviceCode == deviceCode && x.IsActive && !x.IsDeleted);
        if (device is null) return AuthenticateResult.Fail("Unknown or revoked device.");

        if (!_hasher.Verify(apiKey, device.ApiKeyHash))
            return AuthenticateResult.Fail("Invalid api key.");

        var claims = new[]
        {
            new Claim("device_code", device.DeviceCode),
            new Claim("device_id",   device.Id.ToString()),
            new Claim(ClaimTypes.NameIdentifier, device.Id.ToString()),
            new Claim(ClaimTypes.Name, device.DeviceName),
        };
        var identity = new ClaimsIdentity(claims, Scheme.Name);
        return AuthenticateResult.Success(new AuthenticationTicket(new ClaimsPrincipal(identity), Scheme.Name));
    }
}
```

### 13.3. Đăng ký (Program.cs — xem mục 20)

```csharp
builder.Services
    .AddAuthentication() // giữ chain — JWT từ SharedInfrastructure đã add JwtBearer scheme default
    .AddScheme<GatewayAuthOptions, GatewayApiKeyAuthenticationHandler>("GatewayApiKey", _ => { });
```

---

## 14. Outbox (reuse pattern AuthService)

### 14.1. `OutboxMessagePublisher`

```csharp
// services/SmsService/src/SmsService.Infrastructure/Services/OutboxMessagePublisher.cs
// Copy nguyên từ AuthService.Infrastructure.Implements.Services.OutboxMessagePublisher.
using System.Text.Json;
using SharedContracts.Events.Root;
using SharedContracts.Interfaces;
using SmsService.Domain.Entities;
using SmsService.Infrastructure.Persistence;

namespace SmsService.Infrastructure.Services;

public class OutboxMessagePublisher : IMessageProducerService
{
    private readonly SmsDbContext _dbContext;
    public OutboxMessagePublisher(SmsDbContext dbContext) => _dbContext = dbContext;

    public Task PublishAsync<T>(T message, CancellationToken cancellationToken = default) where T : IntegrationEvent
    {
        var outbox = new OutboxMessage
        {
            Id = Guid.NewGuid(),
            EventType = typeof(T).AssemblyQualifiedName ?? typeof(T).FullName ?? typeof(T).Name,
            Payload = JsonSerializer.Serialize(message, message.GetType()),
            OccurredAt = message.OccurredAt,
            ProcessedAt = null,
            RetryCount = 0,
            LastError = null,
            CreatedAt = DateTime.UtcNow
        };
        _dbContext.OutboxMessages.Add(outbox);
        return Task.CompletedTask;
    }
}
```

### 14.2. `OutboxRelayBackgroundService` + `OutboxOptions`

```csharp
// services/SmsService/src/SmsService.Infrastructure/Options/OutboxOptions.cs
namespace SmsService.Infrastructure.Options;

public class OutboxOptions
{
    public const string SectionName = "Outbox";
    public int PollIntervalSeconds { get; set; } = 5;
    public int BatchSize           { get; set; } = 50;
    public int MaxRetries          { get; set; } = 10;
}
```

```csharp
// services/SmsService/src/SmsService.Infrastructure/BackgroundJobs/OutboxRelayBackgroundService.cs
// Copy nguyên xi từ AuthService.Infrastructure.BackgroundJobs.OutboxRelayBackgroundService,
// chỉ đổi ApplicationDbContext → SmsDbContext.
using System.Text.Json;
using MassTransit;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using SharedInfrastructure.Metrics;
using SmsService.Infrastructure.Options;
using SmsService.Infrastructure.Persistence;

namespace SmsService.Infrastructure.BackgroundJobs;

public class OutboxRelayBackgroundService : BackgroundService
{
    private readonly IServiceScopeFactory _scopeFactory;
    private readonly OutboxOptions _options;
    private readonly ILogger<OutboxRelayBackgroundService> _logger;

    public OutboxRelayBackgroundService(
        IServiceScopeFactory scopeFactory,
        IOptions<OutboxOptions> options,
        ILogger<OutboxRelayBackgroundService> logger)
    {
        _scopeFactory = scopeFactory;
        _options = options.Value;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromSeconds(_options.PollIntervalSeconds));
        _logger.LogInformation("OutboxRelay started. Interval={Seconds}s, BatchSize={Batch}, MaxRetries={Max}",
            _options.PollIntervalSeconds, _options.BatchSize, _options.MaxRetries);

        while (!stoppingToken.IsCancellationRequested && await timer.WaitForNextTickAsync(stoppingToken))
        {
            try { await ProcessBatchAsync(stoppingToken); }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { break; }
            catch (Exception ex) { _logger.LogError(ex, "OutboxRelay tick failed unexpectedly."); }
        }
    }

    private async Task ProcessBatchAsync(CancellationToken cancellationToken)
    {
        await using var scope = _scopeFactory.CreateAsyncScope();
        var dbContext = scope.ServiceProvider.GetRequiredService<SmsDbContext>();
        var publishEndpoint = scope.ServiceProvider.GetRequiredService<IPublishEndpoint>();

        var pending = await dbContext.OutboxMessages
            .Where(o => o.ProcessedAt == null && o.RetryCount < _options.MaxRetries)
            .OrderBy(o => o.OccurredAt)
            .Take(_options.BatchSize)
            .ToListAsync(cancellationToken);

        if (pending.Count == 0) return;

        foreach (var msg in pending)
        {
            try
            {
                var eventType = Type.GetType(msg.EventType);
                if (eventType is null)
                {
                    msg.RetryCount += 1;
                    msg.LastError = $"Cannot resolve type '{msg.EventType}'.";
                    _logger.LogError("OutboxRelay cannot resolve type {Type} for message {Id}.", msg.EventType, msg.Id);
                    continue;
                }

                var eventObj = JsonSerializer.Deserialize(msg.Payload, eventType);
                if (eventObj is null)
                {
                    msg.RetryCount += 1;
                    msg.LastError = $"Deserialize returned null for type '{msg.EventType}'.";
                    continue;
                }

                await publishEndpoint.Publish(eventObj, eventType, cancellationToken);
                msg.ProcessedAt = DateTime.UtcNow;
                msg.LastError = null;

                AppMetrics.OutboxProcessed.WithLabels(eventType.Name).Inc();
            }
            catch (Exception ex)
            {
                msg.RetryCount += 1;
                msg.LastError = ex.Message.Length > 2000 ? ex.Message[..2000] : ex.Message;
                _logger.LogWarning(ex, "OutboxRelay failed to publish message {Id} (retry {Retry}/{Max}).",
                    msg.Id, msg.RetryCount, _options.MaxRetries);

                AppMetrics.OutboxFailures.WithLabels(ex.GetType().Name).Inc();
                if (msg.RetryCount >= _options.MaxRetries)
                    AppMetrics.OutboxSkippedMaxRetry.Inc();
            }
        }

        await dbContext.SaveChangesAsync(cancellationToken);
    }
}
```

### 14.3. Đăng ký

Đã wire trong **Mục 20 (Program.cs)**:

- Step 1: `Configure<OutboxOptions>(...)` đọc section `Outbox` từ appsettings.
- Step 5: `AddScoped<IMessageProducerService, OutboxMessagePublisher>()` — **ghi đè**
  default `MassTransitProducer` của `AddMessageBus` bằng Outbox publisher.
- Step 5: `AddHostedService<OutboxRelayBackgroundService>()` — background poller.

⚠️ Thứ tự đăng ký **quan trọng**: `OutboxMessagePublisher` phải được `AddScoped` **SAU**
`AddMessageBus(...)` (đã register `MassTransitProducer` lúc đó); cuối cùng resolver
trả `OutboxMessagePublisher` (last-registration-wins cho cùng interface).

---

## 15. Inbox (Redis — đã có sẵn `SharedInfrastructure.Idempotency`)

Không tạo gì mới. Chỉ cần:

```csharp
// Program.cs
builder.Services.AddInboxIdempotency(builder.Configuration);
```

(Helper này đã có trong `SmsService.Api/Program.cs` hiện tại — giữ nguyên.)

Trong consumer: dùng `await context.ProcessOnceAsync(_inboxStore, nameof(ThisConsumer), async () => { ... })`.

> **Khác biệt với Outbox**: Inbox không nằm trong DB của SmsService, mà ở Redis chung
> (`inbox:<consumerName>:<messageId>`). TTL mặc định 7 ngày (`InboxOptions.TtlDays`).

---

## 16. Rate limiting + Daily limit

### 16.1. Per-device rate limit (60 req/phút)

```csharp
// Program.cs — đăng ký
builder.Services.AddRateLimiter(o =>
{
    o.AddPolicy("gateway", httpContext =>
    {
        var deviceCode = httpContext.Request.Headers["X-Device-Code"].ToString();
        return RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: string.IsNullOrEmpty(deviceCode) ? "anon" : deviceCode,
            factory: _ => new System.Threading.RateLimiting.FixedWindowRateLimiterOptions
            {
                PermitLimit = 60,
                Window = TimeSpan.FromMinutes(1),
                QueueLimit = 0
            });
    });
    o.RejectionStatusCode = 429;
});

app.UseRateLimiter();
```

Controller `[EnableRateLimiting("gateway")]`.

### 16.2. Daily limit

Tự động trong `ClaimPendingMessagesCommandHandler` (mục 9.4). Đếm tăng trong
`ReportSmsResultCommandHandler` khi status `Sent` (mục 9.5).

---

## 17. Background services

### 17.1. `StaleSmsReaperBackgroundService` (5 phút stale)

```csharp
// services/SmsService/src/SmsService.Infrastructure/BackgroundJobs/StaleSmsReaperBackgroundService.cs
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using SmsService.Domain.Entities;
using SmsService.Domain.Enums;
using SmsService.Infrastructure.Persistence;

namespace SmsService.Infrastructure.BackgroundJobs;

public class StaleSmsReaperBackgroundService : BackgroundService
{
    private static readonly TimeSpan TickInterval = TimeSpan.FromMinutes(1);
    private static readonly TimeSpan StaleThreshold = TimeSpan.FromMinutes(5);

    private readonly IServiceScopeFactory _scopeFactory;
    private readonly ILogger<StaleSmsReaperBackgroundService> _logger;

    public StaleSmsReaperBackgroundService(IServiceScopeFactory scopeFactory, ILogger<StaleSmsReaperBackgroundService> logger)
    {
        _scopeFactory = scopeFactory;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(TickInterval);
        while (!stoppingToken.IsCancellationRequested && await timer.WaitForNextTickAsync(stoppingToken))
        {
            try
            {
                await using var scope = _scopeFactory.CreateAsyncScope();
                var db = scope.ServiceProvider.GetRequiredService<SmsDbContext>();
                var threshold = DateTime.UtcNow - StaleThreshold;

                var stale = await db.SmsMessages
                    .Where(x => x.Status == SmsStatus.Sending && x.PickedAt != null && x.PickedAt < threshold && !x.IsDeleted)
                    .ToListAsync(stoppingToken);

                var now = DateTime.UtcNow;
                foreach (var m in stale)
                {
                    m.ReapStaleClaim(now);
                    db.SmsAuditLogs.Add(new SmsAuditLog
                    {
                        Id = Guid.NewGuid(), SmsMessageId = m.Id,
                        Event = SmsAuditEvent.Reaped, CreatedAt = now,
                        Detail = "Stale claim reaped after 5 minutes."
                    });
                }
                if (stale.Count > 0)
                {
                    try
                    {
                        await db.SaveChangesAsync(stoppingToken);
                        _logger.LogInformation("StaleSmsReaper reverted {Count} stale SMS.", stale.Count);
                    }
                    catch (DbUpdateConcurrencyException ex)
                    {
                        // Một số row đã bị device khác claim/report cùng lúc — bỏ qua, tick sau xử lý.
                        _logger.LogWarning(ex, "StaleSmsReaper concurrency conflict; will retry next tick.");
                    }
                }
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { break; }
            catch (Exception ex) { _logger.LogError(ex, "StaleSmsReaper tick failed."); }
        }
    }
}
```

### 17.2. `SmsMessageRedactorBackgroundService` (xóa cột `message` sau 24h khi `Sent`)

```csharp
// services/SmsService/src/SmsService.Infrastructure/BackgroundJobs/SmsMessageRedactorBackgroundService.cs
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using SmsService.Domain.Entities;
using SmsService.Domain.Enums;
using SmsService.Infrastructure.Persistence;

namespace SmsService.Infrastructure.BackgroundJobs;

public class SmsMessageRedactorBackgroundService : BackgroundService
{
    private static readonly TimeSpan TickInterval = TimeSpan.FromMinutes(15);
    private static readonly TimeSpan RetainAfterSent = TimeSpan.FromHours(24);

    private readonly IServiceScopeFactory _scopeFactory;
    private readonly ILogger<SmsMessageRedactorBackgroundService> _logger;

    public SmsMessageRedactorBackgroundService(IServiceScopeFactory scopeFactory, ILogger<SmsMessageRedactorBackgroundService> logger)
    {
        _scopeFactory = scopeFactory;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(TickInterval);
        while (!stoppingToken.IsCancellationRequested && await timer.WaitForNextTickAsync(stoppingToken))
        {
            try
            {
                await using var scope = _scopeFactory.CreateAsyncScope();
                var db = scope.ServiceProvider.GetRequiredService<SmsDbContext>();
                var now = DateTime.UtcNow;
                var cutoff = now - RetainAfterSent;
                var candidates = await db.SmsMessages
                    .Where(x => x.Status == SmsStatus.Sent
                                && x.SentAt != null && x.SentAt < cutoff
                                && x.Message != null
                                && !x.IsDeleted)
                    .Take(500)
                    .ToListAsync(stoppingToken);

                foreach (var m in candidates)
                {
                    m.Redact(now);
                    db.SmsAuditLogs.Add(new SmsAuditLog
                    {
                        Id = Guid.NewGuid(), SmsMessageId = m.Id,
                        Event = SmsAuditEvent.Redacted, CreatedAt = now,
                        Detail = "Message content redacted after 24h retention."
                    });
                }
                if (candidates.Count > 0)
                {
                    await db.SaveChangesAsync(stoppingToken);
                    _logger.LogInformation("Redacted {Count} SMS messages older than 24h.", candidates.Count);
                }
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { break; }
            catch (Exception ex) { _logger.LogError(ex, "SmsMessageRedactor tick failed."); }
        }
    }
}
```

---

## 18. Idempotency cho REST report

Đã implement trong `ReportSmsResultCommandHandler` (mục 9.5):

- Chỉ accept khi `Status == Sending` AND `GatewayDeviceCode` khớp.
- Mọi trạng thái khác (`Sent`/`Failed`/`Pending`/`Cancelled`) → trả 200 no-op với `Message` mô tả lý do.
- `DbUpdateConcurrencyException` (do `xmin`) → trả 200 "treated as duplicate".

Flutter app retry POST `/report` bao nhiêu lần cũng an toàn.

---

## 19. Configuration

### 19.1. `appsettings.json` (SmsService.Api)

```json
{
  "ConnectionStrings": {
    "SmsDb": "Host=localhost;Port=5432;Database=sms_service_db;Username=postgres;Password=postgres",
    "Redis": "localhost:6379"
  },
  "RabbitMQ": {
    "Host": "localhost",
    "Username": "guest",
    "Password": "guest"
  },
  "JwtSettings": {
    "SecretKey": "<copy đúng giá trị từ AuthService — phải khớp để verify JWT admin>",
    "Issuer": "https://localhost:5001",
    "Audience": "https://localhost:5001",
    "AccessTokenExpirationMinutes": 60
  },
  "Outbox": {
    "PollIntervalSeconds": 5,
    "BatchSize": 50,
    "MaxRetries": 10
  },
  "Inbox": {
    "TtlDays": 7,
    "FailOpenWhenRedisDown": false
  },
  "MessageBus": {
    "PrefetchCount": 16,
    "ConcurrentMessageLimit": 8
  },
  "Sms": {
    "DefaultDailyLimit": 100
  }
}
```

> ⚠️ **Redis phải nằm trong `ConnectionStrings`** (KHÔNG phải `Redis:ConnectionString`):
> `AddSharedInfrastructure` gọi `AddStackExchangeRedisCache` đọc qua
> `configuration.GetConnectionString("Redis")` — sẽ trả null nếu để ở section khác.

### 19.1.1. `SmsOptions` class

```csharp
// services/SmsService/src/SmsService.Infrastructure/Options/SmsOptions.cs
namespace SmsService.Infrastructure.Options;

public class SmsOptions
{
    public const string SectionName = "Sms";

    /// <summary>Daily limit mặc định khi tạo device mới qua admin endpoint.</summary>
    public int DefaultDailyLimit { get; set; } = 100;
}
```

(File hiện có ở repo — chỉ cần mở rộng thêm `DefaultDailyLimit` nếu chưa có. `SectionName`
phải match `appsettings.json` key `Sms`.)

### 19.2. Env var fallback

`Program.cs` dùng `EnvFileLoader.LoadIfExists()` (đã có trong
`SharedInfrastructure.Extensions`). Connection string đọc theo chuỗi fallback
`ConnectionStrings__SmsDb` / `SmsDb` / `Sms_Db` / `SMS_DB`.

Redis: env var ưu tiên `ConnectionStrings__Redis` (cho cả `RedisCache` của
`AddSharedInfrastructure` và `IConnectionMultiplexer` của `AddInboxIdempotency`).
`AddInboxIdempotency` có fallback `Redis:ConnectionString` rồi `localhost:6379`,
nhưng `AddStackExchangeRedisCache` KHÔNG có fallback → bắt buộc set
`ConnectionStrings:Redis`.

Convention `.env.Docker` example (xem `/Users/alex/Documents/capstone/backend/.env.Docker`):

```
ConnectionStrings__SmsDb=Host=postgres;Port=5432;Database=sms_service_db;Username=postgres;Password=postgres
ConnectionStrings__Redis=redis:6379
RabbitMQ__Host=rabbitmq
RabbitMQ__Username=guest
RabbitMQ__Password=guest
JwtSettings__SecretKey=<copy từ AuthService>
JwtSettings__Issuer=https://localhost:5001
JwtSettings__Audience=https://localhost:5001
Inbox__TtlDays=7
Inbox__FailOpenWhenRedisDown=false
Outbox__PollIntervalSeconds=5
Outbox__BatchSize=50
Outbox__MaxRetries=10
```

---

## 20. `Program.cs` — wiring đầy đủ

```csharp
// services/SmsService/src/SmsService.Api/Program.cs
using Microsoft.AspNetCore.Authentication;
using Microsoft.EntityFrameworkCore;
using Prometheus;
using SharedContracts.Interfaces;
using SharedInfrastructure.Bus;
using SharedInfrastructure.DependencyInjection;
using SharedInfrastructure.Extensions;
using SharedInfrastructure.Idempotency;
using SmsService.Application.Abstractions;
using SmsService.Application.DependencyInjection;
using SmsService.Infrastructure.BackgroundJobs;
using SmsService.Infrastructure.Options;
using SmsService.Infrastructure.Persistence;
using SmsService.Infrastructure.Persistence.Repositories;
using SmsService.Infrastructure.Realtime;
using SmsService.Infrastructure.Security;
using SmsService.Infrastructure.Services;

EnvFileLoader.LoadIfExists();

var builder = WebApplication.CreateBuilder(args);

// ── 1. Config ────────────────────────────────────────────────
builder.Services.Configure<SmsOptions>(builder.Configuration.GetSection(SmsOptions.SectionName));
builder.Services.Configure<OutboxOptions>(builder.Configuration.GetSection(OutboxOptions.SectionName));

// ── 2. DbContext ─────────────────────────────────────────────
var connectionString = builder.Configuration.GetConnectionString("SmsDb")
                      ?? builder.Configuration["SmsDb"]
                      ?? builder.Configuration["Sms_Db"]
                      ?? builder.Configuration["SMS_DB"]
                      ?? throw new InvalidOperationException(
                          "Missing SMS database connection string. Expected ConnectionStrings__SmsDb / SmsDb / Sms_Db / SMS_DB.");

builder.Services.AddDbContext<SmsDbContext>(opt => opt.UseNpgsql(connectionString));
builder.Services.AddScoped<DbContext>(sp => sp.GetRequiredService<SmsDbContext>());
builder.Services.AddScoped<ISmsUnitOfWork, SmsUnitOfWork>();

// ── 3. SharedInfrastructure ──────────────────────────────────
// Side-effect: đăng ký sẵn — Logging+ValidationBehavior, IGenericRepository<>,
// ICurrentUserService, AuditableEntityInterceptor, MediatRInfrastructure (qua assemblyName),
// CORS ("AllowAll"), JWT scheme (default), RoleAuthorize, ModelStateResponse,
// SwaggerGen, StackExchangeRedisCache (đọc ConnectionStrings:Redis), ICacheService.
// ⚠️ KHÔNG đăng ký lại các thứ trên ở đây — sẽ tạo duplicate.
//
// 🚨 CRITICAL: assemblyName PHẢI là tên Application assembly ("SmsService.Application"),
// KHÔNG phải Api. `AddMediatRInfrastructure` dùng Assembly.Load(assemblyName) để scan
// handlers — sai tên → handlers không được đăng ký → runtime crash khi mediator.Send.
// Pattern khớp với AuthService: `services.AddSharedInfrastructure(configuration, "AuthService.Application", ...)`.
builder.Services.AddSharedInfrastructure(
    builder.Configuration,
    assemblyName: "SmsService.Application",
    apiTitle: "SmsService API");

// ── 4. (Đã bỏ AddSmsApplication) ─────────────────────────────
// MediatR handlers từ SmsService.Application đã được AddSharedInfrastructure ở step 3 quét.
// Nếu sau này cần thêm DI cho Application (validators, pipeline behaviors riêng), tạo
// helper extension MỚI nhưng KHÔNG gọi AddMediatR lần 2 — sẽ tạo duplicate handler.

// ── 5. Inbox (Redis) ─────────────────────────────────────────
builder.Services.AddInboxIdempotency(builder.Configuration);

// ── 6. MassTransit consumers ─────────────────────────────────
// Consumer assembly: SmsService.Application (chứa SendSmsCommandConsumer, SendPhoneOtpConsumer).
// AddMessageBus đăng ký IMessageProducerService = MassTransitProducer — nhưng step 7 dưới
// đây sẽ OVERRIDE bằng OutboxMessagePublisher để publish atomic với DbContext.
builder.Services.AddMessageBus(
    builder.Configuration,
    configure: null,
    ManageDependencyInjection.ApplicationAssembly);
// (`ManageDependencyInjection` chỉ là static helper expose Assembly — tham khảo mục 9.10).

// ── 7. Outbox publisher (PHẢI đăng ký SAU AddMessageBus để override) ───
// Last-registration-wins: handler resolve IMessageProducerService → OutboxMessagePublisher.
// OutboxRelayBackgroundService poll DB → dùng IPublishEndpoint (MassTransit) publish thật.
builder.Services.AddScoped<IMessageProducerService, OutboxMessagePublisher>();
builder.Services.AddHostedService<OutboxRelayBackgroundService>();

// ── 8. SignalR + Notifier ───────────────────────────────────
builder.Services.AddSignalR(o =>
{
    o.EnableDetailedErrors        = builder.Environment.IsDevelopment();
    o.KeepAliveInterval           = TimeSpan.FromSeconds(15);
    o.ClientTimeoutInterval       = TimeSpan.FromSeconds(60);
});
builder.Services.AddSingleton<ISmsGatewayNotifier, SignalRSmsGatewayNotifier>();

// ── 9. Security ─────────────────────────────────────────────
builder.Services.AddSingleton<IGatewayApiKeyHasher, BcryptGatewayApiKeyHasher>();
builder.Services
    .AddAuthentication() // JWT scheme đã add bởi SharedInfrastructure
    .AddScheme<GatewayAuthOptions, GatewayApiKeyAuthenticationHandler>("GatewayApiKey", _ => { });

builder.Services.AddAuthorization(options =>
{
    options.AddPolicy("GatewayDevice", p => p
        .AddAuthenticationSchemes("GatewayApiKey")
        .RequireAuthenticatedUser()
        .RequireClaim("device_code"));
});

// ── 10. Rate limiter ────────────────────────────────────────
builder.Services.AddRateLimiter(o =>
{
    o.AddPolicy("gateway", httpContext =>
    {
        var deviceCode = httpContext.Request.Headers["X-Device-Code"].ToString();
        return System.Threading.RateLimiting.RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: string.IsNullOrEmpty(deviceCode) ? "anon" : deviceCode,
            factory: _ => new System.Threading.RateLimiting.FixedWindowRateLimiterOptions
            {
                PermitLimit = 60,
                Window = TimeSpan.FromMinutes(1),
                QueueLimit = 0
            });
    });
    o.RejectionStatusCode = 429;
});

// ── 11. Background workers ──────────────────────────────────
builder.Services.AddHostedService<StaleSmsReaperBackgroundService>();
builder.Services.AddHostedService<SmsMessageRedactorBackgroundService>();

// ── 12. Controllers ─────────────────────────────────────────
builder.Services.AddControllers();

// ── 13. Build & pipeline ────────────────────────────────────
var app = builder.Build();

app.UseSharedInfrastructure();     // SecurityHeaders + CorrelationId + RequestLogging + GlobalException + CommonResponseStatusCodes
app.UseHttpMetrics();

if (!app.Environment.IsProduction())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

if (!app.Environment.IsEnvironment("Docker")
    && !builder.Configuration.GetValue("DisableHttpsRedirection", false))
{
    app.UseHttpsRedirection();
}

app.UseCors("AllowAll");           // đã đăng ký bởi AddCorsExtentions() trong AddSharedInfrastructure
app.UseRateLimiter();
app.UseAuthentication();
app.UseAuthorization();

app.MapGet("/", () => "SMS Service is Running...");
app.MapMetrics();
app.MapControllers();
app.MapHub<SmsGatewayHub>("/hubs/sms-gateway"); // qualified bởi using SmsService.Infrastructure.Realtime

app.Run();

public partial class Program { }
```

> 📝 Thứ tự middleware: `UseRateLimiter` → `UseAuthentication` → `UseAuthorization`
> → `MapControllers` / `MapHub`. **Hub thừa hưởng middleware chain** — không cần config riêng.

---

## 21. Migration & schema

> ⚠️ **Chạy từ REPO ROOT** (`capstone/backend/`), KHÔNG phải từ `services/SmsService/`.
> Path trong `SmsDbContextFactory.SetBasePath(Directory.GetCurrentDirectory())` +
> relative `services/SmsService/src/SmsService.Api/appsettings.*.json` — match khi cwd là root.

```bash
# Từ thư mục REPO ROOT capstone/backend/
cd /Users/alex/Documents/capstone/backend

dotnet ef migrations add Initial_SmsGateway_Schema \
    --project services/SmsService/src/SmsService.Infrastructure \
    --startup-project services/SmsService/src/SmsService.Api \
    --context SmsDbContext

dotnet ef database update \
    --project services/SmsService/src/SmsService.Infrastructure \
    --startup-project services/SmsService/src/SmsService.Api \
    --context SmsDbContext
```

Migration tạo: `sms_messages`, `sms_gateway_devices`, `sms_audit_logs`, `outbox_messages`
cùng index như configurations đã khai báo, kèm cột shadow `xmin` cho `sms_messages` và
`sms_gateway_devices`.

---

## 22. Tích hợp với service khác

### 22.1. AuthService — migrate sang `SendSmsCommand`

Trong handler `SendPhoneOtpCommandHandler`:

```csharp
// TRƯỚC
await _messageProducer.PublishAsync(new SendPhoneOtpEvent(account.PhoneNumber, otp), cancellationToken);

// SAU
var body = $"Ma OTP cua ban la {otp}. Vui long khong chia se ma nay.";
await _messageProducer.PublishAsync(new SendSmsCommand(
    PhoneNumber:   account.PhoneNumber,
    Message:       body,
    SourceService: "auth",
    CorrelationId: Guid.NewGuid(), // Để track end-to-end; nếu muốn link với OTP record, dùng OtpRequest.Id.
    Category:      "otp"
), cancellationToken);
```

Đường rút lui: `SendPhoneOtpConsumer` ở SmsService vẫn nhận event cũ → an toàn rollback.

> 🚨 **CẢNH BÁO atomic switch**: AuthService **CHỈ ĐƯỢC publish 1 trong 2 event**
> (`SendPhoneOtpEvent` HOẶC `SendSmsCommand`) — không bao giờ cả 2 cùng lúc trong
> cùng một request. Nếu publish cả 2:
> - `SendPhoneOtpConsumer` và `SendSmsCommandConsumer` đều consume → tạo **2 row
>   `sms_messages`** → người dùng nhận **2 tin OTP**.
> - Inbox dedup theo `(consumerName, messageId)` — vì 2 event khác `Id`, dedup không
>   chặn được.
>
> Cách deploy an toàn:
> 1. Deploy SmsService có `SendSmsCommandConsumer` trước (Phase 5/6), giữ
>    `SendPhoneOtpConsumer` vẫn chạy.
> 2. Verify SmsService nhận `SendSmsCommand` OK trong staging.
> 3. Deploy AuthService với change publish — chỉ phát `SendSmsCommand`, **xoá hẳn**
>    `PublishAsync(new SendPhoneOtpEvent(...))` trong cùng commit.
> 4. Sau 1–2 sprint không thấy `SendPhoneOtpEvent` nữa, mới xoá
>    `SendPhoneOtpConsumer` ở SmsService.

### 22.2. BatteryService — gửi cảnh báo

```csharp
await _messageProducer.PublishAsync(new SendSmsCommand(
    PhoneNumber:   site.OnCallPhone,
    Message:       $"Battery {asset.Code} alert: {alert.Title}",
    SourceService: "battery",
    CorrelationId: alert.Id,
    Category:      "alert"
), cancellationToken);
```

### 22.3. (Optional) Subscribe `SmsDeliveryReportEvent`

Service nào cần biết kết quả tạo `IConsumer<SmsDeliveryReportEvent>` riêng và đăng ký
qua `AddMessageBus(...)` của service đó. MassTransit auto-bind queue.

---

## 23. Phase triển khai

### Phase 0 — Setup môi trường (0.5 ngày)
- Tạo database `sms_service_db` trên Postgres dev.
- Cập nhật `appsettings.Development.json` của SmsService.
- Chốt lại các quyết định mục 4 (đã có) với team.

### Phase 1 — Domain + Persistence (1 ngày)
- Tạo `SmsService.Domain` project + entities (4 class: `SmsMessage`, `SmsGatewayDevice`,
  `SmsAuditLog`, `OutboxMessage`) + 2 enum (`SmsStatus`, `SmsAuditEvent`). **KHÔNG**
  tạo Domain events (mục 6.7 giải thích).
- Cập nhật `.slnx`.
- Tạo `SmsService.Infrastructure/Persistence`:
  - `SmsDbContext` với **2 constructor** (design-time + runtime với `AuditableEntityInterceptor`)
    và `OnConfiguring` attach interceptor (mục 7.1) — bắt buộc cho soft-delete + CreatedBy auto-set.
  - `SmsDbContextFactory` (`IDesignTimeDbContextFactory`) cho `dotnet ef`.
  - 4 Configuration files với manual snake_case mapping + `b.Ignore(DomainEvents)`.
  - `SmsUnitOfWork` impl `ISmsUnitOfWork` từ Application (forward ref Phase 2).
- Sinh migration `Initial_SmsGateway_Schema` và apply lên DB dev.
- ✅ Checkpoint: `dotnet ef database update` thành công, 4 bảng + tất cả index + cột `xmin`
  shadow trên `sms_messages` và `sms_gateway_devices` xuất hiện.

### Phase 2 — Application core CQRS (1.5 ngày)
- Tạo `SmsService.Application` project (chỉ reference MediatR package, **KHÔNG**
  tự register MediatR — sẽ được `AddSharedInfrastructure(... "SmsService.Application")`
  ở Phase 4 quét tự động). Marker class `ManageDependencyInjection.ApplicationAssembly`
  expose Assembly cho MassTransit dùng ở Phase 5.
- Implement: `QueueSmsCommand`, `ClaimPendingMessagesCommand`, `ReportSmsResultCommand`,
  `HeartbeatCommand`, `CancelSmsCommand`.
- `PhoneNumberNormalizer`.
- Implement `ISmsUnitOfWork` + `SmsUnitOfWork`.
- Implement `NullSmsGatewayNotifier` cho test.
- Unit test claim race + report idempotency.
- ✅ Checkpoint: unit test pass.

### Phase 3 — Authentication & Admin (1 ngày)
- `BcryptGatewayApiKeyHasher` + `GatewayApiKeyAuthenticationHandler`.
- `CreateGatewayDeviceCommand` + `RevokeGatewayDeviceCommand` + `ListGatewayDevicesQuery`.
- `AdminGatewayDevicesController` (JWT-protected).
- ✅ Checkpoint: tạo device qua curl, copy apiKey plaintext.

### Phase 4 — REST gateway endpoints (0.5 ngày)
- `SmsGatewayController` với 3 action.
- Wire `gateway` rate limiter.
- ✅ Checkpoint: curl `pending` / `report` / `heartbeat` đúng.

### Phase 5 — RabbitMQ inbound (1 ngày)
- Tạo `SharedContracts.Events.SendSmsCommand` + 2 events outbound.
- Tạo `SendSmsCommandConsumer` trong `SmsService.Application/Consumers`.
- Di chuyển `SendPhoneOtpConsumer` từ Infrastructure → Application, rewrite gọi
  `IMediator.Send(QueueSmsCommand)`.
- **Cleanup obsolete code**:
  - Xóa `SmsService.Infrastructure/Services/FakeSmsSender.cs`.
  - Xóa interface `ISmsSender` (nếu có file riêng).
  - Xóa dòng `builder.Services.AddSingleton<ISmsSender, FakeSmsSender>();` trong Program.cs cũ.
  - Gateway architecture không gửi SMS trực tiếp → không cần `ISmsSender`.
- Wire MassTransit với assembly mới ở `Program.cs` (mục 20 step 6).
- ✅ Checkpoint: publish `SendSmsCommand` từ console test → row `Pending` xuất hiện trong DB.

### Phase 6 — Outbox (0.5 ngày)
- `OutboxMessage` entity đã có ở Phase 1 — không tạo lại.
- Copy `OutboxMessagePublisher` (mục 14.1) + `OutboxRelayBackgroundService` từ
  AuthService, đổi `ApplicationDbContext` → `SmsDbContext`.
- Verify `ReportSmsResultCommandHandler` (mục 9.5) đã gọi `_messageProducer.PublishAsync`
  TRƯỚC `SaveChangesAsync` — đảm bảo atomic outbox.
- ✅ Checkpoint: report `Sent` → row trong `outbox_messages` với `processed_at = null`
  → vài giây sau `OutboxRelay` publish → event xuất hiện ở RabbitMQ management UI.

### Phase 7 — SignalR (1 ngày)
- Tạo `SmsGatewayHub` trong `SmsService.Infrastructure/Realtime/`.
- Implement `SignalRSmsGatewayNotifier`.
- Map hub trong `Program.cs`.
- Tích hợp notify vào `QueueSmsCommandHandler` (đã có sẵn).
- ✅ Checkpoint: test bằng JS console nhận `NewPendingSms` < 1 giây sau khi queue.

### Phase 8 — Background polish (0.5 ngày)
- `StaleSmsReaperBackgroundService` + `SmsMessageRedactorBackgroundService`.
- Cập nhật `services/SmsService/README.md`.
- Verify Serilog/Prometheus đã wire đúng.

### Phase 9 — Integration với AuthService (0.5 ngày)
- AuthService: chuyển publish `SendPhoneOtpEvent` → `SendSmsCommand`.
- Verify backward-compat `SendPhoneOtpConsumer` vẫn còn (chưa xóa).
- Test 1 chu kỳ login OTP qua flow mới.

### Phase 10 — End-to-end với app Flutter (1 ngày)
- Tạo device qua admin endpoint.
- Cấu hình app Flutter: backend URL + token + device code.
- Test: queue SMS → SignalR push < 1s → SIM gửi → report → callback event.
- Test fallback polling (tắt Hub).
- Test daily limit, retry, cancel.
- Test 2 device đua claim.

**Tổng cộng: ~8.5 ngày dev (1 dev). MVP (bỏ Phase 7+8) ≈ 5 ngày.**

---

## 24. Checklist trước khi merge

- [ ] `dotnet build` toàn solution thành công.
- [ ] Migration tạo 4 bảng + index + cột xmin.
- [ ] Unit test `QueueSms`, `ClaimPendingMessages`, `ReportSmsResult` (idempotency!), `Heartbeat` pass.
- [ ] Integration test claim race (2 handler đua `xmin` concurrency token trên `sms_messages`) pass.
- [ ] Integration test daily-limit race (2 ClaimPending đồng thời không over-claim quá `DailyLimit`) pass.
- [ ] Integration test REST report idempotency (POST trùng 2 lần không bump RetryCount) pass.
- [ ] Admin endpoint tạo device + return apiKey plaintext 1 lần duy nhất.
- [ ] curl 3 endpoint gateway với BCrypt-hashed token, header + query.
- [ ] RabbitMQ `SendSmsCommand` → Pending row + SignalR `NewPendingSms`.
- [ ] RabbitMQ inbox dedup: publish 2 message MessageId trùng → chỉ 1 row Pending.
- [ ] Outbox: report `Sent` → `OutboxMessage` row → `OutboxRelay` publish → service đăng ký nhận event.
- [ ] SignalR `NewPendingSms` < 1 giây từ queue → JS test client.
- [ ] `StaleSmsReaper` revert đúng sau 5 phút.
- [ ] `SmsMessageRedactor` xóa cột `message` sau 24h kể từ `Sent`.
- [ ] Rate limiter 60 req/phút/device hoạt động (429 sau giới hạn).
- [ ] Daily limit reset đúng khi sang ngày mới (UTC).
- [ ] Flutter app `sms_fowarder` end-to-end gửi SMS qua SIM thật thành công.
- [ ] AuthService gửi OTP qua `SendSmsCommand` mới + consumer cũ backward-compat vẫn chạy.
- [ ] Logs structured + correlation id xuyên suốt request.
- [ ] `services/SmsService/README.md` cập nhật.
- [ ] Cập nhật `MEMORY.md` ghi quyết định non-obvious nếu có.

---

## 25. Test end-to-end với app Flutter

1. **Build & migrate** (từ repo root `capstone/backend`):
   ```bash
   cd /Users/alex/Documents/capstone/backend
   dotnet ef database update \
       --project services/SmsService/src/SmsService.Infrastructure \
       --startup-project services/SmsService/src/SmsService.Api \
       --context SmsDbContext

   # Run SmsService (internal, port theo launchSettings)
   dotnet run --project services/SmsService/src/SmsService.Api

   # Run ApiGateway (entry point cho app Flutter) — terminal khác
   dotnet run --project services/ApiGateway/src/ApiGateway
   ```
   Cần chạy **cả hai service** + AuthService + RabbitMQ + Postgres + Redis. Khuyến nghị dùng `docker-compose up` từ repo root để bootstrap toàn bộ stack một lần.

2. **Tạo device**: cần admin JWT — login trước qua AuthService với account có role `Admin`.
   **Tất cả request đi qua ApiGateway** (port 5000 cho local dev, đổi theo `launchSettings.json`
   của ApiGateway):
   ```bash
   # Lấy admin JWT — qua ApiGateway → AuthService
   curl -X POST https://localhost:5000/api/auth/login \
        -H "Content-Type: application/json" \
        -d '{"email":"admin@example.com","password":"<admin-password>"}'
   # → Copy "accessToken" từ response.

   # Tạo device gateway — qua ApiGateway → SmsService
   curl -X POST https://localhost:5000/api/admin/sms-gateway/devices \
        -H "Authorization: Bearer <admin-jwt-vừa-lấy>" \
        -H "Content-Type: application/json" \
        -d '{"deviceName":"Phone A","deviceCode":"android-gateway-001","dailyLimit":100}'
   # → Copy "data.apiKey" — hiển thị 1 lần duy nhất.
   ```

3. **Cấu hình app Flutter** (`Settings` screen):
   - Backend URL: `https://<máy-chạy-ApiGateway>:5000` (KHÔNG phải SmsService port trực tiếp)
   - Gateway token: `<apiKey>` vừa copy
   - Device code: `android-gateway-001`
   - Polling interval: `10`

4. **Bấm Start gateway** → kiểm tra chip realtime hiện `REALTIME` (xanh).
   Nếu chip vẫn `POLL 10s`, kiểm tra ApiGateway đã forward WebSocket upgrade
   chưa (xem mục 27.1).

5. **Queue SMS qua RabbitMQ** — 2 cách:

   **Cách A — gọi AuthService login OTP qua ApiGateway**: `AccountId` được lấy
   từ JWT claim (`SendPhoneOtpCommand.AccountId` có `[JsonIgnore]`), controller
   gán bằng claim. Body request rỗng:
   ```bash
   curl -X POST https://localhost:5000/api/auth/send-phone-otp \
        -H "Authorization: Bearer <user-jwt-có-phone-number-trong-account>" \
        -H "Content-Length: 0"
   ```
   ⚠️ Phải login trước (`POST /api/auth/login`) để lấy user JWT — cồng kềnh cho
   manual test. Khuyến nghị dùng **Cách B** cho test e2e nhanh.

   **Cách B — publish trực tiếp `SendSmsCommand` bằng script test**
   (`dotnet run` 1 console nhỏ với MassTransit + `SharedContracts` reference). Dùng
   `Bus.Factory` trực tiếp cho console không có `IHost` — nếu dùng `AddMassTransit`
   qua `ServiceCollection`, cần `MassTransitHostedService` để bus start, phức tạp hơn.

   Console test csproj:
   ```xml
   <Project Sdk="Microsoft.NET.Sdk">
       <PropertyGroup>
           <TargetFramework>net8.0</TargetFramework>
           <OutputType>Exe</OutputType>
       </PropertyGroup>
       <ItemGroup>
           <PackageReference Include="MassTransit.RabbitMQ" Version="8.5.9" />
           <ProjectReference Include="../../shared/src/SharedContracts/SharedContracts.csproj" />
       </ItemGroup>
   </Project>
   ```
   ```csharp
   // Program.cs của console test
   using MassTransit;
   using SharedContracts.Events;

   var bus = Bus.Factory.CreateUsingRabbitMq(cfg =>
   {
       cfg.Host("localhost", "/", h => { h.Username("guest"); h.Password("guest"); });
   });

   await bus.StartAsync();
   try
   {
       await bus.Publish(new SendSmsCommand(
           PhoneNumber:   "0901234567",
           Message:       "Test from .NET console",
           SourceService: "manual-test",
           CorrelationId: Guid.NewGuid()));
       Console.WriteLine("Published SendSmsCommand. Check SmsService logs + DB.");
   }
   finally
   {
       await bus.StopAsync();
   }
   ```

   App Flutter phải gửi SMS trong < 1 giây. DB row chuyển `Pending → Sending → Sent`.

6. **Verify outbound event**: subscribe queue `SmsDeliveryReportEvent` (RabbitMQ UI),
   thấy 1 event sau khi report.

---

## 26. Bảo mật

| Hạng mục | Cách làm |
| -------- | -------- |
| **SmsService KHÔNG expose ra internet** | Chỉ ApiGateway expose public; SmsService internal sau ApiGateway (docker network / private subnet) |
| Token gateway dạng plaintext **không tái dùng** JWT user | Scheme `GatewayApiKey` (mục 13) |
| Hash token trong DB | BCrypt workFactor 11 |
| Rate limit phút | Mục 16 (60 req/phút/device) — áp dụng ở SmsService level; ApiGateway có thể thêm rate limit của riêng nó |
| Daily limit | Mục 9 + entity property |
| Audit log mọi event | `sms_audit_logs` |
| Validate số điện thoại | `PhoneNumberNormalizer` |
| HTTPS | TLS terminate ở ApiGateway. SmsService internal có thể plain HTTP (docker network). |
| Disable device | `RevokeGatewayDeviceCommand` set `IsActive = false` |
| Không log plaintext OTP | OTP business stay tại AuthService; SmsService chỉ lưu rendered text, TTL redact sau 24h |
| WebSocket query token chỉ trên HTTPS | ApiGateway terminate TLS → upgrade WebSocket sang `wss://` cho Flutter, plain `ws://` về SmsService internal. |

---

## 27. ApiGateway routing (đã setup) — checklist verify

App Flutter **CHỈ kết nối qua ApiGateway** (đã wire trong `services/ApiGateway`).
SmsService không expose trực tiếp ra internet. Phần này là checklist verify
cấu hình YARP đã đúng cho SMS Forwarder use case.

### 27.1. Routes phải có trong `services/ApiGateway/src/ApiGateway/appsettings.json`

```json
{
  "ReverseProxy": {
    "Routes": {
      "sms-gateway-rest": {
        "ClusterId": "sms-service",
        "Match": { "Path": "/api/sms-gateway/{**catch-all}" }
      },
      "sms-gateway-admin": {
        "ClusterId": "sms-service",
        "Match": { "Path": "/api/admin/sms-gateway/{**catch-all}" }
      },
      "sms-gateway-hub": {
        "ClusterId": "sms-service",
        "Match": { "Path": "/hubs/sms-gateway/{**catch-all}" }
      }
    },
    "Clusters": {
      "sms-service": {
        "Destinations": {
          "d1": { "Address": "http://sms-service:8080/" }
        }
      }
    }
  }
}
```

### 27.2. WebSocket upgrade — checklist

YARP **forward WebSocket upgrade tự động** cho route nào không có explicit transform.
Verify:

- [ ] `ApiGateway/Program.cs` có `app.UseWebSockets()` **trước** `app.MapReverseProxy()`.
- [ ] Không có transform nào strip `Upgrade` / `Connection` headers cho route `sms-gateway-hub`.
- [ ] Cluster destination dùng `http://` (không `https://`) vì internal docker network
      thường plain HTTP — TLS terminate ở ApiGateway.
- [ ] Timeout WebSocket >= 60s (default OK; tăng nếu nginx/Cloudflare trước ApiGateway).

### 27.3. Authorization header forward

Flutter gửi `Authorization: Bearer <apiKey>` (KHÔNG phải JWT). YARP **forward header
mặc định**, nhưng nếu ApiGateway có middleware validate JWT trên TẤT CẢ routes, sẽ
reject request gateway vì `apiKey` không phải JWT format.

- [ ] ApiGateway **không** validate JWT cho route prefix `/api/sms-gateway/*` và
      `/hubs/sms-gateway` — chuyển trách nhiệm auth xuống SmsService
      (`GatewayApiKey` scheme).
- [ ] Route `/api/admin/sms-gateway/*` thì có thể validate JWT ở ApiGateway hoặc
      forward thẳng — SmsService có `[Authorize(AuthenticationSchemes = JwtBearer, Roles = "Admin")]`
      sẽ enforce ở cuối đường.

### 27.4. `X-Device-Code` header forward

Flutter gửi `X-Device-Code: android-gateway-001`. YARP forward custom header
mặc định. Verify không có CORS hoặc transform strip header này.

### 27.5. Cloudflare / nginx trước ApiGateway (nếu có)

Nếu Cloudflare hoặc nginx đứng trước ApiGateway:

- Cloudflare: bật **WebSocket** trong Network settings (mặc định bật).
- nginx: cần proxy upgrade headers cho `/hubs/`:
  ```nginx
  location /hubs/ {
      proxy_pass http://apigateway_upstream;
      proxy_http_version 1.1;
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection "upgrade";
      proxy_read_timeout 600s;
  }
  ```

---

## 28. Monitoring & troubleshooting

| Triệu chứng | Cách kiểm tra |
| ----------- | -------------- |
| App Flutter 404 trên `/api/sms-gateway/messages/pending` | ApiGateway chưa route đúng. Verify mục 27.1 — kiểm tra `appsettings.json` của ApiGateway có 3 routes (sms-gateway-rest/admin/hub). Hit `https://localhost:5000/api/sms-gateway/messages/pending` trực tiếp bằng curl; nếu 404 thì ApiGateway sai. Hit trực tiếp `http://sms-service:8080/...` trong docker để xác nhận SmsService alive. |
| App Flutter 401 "Missing X-Device-Code" mặc dù gửi đúng | ApiGateway transform strip header. Check transforms trong route config; thêm `RequestHeaderRemove` exemption. |
| App Flutter log "Realtime unavailable" ngay khi Start | ApiGateway chưa forward WebSocket upgrade. Verify `app.UseWebSockets()` trong ApiGateway Program.cs, đặt TRƯỚC `MapReverseProxy()`. Curl `POST https://localhost:5000/hubs/sms-gateway/negotiate?deviceCode=...` với token để test handshake. |
| App Flutter "Realtime reconnecting" liên tục | KeepAlive timeout không khớp giữa client & ApiGateway/proxy chain. Check `proxy_read_timeout` ở mọi hop (Cloudflare → nginx → ApiGateway). Tăng ≥ 600s. |
| Queue SMS xong app không phản ứng < 1s | `QueueSmsCommandHandler` quên gọi `_notifier.Notify...`, hoặc device nằm trong group khác. Check log "SignalR notify failed". |
| Authentication fail trên WebSocket nhưng REST OK | Handler chưa đọc `access_token` query — mục 13.2. |
| `OutboxRelayBackgroundService` không publish | Check `outbox_messages.processed_at` còn null, `last_error` có nội dung gì. Kiểm tra RabbitMQ connection. |
| Inbox skip cả message hợp lệ | Redis flushdb mất state. Bật metric `inbox_skipped_duplicate` để watch. |
| Nhiều device nhận cùng 1 SMS | Đúng theo design — chỉ device claim được mới gửi. EF `xmin` đảm bảo race-free. |
| Daily counter không reset | Check `sent_today_date` — phải khớp với `DateOnly.FromDateTime(UtcNow)`. |
| `StaleSmsReaper` revert quá nhiều | Có thể app đang online nhưng claim không gửi được. Check log device. |

Prometheus metrics có sẵn qua `SharedInfrastructure.Metrics`:

- `outbox_processed_total{event_type}`
- `outbox_failures_total{exception_type}`
- `outbox_skipped_max_retry_total`
- `inbox_processed_total{consumer}`
- `inbox_skipped_duplicate_total{consumer}`

Endpoint `/metrics` (đã `MapMetrics()`).

---

## Phụ lục A — `SmsService.Api.csproj`

```xml
<Project Sdk="Microsoft.NET.Sdk.Web">
    <PropertyGroup>
        <TargetFramework>net8.0</TargetFramework>
        <Nullable>enable</Nullable>
        <ImplicitUsings>enable</ImplicitUsings>
    </PropertyGroup>
    <ItemGroup>
        <PackageReference Include="DotNetEnv" Version="3.2.0" />
        <PackageReference Include="Microsoft.EntityFrameworkCore.Design" Version="8.0.2">
            <IncludeAssets>runtime; build; native; contentfiles; analyzers; buildtransitive</IncludeAssets>
            <PrivateAssets>all</PrivateAssets>
        </PackageReference>
        <PackageReference Include="Swashbuckle.AspNetCore" Version="6.6.2" />
    </ItemGroup>
    <ItemGroup>
        <ProjectReference Include="..\SmsService.Application\SmsService.Application.csproj" />
        <ProjectReference Include="..\SmsService.Infrastructure\SmsService.Infrastructure.csproj" />
    </ItemGroup>
</Project>
```

## Phụ lục B — `SmsService.Infrastructure.csproj`

> ⚠️ **`FrameworkReference Microsoft.AspNetCore.App` BẮT BUỘC**: Infrastructure project
> dùng SDK `Microsoft.NET.Sdk` (không phải `.Sdk.Web`), nhưng cần namespace
> `Microsoft.AspNetCore.SignalR` (cho Hub + `IHubContext<>`), `Microsoft.AspNetCore.Authentication`
> (cho `GatewayApiKeyAuthenticationHandler`), `Microsoft.AspNetCore.Authorization`
> (cho `[Authorize]` trên Hub). Không có FrameworkReference, build sẽ fail với
> `The type or namespace 'SignalR' does not exist in the namespace 'Microsoft.AspNetCore'`.

```xml
<Project Sdk="Microsoft.NET.Sdk">
    <PropertyGroup>
        <TargetFramework>net8.0</TargetFramework>
        <Nullable>enable</Nullable>
        <ImplicitUsings>enable</ImplicitUsings>
    </PropertyGroup>
    <ItemGroup>
        <FrameworkReference Include="Microsoft.AspNetCore.App" />
    </ItemGroup>
    <ItemGroup>
        <PackageReference Include="BCrypt.Net-Next" Version="4.0.3" />
        <PackageReference Include="MassTransit.RabbitMQ" Version="8.5.9" />
        <PackageReference Include="Microsoft.EntityFrameworkCore" Version="8.0.2" />
        <PackageReference Include="Microsoft.EntityFrameworkCore.Design" Version="8.0.2">
            <IncludeAssets>runtime; build; native; contentfiles; analyzers; buildtransitive</IncludeAssets>
            <PrivateAssets>all</PrivateAssets>
        </PackageReference>
        <PackageReference Include="Npgsql.EntityFrameworkCore.PostgreSQL" Version="8.0.2" />
    </ItemGroup>
    <ItemGroup>
        <ProjectReference Include="..\SmsService.Application\SmsService.Application.csproj" />
        <ProjectReference Include="..\SmsService.Domain\SmsService.Domain.csproj" />
        <ProjectReference Include="..\..\..\..\shared\src\SharedContracts\SharedContracts.csproj" />
        <ProjectReference Include="..\..\..\..\shared\src\SharedInfrastructure\SharedInfrastructure.csproj" />
        <ProjectReference Include="..\..\..\..\shared\src\SharedKernels\SharedKernels.csproj" />
    </ItemGroup>
</Project>
```

## Phụ lục C — Hợp đồng app Flutter (cần 1 patch)

### C.1. Phần đã khớp (không đổi)

`lib/core/constants/api_constants.dart`:

```dart
class ApiConstants {
  static const String pendingMessagesPath = '/api/sms-gateway/messages/pending';
  static const String reportPath          = '/api/sms-gateway/messages/report';
  static const String heartbeatPath       = '/api/sms-gateway/heartbeat';
  static const String hubPath             = '/hubs/sms-gateway';
}
```

`lib/core/network/api_client.dart` headers:

```dart
headers: {
  'Authorization': 'Bearer $gatewayToken',
  'X-Device-Code': deviceCode,
  'Content-Type': 'application/json',
  'Accept': 'application/json',
}
```

SignalR negotiate URL: `{backendUrl}/hubs/sms-gateway?deviceCode={code}` với token đi qua `access_token` query khi handshake WebSocket.

→ Backend khớp đúng path + 2 header này + 2 SignalR event (`NewPendingSms`, `BatchRevoked`).

> 📍 **`backendUrl` trỏ về ApiGateway**, không phải SmsService trực tiếp. App nhập
> URL ApiGateway ở màn Settings — paths và headers KHÔNG thay đổi, ApiGateway
> forward nguyên về SmsService.

### C.2. Phần PHẢI patch (bắt buộc)

Backend trả **`CommonResponse<T>` wrapper** cho mọi REST endpoint:

```json
{ "isSuccess": true, "statusCode": 200, "message": "OK", "data": [ ... ] }
```

Hàm `fetchPendingMessages()` ở
`lib/features/sms_gateway/data/datasources/sms_gateway_remote_datasource.dart` đang
parse raw list / `raw['items']` — sẽ **luôn nhận `[]`** và app **không bao giờ gửi
SMS nào**.

**Bắt buộc patch**:

```dart
Future<List<PendingSmsModel>> fetchPendingMessages({int limit = ApiConstants.defaultBatchSize}) async {
  final response = await apiClient.get(
    ApiConstants.pendingMessagesPath,
    queryParameters: {'limit': limit},
  );

  final raw = response.data;
  if (raw == null) return const [];

  final List<dynamic> data;
  if (raw is Map<String, dynamic> && raw['data'] is List) {
    data = raw['data'] as List<dynamic>;           // 🆕 backend wrapper
  } else if (raw is List<dynamic>) {
    data = raw;                                     // legacy fallback
  } else if (raw is Map<String, dynamic> && raw['items'] is List) {
    data = raw['items'] as List<dynamic>;           // legacy fallback
  } else {
    data = const [];
  }

  return data
      .map((item) => PendingSmsModel.fromJson(item as Map<String, dynamic>))
      .toList(growable: false);
}
```

### C.3. Phần tuỳ chọn (nên làm để robust)

Check `isSuccess` để báo lỗi đúng khi device bị revoke (`403`) thay vì silently nhận `[]`:

```dart
if (raw is Map<String, dynamic> && raw.containsKey('isSuccess')) {
  if (!(raw['isSuccess'] as bool? ?? false)) {
    throw NetworkException(
      raw['message']?.toString() ?? 'Backend rejected pending fetch',
      statusCode: raw['statusCode'] as int?,
    );
  }
}
```

### C.4. Không cần đổi

- `/report` POST: datasource fire-and-forget, không parse body. Backend mới idempotent
  trả 200 cho duplicate report → khớp hành vi Flutter.
- `/heartbeat` POST: không parse body.
- SignalR event names + payload: backend giữ đúng `NewPendingSms` + `BatchRevoked`,
  payload là single object → `_asMap` parse OK.

---

**HẾT.**
