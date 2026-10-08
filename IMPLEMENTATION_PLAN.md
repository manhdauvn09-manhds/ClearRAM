# MemoryClear — Kế hoạch triển khai

Phiên bản: 2026-10-08.5. Cập nhật: 2026-10-08 (Asia/Tokyo).

Đã chốt PowerShell GUI trước: Windows 10/11 x64, Windows PowerShell 5.1 + WPF, portable folder + CLI. Clear một chạm không cần chọn; có tiến trình/quét/xử lý/hoàn tất và tùy chọn Clear mạnh hơn (opt-in), cả hai chỉ trim working set, giữ process/dữ liệu. Đóng/force kill xác nhận riêng, auto kill tắt; app cá nhân chưa được cung cấp. C#/Avalonia và Linux để sau.

## Trạng thái tổng quan

**Quy định bắt buộc:** Cuối mỗi phase bắt buộc tạo docs/handoffs/PHASE-XX-HANDOFF.md theo TEMPLATE.md, cập nhật evidence của HO-XX và gửi link cho người dùng. Phase chỉ hoàn tất khi task và handoff đã hoàn tất. Nếu dừng giữa chừng, viết bản nháp và giữ trạng thái chưa hoàn tất.

Mẫu: [TEMPLATE.md](docs/handoffs/TEMPLATE.md). Bàn giao hiện có: [Phase 00](docs/handoffs/PHASE-00-HANDOFF.md). Quy trình tiếp tục: [AGENTS.md](AGENTS.md). Các phase chưa hoàn thành chỉ có task handoff; không tạo báo cáo giả cho công việc chưa làm.

- Tài liệu: 4/4 task hoàn tất.
- MVP Windows: 11/35 task hoàn tất.
- Mở rộng: 0/5 task hoàn tất.

Tiến độ tính theo số task, không phải theo thời gian. Ngày công là khoảng tham khảo cho một người; chưa có lịch phát hành cam kết.

## Cập nhật sau mỗi buổi làm

1. Đọc file này và `plan/tasks.json` trước khi triển khai. Chỉ thực hiện trong phạm vi người dùng đã chốt.
2. Khi bắt đầu: đặt status=doing và ghi owner. Khi xong code nhưng chưa kiểm tra: review.
3. Chỉ đặt done khi đạt tiêu chí và có evidence (đường dẫn, commit, lệnh/biên bản nghiệm thu). Task phụ thuộc phải hoàn tất.
4. blocked cần ghi nguyên nhân và bước gỡ chặn; decision là đang chờ lựa chọn của người dùng. Không coi chưa đến lượt là blocked.
5. Cập nhật updated theo ngày Asia/Tokyo, evidence và notes. Chưa biết kết quả thì không ghi đã đạt.
6. Chạy `node plan/build-plan.mjs` để dựng lại HTML và Markdown. Không chỉnh tay trạng thái trong HTML.
7. Nếu đã sửa trên trình duyệt: xuất JSON và đối chiếu/nhập vào tasks.json trước khi dựng lại; HTML không tự sửa file trên ổ đĩa. Bản localStorage của cùng revision có thể ghi đè trạng thái hiển thị, vì vậy nhập JSON mới nhất hoặc đổi revision khi cập nhật nguồn.

## Các cổng nghiệm thu

- G0: DEC-01…03 — chốt nền tảng, bảo vệ, chỉ tiêu đo.
- G1: QA-01 — số liệu đúng và overhead đạt ngân sách.
- G2: SAFE-04 + QA-02 — policy và thao tác thủ công đã kiểm chứng bằng VM.
- G3: QA-03 — khẩn cấp, hủy và điều kiện dừng đạt tiêu chí.
- G4: REL-02 + REL-03 — ma trận tương thích, tài liệu và người dùng nghiệm thu.

## Rủi ro cần theo dõi

| Rủi ro | Biện pháp / task chịu trách nhiệm |
|---|---|
| Kill nhầm hệ thống hoặc PID tái sử dụng | SAFE-01, SAFE-03, SAFE-04; fail closed khi không đủ thông tin |
| Mất dữ liệu chưa lưu | ACT-01, ACT-02; không tự force sau timeout |
| RAM giảm trên biểu đồ nhưng app chậm hơn | QA-01, QA-03; theo dõi available RAM và phản hồi, không purge cache |
| Công cụ tự tốn tài nguyên | DEC-03, QA-01, REL-02; lấy mẫu thích ứng và benchmark |
| Quyền nâng cao bị lạm dụng | ACT-03; helper tối thiểu, kiểm tra caller/policy |
| Linux/Windows build khác nhau | DEC-01, REL-02, EXT-01/02; capability và ma trận kiểm thử |

## Danh sách công việc

### 00 · Tài liệu

#### DOC-01 — Đề xuất sản phẩm và kiến trúc

- **Trạng thái:** Hoàn tất · **Ưu tiên:** P0
- **Phụ trách:** Codex · **Ước lượng:** Đã làm
- **Phụ thuộc:** Không có
- **Tiêu chí hoàn thành:** Có phương án công nghệ, kỹ thuật quản lý RAM, cơ chế bảo vệ, mockup và lộ trình.
- **Bằng chứng:** MemoryClear-Plan.html: các mục 01–06 đã tạo từ yêu cầu trước.
- **Ghi chú / bước tiếp theo:** Đây là đề xuất; không đồng nghĩa kiến trúc đã được duyệt.
- **Cập nhật:** 2026-10-07

#### DOC-02 — Xuất bản tài liệu HTML offline

- **Trạng thái:** Hoàn tất · **Ưu tiên:** P0
- **Phụ trách:** Codex · **Ước lượng:** Đã làm
- **Phụ thuộc:** DOC-01
- **Tiêu chí hoàn thành:** Có file HTML độc lập, định dạng responsive, nguồn tham khảo và nút in.
- **Bằng chứng:** MemoryClear-Plan.html đã lưu và kiểm tra tồn tại; người dùng đang mở file.
- **Ghi chú / bước tiếp theo:** Không phải ứng dụng MemoryClear đã hoạt động.
- **Cập nhật:** 2026-10-07

#### DOC-03 — Kế hoạch chi tiết và bảng quản lý tiến độ

- **Trạng thái:** Hoàn tất · **Ưu tiên:** P0
- **Phụ trách:** Codex · **Ước lượng:** Đã làm
- **Phụ thuộc:** DOC-02
- **Tiêu chí hoàn thành:** Có task ID, trạng thái, phụ thuộc, tiêu chí, ghi chú, xuất/nhập JSON và hướng dẫn cập nhật.
- **Bằng chứng:** plan/tasks.json, IMPLEMENTATION_PLAN.md, MemoryClear-Plan.html; node plan/check-plan.mjs PASS: đồng bộ dữ liệu, cú pháp JS, status/dependency gates, lọc, escape, xuất/nhập, lưu/khôi phục và lỗi storage.
- **Ghi chú / bước tiếp theo:** Đã kiểm tra logic tự động. Chưa kiểm tra lại hiển thị bằng browser vì công cụ UI lỗi sandbox; đây không phải bằng chứng ứng dụng MemoryClear đã triển khai.
- **Cập nhật:** 2026-10-07

#### HO-00 — Tạo tài liệu handoff và kết thúc phase 00

- **Trạng thái:** Hoàn tất · **Ưu tiên:** P0
- **Phụ trách:** Codex · **Ước lượng:** Đã làm
- **Phụ thuộc:** DOC-01, DOC-02, DOC-03
- **Tiêu chí hoàn thành:** Tạo docs/handoffs/PHASE-00-HANDOFF.md theo TEMPLATE.md: kết quả/task IDs, quyết định, file thay đổi, lệnh và kết quả kiểm tra, tồn tại, bước tiếp theo. Cập nhật status/evidence; gửi link bàn giao. Không đóng phase nếu task bắt buộc chưa đạt.
- **Bằng chứng:** docs/handoffs/PHASE-00-HANDOFF.md; node plan/build-plan.mjs và node plan/check-plan.mjs kiểm tra liên kết, phụ thuộc và logic bảng tiến độ.
- **Ghi chú / bước tiếp theo:** Bàn giao tài liệu đề xuất; chưa triển khai app. Kiểm tra hiển thị trình duyệt vẫn chưa chạy được vì lỗi sandbox.
- **Cập nhật:** 2026-10-07


### 01 · Chốt phạm vi

#### DEC-01 — Chốt OS, công nghệ và hình thức phát hành

- **Trạng thái:** Hoàn tất · **Ưu tiên:** P0
- **Phụ trách:** Codex · **Ước lượng:** Cần chốt
- **Phụ thuộc:** DOC-01, HO-00
- **Tiêu chí hoàn thành:** Ghi quyết định Windows build/kiến trúc CPU cần hỗ trợ, stack, GUI/CLI và portable/installer.
- **Bằng chứng:** Người dùng trả lời: “Làm script PowerShell có GUI trước”. README.md; docs/ARCHITECTURE.md; Windows PowerShell 5.1.26100.8875 + WPF smoke đạt.
- **Ghi chú / bước tiếp theo:** Chọn PowerShell/WPF portable GUI + CLI. Windows 10/11 x64 là mục tiêu kiểm thử, mới xác minh trên Win11 build 26200.
- **Cập nhật:** 2026-10-08

#### DEC-02 — Chốt quyền tự động và danh sách app cần giữ

- **Trạng thái:** Hoàn tất · **Ưu tiên:** P0
- **Phụ trách:** Codex · **Ước lượng:** Cần chốt
- **Phụ thuộc:** HO-00
- **Tiêu chí hoàn thành:** Có cấu hình RAM, app nặng, app bảo vệ và quyền đóng/force kill riêng; chốt admin chỉ khi cần.
- **Bằng chứng:** docs/ARCHITECTURE.md; Get-MCSettings defaults; policy tests đạt.
- **Ghi chú / bước tiếp theo:** Người triển khai chọn defaults an toàn để tiếp tục yêu cầu: thủ công, close trước, force xác nhận, auto tắt; protected/allowlist cá nhân trống. Không tuyên bố người dùng đã chọn app hoặc quyền tự động.
- **Cập nhật:** 2026-10-08

#### DEC-03 — Chốt ngân sách tài nguyên và ma trận nghiệm thu

- **Trạng thái:** Hoàn tất · **Ưu tiên:** P0
- **Phụ trách:** Codex · **Ước lượng:** 0.5–1 ngày
- **Phụ thuộc:** DEC-01, DEC-02, HO-00
- **Tiêu chí hoàn thành:** Ghi máy tham chiếu, mục tiêu CPU/RAM của app, sai lệch số đo, chu kỳ lấy mẫu, số process và kịch bản nghiệm thu.
- **Bằng chứng:** docs/ARCHITECTURE.md; artifacts/monitor-baseline.json có máy tham chiếu và số đo.
- **Ghi chú / bước tiếp theo:** Ngân sách ban đầu: GUI ≤2% CPU toàn máy, ≤250 MB working set; thu nhỏ 10s/mẫu. Mục tiêu nghiệm thu, chưa claim GUI đã đạt. Ma trận Win10/11/DPI/VM còn phải chạy.
- **Cập nhật:** 2026-10-08

#### HO-01 — Tạo tài liệu handoff và kết thúc phase 01

- **Trạng thái:** Hoàn tất · **Ưu tiên:** P0
- **Phụ trách:** Codex · **Ước lượng:** 0.25–0.5 ngày
- **Phụ thuộc:** DEC-01, DEC-02, DEC-03
- **Tiêu chí hoàn thành:** Tạo docs/handoffs/PHASE-01-HANDOFF.md theo TEMPLATE.md: kết quả/task IDs, quyết định, file thay đổi, lệnh và kết quả kiểm tra, tồn tại, bước tiếp theo. Cập nhật status/evidence; gửi link bàn giao. Không đóng phase nếu task bắt buộc chưa đạt.
- **Bằng chứng:** docs/handoffs/PHASE-01-HANDOFF.md
- **Ghi chú / bước tiếp theo:** Handoff ghi rõ lựa chọn người dùng, defaults và giới hạn.
- **Cập nhật:** 2026-10-08


### 02 · Nền tảng

#### BASE-01 — Khởi tạo cấu trúc PowerShell/WPF và kiểm tra nguồn

- **Trạng thái:** Hoàn tất · **Ưu tiên:** P0
- **Phụ trách:** Codex · **Ước lượng:** 0.5–1 ngày
- **Phụ thuộc:** DEC-01, HO-01
- **Tiêu chí hoàn thành:** Tách module core, adapter Win32, XAML/GUI, CLI và tests; không dependency tải ngoài; có lệnh kiểm tra local và CI workflow.
- **Bằng chứng:** app/, MemoryClear.ps1, MemoryClear.Cli.ps1, tests/, .github/workflows/verify.yml. 17/17 tests local.
- **Ghi chú / bước tiếp theo:** CI workflow đã viết nhưng chưa chạy trên GitHub. Không cần .NET SDK.
- **Cập nhật:** 2026-10-08

#### BASE-02 — Định nghĩa contract, danh tính process và capability

- **Trạng thái:** Hoàn tất · **Ưu tiên:** P0
- **Phụ trách:** Codex · **Ước lượng:** 1–1.5 ngày
- **Phụ thuộc:** BASE-01, HO-01
- **Tiêu chí hoàn thành:** Có Identity PID/start time/path/SID/session/critical, Snapshot/Row và ActionResult; unknown/thiếu quyền được biểu diễn rõ; capability Win32 giới hạn theo thao tác.
- **Bằng chứng:** docs/ARCHITECTURE.md; app/Native.cs; app/MemoryClear.Core.psm1; snapshot/policy/stale identity tests.
- **Ghi chú / bước tiếp theo:** Contract PSObject + native handle; CPU null ở mẫu đầu, RAM working set và private riêng.
- **Cập nhật:** 2026-10-08

#### BASE-03 — Cấu hình, migration và log cục bộ

- **Trạng thái:** Hoàn tất · **Ưu tiên:** P1
- **Phụ trách:** Codex · **Ước lượng:** 0.5–1 ngày
- **Phụ thuộc:** BASE-02, HO-01
- **Tiêu chí hoàn thành:** Đọc/ghi cấu hình có schema, ghi nguyên tử, khôi phục khi file lỗi; log giới hạn dung lượng và không lưu command line nhạy cảm mặc định.
- **Bằng chứng:** Get/Save-MCSettings, Write-MCEvent; test round-trip, safe fallback và audit 205→200 event đạt.
- **Ghi chú / bước tiếp theo:** Schema 1; không auto kill; settings/log cục bộ. Đồng thời nhiều GUI/CLI writer chưa nghiệm thu.
- **Cập nhật:** 2026-10-08

#### HO-02 — Tạo tài liệu handoff và kết thúc phase 02

- **Trạng thái:** Hoàn tất · **Ưu tiên:** P0
- **Phụ trách:** Codex · **Ước lượng:** 0.25–0.5 ngày
- **Phụ thuộc:** BASE-01, BASE-02, BASE-03
- **Tiêu chí hoàn thành:** Tạo docs/handoffs/PHASE-02-HANDOFF.md theo TEMPLATE.md: kết quả/task IDs, quyết định, file thay đổi, lệnh và kết quả kiểm tra, tồn tại, bước tiếp theo. Cập nhật status/evidence; gửi link bàn giao. Không đóng phase nếu task bắt buộc chưa đạt.
- **Bằng chứng:** docs/handoffs/PHASE-02-HANDOFF.md; artifacts/tests/results.json 17/17.
- **Ghi chú / bước tiếp theo:** Foundation script đã có; các phase nghiệm thu action vẫn chưa hoàn tất.
- **Cập nhật:** 2026-10-08


### 03 · Quan sát

#### MON-01 — Thu thập RAM/CPU toàn hệ thống trên Windows

- **Trạng thái:** Hoàn tất · **Ưu tiên:** P0
- **Phụ trách:** Codex · **Ước lượng:** 1–1.5 ngày
- **Phụ thuộc:** BASE-02, DEC-03, HO-02
- **Tiêu chí hoàn thành:** Đo total/available RAM, commit/limit, CPU theo delta; mẫu đầu không hiển thị CPU giả; xử lý resume/sleep.
- **Bằng chứng:** app/MemoryClear.Core.psm1, app/Native.cs; snapshot/policy tests, artifacts/monitor-baseline.json.
- **Ghi chú / bước tiếp theo:** Số đo native và dữ liệu process thật; unknown/permission errors không làm hỏng vòng quét.
- **Cập nhật:** 2026-10-08

#### MON-02 — Inventory process và phân loại nguồn gốc

- **Trạng thái:** Hoàn tất · **Ưu tiên:** P0
- **Phụ trách:** Codex · **Ước lượng:** 1–2 ngày
- **Phụ thuộc:** BASE-02, HO-02
- **Tiêu chí hoàn thành:** Đọc tên, PID/start time, user/session, path, service mapping, working set/private memory; process thoát/thiếu quyền không làm lỗi cả vòng quét.
- **Bằng chứng:** app/MemoryClear.Core.psm1, app/Native.cs; snapshot/policy tests, artifacts/monitor-baseline.json.
- **Ghi chú / bước tiếp theo:** Số đo native và dữ liệu process thật; unknown/permission errors không làm hỏng vòng quét.
- **Cập nhật:** 2026-10-08

#### MON-03 — Nhóm ứng dụng, CPU process và lịch sử ngắn

- **Trạng thái:** Hoàn tất · **Ưu tiên:** P1
- **Phụ trách:** Codex · **Ước lượng:** 1–2 ngày
- **Phụ thuộc:** MON-01, MON-02, HO-02
- **Tiêu chí hoàn thành:** CPU chuẩn hóa toàn máy; nhóm app có cơ sở và fallback về process; history có giới hạn; không nhận diện tab browser khi thiếu dữ liệu.
- **Bằng chứng:** app/MemoryClear.Core.psm1, app/Native.cs; snapshot/policy tests, artifacts/monitor-baseline.json.
- **Ghi chú / bước tiếp theo:** Fallback danh sách process; chưa gộp app/tab. CPU delta chuẩn hóa, một snapshot trước nên history hữu hạn.
- **Cập nhật:** 2026-10-08

#### UI-01 — Dashboard, checkbox và thao tác Clear một chạm

- **Trạng thái:** Chờ kiểm tra · **Ưu tiên:** P0
- **Phụ trách:** Codex · **Ước lượng:** 1.5–3 ngày
- **Phụ thuộc:** MON-01, MON-02, HO-02
- **Tiêu chí hoàn thành:** Bảng RAM/CPU có sort/filter, detail và nhãn unknown; cập nhật không đơ UI; keyboard và DPI cơ bản dùng được.
- **Bằng chứng:** app/MainWindow.xaml; MemoryClear.ps1; WPF smoke; tests/Check-Checkboxes.ps1 PASS; artifacts/checkbox-tests.json (Windows PowerShell 5.1). Clear: artifacts/clear-tests.json, artifacts/clear-preview.png. Desktop shortcut: scripts/Create-DesktopShortcut.ps1; artifacts/desktop-shortcut.json Verified=true (PowerShell 5.1; not launched). Public snapshots: docs/verification/ (historical local checks, not new CI).
- **Ghi chú / bước tiếp theo:** Checkbox có test hồi quy. Clear có progress bar/count, thời gian/trạng thái kết thúc, Strong opt-in và khóa mode khi chạy; test WPF offscreen đã đạt. Còn tương tác thực, DPI/keyboard và ma trận Windows; giữ review. Đã tạo MemoryClear.lnk trên Desktop thật/OneDrive và xác minh command; chờ người dùng mở từ đó.
- **Cập nhật:** 2026-10-08

#### CLEAR-01 — Clear một chạm, tiến trình và mức mạnh hơn

- **Trạng thái:** Chờ kiểm tra · **Ưu tiên:** P0
- **Phụ trách:** Codex · **Ước lượng:** Bổ sung theo yêu cầu
- **Phụ thuộc:** MON-01, MON-02, BASE-03, HO-02
- **Tiêu chí hoàn thành:** Không cần chọn process; progress quét/xử lý có count/thời gian thật, terminal success/cancel/timeout/error/cooldown rõ ràng; Normal/Strong có giới hạn và cùng bảo vệ. Fresh policy/identity/CPU/foreground, hủy được, không close/kill; báo RAM trước/sau và giới hạn commit/RAM nạp lại; fixture/VM UX và hiệu năng được kiểm chứng.
- **Bằng chứng:** MemoryClear.ps1; app/MemoryClear.Clear.psm1; clear-policy schemaVersion 2; tests/Check-Clear.ps1 PASS 12/12 trên PowerShell 5.1.26100.8875; artifacts/clear-tests.json; artifacts/clear-preview.png.
- **Ghi chú / bước tiếp theo:** Đã có progress queue từ worker thật, spinner khi quét, count khi xử lý, thời lượng/giờ hoàn tất và trạng thái dừng/lỗi/cooldown riêng. Strong opt-in: 32 process/60 giây/32 MB/CPU 1%/target 35%/cooldown 120 giây, giữ mọi bảo vệ. Test chỉ trim fixture, không app công việc. Chưa nghiệm thu VM pressure/foreground/cancel/page faults, Windows 10 hoặc overhead GUI; giữ review.
- **Cập nhật:** 2026-10-08

#### QA-01 — Đối chiếu số liệu và đo overhead baseline

- **Trạng thái:** Chờ kiểm tra · **Ưu tiên:** P0
- **Phụ trách:** Codex · **Ước lượng:** 1–2 ngày
- **Phụ thuộc:** MON-03, UI-01, DEC-03, HO-02
- **Tiêu chí hoàn thành:** Báo cáo trên máy tham chiếu: idle/load, nhiều process, thu nhỏ/mở; so sánh cùng loại metric và thời điểm với công cụ OS trong ngưỡng đã chốt.
- **Bằng chứng:** artifacts/monitor-baseline.json: 4 mẫu, total/available RAM đối chiếu CIM; collector 1.23% CPU, 97.6 MB working set.
- **Ghi chú / bước tiếp theo:** Chưa phải overhead toàn GUI/soak, tải/thu nhỏ hoặc Windows 10; phase chưa đủ nghiệm thu. Snapshot GUI smoke hiện lưu: 19 controls/394 rows/255.5 MB, trước Clear controls; chưa đạt budget và cần đo lại. docs/verification/gui-smoke.json.
- **Cập nhật:** 2026-10-08

#### HO-03 — Tạo tài liệu handoff và kết thúc phase 03

- **Trạng thái:** Chờ kiểm tra · **Ưu tiên:** P0
- **Phụ trách:** Codex · **Ước lượng:** 0.25–0.5 ngày
- **Phụ thuộc:** MON-01, MON-02, MON-03, UI-01, QA-01, CLEAR-01
- **Tiêu chí hoàn thành:** Tạo docs/handoffs/PHASE-03-HANDOFF.md theo TEMPLATE.md: kết quả/task IDs, quyết định, file thay đổi, lệnh và kết quả kiểm tra, tồn tại, bước tiếp theo. Cập nhật status/evidence; gửi link bàn giao. Không đóng phase nếu task bắt buộc chưa đạt.
- **Bằng chứng:** docs/handoffs/PHASE-03-HANDOFF.md (nháp); Handoff.md; artifacts/clear-tests.json; node plan/build-plan.mjs + node plan/check-plan.mjs.
- **Ghi chú / bước tiếp theo:** Handoff nháp cập nhật tiến trình Clear và Strong, có báo cáo 12 kiểm tra. UI-01/CLEAR-01/QA-01 còn nghiệm thu; phase 03 chưa hoàn tất.
- **Cập nhật:** 2026-10-08


### 04 · Bảo vệ

#### SAFE-01 — Policy bảo vệ theo nhiều tín hiệu

- **Trạng thái:** Chưa bắt đầu · **Ưu tiên:** P0
- **Phụ trách:** Chưa phân công · **Ước lượng:** 1.5–2.5 ngày
- **Phụ thuộc:** MON-02, DEC-02, HO-03
- **Tiêu chí hoàn thành:** Chặn system/service/security/login, session khác, chính app và helper; unknown bị chặn tự động; allowlist không vượt quy tắc chặn cứng.
- **Bằng chứng:** Chưa có
- **Ghi chú / bước tiếp theo:** Không chỉ dựa vào tên process; policy kiểm tra cả GUI và CLI. Source preview đã có trong module/GUI/CLI, chưa coi là nghiệm thu phase; tiếp tục theo gate khi HO-03 hoàn tất.
- **Cập nhật:** 2026-10-07

#### SAFE-02 — Quản lý app được bảo vệ và app được phép đóng

- **Trạng thái:** Chưa bắt đầu · **Ưu tiên:** P0
- **Phụ trách:** Chưa phân công · **Ước lượng:** 1–1.5 ngày
- **Phụ thuộc:** SAFE-01, BASE-03, UI-01, HO-03
- **Tiêu chí hoàn thành:** Chỉnh và lưu quy tắc theo danh tính phù hợp; close/force permission tách biệt; UI giải thích vì sao được phép hoặc bị chặn.
- **Bằng chứng:** Chưa có
- **Ghi chú / bước tiếp theo:** Đổi executable hoặc thiếu xác minh phải kiểm tra lại quyền đã cấp. Source preview đã có trong module/GUI/CLI, chưa coi là nghiệm thu phase; tiếp tục theo gate khi HO-03 hoàn tất.
- **Cập nhật:** 2026-10-07

#### SAFE-03 — Chống PID tái sử dụng và phương án hết hạn

- **Trạng thái:** Chưa bắt đầu · **Ưu tiên:** P0
- **Phụ trách:** Chưa phân công · **Ước lượng:** 1–2 ngày
- **Phụ thuộc:** SAFE-01, BASE-02, HO-03
- **Tiêu chí hoàn thành:** Revalidate identity và policy ngay trước thao tác; dùng handle ổn định; thay đổi identity/target set thì hủy hoặc lập lại phương án.
- **Bằng chứng:** Chưa có
- **Ghi chú / bước tiếp theo:** Không giữ PID rồi kill mù; không mặc định mở rộng cả cây process. Source preview đã có trong module/GUI/CLI, chưa coi là nghiệm thu phase; tiếp tục theo gate khi HO-03 hoàn tất.
- **Cập nhật:** 2026-10-07

#### SAFE-04 — Kiểm thử âm tính và race condition của policy

- **Trạng thái:** Chưa bắt đầu · **Ưu tiên:** P0
- **Phụ trách:** Chưa phân công · **Ước lượng:** 1–2 ngày
- **Phụ thuộc:** SAFE-02, SAFE-03, HO-03
- **Tiêu chí hoàn thành:** Test giả lập protected/unknown, PID đổi, thiếu quyền, process biến mất, tên giả, descendant chưa duyệt; không có lệnh tác động mục tiêu bị chặn.
- **Bằng chứng:** Chưa có
- **Ghi chú / bước tiếp theo:** Gate bắt buộc trước nghiệm thu hành động thực. Source preview đã có trong module/GUI/CLI, chưa coi là nghiệm thu phase; tiếp tục theo gate khi HO-03 hoàn tất.
- **Cập nhật:** 2026-10-07

#### HO-04 — Tạo tài liệu handoff và kết thúc phase 04

- **Trạng thái:** Chưa bắt đầu · **Ưu tiên:** P0
- **Phụ trách:** Người hoàn tất phase · **Ước lượng:** 0.25–0.5 ngày
- **Phụ thuộc:** SAFE-01, SAFE-02, SAFE-03, SAFE-04
- **Tiêu chí hoàn thành:** Tạo docs/handoffs/PHASE-04-HANDOFF.md theo TEMPLATE.md: kết quả/task IDs, quyết định, file thay đổi, lệnh và kết quả kiểm tra, tồn tại, bước tiếp theo. Cập nhật status/evidence; gửi link bàn giao. Không đóng phase nếu task bắt buộc chưa đạt.
- **Bằng chứng:** Chưa có
- **Ghi chú / bước tiếp theo:** Nếu tạm dừng trước khi xong phase, viết handoff nháp và giữ doing/review. Không cần xin phép riêng để tạo tài liệu handoff.
- **Cập nhật:** 2026-10-07


### 05 · Thao tác thủ công

#### ACT-01 — Đóng bình thường với timeout và hủy chờ

- **Trạng thái:** Chưa bắt đầu · **Ưu tiên:** P0
- **Phụ trách:** Chưa phân công · **Ước lượng:** 1–1.5 ngày
- **Phụ thuộc:** SAFE-03, SAFE-04, HO-04
- **Tiêu chí hoàn thành:** Gửi yêu cầu đóng hợp lệ, chờ bất đồng bộ, trả kết quả refused/timeout/exited; hộp thoại lưu không tự chuyển sang force kill.
- **Bằng chứng:** Chưa có
- **Ghi chú / bước tiếp theo:** Hủy chờ không hoàn tác lệnh đóng đã gửi. Source preview đã có trong module/GUI/CLI, chưa coi là nghiệm thu phase; tiếp tục theo gate khi HO-03 hoàn tất.
- **Cập nhật:** 2026-10-07

#### ACT-02 — Force kill với xác nhận đúng mục tiêu

- **Trạng thái:** Chưa bắt đầu · **Ưu tiên:** P0
- **Phụ trách:** Chưa phân công · **Ước lượng:** 1–1.5 ngày
- **Phụ thuộc:** ACT-01, HO-04
- **Tiêu chí hoàn thành:** Hiện đúng app/PID/phạm vi và mất dữ liệu chưa lưu; kiểm tra lại quyền; chờ xác minh đã kết thúc; không báo thành công chỉ vì gửi lệnh.
- **Bằng chứng:** Chưa có
- **Ghi chú / bước tiếp theo:** Không hỗ trợ force kill thành phần hệ thống trong MVP. Source preview đã có trong module/GUI/CLI, chưa coi là nghiệm thu phase; tiếp tục theo gate khi HO-03 hoàn tất.
- **Cập nhật:** 2026-10-07

#### ACT-03 — Giới hạn quyền người dùng và đánh giá nhu cầu helper

- **Trạng thái:** Chưa bắt đầu · **Ưu tiên:** P0
- **Phụ trách:** Codex · **Ước lượng:** 1.5–3 ngày
- **Phụ thuộc:** ACT-02, DEC-02, HO-04
- **Tiêu chí hoàn thành:** GUI chạy user thường; target thiếu quyền bị chặn, không bypass OS protection. Nếu scope sau cần helper: xác thực caller/target và policy, helper thoát khi xong.
- **Bằng chứng:** Chưa có
- **Ghi chú / bước tiếp theo:** Bản PowerShell không có helper/admin; thiếu quyền trả Denied. Nghiệm thu quyền trên môi trường user thường vẫn còn.
- **Cập nhật:** 2026-10-08

#### ACT-04 — CLI dùng chung policy và executor

- **Trạng thái:** Chưa bắt đầu · **Ưu tiên:** P1
- **Phụ trách:** Chưa phân công · **Ước lượng:** 1–1.5 ngày
- **Phụ thuộc:** ACT-02, BASE-03, HO-04
- **Tiêu chí hoàn thành:** list/inspect/plan/close/kill có help, exit code và JSON output; dry-run mặc định cho phương án; không có đường tắt bỏ policy.
- **Bằng chứng:** Chưa có
- **Ghi chú / bước tiếp theo:** Tên process không được nội suy thành shell command. Source preview đã có trong module/GUI/CLI, chưa coi là nghiệm thu phase; tiếp tục theo gate khi HO-03 hoàn tất.
- **Cập nhật:** 2026-10-07

#### QA-02 — Nghiệm thu hành động trong máy ảo

- **Trạng thái:** Chưa bắt đầu · **Ưu tiên:** P0
- **Phụ trách:** Chưa phân công · **Ước lượng:** 1–2 ngày
- **Phụ thuộc:** ACT-03, ACT-04, SAFE-04, HO-04
- **Tiêu chí hoàn thành:** App thử bình thường/treo/chưa lưu, timeout, deny access và protected target; GUI/CLI cùng kết quả policy; lưu log và báo cáo.
- **Bằng chứng:** Chưa có
- **Ghi chú / bước tiếp theo:** Không thử kill trên công việc thật của người dùng.
- **Cập nhật:** 2026-10-07

#### HO-05 — Tạo tài liệu handoff và kết thúc phase 05

- **Trạng thái:** Chưa bắt đầu · **Ưu tiên:** P0
- **Phụ trách:** Người hoàn tất phase · **Ước lượng:** 0.25–0.5 ngày
- **Phụ thuộc:** ACT-01, ACT-02, ACT-03, ACT-04, QA-02
- **Tiêu chí hoàn thành:** Tạo docs/handoffs/PHASE-05-HANDOFF.md theo TEMPLATE.md: kết quả/task IDs, quyết định, file thay đổi, lệnh và kết quả kiểm tra, tồn tại, bước tiếp theo. Cập nhật status/evidence; gửi link bàn giao. Không đóng phase nếu task bắt buộc chưa đạt.
- **Bằng chứng:** Chưa có
- **Ghi chú / bước tiếp theo:** Nếu tạm dừng trước khi xong phase, viết handoff nháp và giữ doing/review. Không cần xin phép riêng để tạo tài liệu handoff.
- **Cập nhật:** 2026-10-07


### 06 · Giải phóng khẩn cấp

#### EMG-01 — Planner theo mục tiêu RAM và thứ tự cho phép

- **Trạng thái:** Chưa bắt đầu · **Ưu tiên:** P0
- **Phụ trách:** Chưa phân công · **Ước lượng:** 1–2 ngày
- **Phụ thuộc:** QA-01, QA-02, HO-05
- **Tiêu chí hoàn thành:** Chỉ chọn allowlist, tôn trọng bảo vệ; preview từng thao tác; ước lượng không cộng trùng RAM; phương án có thời hạn và identity.
- **Bằng chứng:** Chưa có
- **Ghi chú / bước tiếp theo:** Mục tiêu là available RAM; không cam kết đủ tài nguyên nếu hết ứng viên. Source preview đã có trong module/GUI/CLI, chưa coi là nghiệm thu phase; tiếp tục theo gate khi HO-03 hoàn tất.
- **Cập nhật:** 2026-10-07

#### EMG-02 — Thực thi tuần tự, dừng và đo lại

- **Trạng thái:** Chưa bắt đầu · **Ưu tiên:** P0
- **Phụ trách:** Chưa phân công · **Ước lượng:** 1–2 ngày
- **Phụ thuộc:** EMG-01, HO-05
- **Tiêu chí hoàn thành:** Một operation tại một thời điểm, revalidate từng target; dừng khi đủ/hết ứng viên/hủy; cancel chỉ ngăn lệnh tiếp theo; force chỉ theo quyền đã chốt.
- **Bằng chứng:** Chưa có
- **Ghi chú / bước tiếp theo:** Không tự force kill app đang đợi lưu trong cấu hình thủ công. Source preview đã có trong module/GUI/CLI, chưa coi là nghiệm thu phase; tiếp tục theo gate khi HO-03 hoàn tất.
- **Cập nhật:** 2026-10-07

#### EMG-03 — Màn hình preview, tiến độ và kết quả khẩn cấp

- **Trạng thái:** Chưa bắt đầu · **Ưu tiên:** P1
- **Phụ trách:** Chưa phân công · **Ước lượng:** 1–1.5 ngày
- **Phụ thuộc:** EMG-02, UI-01, HO-05
- **Tiêu chí hoàn thành:** Hiện ứng viên, hành động, cảnh báo, kết quả từng app, available RAM trước/sau và lý do dừng; không hiển thị nút Undo gây hiểu nhầm.
- **Bằng chứng:** Chưa có
- **Ghi chú / bước tiếp theo:** Phân biệt app đã thoát với RAM toàn máy thay đổi do tác vụ khác. Source preview đã có trong module/GUI/CLI, chưa coi là nghiệm thu phase; tiếp tục theo gate khi HO-03 hoàn tất.
- **Cập nhật:** 2026-10-07

#### QA-03 — Kiểm thử áp lực RAM và các điều kiện dừng

- **Trạng thái:** Chưa bắt đầu · **Ưu tiên:** P0
- **Phụ trách:** Chưa phân công · **Ước lượng:** 1–2 ngày
- **Phụ thuộc:** EMG-03, HO-05
- **Tiêu chí hoàn thành:** Trong VM: đủ RAM giữa chừng, không đủ ứng viên, app tự khởi động lại, target đổi, cancel, app treo và RAM dao động; UI còn phản hồi.
- **Bằng chứng:** Chưa có
- **Ghi chú / bước tiếp theo:** Gate bắt buộc trước đóng gói MVP.
- **Cập nhật:** 2026-10-07

#### HO-06 — Tạo tài liệu handoff và kết thúc phase 06

- **Trạng thái:** Chưa bắt đầu · **Ưu tiên:** P0
- **Phụ trách:** Người hoàn tất phase · **Ước lượng:** 0.25–0.5 ngày
- **Phụ thuộc:** EMG-01, EMG-02, EMG-03, QA-03
- **Tiêu chí hoàn thành:** Tạo docs/handoffs/PHASE-06-HANDOFF.md theo TEMPLATE.md: kết quả/task IDs, quyết định, file thay đổi, lệnh và kết quả kiểm tra, tồn tại, bước tiếp theo. Cập nhật status/evidence; gửi link bàn giao. Không đóng phase nếu task bắt buộc chưa đạt.
- **Bằng chứng:** Chưa có
- **Ghi chú / bước tiếp theo:** Nếu tạm dừng trước khi xong phase, viết handoff nháp và giữ doing/review. Không cần xin phép riêng để tạo tài liệu handoff.
- **Cập nhật:** 2026-10-07


### 07 · Phát hành MVP

#### REL-01 — Đóng gói portable và tài liệu vận hành

- **Trạng thái:** Chưa bắt đầu · **Ưu tiên:** P0
- **Phụ trách:** Chưa phân công · **Ước lượng:** 1–2 ngày
- **Phụ thuộc:** QA-03, HO-06
- **Tiêu chí hoàn thành:** Có artifact theo kiến trúc đã chốt, version/checksum, README chạy/quyền/giới hạn, đường dẫn settings/log; không tự thêm startup/service.
- **Bằng chứng:** Chưa có
- **Ghi chú / bước tiếp theo:** Quyết định ký số và kênh phân phối được ghi rõ, không tuyên bố đã ký nếu chưa làm.
- **Cập nhật:** 2026-10-07

#### REL-02 — Ma trận Windows và benchmark cuối

- **Trạng thái:** Chưa bắt đầu · **Ưu tiên:** P0
- **Phụ trách:** Chưa phân công · **Ước lượng:** 1.5–3 ngày
- **Phụ thuộc:** REL-01, DEC-03, HO-06
- **Tiêu chí hoàn thành:** Chạy trên Windows 10/11 build đã chọn, user thường/admin khi cần, DPI, locale, không có runtime cài sẵn; đo overhead và soak test có thời lượng ghi rõ.
- **Bằng chứng:** Chưa có
- **Ghi chú / bước tiếp theo:** Không claim tương thích các build chưa được kiểm chứng.
- **Cập nhật:** 2026-10-07

#### REL-03 — Người dùng nghiệm thu và chốt bản đầu

- **Trạng thái:** Chưa bắt đầu · **Ưu tiên:** P0
- **Phụ trách:** Người dùng + người triển khai · **Ước lượng:** Chờ lịch nghiệm thu
- **Phụ thuộc:** REL-02, HO-06
- **Tiêu chí hoàn thành:** Chạy kịch bản đã chốt, không còn lỗi P0/P1 ảnh hưởng bảo vệ, ghi lỗi còn lại và xác nhận phát hành.
- **Bằng chứng:** Chưa có
- **Ghi chú / bước tiếp theo:** App build được chưa đủ để đánh dấu phát hành hoàn tất.
- **Cập nhật:** 2026-10-07

#### HO-07 — Tạo tài liệu handoff và kết thúc phase 07

- **Trạng thái:** Chưa bắt đầu · **Ưu tiên:** P0
- **Phụ trách:** Người hoàn tất phase · **Ước lượng:** 0.25–0.5 ngày
- **Phụ thuộc:** REL-01, REL-02, REL-03
- **Tiêu chí hoàn thành:** Tạo docs/handoffs/PHASE-07-HANDOFF.md theo TEMPLATE.md: kết quả/task IDs, quyết định, file thay đổi, lệnh và kết quả kiểm tra, tồn tại, bước tiếp theo. Cập nhật status/evidence; gửi link bàn giao. Không đóng phase nếu task bắt buộc chưa đạt.
- **Bằng chứng:** Chưa có
- **Ghi chú / bước tiếp theo:** Nếu tạm dừng trước khi xong phase, viết handoff nháp và giữ doing/review. Không cần xin phép riêng để tạo tài liệu handoff.
- **Cập nhật:** 2026-10-07


### 08 · Mở rộng

#### EXT-01 — Linux adapter và capability theo distro

- **Trạng thái:** Để sau · **Ưu tiên:** P1
- **Phụ trách:** Chưa phân công · **Ước lượng:** Ước lượng sau khi chốt distro
- **Phụ thuộc:** REL-03, HO-07
- **Tiêu chí hoàn thành:** Chốt distro/kernel/session; đọc /proc và PSS khi có quyền; SIGTERM/SIGKILL, pidfd nếu hỗ trợ; bảo vệ PID 1/session/service/cgroup.
- **Bằng chứng:** Chưa có
- **Ghi chú / bước tiếp theo:** Fallback không đảm bảo danh tính thì chặn thao tác; không kill cả cgroup/session mặc định.
- **Cập nhật:** 2026-10-07

#### EXT-02 — Đóng gói và nghiệm thu desktop Linux

- **Trạng thái:** Để sau · **Ưu tiên:** P1
- **Phụ trách:** Chưa phân công · **Ước lượng:** Ước lượng sau khi chốt distro
- **Phụ thuộc:** EXT-01, HO-07
- **Tiêu chí hoàn thành:** Kiểm tra X11/Wayland theo phạm vi, quyền user, dependency, GUI/CLI và policy trong VM; có gói và hướng dẫn.
- **Bằng chứng:** Chưa có
- **Ghi chú / bước tiếp theo:** Không dùng sudo toàn app và không drop_caches mặc định.
- **Cập nhật:** 2026-10-07

#### EXT-03 — Tự xử lý theo ngưỡng có hysteresis/cooldown

- **Trạng thái:** Để sau · **Ưu tiên:** P2
- **Phụ trách:** Chưa phân công · **Ước lượng:** Cần chốt riêng
- **Phụ thuộc:** REL-03, DEC-02, HO-07
- **Tiêu chí hoàn thành:** Opt-in, allowlist, ngưỡng kéo dài, hysteresis/cooldown, giới hạn số thao tác, audit và nút tắt; không force khi chưa cấp quyền.
- **Bằng chứng:** Chưa có
- **Ghi chú / bước tiếp theo:** Không dùng phần trăm RAM đơn lẻ làm tín hiệu duy nhất.
- **Cập nhật:** 2026-10-07

#### EXT-04 — Trim và giảm ưu tiên CPU tùy chọn

- **Trạng thái:** Để sau · **Ưu tiên:** P2
- **Phụ trách:** Chưa phân công · **Ước lượng:** Cần benchmark riêng
- **Phụ thuộc:** REL-03, HO-07
- **Tiêu chí hoàn thành:** Chỉ target đủ điều kiện; UI giải thích tác dụng; benchmark trước/sau và khả năng RAM tăng lại; không quảng cáo suspend là dọn RAM.
- **Bằng chứng:** Chưa có
- **Ghi chú / bước tiếp theo:** Clear trim được đưa vào preview hiện tại theo yêu cầu 2026-10-08 (CLEAR-01). Task mở rộng này vẫn để sau cho benchmark sâu/giảm ưu tiên CPU; không purge cache hay tắt bảo mật.
- **Cập nhật:** 2026-10-07

#### HO-08 — Tạo tài liệu handoff và kết thúc phase 08

- **Trạng thái:** Để sau · **Ưu tiên:** P0
- **Phụ trách:** Người hoàn tất phase · **Ước lượng:** 0.25–0.5 ngày
- **Phụ thuộc:** EXT-01, EXT-02, EXT-03, EXT-04
- **Tiêu chí hoàn thành:** Tạo docs/handoffs/PHASE-08-HANDOFF.md theo TEMPLATE.md: kết quả/task IDs, quyết định, file thay đổi, lệnh và kết quả kiểm tra, tồn tại, bước tiếp theo. Cập nhật status/evidence; gửi link bàn giao. Không đóng phase nếu task bắt buộc chưa đạt.
- **Bằng chứng:** Chưa có
- **Ghi chú / bước tiếp theo:** Nếu tạm dừng trước khi xong phase, viết handoff nháp và giữ doing/review. Không cần xin phép riêng để tạo tài liệu handoff.
- **Cập nhật:** 2026-10-07
