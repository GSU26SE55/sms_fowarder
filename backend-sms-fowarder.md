# Backend .NET cho SMS Forwarder Gateway

> Tài liệu này mô tả **đầy đủ** phần backend `.NET` để kết nối với app Flutter Android
> SMS Gateway (repo `sms_gateway_app` ở thư mục cùng cấp). Bạn copy các đoạn code
> vào project backend `capstone/backend` rồi ráp lại theo cấu trúc hiện có.
>
> Mục tiêu:
> - Cung cấp endpoint cho **frontend/admin/service** nội bộ tạo yêu cầu gửi SMS.
> - Cung cấp endpoint cho **app Android gateway** lấy SMS pending, gửi và report
>   trạng thái.
> - Có authentication riêng cho gateway, rate limit, retry, audit, daily limit.
>
> Đường đi tổng thể:
>
> ```text
> Frontend / Service nội bộ
>     ↓ POST /api/sms/send
> SmsController
>     ↓ ISmsService.QueueSmsAsync()
> sms_messages table (Pending)
>     ↑ poll
> Flutter Android Gateway (sms_gateway_app)
>     ↓ GET /api/sms-gateway/messages/pending  (Pending → Sending)
>     ↓ Android gửi SMS bằng SIM thật
>     ↓ POST /api/sms-gateway/messages/report   (Sent / Failed)
> SmsGatewayController
>     ↓ update sms_messages (+ retry logic)
> ```

---

## 0. Hợp đồng API (App Flutter đang gọi)

Để khớp 100% với app Flutter ở repo này, backend **bắt buộc** expose 3 endpoint REST
và 1 SignalR Hub, nhận header `Authorization: Bearer <token>` và `X-Device-Code: <device-code>`:

| Kind     | Path                                | Mục đích                              |
| -------- | ----------------------------------- | ------------------------------------- |
| REST GET | `/api/sms-gateway/messages/pending` | Lấy danh sách SMS chờ gửi (claim).    |
| REST POST| `/api/sms-gateway/messages/report`  | Báo trạng thái `Sent` hoặc `Failed`.  |
| REST POST| `/api/sms-gateway/heartbeat`        | Báo thiết bị còn online (mỗi 1 phút). |
| **Hub**  | **`/hubs/sms-gateway`**             | **Realtime push từ backend tới app (mục 21).** |

App Flutter dùng **SignalR Hub làm primary channel** để biết khi nào có SMS mới
(latency < 1s); 3 REST còn lại vẫn dùng để claim, report, heartbeat. Khi Hub không
khả dụng (backend chưa expose hoặc mất kết nối), app **tự fallback** sang polling
REST như mô tả từ đầu tài liệu — không cần backend làm gì thêm.

Ngoài ra cần endpoint cho nội bộ:

| Method | Path             | Mục đích                       |
| ------ | ---------------- | ------------------------------ |
| POST   | `/api/sms/send`  | Queue 1 SMS (admin/service).   |

Chi tiết JSON, headers và status code mô tả ở mục 8, 9, và mục 21 (SignalR).

---

## 1. Sơ đồ thư mục đề xuất

Trong project backend `.NET` của bạn:

```text
src/
├── Domain/
│   ├── Entities/
│   │   ├── SmsMessage.cs
│   │   ├── SmsGatewayDevice.cs
│   │   └── SmsAuditLog.cs
│   └── Enums/
│       └── SmsStatus.cs
│
├── Application/
│   ├── Abstractions/
│   │   └── ISmsService.cs
│   ├── Services/
│   │   └── SmsService.cs
│   ├── Dto/
│   │   ├── QueueSmsRequest.cs
│   │   ├── SmsReportRequest.cs
│   │   ├── PendingSmsResponse.cs
│   │   └── HeartbeatRequest.cs
│   └── Validators/
│       └── PhoneNumberValidator.cs
│
├── Infrastructure/
│   ├── Persistence/
│   │   ├── AppDbContext.cs
│   │   └── Configurations/
│   │       ├── SmsMessageConfiguration.cs
│   │       ├── SmsGatewayDeviceConfiguration.cs
│   │       └── SmsAuditLogConfiguration.cs
│   └── Security/
│       ├── GatewayApiKeyHasher.cs
│       └── GatewayAuthenticationHandler.cs
│
└── Api/
    ├── Controllers/
    │   ├── SmsController.cs
    │   └── SmsGatewayController.cs
    ├── Hubs/                                  # 🆕 mục 21
    │   └── SmsGatewayHub.cs
    ├── Middlewares/
    │   └── GatewayRateLimitMiddleware.cs
    └── Program.cs (cập nhật DI + MapHub)
```

Tên namespace điều chỉnh theo project hiện tại (`YourApp.Domain.Entities`, …).

---

## 2. Enum `SmsStatus`

```csharp
namespace YourApp.Domain.Enums;

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
```

---

## 3. Entity `SmsMessage`

```csharp
using YourApp.Domain.Enums;

namespace YourApp.Domain.Entities;

public class SmsMessage
{
    public Guid Id { get; set; } = Guid.NewGuid();

    public string PhoneNumber { get; set; } = default!;
    public string Message     { get; set; } = default!;

    public SmsStatus Status { get; set; } = SmsStatus.Pending;

    public int RetryCount    { get; set; }
    public int MaxRetryCount { get; set; } = 3;

    public string? ErrorMessage { get; set; }

    /// Khoá để chỉ thiết bị này được tiếp tục report SMS đã claim.
    public string? GatewayDeviceCode { get; set; }
    public Guid?   GatewayDeviceId   { get; set; }

    public DateTime  CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? PickedAt  { get; set; }
    public DateTime? SentAt    { get; set; }
    public DateTime? FailedAt  { get; set; }

    /// Phân loại nguồn gửi (otp, transaction, marketing, …) để rate-limit riêng.
    public string? Category { get; set; }

    /// Optimistic concurrency để tránh 2 device cùng claim 1 row.
    public uint RowVersion { get; set; }
}
```

EF Core configuration:

```csharp
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using YourApp.Domain.Entities;

namespace YourApp.Infrastructure.Persistence.Configurations;

public class SmsMessageConfiguration : IEntityTypeConfiguration<SmsMessage>
{
    public void Configure(EntityTypeBuilder<SmsMessage> b)
    {
        b.ToTable("sms_messages");
        b.HasKey(x => x.Id);

        b.Property(x => x.PhoneNumber).HasMaxLength(20).IsRequired();
        b.Property(x => x.Message).HasMaxLength(1600).IsRequired();
        b.Property(x => x.Status).HasConversion<int>();
        b.Property(x => x.GatewayDeviceCode).HasMaxLength(64);
        b.Property(x => x.ErrorMessage).HasMaxLength(500);
        b.Property(x => x.Category).HasMaxLength(32);

        b.Property(x => x.RowVersion).IsRowVersion();

        b.HasIndex(x => new { x.Status, x.CreatedAt })
         .HasDatabaseName("ix_sms_messages_status_created");
        b.HasIndex(x => x.PhoneNumber);
    }
}
```

---

## 4. Entity `SmsGatewayDevice`

```csharp
namespace YourApp.Domain.Entities;

public class SmsGatewayDevice
{
    public Guid Id { get; set; } = Guid.NewGuid();

    /// Tên hiển thị trong admin UI.
    public string DeviceName { get; set; } = default!;

    /// Mã unique gửi kèm header `X-Device-Code`.
    public string DeviceCode { get; set; } = default!;

    /// HASH (BCrypt/Argon2/PBKDF2) của API key. **KHÔNG bao giờ lưu plain text.**
    public string ApiKeyHash { get; set; } = default!;

    public bool IsActive { get; set; } = true;

    public int DailyLimit { get; set; } = 100;
    public int SentToday  { get; set; }
    public DateOnly? SentTodayDate { get; set; }

    public DateTime CreatedAt   { get; set; } = DateTime.UtcNow;
    public DateTime? LastSeenAt { get; set; }
    public string?   LastSeenIp { get; set; }
}
```

Configuration:

```csharp
public class SmsGatewayDeviceConfiguration : IEntityTypeConfiguration<SmsGatewayDevice>
{
    public void Configure(EntityTypeBuilder<SmsGatewayDevice> b)
    {
        b.ToTable("sms_gateway_devices");
        b.HasKey(x => x.Id);

        b.Property(x => x.DeviceName).HasMaxLength(64).IsRequired();
        b.Property(x => x.DeviceCode).HasMaxLength(64).IsRequired();
        b.HasIndex(x => x.DeviceCode).IsUnique();

        b.Property(x => x.ApiKeyHash).HasMaxLength(256).IsRequired();
    }
}
```

---

## 5. Entity `SmsAuditLog` (tuỳ chọn nhưng nên có)

```csharp
namespace YourApp.Domain.Entities;

public class SmsAuditLog
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid SmsMessageId { get; set; }
    public string Event { get; set; } = default!; // Queued, Picked, Sent, Failed, Retry, Cancelled
    public string? DeviceCode { get; set; }
    public string? Detail { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}
```

---

## 6. DbContext

```csharp
using Microsoft.EntityFrameworkCore;
using YourApp.Domain.Entities;

namespace YourApp.Infrastructure.Persistence;

public class AppDbContext : DbContext
{
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) { }

    public DbSet<SmsMessage>        SmsMessages       => Set<SmsMessage>();
    public DbSet<SmsGatewayDevice>  SmsGatewayDevices => Set<SmsGatewayDevice>();
    public DbSet<SmsAuditLog>       SmsAuditLogs      => Set<SmsAuditLog>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);
        modelBuilder.ApplyConfigurationsFromAssembly(typeof(AppDbContext).Assembly);
    }
}
```

Migration:

```bash
dotnet ef migrations add Add_SmsGateway_Tables --project src/Infrastructure --startup-project src/Api
dotnet ef database update                       --project src/Infrastructure --startup-project src/Api
```

---

## 7. SmsService

### 7.1. Interface

```csharp
namespace YourApp.Application.Abstractions;

public interface ISmsService
{
    Task<Guid> QueueSmsAsync(
        string phoneNumber,
        string message,
        string? category = null,
        CancellationToken cancellationToken = default);

    Task<bool> CancelAsync(Guid smsId, CancellationToken cancellationToken = default);
}
```

### 7.2. Implementation

```csharp
using Microsoft.EntityFrameworkCore;
using YourApp.Application.Abstractions;
using YourApp.Application.Validators;
using YourApp.Domain.Entities;
using YourApp.Domain.Enums;
using YourApp.Infrastructure.Persistence;

namespace YourApp.Application.Services;

public class SmsService : ISmsService
{
    private readonly AppDbContext _db;
    private readonly ISmsGatewayNotifier _notifier; // mục 21 — null-safe nếu chưa làm SignalR

    public SmsService(AppDbContext db, ISmsGatewayNotifier notifier)
    {
        _db = db;
        _notifier = notifier;
    }

    public async Task<Guid> QueueSmsAsync(
        string phoneNumber,
        string message,
        string? category = null,
        CancellationToken cancellationToken = default)
    {
        var normalized = PhoneNumberValidator.NormalizeVn(phoneNumber)
            ?? throw new ArgumentException("Invalid phone number", nameof(phoneNumber));

        if (string.IsNullOrWhiteSpace(message))
            throw new ArgumentException("Message is required", nameof(message));
        if (message.Length > 1600)
            throw new ArgumentException("Message too long (max 1600 chars)", nameof(message));

        var sms = new SmsMessage
        {
            Id          = Guid.NewGuid(),
            PhoneNumber = normalized,
            Message     = message.Trim(),
            Status      = SmsStatus.Pending,
            Category    = category,
            CreatedAt   = DateTime.UtcNow
        };

        _db.SmsMessages.Add(sms);
        _db.SmsAuditLogs.Add(new SmsAuditLog
        {
            SmsMessageId = sms.Id,
            Event = "Queued",
            Detail = category
        });
        await _db.SaveChangesAsync(cancellationToken);

        // Push realtime tới gateway devices. Try/catch để Hub fail không phá API.
        // Nếu chưa làm mục 21, register `NullSmsGatewayNotifier` (xem mục 21.6).
        try
        {
            await _notifier.NotifyNewPendingSmsAsync(sms.Id, sms.PhoneNumber, ct: cancellationToken);
        }
        catch
        {
            // Polling REST sẽ là fallback — không throw.
        }

        return sms.Id;
    }

    public async Task<bool> CancelAsync(Guid smsId, CancellationToken ct = default)
    {
        var sms = await _db.SmsMessages.FirstOrDefaultAsync(x => x.Id == smsId, ct);
        if (sms is null) return false;
        if (sms.Status is SmsStatus.Sent or SmsStatus.Failed or SmsStatus.Cancelled) return false;

        sms.Status = SmsStatus.Cancelled;
        _db.SmsAuditLogs.Add(new SmsAuditLog
        {
            SmsMessageId = sms.Id,
            Event = "Cancelled"
        });
        await _db.SaveChangesAsync(ct);

        try
        {
            await _notifier.NotifyBatchRevokedAsync(new[] { smsId }, ct: ct);
        }
        catch { /* Hub fail không ảnh hưởng nghiệp vụ cancel */ }

        return true;
    }
}
```

> **Nếu chưa triển khai SignalR (mục 21)**, đăng ký impl rỗng trong `Program.cs` để
> code biên dịch:
>
> ```csharp
> public class NullSmsGatewayNotifier : ISmsGatewayNotifier
> {
>     public Task NotifyNewPendingSmsAsync(Guid id, string phone, string? code = null, CancellationToken ct = default)
>         => Task.CompletedTask;
>     public Task NotifyBatchRevokedAsync(IEnumerable<Guid> ids, string? code = null, CancellationToken ct = default)
>         => Task.CompletedTask;
> }
>
> builder.Services.AddSingleton<ISmsGatewayNotifier, NullSmsGatewayNotifier>();
> ```

### 7.3. Phone validator

```csharp
using System.Text.RegularExpressions;

namespace YourApp.Application.Validators;

public static class PhoneNumberValidator
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

---

## 8. SmsController (cho frontend/admin/service nội bộ gọi)

```csharp
using Microsoft.AspNetCore.Mvc;
using YourApp.Application.Abstractions;
using YourApp.Application.Dto;

namespace YourApp.Api.Controllers;

[ApiController]
[Route("api/sms")]
[Microsoft.AspNetCore.Authorization.Authorize] // dùng JWT/policy của project
public class SmsController : ControllerBase
{
    private readonly ISmsService _smsService;
    public SmsController(ISmsService smsService) => _smsService = smsService;

    [HttpPost("send")]
    public async Task<IActionResult> Send([FromBody] QueueSmsRequest req, CancellationToken ct)
    {
        try
        {
            var smsId = await _smsService.QueueSmsAsync(req.PhoneNumber, req.Message, req.Category, ct);
            return Ok(new { smsId, status = "Pending" });
        }
        catch (ArgumentException ex)
        {
            return BadRequest(new { error = ex.Message });
        }
    }

    [HttpPost("{smsId:guid}/cancel")]
    public async Task<IActionResult> Cancel(Guid smsId, CancellationToken ct)
    {
        var ok = await _smsService.CancelAsync(smsId, ct);
        return ok ? NoContent() : NotFound();
    }
}

public record QueueSmsRequest(string PhoneNumber, string Message, string? Category = null);
```

Request mẫu:

```http
POST /api/sms/send
Authorization: Bearer <jwt-internal>
Content-Type: application/json

{
  "phoneNumber": "0901234567",
  "message": "Ma OTP cua ban la 123456",
  "category": "otp"
}
```

Response:

```json
{ "smsId": "5d6e7fd6-8e56-4db2-9316-55fbf7e01234", "status": "Pending" }
```

---

## 9. SmsGatewayController (cho app Flutter Android gọi)

### 9.1. GET `/api/sms-gateway/messages/pending?limit=5`

Logic atomically claim `n` SMS:

- Lọc `Status = Pending` và (`PickedAt` null hoặc `PickedAt < UtcNow - 2 phút` để
  retry lại những SMS bị bỏ rơi).
- Đổi `Pending → Sending`, set `PickedAt`, `GatewayDeviceCode`, `GatewayDeviceId`.
- Dùng `RowVersion` để loại race khi nhiều device cùng poll.

### 9.2. POST `/api/sms-gateway/messages/report`

- `status=Sent` → set `Sent`, `SentAt`, clear `ErrorMessage`.
- `status=Failed` → `RetryCount++`. Nếu `< MaxRetryCount` → quay về `Pending`,
  nếu `>=` → `Failed` final + `FailedAt`.
- Chỉ chấp nhận report nếu `GatewayDeviceCode` khớp với device gọi → tránh
  device A báo nhầm SMS của device B.

### 9.3. POST `/api/sms-gateway/heartbeat`

- Cập nhật `LastSeenAt`, `LastSeenIp` cho device.

Code:

```csharp
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using YourApp.Application.Dto;
using YourApp.Domain.Entities;
using YourApp.Domain.Enums;
using YourApp.Infrastructure.Persistence;

namespace YourApp.Api.Controllers;

[ApiController]
[Route("api/sms-gateway")]
[Authorize(AuthenticationSchemes = "GatewayApiKey")] // schema riêng cho Android
public class SmsGatewayController : ControllerBase
{
    private readonly AppDbContext _db;
    private static readonly TimeSpan PickStaleAfter = TimeSpan.FromMinutes(2);

    public SmsGatewayController(AppDbContext db) => _db = db;

    private string DeviceCode =>
        User.FindFirst("device_code")?.Value
        ?? throw new InvalidOperationException("Missing device_code claim");

    private Guid DeviceId =>
        Guid.Parse(User.FindFirst("device_id")!.Value);

    [HttpGet("messages/pending")]
    public async Task<IActionResult> GetPending([FromQuery] int limit = 5, CancellationToken ct = default)
    {
        limit = Math.Clamp(limit, 1, 20);
        var now = DateTime.UtcNow;
        var staleBefore = now - PickStaleAfter;

        // Daily-limit guard
        var device = await _db.SmsGatewayDevices.FirstAsync(x => x.Id == DeviceId, ct);
        ResetDailyCounterIfNeeded(device, now);
        if (device.SentToday >= device.DailyLimit)
            return Ok(Array.Empty<PendingSmsResponse>()); // im lặng, không gửi nữa hôm nay

        var allowance = device.DailyLimit - device.SentToday;
        var take = Math.Min(limit, allowance);

        var messages = await _db.SmsMessages
            .Where(x =>
                (x.Status == SmsStatus.Pending) ||
                (x.Status == SmsStatus.Sending && x.PickedAt != null && x.PickedAt < staleBefore))
            .OrderBy(x => x.CreatedAt)
            .Take(take)
            .ToListAsync(ct);

        foreach (var m in messages)
        {
            m.Status            = SmsStatus.Sending;
            m.PickedAt          = now;
            m.GatewayDeviceCode = DeviceCode;
            m.GatewayDeviceId   = DeviceId;

            _db.SmsAuditLogs.Add(new SmsAuditLog
            {
                SmsMessageId = m.Id,
                Event        = "Picked",
                DeviceCode   = DeviceCode
            });
        }

        try
        {
            await _db.SaveChangesAsync(ct);
        }
        catch (DbUpdateConcurrencyException)
        {
            // Một thiết bị khác đã claim trước. Trả về rỗng cho lần này;
            // lần poll tiếp theo sẽ nhận batch khác.
            return Ok(Array.Empty<PendingSmsResponse>());
        }

        var response = messages.Select(m => new PendingSmsResponse(m.Id, m.PhoneNumber, m.Message));
        return Ok(response);
    }

    [HttpPost("messages/report")]
    public async Task<IActionResult> Report([FromBody] SmsReportRequest req, CancellationToken ct)
    {
        var sms = await _db.SmsMessages.FirstOrDefaultAsync(x => x.Id == req.SmsId, ct);
        if (sms is null) return NotFound();

        if (!string.Equals(sms.GatewayDeviceCode, DeviceCode, StringComparison.Ordinal))
            return Forbid(); // device này không phải bên đang giữ SMS

        var now = DateTime.UtcNow;
        switch (req.Status)
        {
            case "Sent":
                sms.Status       = SmsStatus.Sent;
                sms.SentAt       = now;
                sms.ErrorMessage = null;

                var device = await _db.SmsGatewayDevices.FirstAsync(x => x.Id == DeviceId, ct);
                ResetDailyCounterIfNeeded(device, now);
                device.SentToday++;

                _db.SmsAuditLogs.Add(new SmsAuditLog
                {
                    SmsMessageId = sms.Id, Event = "Sent", DeviceCode = DeviceCode
                });
                break;

            case "Failed":
                sms.RetryCount++;
                sms.ErrorMessage = req.ErrorMessage;
                if (sms.RetryCount < sms.MaxRetryCount)
                {
                    sms.Status            = SmsStatus.Pending;
                    sms.GatewayDeviceCode = null;
                    sms.GatewayDeviceId   = null;
                    sms.PickedAt          = null;
                    _db.SmsAuditLogs.Add(new SmsAuditLog
                    {
                        SmsMessageId = sms.Id, Event = "Retry",
                        DeviceCode = DeviceCode, Detail = req.ErrorMessage
                    });
                }
                else
                {
                    sms.Status   = SmsStatus.Failed;
                    sms.FailedAt = now;
                    _db.SmsAuditLogs.Add(new SmsAuditLog
                    {
                        SmsMessageId = sms.Id, Event = "Failed",
                        DeviceCode = DeviceCode, Detail = req.ErrorMessage
                    });
                }
                break;

            default:
                return BadRequest(new { error = "Invalid status" });
        }

        await _db.SaveChangesAsync(ct);
        return Ok();
    }

    [HttpPost("heartbeat")]
    public async Task<IActionResult> Heartbeat(CancellationToken ct)
    {
        var device = await _db.SmsGatewayDevices.FirstAsync(x => x.Id == DeviceId, ct);
        device.LastSeenAt = DateTime.UtcNow;
        device.LastSeenIp = HttpContext.Connection.RemoteIpAddress?.ToString();
        await _db.SaveChangesAsync(ct);
        return Ok();
    }

    private static void ResetDailyCounterIfNeeded(SmsGatewayDevice d, DateTime now)
    {
        var today = DateOnly.FromDateTime(now);
        if (d.SentTodayDate != today)
        {
            d.SentTodayDate = today;
            d.SentToday = 0;
        }
    }
}
```

### 9.4. DTOs

```csharp
namespace YourApp.Application.Dto;

public record PendingSmsResponse(Guid Id, string PhoneNumber, string Message);

public record SmsReportRequest(Guid SmsId, string Status, string? ErrorMessage);
```

---

## 10. Authentication cho Gateway API

App Flutter gửi 2 header:

```http
Authorization: Bearer <api-key-plaintext>
X-Device-Code: android-gateway-001
```

Backend không lưu `<api-key-plaintext>`, chỉ lưu `ApiKeyHash`. Khi nhận request:

1. Lấy `DeviceCode` từ header `X-Device-Code`.
2. Tìm device theo `DeviceCode`, check `IsActive`.
3. Lấy token từ `Authorization: Bearer …`, hash rồi so với `ApiKeyHash`.
4. Nếu khớp → tạo `ClaimsPrincipal` với claim `device_code` và `device_id`.

### 10.1. Hasher

```csharp
using System.Security.Cryptography;
using System.Text;

namespace YourApp.Infrastructure.Security;

public static class GatewayApiKeyHasher
{
    /// PBKDF2 với salt cố định + per-device salt (deviceCode). Đơn giản, không cần
    /// thêm cột salt riêng. Production có thể nâng cấp lên BCrypt/Argon2.
    public static string Hash(string apiKey, string deviceCode)
    {
        var salt = Encoding.UTF8.GetBytes($"sms-gateway::{deviceCode}");
        var derived = Rfc2898DeriveBytes.Pbkdf2(
            password: apiKey,
            salt: salt,
            iterations: 100_000,
            hashAlgorithm: HashAlgorithmName.SHA256,
            outputLength: 32);
        return Convert.ToBase64String(derived);
    }

    public static bool Verify(string apiKey, string deviceCode, string expectedHash)
    {
        var actual = Hash(apiKey, deviceCode);
        return CryptographicOperations.FixedTimeEquals(
            Convert.FromBase64String(actual),
            Convert.FromBase64String(expectedHash));
    }
}
```

### 10.2. Authentication handler

```csharp
using System.Security.Claims;
using System.Text.Encodings.Web;
using Microsoft.AspNetCore.Authentication;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using YourApp.Infrastructure.Persistence;

namespace YourApp.Infrastructure.Security;

public class GatewayAuthOptions : AuthenticationSchemeOptions { }

public class GatewayAuthenticationHandler : AuthenticationHandler<GatewayAuthOptions>
{
    private readonly AppDbContext _db;

    public GatewayAuthenticationHandler(
        IOptionsMonitor<GatewayAuthOptions> options,
        ILoggerFactory logger,
        UrlEncoder encoder,
        AppDbContext db) : base(options, logger, encoder)
    {
        _db = db;
    }

    protected override async Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        // Device code có thể đến từ header (REST) hoặc query (SignalR negotiate
        // qua WebSocket không gửi được custom header).
        var deviceCode = Request.Headers["X-Device-Code"].ToString();
        if (string.IsNullOrWhiteSpace(deviceCode))
            deviceCode = Request.Query["deviceCode"].ToString();
        if (string.IsNullOrWhiteSpace(deviceCode))
            return AuthenticateResult.Fail("Missing X-Device-Code / deviceCode");

        // Token có thể đến từ Authorization header (REST + SignalR HTTP
        // long-polling/SSE) hoặc query `access_token` (SignalR WebSocket).
        string apiKey;
        var auth = Request.Headers.Authorization.ToString();
        if (auth.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase))
        {
            apiKey = auth["Bearer ".Length..].Trim();
        }
        else
        {
            apiKey = Request.Query["access_token"].ToString();
            if (string.IsNullOrWhiteSpace(apiKey))
                return AuthenticateResult.Fail("Missing Bearer token / access_token");
        }

        var device = await _db.SmsGatewayDevices
            .AsNoTracking()
            .FirstOrDefaultAsync(x => x.DeviceCode == deviceCode && x.IsActive);
        if (device is null) return AuthenticateResult.Fail("Unknown device");

        if (!GatewayApiKeyHasher.Verify(apiKey, deviceCode, device.ApiKeyHash))
            return AuthenticateResult.Fail("Invalid api key");

        var claims = new[]
        {
            new Claim("device_code", device.DeviceCode),
            new Claim("device_id",   device.Id.ToString()),
            new Claim(ClaimTypes.NameIdentifier, device.Id.ToString()),
            new Claim(ClaimTypes.Name, device.DeviceName),
        };
        var identity = new ClaimsIdentity(claims, Scheme.Name);
        var principal = new ClaimsPrincipal(identity);
        return AuthenticateResult.Success(new AuthenticationTicket(principal, Scheme.Name));
    }
}
```

### 10.3. Đăng ký trong `Program.cs`

```csharp
builder.Services
    .AddAuthentication() // nếu project đã có JWT thì giữ nguyên, thêm scheme bên dưới
    .AddScheme<GatewayAuthOptions, GatewayAuthenticationHandler>("GatewayApiKey", _ => { });

builder.Services.AddAuthorization(options =>
{
    options.AddPolicy("GatewayDevice", p => p
        .AddAuthenticationSchemes("GatewayApiKey")
        .RequireAuthenticatedUser()
        .RequireClaim("device_code"));
});

builder.Services.AddScoped<ISmsService, SmsService>();
```

---

## 11. Tạo device + API key (admin)

Endpoint hoặc CLI script tự sinh API key dài ≥ 32 ký tự:

```csharp
public record CreateDeviceRequest(string DeviceName, string DeviceCode, int DailyLimit = 100);

[HttpPost("/api/admin/sms-gateway/devices")]
[Authorize(Roles = "Admin")]
public async Task<IActionResult> CreateDevice(
    [FromBody] CreateDeviceRequest req,
    [FromServices] AppDbContext db)
{
    var apiKey = Convert.ToBase64String(System.Security.Cryptography.RandomNumberGenerator.GetBytes(32));
    var device = new SmsGatewayDevice
    {
        DeviceName = req.DeviceName,
        DeviceCode = req.DeviceCode,
        ApiKeyHash = GatewayApiKeyHasher.Hash(apiKey, req.DeviceCode),
        DailyLimit = req.DailyLimit
    };
    db.SmsGatewayDevices.Add(device);
    await db.SaveChangesAsync();

    // Plain text apiKey **chỉ hiển thị một lần** cho admin copy.
    return Ok(new { device.Id, device.DeviceCode, apiKey });
}
```

Sau khi nhận `apiKey`, admin nhập vào màn hình *Settings* của app Flutter:
- Backend URL.
- Gateway token = `apiKey`.
- Device code = `DeviceCode`.

---

## 12. Rate limit

Đề xuất 3 tầng:

1. **Global per device** — built-in `RateLimiter`:

```csharp
using System.Threading.RateLimiting;

builder.Services.AddRateLimiter(o =>
{
    o.AddPolicy("gateway", httpContext =>
    {
        var deviceCode = httpContext.Request.Headers["X-Device-Code"].ToString();
        return RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: string.IsNullOrEmpty(deviceCode) ? "anon" : deviceCode,
            factory: _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 60,            // 60 request/phút/device
                Window      = TimeSpan.FromMinutes(1),
                QueueLimit  = 0
            });
    });

    o.RejectionStatusCode = 429;
});

app.UseRateLimiter();
```

Áp dụng cho controller:

```csharp
[EnableRateLimiting("gateway")]
public class SmsGatewayController : ControllerBase { … }
```

2. **OTP per phone** — bảng phụ hoặc Redis: `otp:<phone>` đếm trong 10 phút, max 3.
3. **Daily limit per device** — đã có trong logic `GetPending` (mục 9.3).

Đề xuất theo guide gốc:

```text
MVP/demo   : 5 SMS/phút
Nội bộ nhỏ: 30–50 SMS/ngày
OTP test  : 3 OTP/số/10 phút
```

---

## 13. Background job dọn rác (tuỳ chọn)

Hosted service quét mỗi 1 phút:

- SMS `Sending` mà `PickedAt < UtcNow - 5 phút` → revert về `Pending` để device khác claim.
- SMS `Failed` cũ hơn 30 ngày → xoá hoặc archive.

```csharp
public class StaleSmsReaper : BackgroundService
{
    private readonly IServiceScopeFactory _scopeFactory;
    public StaleSmsReaper(IServiceScopeFactory scopeFactory) => _scopeFactory = scopeFactory;

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            using var scope = _scopeFactory.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            var threshold = DateTime.UtcNow - TimeSpan.FromMinutes(5);
            var stale = await db.SmsMessages
                .Where(x => x.Status == SmsStatus.Sending && x.PickedAt < threshold)
                .ToListAsync(stoppingToken);
            foreach (var m in stale)
            {
                m.Status = SmsStatus.Pending;
                m.GatewayDeviceCode = null;
                m.GatewayDeviceId = null;
                m.PickedAt = null;
            }
            if (stale.Count > 0) await db.SaveChangesAsync(stoppingToken);
            await Task.Delay(TimeSpan.FromMinutes(1), stoppingToken);
        }
    }
}

// Program.cs
builder.Services.AddHostedService<StaleSmsReaper>();
```

---

## 14. Tích hợp với SmsService đang có (nếu project đã có sẵn)

Nếu repo backend của bạn đã có `SmsService` đang gọi nhà mạng/Twilio, có 2 cách phối hợp:

1. **Provider pattern**: tạo `ISmsProvider` với 2 impl:
   - `AndroidGatewayProvider` → chỉ queue vào DB (cho gateway này lấy).
   - `TwilioProvider` (fallback) → gửi qua Twilio nếu device offline > N phút.

   `SmsService.SendAsync()` chọn provider qua cấu hình hoặc `device.LastSeenAt`.

2. **Single queue + fallback worker**: tất cả đều queue vào `sms_messages`, một
   background worker (`SmsFallbackWorker`) check sau X phút thấy SMS vẫn `Pending`
   thì gọi provider khác.

Cá nhân khuyến nghị cách 1 cho rõ ràng.

---

## 15. Bảo mật bắt buộc (mục 24 của guide gốc)

| Checklist                                            | Cách làm                                                 |
| ---------------------------------------------------- | -------------------------------------------------------- |
| Gateway token riêng (không tái dùng JWT user)         | Scheme `GatewayApiKey` ở mục 10.                         |
| Hash token trong DB                                  | `GatewayApiKeyHasher` (PBKDF2).                          |
| Rate limit phút/ngày                                 | Mục 12 + daily counter mục 9.                            |
| Daily limit / device                                  | `SmsGatewayDevice.DailyLimit`.                           |
| Audit log mọi SMS                                    | Bảng `sms_audit_logs`.                                   |
| Validate số điện thoại                               | `PhoneNumberValidator`.                                  |
| Chỉ cho phép range nhà mạng/quốc gia (tuỳ business) | Thêm whitelist regex trong `SmsService.QueueSmsAsync`.   |
| HTTPS                                                | Bắt buộc reverse proxy (nginx/Caddy) trước Kestrel.      |
| Disable device                                       | Set `IsActive = false`; handler từ chối ngay.            |
| Không log plaintext OTP                               | OTP nên lưu hash riêng; bảng `sms_messages` chỉ phục vụ delivery. |

---

## 16. OTP riêng (mục 4.2 guide gốc)

OTP **không nên** chỉ phụ thuộc bảng `sms_messages`. Tách bảng:

```csharp
public class OtpRequest
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string PhoneNumber { get; set; } = default!;
    public string CodeHash { get; set; } = default!;   // SHA256(code + salt)
    public DateTime ExpiresAt { get; set; }
    public int Attempts { get; set; }
    public bool Consumed { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}
```

Flow:

```text
POST /api/otp/request  -> tạo OtpRequest, queue SmsMessage chứa code, trả otpId.
POST /api/otp/verify   -> hash code nhập, so với CodeHash, đánh dấu Consumed.
```

Rate limit: 3 request/số/10 phút, 5 lần verify sai → block.

---

## 17. Checklist triển khai

Backend `.NET`:

- [ ] Tạo `SmsStatus`.
- [ ] Tạo `SmsMessage`, `SmsGatewayDevice`, `SmsAuditLog` + EF configs.
- [ ] Migration `Add_SmsGateway_Tables`.
- [ ] Tạo `ISmsService` + `SmsService.QueueSmsAsync` + `CancelAsync`.
- [ ] `SmsController` với `POST /api/sms/send` (yêu cầu auth nội bộ).
- [ ] `SmsGatewayController` với 3 endpoint (`pending`, `report`, `heartbeat`).
- [ ] `GatewayAuthenticationHandler` + scheme `GatewayApiKey` (đọc token từ header **VÀ** query `access_token` cho SignalR).
- [ ] `GatewayApiKeyHasher` (PBKDF2).
- [ ] Endpoint admin `POST /api/admin/sms-gateway/devices` để cấp device.
- [ ] `RateLimiter` `gateway`.
- [ ] `StaleSmsReaper` hosted service.
- [ ] **SignalR Realtime Hub (mục 21)**: cài package, tạo `SmsGatewayHub`, map `/hubs/sms-gateway`, đăng ký `ISmsGatewayNotifier`, gọi `NotifyNewPendingSms` sau `SmsService.QueueSmsAsync`. **Đây là điểm nâng cấp quan trọng nhất** giảm latency từ ~5s xuống <1s.
- [ ] Reverse proxy support WebSocket upgrade (nginx/Caddy/Cloudflare).
- [ ] Bật HTTPS.
- [ ] Test end-to-end với app Flutter `sms_gateway_app`.

---

## 18. Test end-to-end nhanh

1. Build backend, chạy `dotnet ef database update`.
2. Tạo device:
   ```bash
   curl -X POST https://localhost:5001/api/admin/sms-gateway/devices \
        -H "Authorization: Bearer <admin-jwt>" \
        -H "Content-Type: application/json" \
        -d '{"deviceName":"Phone A","deviceCode":"android-gateway-001"}'
   # Copy "apiKey" trả về.
   ```
3. Mở app Flutter trên máy Android cùng LAN, vào **Settings**:
   - Backend URL: `https://<máy-bạn>:5001`
   - Gateway token: `<apiKey>` vừa copy
   - Device code: `android-gateway-001`
   - Polling interval: `10`
4. Bấm **Start gateway**, cấp quyền SMS + notification.
5. Queue 1 SMS thử:
   ```bash
   curl -X POST https://localhost:5001/api/sms/send \
        -H "Authorization: Bearer <internal-jwt>" \
        -H "Content-Type: application/json" \
        -d '{"phoneNumber":"0901234567","message":"Test from .NET backend"}'
   ```
6. Trong vòng < 10 giây, app Android phải gửi SMS bằng SIM. Logs trong app sẽ
   hiển thị `Fetched 1 pending SMS` → `Sending SMS to +84901234567` → `Sent SMS id=…`.
7. Trong DB, row `sms_messages` chuyển `Pending → Sending → Sent`, `SentAt` được set.

---

## 19. Lưu ý khi gắn vào project backend hiện có

- Đổi tên namespace cho khớp.
- Nếu project dùng MediatR/CQRS, đóng gói `SmsService.QueueSmsAsync` thành
  `QueueSmsCommand` + handler.
- Nếu đã có `DbContext` khác, copy 3 entity vào assembly Infrastructure tương ứng
  và `ApplyConfigurationsFromAssembly`.
- Nếu đã có scheme JWT, thêm scheme `GatewayApiKey` **song song**; controller
  gateway chỉ định `[Authorize(AuthenticationSchemes = "GatewayApiKey")]` để
  không xung đột.
- Nếu deploy nhiều instance, đảm bảo claim SMS dùng `RowVersion`
  (đã có trong cấu hình) hoặc bọc trong transaction `SERIALIZABLE`.

---

## 20. Tham chiếu nhanh các endpoint app Flutter đang gọi

Trong code Flutter ở repo này (`lib/core/constants/api_constants.dart`):

```dart
class ApiConstants {
  static const String pendingMessagesPath = '/api/sms-gateway/messages/pending';
  static const String reportPath          = '/api/sms-gateway/messages/report';
  static const String heartbeatPath       = '/api/sms-gateway/heartbeat';
  static const String hubPath             = '/hubs/sms-gateway';  // 🆕 SignalR
}
```

Và headers gửi đi (`lib/core/network/api_client.dart`):

```dart
headers: {
  'Authorization': 'Bearer $gatewayToken',
  'X-Device-Code': deviceCode,
  'Content-Type': 'application/json',
  'Accept': 'application/json',
}
```

SignalR negotiate URL: `{backendUrl}/hubs/sms-gateway?deviceCode={code}` với token đi
qua `access_token` query string khi handshake WebSocket (mục 21).

→ **Backend phải khớp đúng path + 2 header này** thì app Flutter không cần thay đổi.

---

## 21. SignalR Realtime Hub (NÂNG CẤP TỪ POLLING SANG PUSH)

> Đây là phần **bắt buộc** nếu bạn muốn latency gửi SMS đến khách < 1 giây.
> Nếu chưa làm phần này, app vẫn chạy nhưng dùng polling 10s như mô tả ở mục 9
> (latency trung bình ~5s).

### 21.0. Tổng quan kiến trúc

```text
.NET Backend                                      Flutter Android (sms_gateway_app)
─────────────                                     ───────────────────────────────
SmsService.QueueSmsAsync(phone, msg, ct)
        ↓ (1) save sms_messages = Pending
        ↓ (2) ISmsGatewayNotifier.NotifyNewPendingSms(...)
        ↓                                          ⚡ WebSocket connection (luôn mở)
SmsGatewayHub.Clients
    .Group("device:android-gateway-001")
    .SendAsync("NewPendingSms", payload)  ────▶  HubConnection.on("NewPendingSms",
                                                                   handler)
                                                       ↓ < 200ms latency
                                                  processPendingMessages()
                                                       ↓
                                                  GET /pending → REST như cũ
                                                       ↓
                                                  Send SMS via SIM
                                                       ↓
                                                  POST /report
```

App Flutter:
- Kết nối Hub **một lần** khi `Start gateway`.
- Đặt handler cho event `NewPendingSms` → gọi luôn `GET /pending` (REST cũ).
- Vẫn giữ Timer polling 60s như **safety net** (đề phòng Hub bị mất kết nối ngắn).
- Nếu Hub không khả dụng (backend cũ chưa expose) → log warning và rơi xuống
  polling-only ở interval cấu hình (mặc định 10s). Không crash.

### 21.1. Package NuGet

`Microsoft.AspNetCore.SignalR` đã có sẵn trong ASP.NET Core, không cần install
thêm. Nếu muốn dùng **MessagePack** thay JSON (nhanh hơn ~30%, payload nhỏ hơn):

```bash
dotnet add package Microsoft.AspNetCore.SignalR.Protocols.MessagePack
```

App Flutter đã hỗ trợ cả 2 protocol; default dùng JSON nên không cần MessagePack.

### 21.2. Hub class

```csharp
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using YourApp.Infrastructure.Persistence;

namespace YourApp.Api.Hubs;

/// <summary>
/// SignalR Hub cho gateway. Mỗi điện thoại Android giữ 1 WebSocket connection
/// vào Hub này. Backend push event "NewPendingSms" khi có SMS mới được queue
/// cho device đó (hoặc broadcast tới group "gateway:all" nếu chưa assign).
/// </summary>
[Authorize(AuthenticationSchemes = "GatewayApiKey")]
public class SmsGatewayHub : Hub
{
    private readonly AppDbContext _db;
    private readonly ILogger<SmsGatewayHub> _logger;

    public SmsGatewayHub(AppDbContext db, ILogger<SmsGatewayHub> logger)
    {
        _db = db;
        _logger = logger;
    }

    public static string DeviceGroup(string code) => $"device:{code}";
    public const string AllDevicesGroup = "gateway:all";

    public override async Task OnConnectedAsync()
    {
        var deviceCode = Context.User?.FindFirst("device_code")?.Value;
        if (string.IsNullOrEmpty(deviceCode))
        {
            Context.Abort();
            return;
        }

        await Groups.AddToGroupAsync(Context.ConnectionId, DeviceGroup(deviceCode));
        await Groups.AddToGroupAsync(Context.ConnectionId, AllDevicesGroup);

        // Cập nhật LastSeenAt để admin biết device đang online.
        var deviceIdStr = Context.User?.FindFirst("device_id")?.Value;
        if (Guid.TryParse(deviceIdStr, out var deviceId))
        {
            var device = await _db.SmsGatewayDevices.FirstOrDefaultAsync(x => x.Id == deviceId);
            if (device != null)
            {
                device.LastSeenAt = DateTime.UtcNow;
                device.LastSeenIp = Context.GetHttpContext()?.Connection.RemoteIpAddress?.ToString();
                await _db.SaveChangesAsync();
            }
        }

        _logger.LogInformation("Gateway device connected: {DeviceCode} ({ConnectionId})",
            deviceCode, Context.ConnectionId);

        await base.OnConnectedAsync();
    }

    public override async Task OnDisconnectedAsync(Exception? exception)
    {
        var deviceCode = Context.User?.FindFirst("device_code")?.Value;
        _logger.LogInformation("Gateway device disconnected: {DeviceCode} ({ConnectionId}). Reason: {Reason}",
            deviceCode, Context.ConnectionId, exception?.Message ?? "client close");
        await base.OnDisconnectedAsync(exception);
    }

    /// <summary>
    /// Client (app Flutter) có thể gọi để giữ kết nối sống nếu cần (SignalR đã
    /// auto-ping nhưng method này hữu ích để app log "đã nói chuyện được với hub").
    /// </summary>
    public Task<string> Ping() => Task.FromResult("pong");
}
```

### 21.3. Notifier service (gọi từ SmsService)

Tách interface để `SmsService` không phụ thuộc trực tiếp vào `IHubContext`:

```csharp
namespace YourApp.Application.Abstractions;

public interface ISmsGatewayNotifier
{
    Task NotifyNewPendingSmsAsync(Guid smsId, string phoneNumber, string? targetDeviceCode = null, CancellationToken ct = default);
    Task NotifyBatchRevokedAsync(IEnumerable<Guid> smsIds, string? targetDeviceCode = null, CancellationToken ct = default);
}
```

Implementation:

```csharp
using Microsoft.AspNetCore.SignalR;
using YourApp.Application.Abstractions;
using YourApp.Api.Hubs;

namespace YourApp.Infrastructure.Realtime;

public class SignalRSmsGatewayNotifier : ISmsGatewayNotifier
{
    private readonly IHubContext<SmsGatewayHub> _hub;
    public SignalRSmsGatewayNotifier(IHubContext<SmsGatewayHub> hub) => _hub = hub;

    public Task NotifyNewPendingSmsAsync(
        Guid smsId, string phoneNumber, string? targetDeviceCode = null, CancellationToken ct = default)
    {
        // Payload nhỏ — app chỉ cần biết "có SMS mới" để chủ động GET /pending.
        // Không gửi cả message body qua Hub để tránh expose nội dung SMS qua
        // WebSocket nhiều hơn mức cần thiết, và để SmsGatewayController.GetPending
        // remain authoritative cho claim logic.
        var payload = new { smsId, phoneNumber, ts = DateTimeOffset.UtcNow };

        return targetDeviceCode is null
            ? _hub.Clients.Group(SmsGatewayHub.AllDevicesGroup).SendAsync("NewPendingSms", payload, ct)
            : _hub.Clients.Group(SmsGatewayHub.DeviceGroup(targetDeviceCode))
                          .SendAsync("NewPendingSms", payload, ct);
    }

    public Task NotifyBatchRevokedAsync(
        IEnumerable<Guid> smsIds, string? targetDeviceCode = null, CancellationToken ct = default)
    {
        var payload = new { smsIds = smsIds.ToArray(), ts = DateTimeOffset.UtcNow };
        return targetDeviceCode is null
            ? _hub.Clients.Group(SmsGatewayHub.AllDevicesGroup).SendAsync("BatchRevoked", payload, ct)
            : _hub.Clients.Group(SmsGatewayHub.DeviceGroup(targetDeviceCode))
                          .SendAsync("BatchRevoked", payload, ct);
    }
}
```

### 21.4. Inject vào SmsService

**Đã có sẵn ở mục 7.2** — `SmsService` đã inject `ISmsGatewayNotifier` và gọi
`NotifyNewPendingSmsAsync` sau `SaveChangesAsync`. Nếu bạn copy theo mục 7.2 thì
không cần thêm gì ở đây.

### 21.5. Cancel cũng đã notify ở mục 7.2

`CancelAsync` đã gọi `NotifyBatchRevokedAsync` (bao trong try/catch). App
Flutter nhận event `BatchRevoked` qua `SmsGatewayRealtimeDatasource` và log
warning "Batch revoked by backend".

### 21.6. Đăng ký trong `Program.cs`

```csharp
// SignalR
builder.Services.AddSignalR(options =>
{
    options.EnableDetailedErrors = builder.Environment.IsDevelopment();
    options.KeepAliveInterval = TimeSpan.FromSeconds(15);   // server ping client mỗi 15s
    options.ClientTimeoutInterval = TimeSpan.FromSeconds(60);
})
// Optional: MessagePack
// .AddMessagePackProtocol()
;

// Notifier
builder.Services.AddSingleton<ISmsGatewayNotifier, SignalRSmsGatewayNotifier>();

// ... existing services ...

var app = builder.Build();

// ... existing middleware ...

app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();

// 👇 Map Hub TRƯỚC khi app.Run()
app.MapHub<SmsGatewayHub>("/hubs/sms-gateway");

app.Run();
```

> ⚠️ **Thứ tự middleware**: `UseAuthentication` + `UseAuthorization` PHẢI nằm trước
> cả `MapControllers` và `MapHub`. Nếu project có CORS, đặt `UseCors` sau
> `UseRouting` (nếu dùng) và trước Authentication. SignalR Hub thừa hưởng cùng
> middleware pipeline với Controllers — không cần config riêng.

### 21.7. Reverse proxy (nginx) — bắt buộc cho WebSocket

Nếu chạy backend sau nginx, phải bật WebSocket upgrade:

```nginx
location /hubs/ {
    proxy_pass http://backend_upstream;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    # WebSocket idle timeout phải > KeepAliveInterval
    proxy_read_timeout 600s;
    proxy_send_timeout 600s;
}

location /api/ {
    proxy_pass http://backend_upstream;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
}
```

Cloudflare: bật WebSocket trong **Network** settings (mặc định đã bật). Free
plan giới hạn 100 concurrent WebSocket — đủ cho gateway nội bộ.

### 21.8. Authentication qua query string (đã có ở mục 10.2)

SignalR khi handshake WebSocket **không thể gửi `Authorization` header**, nên
nó tự động chuyển token vào query `?access_token=…`. `GatewayAuthenticationHandler`
đã được cập nhật ở mục 10.2 để đọc cả `access_token` query và `deviceCode` query.

Khi SignalR negotiate trên HTTP long-polling/SSE thì vẫn dùng header bình thường —
handler hỗ trợ cả 2.

### 21.9. Targeting device (chọn device nào nhận event)

Cách đơn giản nhất: **broadcast tới group `gateway:all`** — tất cả device cùng
nhận event và đua claim qua `GET /pending`. EF `RowVersion` đảm bảo chỉ 1 device
claim được mỗi SMS, các device khác nhận response rỗng.

Khi muốn route theo device cụ thể (vd: SMS có category "premium" → device A,
"bulk" → device B), pass `targetDeviceCode` vào `NotifyNewPendingSmsAsync`.

### 21.10. Test SignalR bằng curl/postman

```bash
# 1. Negotiate trước
curl -X POST "https://localhost:5001/hubs/sms-gateway/negotiate?negotiateVersion=1&deviceCode=android-gateway-001" \
     -H "Authorization: Bearer <api-key>"

# Response chứa connectionToken — copy.
```

Sau đó test bằng JS console:

```js
const conn = new signalR.HubConnectionBuilder()
  .withUrl("https://localhost:5001/hubs/sms-gateway?deviceCode=android-gateway-001", {
    accessTokenFactory: () => "<api-key>"
  })
  .build();
conn.on("NewPendingSms", (p) => console.log("New SMS:", p));
await conn.start();
```

Sau đó queue SMS → console phải in `New SMS: {...}` trong < 1s.

### 21.11. Performance & scale

- 1 device giữ 1 WebSocket connection. Kestrel xử lý vài chục nghìn connection/host.
- Nếu deploy nhiều instance backend, dùng **SignalR Redis backplane** để event
  broadcast cross-instance:

  ```bash
  dotnet add package Microsoft.AspNetCore.SignalR.StackExchangeRedis
  ```

  ```csharp
  builder.Services.AddSignalR().AddStackExchangeRedis("localhost:6379");
  ```

- Heartbeat REST `/api/sms-gateway/heartbeat` vẫn nên giữ — phòng khi SignalR
  connection alive nhưng device thật sự không gửi được SMS (SIM mất tín hiệu).
  Heartbeat 1 phút/lần.

### 21.12. Monitoring & troubleshooting

| Triệu chứng                                         | Cách kiểm tra                                                                                        |
| --------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| App log "Realtime unavailable" ngay khi Start       | Backend chưa map Hub, sai path, hoặc nginx chưa proxy WebSocket. Test bằng curl `/negotiate`.       |
| App log "Realtime reconnecting" liên tục            | KeepAlive timeout không khớp giữa client (signalr_netcore default 30s) và nginx `proxy_read_timeout`. Tăng nginx ≥ 600s. |
| Queue SMS xong app không phản ứng < 1s              | `SmsService` quên gọi `_notifier.NotifyNewPendingSmsAsync`, hoặc device nằm trong group khác.       |
| Authentication fail trên WebSocket nhưng REST OK    | `GatewayAuthenticationHandler` chưa đọc `access_token` query (mục 10.2).                            |
| Nhiều device nhận cùng 1 SMS                        | Đúng theo design — chỉ device claim được mới gửi. Check log `RowVersion` concurrency.               |

### 21.13. Tóm tắt diff backend

| File                                            | Hành động                                                          |
| ----------------------------------------------- | ------------------------------------------------------------------ |
| `Application/Abstractions/ISmsGatewayNotifier.cs` | Tạo mới                                                            |
| `Infrastructure/Realtime/SignalRSmsGatewayNotifier.cs` | Tạo mới                                                            |
| `Api/Hubs/SmsGatewayHub.cs`                     | Tạo mới                                                            |
| `Application/Services/SmsService.cs`            | Inject `ISmsGatewayNotifier`, gọi `NotifyNewPendingSmsAsync` sau save |
| `Infrastructure/Security/GatewayAuthenticationHandler.cs` | Cập nhật `HandleAuthenticateAsync` đọc query (đã có ở mục 10.2)    |
| `Api/Program.cs`                                | `AddSignalR()`, `AddSingleton<ISmsGatewayNotifier, ...>()`, `MapHub<>`  |
| `nginx.conf` (nếu có)                           | Thêm WebSocket upgrade headers cho `/hubs/`                        |

Sau khi triển khai xong mục 21, app Flutter **không cần thay đổi gì** — code đã sẵn
sàng (`SmsGatewayRealtimeDatasource` tự connect, tự fallback). Mở app, bấm Start
gateway, hero header sẽ hiện chip **REALTIME** màu xanh thay vì **POLL 10s**.
