# MemoryClear — Handoff

Cập nhật 2026-10-08 (Asia/Tokyo), Codex. Kế hoạch nguồn: `plan/tasks.json`, revision 2026-10-08.5. Repository source: https://github.com/manhdauvn09-manhds/ClearRAM, branch main. Chưa phát hành MVP.

## NOW

- Người dùng yêu cầu commit/push source tới ClearRAM. Đã xác minh GitHub API: repo trống, default_branch main và tài khoản hiện tại có push; Git local được khởi tạo ở project, origin đúng URL được chỉ định. Chỉ đưa source app, scripts/tests, kế hoạch/handoff, AGENTS và CI vào commit. `.data`, artifact tạm, shortcut, secrets và harness cài riêng không được stage; snapshot test sạch ở `docs/verification/`. Git history/remote là nguồn xác minh commit sau publication; không coi push là release MVP.
- Source commit `a53e87e09d756d9adcedf386e89a54c75c26a77d` đã push main; `git ls-remote origin refs/heads/main` khớp local SHA. 48 file được review bằng hash staged blob, path/pattern scan và PS5 BOM; `git diff --cached --check`/plan build/check đạt. Commit dùng email noreply trong repo này, không sửa cấu hình Git global.
- CI source commit đã **success**: https://github.com/manhdauvn09-manhds/ClearRAM/actions/runs/37747840494. Đã quan sát mọi step Plan consistency, PowerShell policy/collector, WPF smoke và Clear/progress/Strong/checkbox success. Trace `docs/verification/github-actions-initial.json`; đây là CI của commit source nói trên, không phải nghiệm thu toàn bộ Windows/VM/MVP.
- Snapshot GUI smoke đang lưu: 19 controls/394 rows/255.5 MB (`docs/verification/gui-smoke.json`, 2026-10-08T06:12:45Z), trước các controls Clear hiện tại. Số 149.9 MB trong ghi chú cũ không khớp artifact cuối; không dùng nó để claim đạt budget. QA GUI vẫn review, cần đo lại footprint.
- Theo yêu cầu người dùng, đã tạo `%DesktopKnownFolder%\MemoryClear.lnk`. Target: Windows PowerShell 5.1, `-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File` tới source; working directory là project, không cần admin. `scripts/Create-DesktopShortcut.ps1` chạy thành công trên 5.1 và COM readback xác minh Target/Arguments/WorkingDirectory; bằng chứng `artifacts/desktop-shortcut.json`. Chưa bấm shortcut để tránh tự mở thêm app; kết quả này là kiểm tra file/command, không giả là nghiệm thu mở GUI từ Desktop.
- Người dùng chọn PowerShell GUI trước, Windows 10/11 x64; Linux và C#/Avalonia để sau. Clear không cần chọn process, có tiến trình và tùy chọn mạnh hơn theo yêu cầu mới.
- Source đã có Clear ở header: planner chọn process ít hoạt động đủ điều kiện; executor chỉ EmptyWorkingSet, giữ ứng dụng/dữ liệu và không có quyền close/kill. Fresh identity/policy/service/CPU/foreground; bảo vệ app quan trọng và fail closed khi không xác minh được. Chính sách product_runtime nằm ở `app/clear-policy.json` + schema, không đọc cấu hình harness.
- `tests/Check-Clear.ps1`: 12/12 đạt trên PowerShell 5.1.26100.8875, bằng chứng `artifacts/clear-tests.json`. Test chỉ trim fixture tự tạo, vẫn chạy và dữ liệu hợp lệ; mẫu mới 45.91 → 0.61 MB working set, không coi là lợi ích RAM lâu dài. `artifacts/clear-preview.png` là render offscreen đã xem.
- GUI: indeterminate khi quét/chờ, X/N từ worker khi xử lý, thời gian chạy; kết thúc hiển thị giờ/thời lượng/mode và message RAM trước/sau. Cancel/timeout/error/cooldown riêng; không spinner còn chạy hay thanh 100% giả. Shared ConcurrentQueue được test bằng worker thật; WPF handler/state kiểm tra offscreen, chưa thay tương tác người dùng thật.
- Normal giữ 12 process/30 giây; Strong opt-in 32 process/60 giây, từ 32 MB và CPU ≤1%, target 35%, cooldown 120 giây. Các bảo vệ/foreground/identity và quyền handle không đổi. Policy Clear schema 2, settings schema 1; chuyển mức không bỏ qua cooldown. Strong chỉ mở rộng ứng viên, không cam kết RAM giải phóng thêm.
- `tests/Render-Clear-States.ps1` đạt trên PowerShell 5.1; đã xem hai ảnh running/completed ở `artifacts/clear-*-preview.png`, không cắt ở 1072×700. Chỉ sự kiện minh họa UI, không tác động app thật. Recorder/build/check-plan đạt sau cập nhật revision 2026-10-08.3; vẫn 44 task/15 done và phase 03 review.
- Checkbox có lựa chọn nhiều dòng và cấp quyền đóng riêng. Bằng chứng trước thay đổi Clear: `artifacts/checkbox-tests.json`. Các nghiệm thu đủ phase 03 chưa hoàn tất; `docs/handoffs/PHASE-03-HANDOFF.md` là nháp. MON-01/02/03 done, UI-01/CLEAR-01/QA-01/HO-03 review.
- Hồi quy checkbox sau Clear đã đạt bằng fixture Thread.Sleep nhẹ hơn; một lần trước đó bị chặn ở policy cho fixture, nguyên nhân chưa xác minh. Không suy diễn rằng đây là lỗi sản phẩm hoặc đảm bảo mọi trường hợp thiếu RAM đã được xử lý. `node plan/build-plan.mjs` + `node plan/check-plan.mjs` đạt: 44 task/15 done, source/HTML đồng bộ và logic tracker đạt, không phải kiểm tra browser layout.
- Core test trước đây 17/17 và collector baseline 4 mẫu: 1.23% CPU toàn máy, 97.6 MB working set, ~538 ms/mẫu. Không phải overhead/soak toàn GUI.
- Source workspace đã mới; ZIP `artifacts/MemoryClear-PowerShell-preview.zip` cũ chưa có Clear. Có script operator `scripts/Package-Preview.ps1` tạo ZIP/checksum; chưa chạy đóng gói mới.

## NEXT

1. Đọc IMPLEMENTATION_PLAN, tasks.json và handoff phase 03. Nếu có JSON progress mới từ người dùng, đối chiếu trước khi dựng lại HTML.
2. Kiểm tra lượt Normal/Strong toàn máy trong VM, progress ở từng stage, foreground/cancel/timeout, page faults và phản hồi app sau trim; nghiệm thu UI/DPI/keyboard và GUI idle/minimized/soak.
3. Khi mọi task phase 03 đủ bằng chứng, hoàn thiện handoff/HO-03 rồi đi tiếp phase 04–06 theo dependency. Không coi source action preview là gate đã đạt.
4. Người dùng nạp GUI mới bằng `powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "E:\SourceCode\NEW_APPLICATION\MemoryClear\MemoryClear.ps1"`. Script tự cd vào project. Nếu cần ZIP mới: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "E:\SourceCode\NEW_APPLICATION\MemoryClear\scripts\Package-Preview.ps1"`.

## OPEN

- until: người dùng mở GUI từ Desktop và xác nhận hoạt động. Shortcut đã xác minh cấu trúc; nếu di chuyển project phải chạy lại script tạo shortcut từ vị trí mới.
- until: CLEAR-01 có báo cáo VM áp lực RAM/foreground/cancel/progress Normal/Strong và hiệu năng khi dùng lại app. Hiện fixture/native API/worker/progress/UI state được kiểm chứng; chưa chạy Clear lên process công việc thật.
- until: UI-01/QA-01/CLEAR-01 và handoff đạt tiêu chí. Phase 03 giữ review; Windows 10/DPI/keyboard/GUI overhead/soak còn thiếu.
- until: người dùng cung cấp và duyệt danh sách app đóng một chạm. Không có cách suy ra “chắc chắn không cần” từ CPU thấp hoặc chạy nền; Clear hiện giữ process.
- until: QA-02/03 và REL-02 có kết quả VM/ma trận. Close/Kill/emergency preview chưa đủ nghiệm thu phát hành; process restart/PID reuse/access denied/dữ liệu chưa lưu còn cần ma trận.
- until: operator chạy script package và xác minh artifact mới. ZIP cũ không chứa Clear; không gửi nó như bản mới.
- until: có kiểm thử nhiều instance. Settings/log cùng ghi và cooldown giữa instance chưa được bảo đảm.

## AVOID

- Không chạy Clear/Kill thử trên app công việc, không dựa vào tên/PID/CPU để quyết định đóng; fixture test luôn cô lập dữ liệu và chỉ dọn PID do test tạo.
- Không hứa dọn toàn bộ RAM, không gán biến động available RAM toàn máy cho riêng trim. Trim không decommit, RAM có thể nạp lại; commit gần giới hạn cần lưu/đóng app.
- Không purge cache, tắt pagefile/security, suspend để quảng cáo dọn RAM hoặc tự nâng admin/force kill. Giữ quyền đóng khẩn cấp riêng và có xác nhận.
- Không đánh dấu phase hoàn tất khi handoff/tasks còn review. Không bỏ gate bảo vệ/VM vì render hoặc unit test đã đạt.
- Giữ UTF-8 BOM cho PowerShell có tiếng Việt để Windows PowerShell 5.1 đọc đúng. Test cũng phải dùng `powershell.exe`, không thay bằng `pwsh` rồi claim đã kiểm chứng 5.1.
