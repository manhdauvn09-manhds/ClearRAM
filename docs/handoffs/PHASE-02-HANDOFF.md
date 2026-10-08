# Handoff — Phase 02 · Nền tảng PowerShell

- Ngày: 2026-10-08 (Asia/Tokyo). Người thực hiện: Codex.
- Trạng thái: Hoàn tất foundation cho bản thử nghiệm.
- Task: BASE-01, BASE-02, BASE-03, HO-02.
- Revision: 2026-10-08.1. Không tạo commit.

## 1. Mục tiêu và phạm vi

Thay solution .NET/Avalonia dự kiến bằng bộ script PowerShell + WPF theo quyết định phase 01. GUI/CLI dùng chung module; adapter Win32 nằm trong Native.cs. Không tải/cài SDK hoặc package bên ngoài.

## 2. Kết quả

| Task | Kết quả / bằng chứng |
|---|---|
| BASE-01 | app/ module, GUI/CLI/launcher, tests/ và .github/workflows/verify.yml; kiểm thử local đã chạy |
| BASE-02 | Identity/Snapshot/Row/ActionResult và quy tắc capability mô tả trong docs/ARCHITECTURE.md; Native.cs xác minh handle/start time |
| BASE-03 | settings schema 1, fallback khi lỗi, ghi file tạm và thay nguồn; activity.json giới hạn 200 event; kiểm thử round-trip và bounded log đạt |
| HO-02 | Tài liệu này |

## 3. File thay đổi / điểm vào

- `app/MemoryClear.Core.psm1`: module chung.
- `app/Native.cs`: Win32 + GuardedProcess/Dispose.
- `MemoryClear.ps1`, `app/MainWindow.xaml`: WPF và worker runspace.
- `MemoryClear.Cli.ps1`, `Start-MemoryClear.cmd`: entry points.
- `tests/Run-Tests.ps1`, `tests/Measure-Monitor.ps1`: kiểm chứng và đo.
- `README.md`, `.gitignore`, CI workflow: vận hành và kiểm tra nguồn.

## 4. Cách chạy và kết quả kiểm tra

```text
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File MemoryClear.ps1 -SmokeTest
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/Run-Tests.ps1 -Integration
```

Smoke WPF đạt (19 control), có kiểm tra worker nền, giữ sort và selection khi refresh. Integration đạt **17/17** trên Windows PowerShell 5.1.26100.8875; báo cáo ở `artifacts/tests/results.json`. Tests chỉ tạo/kill fixture riêng, không tác động app của người dùng. Logger đã sửa hành vi mảng JSON trên PS5.1; regression 205 event chỉ giữ 200 event mới nhất. Row dùng lớp CLR với nullable numeric properties để WPF sort ổn định. Settings lỗi chặn hành động đến khi sửa, tránh mất hiệu lực protection cá nhân.

CI workflow mới được viết nhưng **chưa chạy trên GitHub**. Không có claim build trên các Windows khác. `ExecutionPolicy Bypass` chỉ áp dụng process launcher, không thay policy của máy.

## 5. Contract quan trọng

Process identity là PID + UTC StartTicks + SID/session/path/critical. Không đủ quyền => unknown => chặn. CPU mẫu đầu null. RAM MB=working set, Private MB là private allocation. ActionResult phân biệt Requested/Exited/NoWindow/Denied/Pending; close request không đồng nghĩa process đã thoát. Snapshot chỉ giữ một mẫu trước và cache ngắn, không lịch sử vô hạn.

## 6. Tồn tại / rủi ro

- Chưa nghiệm thu nhiều GUI/CLI instance cùng ghi config/log.
- CLI chưa kiểm tra hết help/exit-code/dry-run trên mọi môi trường.
- Graceful close thực với cửa sổ hiển thị và dữ liệu chưa lưu chưa test; fixture chạy hidden xác minh NoWindow và không tự kill.
- Các thao tác GUI/khẩn cấp đã có code trong bản preview để nối luồng, nhưng các phase nghiệm thu sau chưa được coi là hoàn tất.

## 7. Tiếp nhận

Tiếp tục phase 03: kiểm tra tương tác GUI, keyboard/DPI, số liệu theo tải và overhead toàn GUI. Đọc `PHASE-03-HANDOFF.md` nháp. Source nội bộ action không phải bằng chứng hoàn tất SAFE/ACT/EMG; tiếp tục theo task/gate trong kế hoạch. Giữ manual và block ưu tiên allowlist.

## 8. Checklist

- [x] Foundation và contract có source/documentation.
- [x] Settings/log fallback và giới hạn được kiểm thử.
- [x] Lệnh/kết quả/giới hạn được ghi đúng.
- [x] Task/evidence và HO-02 được cập nhật.
- [x] Có link handoff trong phản hồi cuối.
