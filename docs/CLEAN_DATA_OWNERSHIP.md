# Phân tích ứng dụng và dữ liệu — readonly

Cập nhật 2026-10-09 (Asia/Tokyo), revision09.7. `Ownership.ps1` được module Disk nạp; GUI có nút **Phân tích ứng dụng** sau khi quét. Chỉ đối chiếu trang hiện tại, không đọc nội dung dữ liệu cá nhân, không chạy uninstall/repair, không cấp quyền xóa hoặc tự chọn file.

## Nguồn và giới hạn suy luận

- Registry HKCU/HKLM 32/64 và MSIX current-user: metadata tên/publisher/InstallLocation. Không gọi Win32_Product. InstallLocation khớp chỉ là căn cứ đường dẫn; không chứng minh file là cache hay disposable. Hai view cùng app được gộp khi phân loại; các ứng dụng khác nhau cùng khớp được giữ là shared.
- CIM Win32_Process lấy Name/ProcessId/ExecutablePath, không lấy CommandLine. ExecutablePath thiếu quyền là unknown, không là bằng chứng không có process. [Microsoft Win32_Process](https://learn.microsoft.com/windows/win32/cimwin32prov/win32-process) mô tả thuộc tính và điều kiện quyền.
- CIM Win32_Service lấy Name/State/PathName. Chỉ bóc executable không mơ hồ từ PathName, bỏ arguments khỏi evidence; service đang dừng vẫn có thể cần dữ liệu. [Microsoft Win32_Service](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-service).
- CIM MSFT_ScheduledTask trong namespace TaskScheduler lấy TaskName/Actions, chỉ giữ Execute, không giữ Arguments. Execute là trường riêng nên đường dẫn tuyệt đối có khoảng trắng được chấp nhận; COM/relative/environment/không giải được giữ unknown. [Microsoft WMI class source](https://github.com/microsoft/wmi/blob/master/server23h2/root/microsoft/windows/taskscheduler/MSFT_ScheduledTask.go).

Config/schema `app/owner-analysis-policy.json` + schema: product_runtime, readonly, no execution/absence inference/commandline; tối đa5000 entries/source,1000 rows/page, CIM timeout10s/source, freshness60s. Limit/permission/provider/ambiguous path làm inventory incomplete. Timeout/cancel là cooperative giữa calls/entries; chưa có live cancellation-latency benchmark, không hứa hard deadline10s cho cả lượt.

## Kết quả trên màn hình

| State | Nhãn và ý nghĩa | Quyền xóa |
|---|---|---|
| InstalledMetadataProtected | Đường dẫn khớp thông tin cài đặt; app vẫn có thể dùng dữ liệu | Không |
| SharedMetadataProtected | Nhiều app khớp cùng đường dẫn; chưa phân giải owner | Không |
| ReferencedProtected | Có executable process/service/task tham chiếu file/thư mục bên cạnh; có thể là portable/shared | Không |
| UnknownProtected | Thiếu mapping hoặc snapshot thiếu/cũ; không chứng minh app đã gỡ | Không |

Tham chiếu executable trong cùng thư mục là dấu hiệu **cần giữ**, không phải proof rằng mọi file trong đó thuộc executable. Không mapping AppData dựa trên tên folder/app giống nhau. Snapshot cũ/future không được trình bày là tham chiếu hiện tại. Apps gỡ còn cache/empty chỉ mở safe classification sau vendor/history/no-live-dependency proof riêng; catalog hiện tại nhận diện ứng viên Chrome/Edge/VS Code, chưa có đủ proof safe đó. Xem [app profiles](CLEAN_DATA_APP_PROFILES.md) cho dataClass/lifecycle riêng và giới hạn nguồn.

GUI giữ FileID/snapshot/risk ban đầu, thêm OwnerLabel/OwnerEvidence; tìm kiếm được tên app. Scope/filter/page đổi thì bỏ preview và analysis cũ. Worker dùng shared RAM/Disk lock, progress/elapsed/cancel hiện có; incomplete inventory báo Partial. Details do người dùng bấm mới hiển thị evidence; không popup khi quét/phân tích.

## Kiểm chứng

`tests/Check-DiskOwnership.ps1` **13/13** PS5.1.26100.9444: boundary/sibling/no name inference, duplicate views/shared roots, process/service/task/portable references, stale/future, parser/no arguments, unavailable vs complete injected CIM providers, fixture page preservation/cancel/injection guard. **CIM provider test được thay bằng synthetic provider**; không claim đã quét native ứng dụng của người dùng.

`tests/Check-DiskUI.ps1` **30 assertions**,25 controls: real runspace nhận fixture inventory, incomplete→Partial, owner search, shared lock/clear lock, reset analysis khi đổi scope, no deletion. Trace ở `docs/verification/disk-ownership-tests.json` và `disk-ui-tests.json`. Render offscreen đã xem; không thay thế human click/DPI/keyboard/Win10/11 VM/native coverage.

Đã thêm [lịch sử quan sát](CLEAN_DATA_OWNER_HISTORY.md), state PreviouslyObservedMissingProtected chỉ là từng thấy metadata rồi hiện thiếu, vẫn giữ dữ liệu. Chi tiết có UTC/source/entry ID/version; current references và unknown luôn ưu tiên.

CD-02/CD-03 giữ review. Có catalog ba app; cần historical uninstall/verified-version/removed cache-empty proof, live metadata coverage/budgets/cancel latency, UI risk review/restore và VM trước production cleanup. Digest/local metadata không privileged authority.
