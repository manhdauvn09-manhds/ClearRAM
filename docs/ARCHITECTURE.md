# Kiến trúc bản PowerShell

Ngày: 2026-10-08. Người dùng đã chọn **PowerShell có GUI trước**. C# + Avalonia và Linux là hướng mở rộng, không phải dependency của bản hiện tại.

## Thành phần

- `Start-MemoryClear.cmd`: launcher Windows PowerShell 5.1, STA, execution policy trong process hiện tại.
- `MemoryClear.ps1` + `app/MainWindow.xaml`: WPF UI, dispatcher timer, hàng đợi thao tác có xác nhận, quét bất đồng bộ bằng runspace pool một worker.
- `app/MemoryClear.Core.psm1`: thu thập số liệu, cấu hình, policy, hành động và audit dùng chung GUI/CLI.
- `app/MemoryClear.Clear.psm1`: planner và executor Clear một chạm, chỉ trim working set, dùng policy bảo vệ của Core. `app/clear-policy.json` là cấu hình product_runtime và có JSON Schema riêng, không đọc `.harness`.
- `app/Native.cs`: adapter Win32 biên dịch tại chỗ bằng Add-Type; không cần .NET SDK. Handle query/terminate giới hạn theo thao tác; Dispose đóng handle.
- `MemoryClear.Cli.ps1`: list/inspect, dry-run close/kill, xác nhận tương tác khi Execute.

## Contract

**Identity:** Pid, StartTicks (UTC .NET ticks), Path, Sid, Session, Critical, Known, Error. Identity thiếu thông tin không được phép thao tác.

**Snapshot:** System (total/available/commit bytes và system times), Cpu (null ở mẫu đầu), Rows, Samples (CPU theo identity), Metadata, Context, ContextTimestamp, Settings, Timestamp. History chỉ giữ mẫu trước, cache được thay mới theo inventory để không tăng vô hạn.

**Row:** lớp CLR `MemoryClear.ProcessRow` với property Name, Pid, StartTicks, Path, RamMB, PrivateMB, Cpu, Allowed, AllowClose, Policy, Identity. Các số đo là nullable double để WPF sort thống nhất, tránh comparer lỗi với wrapper PSObject. Không gộp process thành app nếu chưa có cơ sở; không nhận diện tab browser.

**Action:** ProcessId + StartTicks + Close/Kill. **Result:** Timestamp, Pid, StartTicks, Action, Status, Message, AvailableBefore/After. Status gồm Denied, Cancelled, Requested, NoWindow, Exited, Pending. Requested không có nghĩa đã thoát.

## Quy tắc và thứ tự thực thi

1. GUI xác nhận danh sách cụ thể; CLI mặc định dry-run và xác nhận khi Execute.
2. Executor lấy handle, xác minh start time và trạng thái process.
3. Kiểm tra critical, user/session, service, Windows directory, host và ProtectedPaths. Service inventory lỗi thì chặn.
4. Kiểm tra lại policy sau thời gian chờ xác nhận; chỉ thao tác đúng handle/identity. Không kill descendant.
5. Close gửi WM_CLOSE tới main window; không có window thì NoWindow. Kill dùng TerminateProcess trên handle đã xác minh và xác nhận exit nếu quan sát được trong thời hạn.
6. Ghi kết quả; available RAM toàn máy chỉ là biến động quan sát, không phải lượng RAM chắc chắn thu hồi.

Snapshot cache service/identity tối đa khoảng 15 giây cho quan sát. **Mọi hành động phải đọc lại service/protection**, không dùng cache UI làm quyền thực thi. Quy tắc block thắng allowlist. Không có helper admin, force kill tự động, cache purge hoặc suspend trong bản này.

## Clear một chạm (yêu cầu bổ sung 2026-10-08)

Clear không dùng lựa chọn trong bảng và không coi nhàn rỗi là “chắc chắn không cần”. Worker lấy ba snapshot để có hai delta CPU; chọn cùng PID/start time, policy Allowed, CPU đã biết ≤0.1% toàn máy ở cả hai delta và working set ≥64 MB. Loại các PID/executable của host, foreground hiện tại và app foreground gần nhất UI quan sát trước đó; không đóng cửa sổ hay kết thúc process.

Trước mỗi trim, `AcquireForTrim` mở handle chỉ QUERY_LIMITED_INFORMATION + SYNCHRONIZE + SET_QUOTA, xác minh identity/running và đọc lại policy/service/config. Lấy thêm CPU probe 150 ms và kiểm tra foreground ngay trước API. Handle trim chặn cả CloseWindow và Kill. Gọi `EmptyWorkingSet` trên handle; ghi kết quả API và available RAM toàn máy trước/sau, không coi số liệu biến động là số RAM riêng chắc chắn đã giải phóng.

Một worker đảm bảo Clear không chạy cùng Close/Kill hoặc Scan. Bấm khi đang scan sẽ xếp yêu cầu Clear ngay sau scan; UI vẫn phản hồi và cho hủy. Cancellation token ngăn thao tác chưa gửi; không hoàn tác trim đã gửi. Giới hạn mặc định 12 process, ngân sách 30 giây kiểm tra giữa bước (không deadline cứng khi CIM đang chạy), cooldown 60 giây theo đồng hồ monotonic trong worker, dừng ở 20% RAM khả dụng. Settings/policy lỗi hoặc thiếu quyền sẽ bỏ qua/chặn, không tự nâng admin. Giới hạn reset khi mở lại app; nhiều instance chưa được nghiệm thu đồng thời.

Working set có thể nạp lại và tăng page faults khi dùng app. Trim không decommit, không chữa commit exhaustion. Nút Clear không có đường gọi Close/Kill; đóng khẩn cấp bằng danh sách cấp quyền là luồng khác có xác nhận. CLI hiện chưa có lệnh Clear.

### Tiến trình và profile Strong (bổ sung 2026-10-08)

GUI tạo một `ConcurrentQueue<object>` cho mỗi lượt và truyền tham chiếu vào worker. Module đẩy sự kiện immutable Stage/Message/Processed/Total; DispatcherTimer hút queue mỗi 250 ms **trước** nhánh chờ async hoàn thành. Worker không truy cập WPF. Chờ scan/lấy mẫu dùng indeterminate; sau planner là count thực, tăng cả khi target bị skip. Đồng hồ GUI chạy liên tục và gồm thời gian chờ. Chỉ trạng thái kết thúc bình thường làm đầy thanh; Error/Cancelled/TimeLimit/Cooldown dừng animation và ghi đúng lý do. Kết quả giữ tới lượt tiếp theo, gồm thời điểm hoàn tất/thời lượng/mode và message RAM trước/sau. Không ước lượng ETA hoặc gọi phần trăm process là phần trăm RAM đã giải phóng.

Mode được chụp lúc click; checkbox bị khóa trong thao tác. Profile Normal giữ mức trước đây; Strong trong `clear-policy.json` schema 2: working set ≥32 MB, CPU ≤1% ở cả hai delta và live probe, tối đa 32 process, ngân sách 60 giây, target 35% available, cooldown 120 giây. Shared sampling/probe và mọi policy critical/service/user/session/protection/foreground/identity không đổi. Validator kiểm tra cả hai profile; malformed Strong chặn cả lượt Normal. Khoảng nghỉ monotonic lấy max(profile hiện tại, lượt trước), nên chuyển mức không rút ngắn cooldown.

`Invoke-MCClear` nhận Mode/ProgressQueue (tùy chọn cho caller ngoài GUI), trả Mode/Processed/CandidateCount/DurationSeconds trong summary; cooldown trả RetryAfterSeconds. Cancel khi chờ scan hoàn tất UI ngay và giải phóng CTS; khi Clear đang chạy chờ worker trả kết quả rồi dispose CTS. Queue hữu hạn theo số bước/32 target, không giữ lịch sử tiến trình qua nhiều lượt.

## Cấu hình và hiệu năng

Schema 1; `.data/settings.json` có ProtectedPaths/AllowClosePaths, refresh mặc định 3 giây (2–30), AutoKill luôn false. Bảo vệ app cá nhân chưa được cung cấp nên danh sách ban đầu trống. Settings lỗi fallback safe defaults. Ghi file tạm rồi thay file nguồn; audit giới hạn 200 event. CLI và GUI nhiều instance cùng ghi settings/log chưa được nghiệm thu đồng thời.

Mục tiêu nghiệm thu ban đầu (chưa phải cam kết đã đạt): idle GUI ≤2% CPU toàn máy, working set GUI ≤250 MB, chế độ thu nhỏ ≤200 MB nếu framework cho phép; kiểm chứng trên Windows 11 build 26200, i5-1345U/12 logical CPU, 15.69 GiB RAM khả dụng cho OS. Tần suất quét 3 giây, thu nhỏ 10 giây; không quét song song. Baseline collector ngắn đã đo 1.23% CPU toàn máy, 97.6 MB working set, ~538 ms/mẫu ổn định. Chưa có soak test GUI/VM hoặc ngân sách được người dùng chỉnh riêng.

## Nghiệm thu còn lại

Windows 10 22H2 x64 và Windows 11 24H2/25H2 x64 là **mục tiêu kiểm thử**, chưa phải mọi build đã chạy thành công. Cần DPI/keyboard/layout, GUI idle/thu nhỏ/soak, app có dữ liệu chưa lưu, hàng đợi khẩn cấp/cancel, app restart và RAM pressure trong VM. Không đánh dấu phase nghiệm thu hoàn tất từ test mock hoặc render offscreen.
