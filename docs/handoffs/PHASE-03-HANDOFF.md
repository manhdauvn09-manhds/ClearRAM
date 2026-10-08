# Handoff nháp — Phase 03 · Quan sát

- Ngày: 2026-10-08 (Asia/Tokyo). Người thực hiện: Codex.
- Trạng thái: **Chờ kiểm tra; phase chưa hoàn tất**.
- Task handoff: HO-03 / review. Revision: 2026-10-08.5. Branch main; lịch sử commit tại repository ClearRAM. Chưa phát hành MVP.

## 1. Mục tiêu

Dashboard thực dùng PowerShell/WPF, RAM/CPU/process theo mẫu. Giữ đúng dữ liệu unknown và không khẳng định tương thích ngoài máy đã kiểm tra.

## 2. Kết quả theo task

| Task | Trạng thái | Bằng chứng |
|---|---|---|
| MON-01 | Hoàn tất | Native.ReadSystem, Get-MCSnapshot; total/available đối chiếu CIM và CPU bounds đạt |
| MON-02 | Hoàn tất | Inventory live có path/SID/session/start time, service, private/working set; fail closed |
| MON-03 | Hoàn tất ở chế độ process | CPU theo delta chuẩn hóa logical CPU, sort RAM và một mẫu lịch sử; không gộp app chưa có cơ sở |
| UI-01 | Chờ kiểm tra | WPF smoke, offscreen render; còn kiểm tra tương tác/DPI/keyboard |
| CLEAR-01 | Chờ kiểm tra | Clear một chạm/progress/Strong đã triển khai; 12/12 test fixture/worker/policy/UI state đạt, còn pressure/foreground/UX trong VM |
| QA-01 | Chờ kiểm tra | Có baseline collector ngắn; chưa đủ ma trận tải và overhead toàn GUI |
| HO-03 | Chờ kiểm tra | Bản nháp này; chưa được đóng phase |

## 3. Điểm vào

`MemoryClear.ps1` điều phối UI/worker; `app/MainWindow.xaml` layout; `Get-MCSnapshot` trong module thu thập dữ liệu. Module được import ở GUI trước khi worker chạy để Add-Type không cạnh tranh khởi tạo. Runspace pool một worker tránh quét trùng và thao tác song song.

## 4. Kiểm chứng

- Bộ test đạt 17/17: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/Run-Tests.ps1 -Integration`.
- WPF: `powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File MemoryClear.ps1 -SmokeTest`. PNG và JSON ở `artifacts/gui-preview.png`, `artifacts/gui-smoke.json`.
- Collector baseline: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/Measure-Monitor.ps1`.
- Đã đo trên Win11 build 26200: 15.69 GiB total, ~538 ms/mẫu ổn định, 1.23% CPU toàn máy, 97.6 MB working set bộ thu thập. Có 4 mẫu ngắn, không phải soak test.
- Ảnh offscreen được xem để kiểm tra layout/font. Không thay thế việc tương tác cửa sổ thật.
- Artifact smoke cuối hiện lưu (`docs/verification/gui-smoke.json`): worker nền, sort/selection/render đạt, 19 controls/394 process/~255.5 MB working set, trước controls Clear hiện tại. Ghi chú 149.9 MB của phiên trước không khớp artifact cuối; không dùng để claim đạt budget 250 MB. Đây là mẫu offscreen, không phải footprint GUI idle đã nghiệm thu. Đã sửa lỗi sort PSObject/WPF bằng typed ProcessRow và giữ selection qua refresh.

## 5. Quyết định

Danh sách hiện là process; không nhận diện tab browser. Working set và private memory là hai chỉ số khác nhau. Không cộng số RAM process thành cam kết giải phóng. Refresh 3 giây, khi thu nhỏ 10 giây; cache metadata ~15 giây, hành động vẫn đọc lại policy.

## 6. Tồn tại

Chưa kiểm tra sort/selection khi cập nhật liên tục, thao tác dialog thật, DPI/keyboard, Windows 10, GUI idle/minimized/soak, dữ liệu chưa lưu, hàng đợi khẩn cấp và áp lực RAM/auto-restart trong VM. Phần action đã có preview source nhưng nghiệm thu SAFE/ACT/EMG vẫn còn theo kế hoạch. Chưa có app bảo vệ cá nhân do người dùng cung cấp.

## 7. Bước tiếp theo

### Sửa lỗi checkbox ngày 2026-10-08

Người dùng báo không tick được các item. Nguyên nhân: DataGridCheckBoxColumn chỉ hiển thị AllowClose trong DataGrid readonly. Đã thay bằng template checkbox bấm trực tiếp và thêm cột **Chọn** riêng, two-way theo DataGridRow.IsSelected. Mouse preview ngăn click checkbox thứ hai làm mất lựa chọn trước đó. Các cột số liệu vẫn readonly.

Checkbox **Cho đóng gấp** gọi `Set-MCAllowClosePermission`: xác minh lại PID/start time, path và policy trước khi lưu; cập nhật các row cùng executable. Protected/unknown bị khóa. Không gửi lệnh close/kill từ checkbox.

Kiểm chứng: `powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File tests/Check-Checkboxes.ps1` **PASS** trên Windows PowerShell 5.1. Báo cáo: `artifacts/checkbox-tests.json`. Kiểm tra chọn hai dòng không Ctrl, bỏ riêng một dòng, refresh, tick/lưu/nạp lại/bỏ quyền, disabled protection và không kết thúc process từ checkbox. Cấu hình được cô lập trong thư mục test; chỉ hai fixture được dọn ở finally. Một lần test đầy đủ trước đó bị lỗi hết bộ nhớ môi trường; test nhẹ tập trung checkbox đã chạy thành công. Chưa thay thế ma trận tương tác/DPI/VM còn thiếu.

File sửa: `app/MainWindow.xaml`, `MemoryClear.ps1`, `app/MemoryClear.Core.psm1`, `tests/Check-Checkboxes.ps1`, `README.md`. Source và ZIP portable được cập nhật; UI-01/HO-03 vẫn review cho phần nghiệm thu còn lại. Người dùng cần đóng cửa sổ MemoryClear cũ rồi mở lại launcher để nạp XML/script mới.

1. Đọc README và khởi động Start-MemoryClear.cmd khi cần dùng bản thử nghiệm.
2. Hoàn thiện UI-01/QA-01 bằng ma trận và bằng chứng còn thiếu.
3. Khi đủ, cập nhật tài liệu này thành handoff hoàn tất, đặt HO-03 done.
4. Tiếp tục phase 04 kiểm chứng policy rồi phase 05/06; không đánh dấu các gate hoàn tất chỉ từ test fixture hiện có.

## 8. Checklist

- [x] Kết quả/source/giới hạn được ghi rõ.
- [x] Có báo cáo test và collector baseline.
- [x] Trạng thái giữ review, không đóng phase giả.
- [ ] UI tương tác/DPI/keyboard đạt.
- [ ] QA đầy đủ và ngân sách GUI được nghiệm thu.
- [ ] HO-03 hoàn tất rồi chuyển phase tiếp theo.

## 9. Bổ sung Clear một chạm — 2026-10-08

Yêu cầu mới: một nút không cần chọn process. Đã thêm **Clear** ở header. Bản này thu hồi working set qua EmptyWorkingSet, giữ nguyên process và dữ liệu, không đoán ứng dụng “chắc chắn không cần” để đóng. Nhàn rỗi chỉ là tín hiệu tránh trim process bận, không là bằng chứng app không quan trọng. Close/Kill và đóng khẩn cấp theo allowlist vẫn là luồng riêng có xác nhận.

Điểm vào: `Start-MCOneClickClear`/worker Clear trong `MemoryClear.ps1`; planner/executor `app/MemoryClear.Clear.psm1`; handle `Native.AcquireForTrim`; cấu hình `app/clear-policy.json` và schema cùng thư mục. Handle trim không thể CloseWindow/Kill. Tái kiểm tra identity/service/protection/CPU/foreground, bỏ qua app foreground/executable vừa dùng và process bị chặn. Một worker; Clear chờ scan hiện tại, không cần click lần hai. Cancellation token bỏ bước chưa gửi. Mặc định ≥64 MB working set, ≤0.1% CPU ở hai delta, tối đa 12 process, ngân sách 30 giây kiểm tra giữa bước, cooldown 60 giây, dừng khi RAM khả dụng ≥20%.

Kiểm chứng: `powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "E:\SourceCode\NEW_APPLICATION\MemoryClear\tests\Check-Clear.ps1"` đạt 10/10 trên Windows PowerShell 5.1.26100.8875; `artifacts/clear-tests.json`. Bao gồm planner unknown/busy/protected/stale/exclusion/cap, policy lỗi, click không selection/hủy, worker thật nhận token hủy, handle không close/kill, protected path, cooldown và trim fixture thật rồi xác minh dữ liệu. Chỉ fixture do test tạo được trim; không trim app công việc. Một lần đo fixture: 46.14 MB → 0.6 MB working set, vẫn chạy và dữ liệu hợp lệ; **không** suy rộng thành RAM khả dụng toàn máy hay hiệu quả lâu dài. Ảnh render `artifacts/clear-preview.png` được xem để kiểm tra nút/layout; không phải nghiệm thu tương tác cửa sổ thật.

File thêm/sửa: `MemoryClear.ps1`, `app/MainWindow.xaml`, `app/Native.cs`, `app/MemoryClear.Clear.psm1`, hai file clear-policy, `tests/Check-Clear.ps1`, `tests/Check-Checkboxes.ps1`, `scripts/Package-Preview.ps1`, `README.md`, `docs/ARCHITECTURE.md`, `plan/record-clear-preview.mjs`, `plan/tasks.json`, HTML/Markdown kế hoạch và `Handoff.md`.

Trim không giải phóng commit; working set có thể nạp lại và gây page faults/chậm khi app hoạt động lại. Không purge standby/cache, không disable pagefile/security, không tự nâng quyền. CPU probe không chứng minh app không cần. Ngân sách thời gian không phải deadline cứng khi CIM đang chờ. Cooldown theo worker và reset khi mở lại app; nhiều instance chưa được nghiệm thu.

Source workspace là bản mới. ZIP preview cũ chưa chứa Clear; `scripts/Package-Preview.ps1` dành cho operator đóng gói, chưa chạy trong lượt này. Mở bản mới bằng `powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "E:\SourceCode\NEW_APPLICATION\MemoryClear\MemoryClear.ps1"`; script tự chuyển tới thư mục của nó và báo khởi tạo controls/worker. Chỉ đóng cửa sổ MemoryClear cũ trước khi mở lại; không kết thúc app công việc để test.

Tiếp theo: nghiệm thu CLEAR-01/UI-01/QA-01 trong VM với áp lực RAM, người dùng đổi foreground, hủy khi đang quét/kiểm tra target, phản hồi/page faults khi mở lại app, cùng ma trận Windows/DPI/overhead còn thiếu. HO-03 vẫn review; phase 03 chưa hoàn tất. Giữ các gate SAFE/ACT/EMG; không dùng 10 test fixture làm bằng chứng nghiệm thu đầy đủ.

Kiểm tra hồi quy checkbox sau Clear: `powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "E:\SourceCode\NEW_APPLICATION\MemoryClear\tests\Check-Checkboxes.ps1"` đạt. Một lần trước đó dừng ở “Own disposable fixtures should be actionable”; chưa xác minh được nguyên nhân. Test được đổi từ tái dùng fixture Windows Forms sang fixture Thread.Sleep nhẹ hơn, rồi chạy lại đạt. Chưa coi đây là bằng chứng bảo đảm GUI dùng được ở mọi mức commit. Test lỗi ghi báo cáo failure thay vì giữ artifact pass cũ. Kế hoạch đã dựng lại và kiểm tra: 44 task/15 done, dependencyValidation passed; check-plan PASS (logic, không thay nghiệm thu layout browser).

## 10. Tiến trình và Clear mạnh hơn — yêu cầu tiếp theo 2026-10-08

Đã thêm checkbox **Clear mạnh hơn** (mặc định tắt), thanh tiến trình, count và đồng hồ. Bấm Clear khi scan đang chạy hiện Chờ; lấy mẫu hiện thanh indeterminate; xử lý target hiện X/N thực, tính cả skipped. Hoàn tất lưu giờ HH:mm:ss, thời lượng/mode và message RAM trước/sau. Cancelled/TimeLimit/Error/Cooldown dừng animation và có nhãn riêng, không được đánh dấu hoàn tất hoặc ép thanh 100%. Pending cancel không để spinner/CTS sót. Không dự báo thời điểm xong.

Worker truyền sự kiện qua `ConcurrentQueue<object>`; timer UI hút trước nhánh async chưa xong nên trạng thái vẫn cập nhật khi worker chờ CIM/CPU. Mode được chụp lúc click và khóa checkbox cho đến kết thúc. `Invoke-MCClear` có Mode/ProgressQueue tùy chọn, summary thêm processed/candidate count/duration/mode. Không gọi UI từ thread worker.

Policy Clear nâng schemaVersion 2, giữ Normal (64 MB/CPU ≤0.1%/12 process/30 giây/target 20%/cooldown 60 giây). Strong (32 MB/CPU ≤1%/32 process/60 giây/target 35%/cooldown 120 giây) mở rộng ứng viên, **không** bỏ bảo vệ/identity/foreground và không đóng/kill. Hai khoảng đo và live probe vẫn áp dụng. Kiểm tra cả hai profile fail closed; chuyển mode không rút ngắn cooldown của lượt trước. `.data/settings.json` vẫn schema 1. RAM có thể nạp lại nhiều hơn; Strong không bảo đảm thu hồi thêm hoặc giảm commit.

`powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "E:\SourceCode\NEW_APPLICATION\MemoryClear\tests\Check-Clear.ps1"`: **12/12 đạt**, `artifacts/clear-tests.json`, PowerShell 5.1.26100.8875. Thêm case Strong chọn thêm ứng viên nhưng giữ protection/foreground, profile được chụp khi click, count 2/7, complete/cancel/timeout/error/cooldown không spinner/success giả, worker thật truyền queue/token/mode và đổi mode không né cooldown. Fixture thật vẫn chạy/dữ liệu đúng sau trim; chỉ fixture được tác động. Ảnh `artifacts/clear-preview.png` được xem, có nhãn hoàn tất/checkbox/thanh và không bị cắt ở viewport test 1072×700.

File thay đổi thêm: `MemoryClear.ps1`, `app/MainWindow.xaml`, module Clear, policy/schema, `tests/Check-Clear.ps1`, `tests/Render-Clear-States.ps1`, README/ARCHITECTURE, `plan/record-clear-feedback.mjs`, tasks/HTML/Markdown và Handoff.md. `plan/record-clear-preview.mjs` từ chối revision mới để tránh quay lùi cập nhật.

Chưa nghiệm thu Strong toàn máy trong VM, hiệu quả lâu dài/page faults, thời gian thật của từng stage khi app đổi foreground liên tục hoặc tương tác GUI thật. Giới hạn 30/60 giây là ngân sách giữa bước; CIM đang chạy có thể kết thúc muộn. UI-01/CLEAR-01/QA-01/HO-03 giữ review. Bước tiếp theo vẫn theo mục 7/9; không đóng phase vì bộ test này đạt.

Kiểm tra layout hai trạng thái: `powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "E:\SourceCode\NEW_APPLICATION\MemoryClear\tests\Render-Clear-States.ps1"` đạt trên PowerShell 5.1. Ảnh `artifacts/clear-running-preview.png` và `artifacts/clear-completed-preview.png` được xem: count 2/7 và nhãn hoàn tất/mode đều hiển thị, controls khóa/mở đúng, không cắt nội dung ở 1072×700. Đây là sự kiện minh họa offscreen, không giả là một lượt Clear trên app công việc. File có UTF-8 BOM để giữ tiếng Việt. `node plan/record-clear-feedback.mjs`, `node plan/build-plan.mjs`, `node plan/check-plan.mjs` đạt: revision 2026-10-08.3, 44 task/15 done; HTML/Markdown đồng bộ, status/dependency/migration logic PASS.

## 11. Shortcut Desktop — 2026-10-08

Người dùng yêu cầu tạo shortcut để gọi GUI từ Desktop. Đã thêm `scripts/Create-DesktopShortcut.ps1`, chạy bằng `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "E:\SourceCode\NEW_APPLICATION\MemoryClear\scripts\Create-DesktopShortcut.ps1"` và tạo `%DesktopKnownFolder%\MemoryClear.lnk` theo Known Folder của người dùng, không đoán Desktop từ USERPROFILE.

Target `C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe`; arguments `-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "E:\SourceCode\NEW_APPLICATION\MemoryClear\MemoryClear.ps1"`; working directory project. Script kiểm tra file nguồn, tránh ghi đè shortcut có command khác, Save rồi đọc lại COM Target/Arguments/WorkingDirectory và ghi `artifacts/desktop-shortcut.json` Verified=true/Launched=false, PowerShell 5.1.26100.8875. Không tự chạy GUI hoặc Clear. Người dùng nhấp đúp MemoryClear trên Desktop; nếu di chuyển project chạy lại script tạo shortcut. README/Handoff/notes UI-01 được cập nhật; phase 03 vẫn review và không thay các nghiệm thu còn thiếu.

## 12. Publication source lên GitHub — 2026-10-08

Người dùng yêu cầu commit/push tới `https://github.com/manhdauvn09-manhds/ClearRAM.git`. GitHub API xác minh repository trống/default main/quyền push; local chưa có Git nên khởi tạo main và origin tại workspace hiện tại. Stage source GUI/CLI/native/policy, scripts/tests, kế hoạch/handoff, AGENTS và workflow; không đưa `.data`, log inventory, ZIP/exe, shortcut cá nhân hoặc harness cài riêng lên repo công khai. Các snapshot sạch và ảnh UI không có inventory ở `docs/verification/`; Desktop paths được ẩn danh trong tài liệu/report public. Snapshot local không đồng nghĩa CI mới đạt.

Thêm `.gitattributes` giữ line endings PowerShell/cmd và UTF-8 BOM hiện có; `.gitignore` chặn .env/shortcut. README có hướng dẫn tải repo/chạy portable/tạo shortcut theo máy. CI thêm checks Clear/progress/Strong/checkbox, exit code được kiểm tra giữa native child commands. `plan/tasks.json` vẫn 44 task/15 done; UI-01/CLEAR-01/QA-01/HO-03 review, publication source không đóng gate MVP. Cần đọc execution trace của GitHub Actions sau push và tiếp tục các bước nghiệm thu còn thiếu, không claim CI pass trước khi quan sát kết quả.

Kết quả publication: source commit `a53e87e09d756d9adcedf386e89a54c75c26a77d` đã push main, remote SHA khớp local. 48 file qua staged review (hash/path/pattern/BOM); plan build/check và whitespace check đạt. Lỗi shell/process do môi trường thiếu commit memory được xử lý bằng kiểm tra một lượt Git + hash nội dung, không trim/kill app công việc. CI thực **success** ở https://github.com/manhdauvn09-manhds/ClearRAM/actions/runs/37747840494, các step plan/policy/collector/WPF/Clear/checkbox đều success. Trace lưu `docs/verification/github-actions-initial.json`. CI không thay thế các gate Windows/VM/overhead còn thiếu; phase 03 vẫn review. Tài liệu kết quả publication được commit tiếp theo, không sửa/amend commit source đã push.
