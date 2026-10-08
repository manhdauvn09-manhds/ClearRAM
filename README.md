# MemoryClear · PowerShell GUI preview

Bản portable cho Windows 10/11 x64, dùng Windows PowerShell 5.1 và WPF có sẵn. Không cần .NET SDK, npm hoặc quyền admin để mở giao diện.

Source preview: https://github.com/manhdauvn09-manhds/ClearRAM. Tải Code → Download ZIP hoặc clone, giải nén rồi nhấp đúp `Start-MemoryClear.cmd`. Các lệnh đường dẫn tuyệt đối bên dưới là ví dụ cho workspace phát triển; khi đặt ở thư mục khác, dùng launcher hoặc đổi đường dẫn tương ứng. Bản này còn nghiệm thu Windows/VM, chưa là release MVP.

## Chạy

Giải nén toàn bộ thư mục rồi mở **Start-MemoryClear.cmd**. Hoặc:

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "E:\SourceCode\NEW_APPLICATION\MemoryClear\MemoryClear.ps1"
```

`Bypass` chỉ áp dụng cho process PowerShell được mở, không thay execution policy của máy. Chính sách doanh nghiệp/AppLocker có thể vẫn chặn script; app sẽ không tự vượt qua chúng.

Để tạo **MemoryClear.lnk** trên Desktop của bạn, chạy script bên dưới. Shortcut dùng Windows PowerShell 5.1/STA, ẩn cửa sổ console và chạy từ thư mục project. Shortcut trỏ tới source hiện tại nên các lần cập nhật script sẽ được nạp khi mở lại app. Máy phát triển đã tạo và xác minh shortcut; mỗi máy/đường dẫn mới cần tạo riêng. Script tự xác định Desktop (kể cả OneDrive):

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "E:\SourceCode\NEW_APPLICATION\MemoryClear\scripts\Create-DesktopShortcut.ps1"
```

## Dùng

- **Clear** ở góc phải: bấm một lần, không cần chọn dòng hay tick quyền đóng. Thu hồi working set của process cùng user/session, ít dùng CPU qua hai khoảng đo, RAM từ 64 MB; giữ nguyên app và dữ liệu. Bỏ qua hệ thống/service/critical, process không xác minh được, app được bảo vệ, app ở foreground và executable của app vừa dùng trước khi bấm. Đây không phải phép đo app “không cần thiết”.
- Clear tối đa 12 process/lượt, ngân sách 30 giây (lệnh kiểm tra đang chạy có thể kết thúc muộn hơn), khoảng nghỉ 60 giây; dừng khi available RAM đạt 20% tổng RAM, hết ứng viên hoặc bạn bấm Dừng. Các mức này ở `app/clear-policy.json`, có schema bên cạnh; cấu hình lỗi chặn Clear.
- **Tiến trình:** khi chờ/quét, thanh chạy liên tục và hiện thời gian đã chạy. Khi đã có danh sách, thanh thể hiện số process đã xử lý/tổng số, gồm cả mục bị bỏ qua. Khi xong hiện **Hoàn tất lúc HH:mm:ss**, thời lượng và RAM trước/sau; hủy, hết thời gian, lỗi hoặc cooldown được ghi riêng, không báo thành công giả. Có thể bấm **Dừng các bước tiếp theo**. Thời gian hiển thị gồm cả lúc chờ scan; không phải dự báo thời điểm xong.
- Tick **Clear mạnh hơn** trước khi bấm Clear nếu muốn xét thêm ứng viên. Mức này vẫn giữ nguyên các kiểm tra bảo vệ/foreground và không đóng/kill app; app có thể nạp RAM lại nhiều hơn và chậm khi dùng tiếp. Không bảo đảm luôn giải phóng thêm RAM.

| Mức Clear | Working set tối thiểu | CPU tối đa toàn máy | Tối đa process | Ngân sách | Mục tiêu RAM khả dụng | Khoảng nghỉ |
|---|---:|---:|---:|---:|---:|---:|
| Thường (mặc định) | 64 MB | 0.1% | 12 | 30 giây | 20% tổng RAM | 60 giây |
| Mạnh hơn (opt-in) | 32 MB | 1% | 32 | 60 giây | 35% tổng RAM | 120 giây |

Hai khoảng đo CPU và live probe cùng áp dụng cho cả hai mức. Khoảng nghỉ dùng mức lớn hơn giữa lượt trước/lượt đang chọn; đổi mức không bỏ qua cooldown. Profile Clear dùng schemaVersion 2, không thay schema của `.data/settings.json`.

- Clear sử dụng Windows `EmptyWorkingSet`, không đóng/kill process và không giải phóng cấp phát commit. RAM có thể được nạp lại, app có thể chậm hơn khi dùng lại; không cam kết “dọn toàn bộ RAM” hoặc một số GB cố định. Commit gần giới hạn cần lưu và đóng bớt app. Tự đoán app không cần để đóng có thể làm mất công việc; đóng tự động chỉ áp dụng danh sách executable bạn cấp quyền riêng.
- RAM MB là working set; Private MB là cấp phát riêng, có thể gồm bộ nhớ đã page out. CPU % tính theo toàn bộ logical CPU. Mẫu đầu chưa có CPU; ô trống là chưa xác minh được.
- Tìm theo tên/PID/path, sort bằng tiêu đề cột, chọn nhiều dòng bằng Ctrl/Shift. Danh sách là **process**, chưa nhận diện tab trình duyệt hay gộp mọi process thành app.
- Checkbox **Chọn** dùng để chọn/bỏ chọn nhiều process mà không cần Ctrl; lựa chọn giữ qua refresh. Checkbox **Cho đóng gấp** lưu quyền đóng khẩn cấp theo executable, không phải chọn process và không đóng app ngay. Process được bảo vệ có checkbox quyền bị khóa.
- **Đóng process đã chọn:** xác nhận danh sách, gửi yêu cầu đóng cửa sổ chính. App có thể hỏi lưu; kết quả Requested chưa có nghĩa đã thoát.
- **Force kill:** xác nhận riêng; có thể mất dữ liệu chưa lưu. Kiểm tra lại PID/start time, user/session, service và protection trước thao tác. Không kill cả cây.
- **Bảo vệ / Bỏ bảo vệ:** lưu đường dẫn executable vào danh sách bảo vệ. Quy tắc hệ thống luôn ưu tiên.
- **Cho phép / Bỏ đóng khẩn cấp:** chọn rõ executable nào được phép đóng khi bấm nút khẩn cấp. Mặc định danh sách trống; không tự động chạy khi thiếu RAM.
- Nút khẩn cấp chỉ đóng bình thường theo danh sách cho phép, đo lại sau mỗi bước và dừng khi đạt mục tiêu/hết ứng viên. Có thể dừng các bước chưa gửi; không hoàn tác được thao tác đã gửi.

Process critical, Windows component, service, host hiện tại, user/session khác hoặc identity không đủ thông tin bị chặn. Không ép xóa cache, không suspend để quảng cáo dọn RAM, không tự bật startup/service hoặc auto kill. Chưa có helper nâng quyền; mục tiêu thiếu quyền được báo lỗi.

## CLI

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\MemoryClear.Cli.ps1 -Command List -Json
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\MemoryClear.Cli.ps1 -Command Inspect -ProcessId 1234
```

Close/Kill cần `-ProcessId` và `-StartTicks` từ List/Inspect. Mặc định dry-run, `-Execute` mới yêu cầu xác nhận tương tác. GUI/CLI sử dụng cùng policy. Không tự dùng `-Confirm:$false` để tác động công việc thật.

## Dữ liệu và kiểm tra

`.data/settings.json` lưu quy tắc; `.data/activity.json` giữ tối đa 200 sự kiện mới nhất. File settings lỗi quay về defaults và chặn hành động đến khi cấu hình được sửa/lưu lại. Sự kiện ghi thay đổi available RAM toàn máy quan sát được; không coi đó là số RAM app chắc chắn thu hồi.

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\MemoryClear.ps1 -SmokeTest
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Check-Clear.ps1
```

`tests/Run-Tests.ps1 -Integration` tạo, đóng và kill **chỉ process thử do bộ test tạo**, ghi báo cáo vào `artifacts/tests/results.json`. Không tự chạy test này trên dữ liệu công việc thực.

Đây là bản thử nghiệm. Ma trận Windows 10/11, kiểm tra layout/DPI, hộp thoại dữ liệu chưa lưu, áp lực RAM trong VM và soak test vẫn phải nghiệm thu trước phát hành chính thức. Xem trạng thái mới nhất trong `IMPLEMENTATION_PLAN.md`.

Source trong workspace đã có Clear. ZIP `MemoryClear-PowerShell-preview.zip` cũ được tạo trước thay đổi Clear. Nếu cần đóng gói source mới, script sau tự chuyển tới đúng thư mục, tạo ZIP tên theo thời điểm và kiểm tra entry/checksum; không đóng gói dữ liệu `.data`:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "E:\SourceCode\NEW_APPLICATION\MemoryClear\scripts\Package-Preview.ps1"
```

## Kế hoạch và handoff

Mở `MemoryClear-Plan.html`; nguồn trạng thái ở `plan/tasks.json`. Kết thúc mọi phase phải có tài liệu trong `docs/handoffs/` theo `TEMPLATE.md`.

Bằng chứng được chọn cho repo công khai nằm ở `docs/verification/` (bản snapshot, không phải CI mới). `artifacts/` và `.data/` là dữ liệu local do app/test tạo, không commit. Log process, settings cá nhân, shortcut và harness cài riêng cũng không được đưa lên repo. CI chạy các kiểm tra hiện có; xem kết quả thực tế trong GitHub Actions, không suy ra CI đã đạt từ báo cáo local.

CI của commit source đầu tiên `a53e87e` đã đạt: [execution trace](https://github.com/manhdauvn09-manhds/ClearRAM/actions/runs/37747840494), snapshot tại `docs/verification/github-actions-initial.json`. Các nghiệm thu Windows/VM/overhead còn thiếu vẫn giữ nguyên trạng thái trong kế hoạch.
