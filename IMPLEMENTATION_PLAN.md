# MemoryClear — Kế hoạch triển khai

Phiên bản: 2026-10-11.2. Cập nhật: 2026-10-11 (Asia/Tokyo).

Windows11/PS5.1 portable preview. Clear Normal/Strong và Dọn Temp có duyệt đã có chức năng thật; không tự kill hoặc xóa dữ liệu app tùy ý. Memory3: saved executable opt-in, native PID/start/window/exe fingerprint, frozen plan/TTL/permission revalidation, graceful-only executor và worker/progress/cancel/journal đã chuẩn bị. QA chỉ đóng app thử nghiệm mới tạo; không sửa settings hoặc đóng app người dùng. Shipped executionEnabled=false giữ gate SAFE-04/QA-02 chưa đủ; không tự force. Windows10/VM, human DPI/save-dialog, orphan appdata production và backup khác ổ chưa nghiệm thu. Bộ portable có script build/checksum/manifest, không kèm .data. Phase10/12 chưa hoàn tất; mọi handoff/status phản ánh giới hạn thực tế.

## Trạng thái tổng quan

**Quy định bắt buộc:** Cuối mỗi phase bắt buộc tạo docs/handoffs/PHASE-XX-HANDOFF.md theo TEMPLATE.md, cập nhật evidence của HO-XX và gửi link cho người dùng. Phase chỉ hoàn tất khi task và handoff đã hoàn tất. Nếu dừng giữa chừng, viết bản nháp và giữ trạng thái chưa hoàn tất.

Mẫu: [TEMPLATE.md](docs/handoffs/TEMPLATE.md). Bàn giao hiện có: [Phase 00](docs/handoffs/PHASE-00-HANDOFF.md). Quy trình tiếp tục: [AGENTS.md](AGENTS.md). Các phase chưa hoàn thành chỉ có task handoff; không tạo báo cáo giả cho công việc chưa làm.

- Tài liệu: 14/14 task hoàn tất.
- MVP Windows: 14/52 task hoàn tất.
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
- **Phụ trách:** Codex · **Ước lượng:** 1–2 ngày
- **Phụ thuộc:** QA-03, HO-06
- **Tiêu chí hoàn thành:** Có artifact theo kiến trúc đã chốt, version/checksum, README chạy/quyền/giới hạn, đường dẫn settings/log; không tự thêm startup/service.
- **Bằng chứng:** scripts/Build-Portable.ps1; docs/verification/portable-build.json khi build hoàn tất; docs/verification/portable-build.json (55 files, packaged WPF/native smoke + ZIP SHA256 entries Passed); source 57fb2d2 main + GitHub Actions 38106638093 success, docs/verification/github-actions-portable.json
- **Ghi chú / bước tiếp theo:** Portable preview được user yêu cầu build trực tiếp. Không là nghiệm thu release/gates/phụ thuộc hoặc binary signing/Win10. Không chứa .data/harness/secrets. Bộ portable preview 2026.10.11.1 đã build; shortcut Desktop readback verified, chưa launch GUI từ shortcut; không là full release acceptance. Publication/CI verified; status phase/full release không đổi vì các dependency/nghiệm thu còn thiếu.
- **Cập nhật:** 2026-10-11

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


### 09 · Clean Data — thiết kế

#### CD-DES01 — Ba mức, catalogue và kiến trúc Clean Data

- **Trạng thái:** Hoàn tất · **Ưu tiên:** P0
- **Phụ trách:** Codex · **Ước lượng:** Đã làm
- **Phụ thuộc:** DOC-02
- **Tiêu chí hoàn thành:** Có retention, ownership, quyền UAC, manifest/revalidate, backup/restore, metrics và gate triển khai.
- **Bằng chứng:** docs/CLEAN_DATA_ARCHITECTURE.md; plan/clean-data-design.json + schema.
- **Ghi chú / bước tiếp theo:** Thiết kế; retention/helper trust/backup destination chưa do người dùng chốt.
- **Cập nhật:** 2026-10-09

#### CD-DES02 — Plan HTML và prototype tương tác offline

- **Trạng thái:** Hoàn tất · **Ưu tiên:** P0
- **Phụ trách:** Codex · **Ước lượng:** 0.5 ngày
- **Phụ thuộc:** CD-DES01
- **Tiêu chí hoàn thành:** HTML đẹp responsive; mô phỏng scan/ba mức/review/backup/manifest/progress/cancel/history; cờ simulated, không đọc/xóa FS.
- **Bằng chứng:** MemoryClear-CleanData-Plan.html + MemoryClear-CleanData-Prototype.html; plan/build-clean-data.mjs; 13/13 design/model/DOM checks. Browser visual QA blocked by file:// policy and documented, not claimed passed.
- **Ghi chú / bước tiếp theo:** Code Clean thật chưa tích hợp vào GUI PowerShell.
- **Cập nhật:** 2026-10-09

#### CD-DES03 — Kiểm chứng contract và luồng prototype

- **Trạng thái:** Hoàn tất · **Ưu tiên:** P0
- **Phụ trách:** Codex · **Ước lượng:** 0.5 ngày
- **Phụ thuộc:** CD-DES02
- **Tiêu chí hoàn thành:** Schema, protected/default/review/admin/busy/TTL/backup/unknown tests; verify JS/HTML/tracker; ghi giới hạn browser và runtime thật.
- **Bằng chứng:** node plan/check-clean-data.mjs 13/13; docs/verification/clean-data-design-checks.json. node plan/build-plan.mjs + node plan/check-plan.mjs PASS source/HTML/gates/import/export. PS5.1.26100.9444 launcher AST parse PASS (not executed). No real FS/UAC/VM/restore/visual browser checks.
- **Ghi chú / bước tiếp theo:** —
- **Cập nhật:** 2026-10-09

#### HO-09 — Handoff kết thúc phase thiết kế Clean Data

- **Trạng thái:** Hoàn tất · **Ưu tiên:** P0
- **Phụ trách:** Codex · **Ước lượng:** 0.25 ngày
- **Phụ thuộc:** CD-DES01, CD-DES02, CD-DES03, CD-DES04, CD-DES05
- **Tiêu chí hoàn thành:** docs/handoffs/PHASE-09-HANDOFF.md theo TEMPLATE.md; evidence task/checks; không coi design-only là executor phát hành.
- **Bằng chứng:** docs/handoffs/PHASE-09-HANDOFF.md cập nhật09.2, CD-DES04/05 complete,18 Disk checks + plan build/check PASS; root Handoff updated. Runtime phase10 still pending.
- **Ghi chú / bước tiếp theo:** —
- **Cập nhật:** 2026-10-09

#### CD-DES04 — Policy cảnh báo theo risk, app đã gỡ và file lớn

- **Trạng thái:** Hoàn tất · **Ưu tiên:** P0
- **Phụ trách:** Codex · **Ước lượng:** 0.5–1 ngày
- **Phụ thuộc:** CD-DES01
- **Tiêu chí hoàn thành:** Safe trực tiếp không popup; danger hai bước, protected không override; verified cache/empty app đã gỡ; large finder age/size/filter chỉ đề xuất.
- **Bằng chứng:** docs/CLEAN_DATA_ARCHITECTURE.md mục9; plan/clean-data-design.json v2 + schema; safe/review/danger/blocked, verified removed cache/empty, large finder readonly; plan HTML updated.
- **Ghi chú / bước tiếp theo:** Thiết kế/prototype không là evidence hành động thật.
- **Cập nhật:** 2026-10-09

#### CD-DES05 — Prototype Disk mới và kiểm chứng risk gates

- **Trạng thái:** Hoàn tất · **Ưu tiên:** P0
- **Phụ trách:** Codex · **Ước lượng:** 0.5–1 ngày
- **Phụ thuộc:** CD-DES04, CD-DES02
- **Tiêu chí hoàn thành:** Không warning cho safe; risky selected-only, dangerous typed confirmation, blocked cannot override; file lớn không auto chọn; progress/cancel/history đúng.
- **Bằng chứng:** node plan/check-clean-data.mjs 18/18 PASS; docs/verification/clean-data-design-checks.json; safe direct/no-popup, selected risky warning, dangerous phrase, large filter/no-auto-select, backup-zero and blocked gates. Visual/native checks unverified.
- **Ghi chú / bước tiếp theo:** Thiết kế/prototype không là evidence hành động thật.
- **Cập nhật:** 2026-10-09


### 10 · Clean Data — triển khai

#### CD-SCOPE — Chốt retention, backup và trust privileged helper

- **Trạng thái:** Hoàn tất · **Ưu tiên:** P0
- **Phụ trách:** Codex · **Ước lượng:** 0.25–0.5 ngày
- **Phụ thuộc:** HO-09
- **Tiêu chí hoàn thành:** Chốt ba mức và rule retention; backup destination; helper ký/cài protected hoặc OS delegation; không bypass UAC.
- **Bằng chứng:** User reply trực tiếp: Portable + Windows xử lý mục hệ thống; Cho xóa vĩnh viễn sau hai bước duyệt. Giữ retention7/14/3 theo design; không cài elevated helper; chưa tự chọn app/file cá nhân. Runtime policy app/clean-data-policy.json.
- **Ghi chú / bước tiếp theo:** User xác nhận chỉ có Windows11 hiện tại. Tiếp tục local Win11; không ghi coverage Windows10/VM và không hỏi lại có VM. Portable + Windows system delegation, permanent data qua hai bước duyệt giữ nguyên. Đã duyệt triển khai; không yêu cầu user confirm lại phương án. Production permanent cần đúng item/scope approval và guards, chưa mở từ HTML/scan.
- **Cập nhật:** 2026-10-10

#### CD-01 — Scanner readonly có identity và scope guard

- **Trạng thái:** Hoàn tất · **Ưu tiên:** P0
- **Phụ trách:** Codex · **Ước lượng:** 1.5–2 ngày
- **Phụ thuộc:** CD-SCOPE, HO-02
- **Tiêu chí hoàn thành:** OS-volume/SID/KnownFolder, streaming/paging, allocated size/dedupe; không follow reparse/cloud/UNC; permission unknown không zero; test/đo RAM.
- **Bằng chứng:** Native FileID/ancestor/allocated scan/paging/filters + ProbeDirectory; Inventory18/18 + AppProfiles16/16 fixtures PS5.1.26100.9444. Latest inventory WS90.4MB, no real user cleanup.
- **Ghi chú / bước tiếp theo:** Scanner readonly đạt local fixtures; unsupported longpath báo Partial. Số WS là snapshot, không GUI/VM/soak benchmark.
- **Cập nhật:** 2026-10-09

#### CD-02 — Inventory app và evidence dữ liệu còn sót

- **Trạng thái:** Chờ kiểm tra · **Ưu tiên:** P0
- **Phụ trách:** Codex · **Ước lượng:** 1–2 ngày
- **Phụ thuộc:** CD-01
- **Tiêu chí hoàn thành:** HKCU/HKLM 32/64/MSIX/portable/shared/vendor; không Win32_Product; appdata unknown protected, ứng viên cần user review. App removed cache/empty chỉ safe khi owner/no-live-dependency/dataClass xác minh; mixed/user data review.
- **Bằng chứng:** OwnerHistory.ps1 + native ObservationStore và policy/payload schemas: metadata observations with UTC/source/InstallationId/version, SID/catalog/root binding, expiry/future/corrupt/locked/junction/hardlink guards, never uninstall/deletion authority. History17/17 + Ownership13/13 + AppProfiles16/16 fixtures PS5.1.26100.9444. docs/CLEAN_DATA_OWNER_HISTORY.md; disk-owner-history-tests.json.
- **Ghi chú / bước tiếp theo:** Lịch sử local là supporting evidence, checksum không chống giả mạo. Còn independent uninstall/version cache semantics/no-live-dependency và live registry/CIM/MSIX/VM proof. Production cleanup disabled.
- **Cập nhật:** 2026-10-09

#### CD-03 — Tích hợp tab Clean Data vào WPF

- **Trạng thái:** Chờ kiểm tra · **Ưu tiên:** P0
- **Phụ trách:** Codex · **Ước lượng:** 1–2 ngày
- **Phụ thuộc:** CD-01, CD-02
- **Tiêu chí hoàn thành:** Category/file preview, three levels, progress/cancel, background runspace, single operation RAM/Disk, keyboard/DPI. Bốn nhãn risk, safe trực tiếp không popup, file finder, warning chỉ risky đã chọn, danger hai bước.
- **Bằng chứng:** DiskUI30 + ReviewUI16 + OperationUI13 PASS; Disk29controls, operation27controls. Native workers Run/Inspect/Restore/History với DispatcherTimer thật, mode resets approval, progress/cancel/final metrics, shared modal lock, recent uninspected history; PNG operation viewed. docs/CLEAN_DATA_OPERATIONS.md.; docs/CLEAN_DATA_TEMP.md; docs/verification/temp-cleanup-tests.json; docs/verification/temp-ui-tests.json; docs/verification/temp-session-verification.json (Win11 readiness14steps + postchange Temp12/UI7, limits recorded)
- **Ghi chú / bước tiếp theo:** 10.3: thêm cửa sổ Temp thật riêng; checkbox một click/two-way, hai bước cố định danh sách, shared lock, worker/timer, X/N/elapsed/endtime/cancel. 7/7 offscreen QA đạt; chưa human/DPI acceptance. Production paths vẫn blocked. Còn production backup destination/external provider, risk authority integration, keyboard/DPI/operator/Win10-11 acceptance. Interactive example script chưa tự launch.
- **Cập nhật:** 2026-10-10

#### CD-04 — Scope guard và revalidation độc lập

- **Trạng thái:** Chờ kiểm tra · **Ưu tiên:** P0
- **Phụ trách:** Codex · **Ước lượng:** 2–3 ngày
- **Phụ thuộc:** CD-01, CD-SCOPE
- **Tiêu chí hoàn thành:** Portable user-only: independent caller/policy/manifest/scope/TTL/risk validation; protected/unknown cannot override. Stable handles/identity/race/file replacement/junction/destination checks; Windows system actions delegated, không elevated helper/bypass.
- **Bằng chứng:** Guard9 + FixtureExecutor17 baseline; Operations17 PASS: độc lập labels/scope/SID/TTL/policy, frozen payload/content SHA256, held-source hash before mutation, consume under mutex, replay/back/context/destination guards. Native metadata-preserving content swap bị chặn. disk-operations-tests.json.; docs/CLEAN_DATA_TEMP.md; docs/verification/temp-cleanup-tests.json; docs/verification/temp-ui-tests.json; docs/verification/temp-session-verification.json (Win11 readiness14steps + postchange Temp12/UI7, limits recorded)
- **Ghi chú / bước tiếp theo:** 10.3: independent ReviewedTopLevelOwnTemp capability đã hoạt động trên file QA trong Temp thật (12/12). Native root/owner/SID/non-elevated/ancestor/FileID/hash/same-handle delete, no recursive/force/replay. Mọi ứng viên Review; age/type không Safe proof. General finder/appdata authority vẫn khóa, vendor/uninstall production còn thiếu. Đã có independent fixture authority. Production owner/risk/manifest authority chưa triển khai; process-local state/hash không privileged boundary. Mapped writers/filter drivers/multi-instance/VM còn thiếu.
- **Cập nhật:** 2026-10-10

#### CD-05 — Journal, executor và backup/restore

- **Trạng thái:** Chờ kiểm tra · **Ưu tiên:** P0
- **Phụ trách:** Codex · **Ước lượng:** 2–3 ngày
- **Phụ thuộc:** CD-03, CD-04
- **Tiêu chí hoàn thành:** Chỉ fixture/VM: hash-verified external backup trước xóa; same-volume gain 0; full disk/destination loss/crash/cancel/restore conflict giữ dữ liệu đúng. Risk gate independent executor, blocked no override, danger final scope approval; empty folder revalidate no new child.
- **Bằng chứng:** Operations17 + actual Crash3 + OperationUI13 PASS. Same-handle backup/hash/delete, v3 durable header/stages/receipt/Finished, separate restore log; partial-copy+verified rename handle no overwrite, backup retained; actual child exit77 after BackupVerified/DeleteStarted/Committed then inspect/survive/restore. disk-crash-tests.json.; docs/CLEAN_DATA_TEMP.md; docs/verification/temp-cleanup-tests.json; docs/verification/temp-ui-tests.json
- **Ghi chú / bước tiếp theo:** 10.3: Temp riêng là permanent sau hai bước, không Undo/backup; UI ghi rõ. Không dùng capability này để xóa dữ liệu app. Backup/restore production khác volume vẫn chưa triển khai/kiểm chứng; fixtures giữ nguyên. Backup fixture cùng volume gain0. External backup provider/full disk/disconnect/power loss chưa có; no auto replay/overwrite. Windows10/11/filter/mapped-write matrix và production authority còn thiếu.
- **Cập nhật:** 2026-10-10

#### CD-06 — Provider Windows và vendor cache

- **Trạng thái:** Chờ kiểm tra · **Ưu tiên:** P0
- **Phụ trách:** Codex · **Ước lượng:** 1–2 ngày
- **Phụ thuộc:** CD-04, CD-05
- **Tiêu chí hoàn thành:** Capability Win10/11, servicing/update/reboot guard; DISM không ResetBase, DO supported; Storage Delegated nếu không có API kiểm chứng; không tự xóa repair cache.
- **Bằng chứng:** WindowsProviders.psm1 + data/schema fixed URI allowlist Storage/Apps/Update; authoritative registry build provenance, Prepared/Delegated/Unavailable/Failed, unknown DeletedBytes.5 provider checks PASS no launch; GUI Dọn bằng Windows + apps buttons/shared lock. Official Learn Settings URI sources in CLEAN_DATA_OPERATIONS.md.
- **Ghi chú / bước tiếp theo:** Chỉ delegated, không direct servicing/DO/delete/UAC bypass. Launch/cleanup completion chưa interactive verify; CD04/05 production gates chưa done.
- **Cập nhật:** 2026-10-10

#### CD-07 — Ma trận VM và nghiệm thu số liệu

- **Trạng thái:** Chờ kiểm tra · **Ưu tiên:** P0
- **Phụ trách:** Codex · **Ước lượng:** 1.5–2 ngày
- **Phụ thuộc:** CD-02, CD-03, CD-05, CD-06, CD-09
- **Tiêu chí hoàn thành:** Win10/Win11 disposable VM, data survival/restore/TOCTOU/admin denial, progress/cancel, allocated vs free delta, performance; không xóa dữ liệu làm việc thật.
- **Bằng chứng:** Current Windows11 client build26200/25H2 (registry provenance), local readiness11 steps PASS; actual fixture crash3 checkpoints và WPF timer workers. artifacts/readiness-20261010-094026-2c5c13f5/readiness.json; operations-session-verification.json. VM flagfalse, no VM proof.; docs/CLEAN_DATA_TEMP.md; docs/verification/temp-cleanup-tests.json; docs/verification/temp-ui-tests.json; docs/verification/temp-session-verification.json (Win11 readiness14steps + postchange Temp12/UI7, limits recorded)
- **Ghi chú / bước tiếp theo:** 10.3: Win11 host26200/25H2 PS5.1.26100.9444, own QA Temp native12 + WPF7 đã đạt; không xóa file có sẵn. User chỉ có Win11. Win10/VM/external faults/mapped writers vẫn unverified. Chưa chạy Win10/Win11 disposable VM matrix, external/full disk/power loss/mapped-write/multi-instance/keyboard/DPI/performance nghiệm thu. Local pass không thay VM.
- **Cập nhật:** 2026-10-10

#### CD-08 — Operator acceptance, đóng gói và docs

- **Trạng thái:** Chờ kiểm tra · **Ưu tiên:** P0
- **Phụ trách:** Codex · **Ước lượng:** 0.5–1 ngày
- **Phụ thuộc:** CD-07
- **Tiêu chí hoàn thành:** Script PS5.1 self-contained/idempotent cho operator; docs/runbook/trust signing; artifact và nghiệm thu user có evidence.
- **Bằng chứng:** Verify-Readiness.ps1 self-cd PS5 checks + optional -Package/-OpenApp; Preview-DiskOperations.ps1 interactive fixture sample. Package-Preview.ps1 thêm Memory/Disk plans và verifies new module/policy/script entries. CLEAN_DATA_OPERATIONS.md/runbook; chưa chạy package hoặc operator acceptance.; docs/CLEAN_DATA_TEMP.md; docs/verification/temp-cleanup-tests.json; docs/verification/temp-ui-tests.json
- **Ghi chú / bước tiếp theo:** 10.3: script Verify-OwnTemp.ps1 tự cd, quyền user, chỉ exact GUID files mới tạo; Verify-Readiness có -OwnTempSelfTest, guard-only report riêng. Chưa package/signing/operator acceptance/server CI. Giữ preview/release unverified; chưa signed artifact, package readback/user acceptance hoặc full gates. Không mark done từ script tồn tại.
- **Cập nhật:** 2026-10-10

#### HO-10 — Handoff kết thúc triển khai Clean Data

- **Trạng thái:** Đang làm · **Ưu tiên:** P0
- **Phụ trách:** Codex · **Ước lượng:** 0.25 ngày
- **Phụ thuộc:** CD-SCOPE, CD-01, CD-02, CD-03, CD-04, CD-05, CD-06, CD-07, CD-08, CD-09
- **Tiêu chí hoàn thành:** docs/handoffs/PHASE-10-HANDOFF.md theo TEMPLATE.md; tất cả task/gates có evidence, incomplete giữ draft/review.
- **Bằng chứng:** docs/handoffs/PHASE-10-HANDOFF.md draft10.2; readiness artifacts/readiness-20261010-094026-2c5c13f5/readiness.json executed11 steps PASS: Disk189/13 suites + Clear12 + core14 + checkbox PASS + builders/plan/Disk18/Memory13/runtime-policy5/PS5 parser. operations-session-verification.json giữ source hashes/OS provenance và first failed test count trace. Production/VM/release chưa đạt; không newCI/commit/push.; docs/CLEAN_DATA_TEMP.md; docs/verification/temp-cleanup-tests.json; docs/verification/temp-ui-tests.json; docs/verification/temp-session-verification.json (Win11 readiness14steps + postchange Temp12/UI7, limits recorded); artifacts\readiness-20261011-020325-f5b9e55a\readiness.json; artifacts\readiness-20261011-020956-50571223\readiness.json; source 57fb2d2 main + GitHub Actions 38106638093 success, docs/verification/github-actions-portable.json
- **Ghi chú / bước tiếp theo:** Draft10.4: Temp production hẹp12+7 đạt; phase10 còn app/orphan authority, external backup và release matrix. Memory scope đã chốt ở ML-SCOPE; không đóng phase khi còn gate. Native TempLedger overload memory-operation đã được hồi quy cùng toàn bộ Disk/Temp. Native TempLedger overload memory-operation đã được hồi quy cùng toàn bộ Disk/Temp. Publication/CI verified; status phase/full release không đổi vì các dependency/nghiệm thu còn thiếu.
- **Cập nhật:** 2026-10-11

#### CD-09 — File lớn/cũ và gợi ý ứng viên không auto-delete

- **Trạng thái:** Chờ kiểm tra · **Ưu tiên:** P0
- **Phụ trách:** Codex · **Ước lượng:** 1–2 ngày
- **Phụ thuộc:** CD-01, CD-02
- **Tiêu chí hoàn thành:** Readonly KnownFolder/user-selected scopes, thresholds/age/type, allocated/logical/hardlink dedupe, locked/cloud/source guard; explicit per-file effects, no size→junk inference.
- **Bằng chứng:** Actual WPF/native finder: default512MB, configurable1–1048576 MB/age0–36500/extensions≤16, scoped local KnownFolder subfolder chooser; filters before matched/page/totals, NeedsReview/no auto-select, reset preview on scope change. Inventory18/18 + UI16 assertions PASS.
- **Ghi chú / bước tiếp theo:** Review: CD-02 ownership chưa done; custom folder positive/operator dialog/keyboard/DPI/Win10-11 VM and future provider dedupe chưa nghiệm thu. Finder không có deletion authority.
- **Cập nhật:** 2026-10-09


### 11 · Memory ba mức — thiết kế

#### MB-DES01 — Thiết kế Memory ba mức và task effects

- **Trạng thái:** Hoàn tất · **Ưu tiên:** P0
- **Phụ trách:** Codex · **Ước lượng:** 0.5–1 ngày
- **Phụ thuộc:** HO-09
- **Tiêu chí hoàn thành:** Normal/Strong giữ trim; L3 disposable/profile close, force riêng; CPU/commit giải thích, protected/unknown chặn, không auto fallback.
- **Bằng chứng:** docs/MEMORY_THREE_LEVELS_DESIGN.md; plan/memory-design.json + schema; three profiles, effects/authority/guards. No runtime PS policy change.
- **Ghi chú / bước tiếp theo:** Thiết kế/prototype không là evidence hành động thật.
- **Cập nhật:** 2026-10-09

#### MB-DES02 — Prototype hai tab Memory / Disk chung UI

- **Trạng thái:** Hoàn tất · **Ưu tiên:** P0
- **Phụ trách:** Codex · **Ước lượng:** 0.5–1 ngày
- **Phụ thuộc:** MB-DES01
- **Tiêu chí hoàn thành:** Ba level cards cả hai tab; effects/reason/risk, safe direct, review/force scoped confirmation, progress/cancel/history riêng, single-operation lock.
- **Bằng chứng:** MemoryClear-Memory-Plan.html + shared MemoryClear-CleanData-Prototype.html; three cards each tab, effects/review/typed force, progress/cancel/history/shared lock. No real process or file operation.
- **Ghi chú / bước tiếp theo:** Thiết kế/prototype không là evidence hành động thật.
- **Cập nhật:** 2026-10-09

#### MB-DES03 — Kiểm chứng Memory model, gate và luồng chung

- **Trạng thái:** Hoàn tất · **Ưu tiên:** P0
- **Phụ trách:** Codex · **Ước lượng:** 0.5–1 ngày
- **Phụ thuộc:** MB-DES02
- **Tiêu chí hoàn thành:** Fixture: safe no-popup, protected/service/foreground, allowlist/start-time, force typed name, close save prompt no fallback, expiry/cancel/inter-tab lock; no real trim/kill.
- **Bằng chứng:** node plan/check-memory-design.mjs 13/13 PASS; docs/verification/memory-design-checks.json; schema/model/DOM fixtures/force identity/held save/shared lock. node plan/build-plan.mjs + check-plan PASS revision09.2; PS5.1.26100.9444 launcher parser PASS, not executed. Visual/native/VM unverified.
- **Ghi chú / bước tiếp theo:** Thiết kế/prototype không là evidence hành động thật.
- **Cập nhật:** 2026-10-09

#### HO-11 — Handoff thiết kế Memory ba mức

- **Trạng thái:** Hoàn tất · **Ưu tiên:** P0
- **Phụ trách:** Codex · **Ước lượng:** 0.25 ngày
- **Phụ thuộc:** MB-DES01, MB-DES02, MB-DES03
- **Tiêu chí hoàn thành:** docs/handoffs/PHASE-11-HANDOFF.md theo template; task/evidence và giới hạn visual/VM/runtime thật rõ.
- **Bằng chứng:** docs/handoffs/PHASE-11-HANDOFF.md; required design tasks complete,13 Memory +18 Disk fixture checks/plan gates PASS, limitations recorded; Handoff.md updated. Runtime phase12 pending user confirm/gates.
- **Ghi chú / bước tiếp theo:** Thiết kế/prototype không là evidence hành động thật.
- **Cập nhật:** 2026-10-09


### 12 · Memory ba mức — triển khai

#### ML-SCOPE — Chốt profile task disposable / close / force

- **Trạng thái:** Hoàn tất · **Ưu tiên:** P0
- **Phụ trách:** Người dùng · **Ước lượng:** Chờ người dùng review
- **Phụ thuộc:** HO-11
- **Tiêu chí hoàn thành:** Chốt app cụ thể, effects chấp nhận và quyền close/force riêng; allowlist mặc định trống, không auto chọn từ tên/CPU/RAM.
- **Bằng chứng:** Trả lời trực tiếp 2026-10-10: Dùng danh sách tôi tự cho phép trong app (đề xuất). docs/MEMORY_TASK_RUNTIME.md.
- **Ghi chú / bước tiếp theo:** Đã chốt saved Cho đóng gấp executable paths, mặc định trống; chỉ graceful, giữ save prompt/timeout, không tự force. Không infer app từ tên/RAM/CPU. Không hỏi lại phạm vi này.
- **Cập nhật:** 2026-10-10

#### ML-01 — Planner ba mức và policy/task identity

- **Trạng thái:** Đang làm · **Ưu tiên:** P0
- **Phụ trách:** Codex · **Ước lượng:** 1–2 ngày
- **Phụ thuộc:** ML-SCOPE, HO-02
- **Tiêu chí hoàn thành:** Giữ Normal/Strong policy, vendor/profile identity/ownership/dependency, risk/effects, manifestTTL/start-time recheck, unknown fail closed.
- **Bằng chứng:** app/MemoryClear.Tasks.psm1; app/Native.cs; docs/verification/task-release-tests.json (13/13 own-child checks); artifacts\readiness-20261011-020956-50571223\readiness.json
- **Ghi chú / bước tiếp theo:** Native nonempty opt-in/fingerprint, context/ack/settings/TTL/no-replay, fresh missing services/hash/window rejection và graceful timeout/cancel đã có trace trên app QA riêng. Test foreground/service/settings/policy providers synthetic, không là full production safety acceptance. Giữ doing, chưa đủ các phụ thuộc nghiệm thu toàn phase.
- **Cập nhật:** 2026-10-11

#### ML-02 — WPF level cards và preview cảnh báo có scope

- **Trạng thái:** Chưa bắt đầu · **Ưu tiên:** P0
- **Phụ trách:** Codex · **Ước lượng:** 1–2 ngày
- **Phụ thuộc:** ML-01
- **Tiêu chí hoàn thành:** Ba cards/inlineeffects, safe no-popup, selected-risk review/force name confirm, operation lock RAM/Disk, DPI/keyboard/progress/cancel.
- **Bằng chứng:** app/MemoryTaskView.xaml/.ps1; docs/verification/task-ui-tests.json (6/6 real worker/DispatcherTimer checks); docs/verification/memory-level-tests.json
- **Ghi chú / bước tiếp theo:** Đã chuẩn bị ack/rescan/progress X/N/elapsed/endtime/cancel và close cleanup, main modal giữ operation lock. Gate sản phẩm vẫn đóng. Human keyboard/DPI và nonempty GUI execution chưa kiểm chứng; chưa nghiệm thu trước ML-01.
- **Cập nhật:** 2026-10-11

#### ML-03 — Executor Close / Force độc lập có guards

- **Trạng thái:** Chưa bắt đầu · **Ưu tiên:** P0
- **Phụ trách:** Codex · **Ước lượng:** 1.5–2 ngày
- **Phụ thuộc:** ML-01, ML-02, SAFE-04, QA-02
- **Tiêu chí hoàn thành:** Graceful exit và verify, save prompt/timeout held gain0; force plan mới/quyền riêng/fresh identity; không kill tree/service/auto escalation.
- **Bằng chứng:** app/MemoryClear.Tasks.psm1; app/Native.cs; memory-operation journal QA; docs/verification/task-release-tests.json
- **Ghi chú / bước tiếp theo:** Executor graceful-only đã chuẩn bị/test child riêng: verified exit, refusal timeout, cancel sau WaitingForExit, không force/tree/service/escalation. Shipped executionEnabled=false; giữ chưa nghiệm thu vì SAFE-04/QA-02 chưa đủ. Manual Force cũ là thao tác riêng, không fallback tự động.
- **Cập nhật:** 2026-10-11

#### ML-04 — VM safety/permissions/metrics và nghiệm thu

- **Trạng thái:** Chưa bắt đầu · **Ưu tiên:** P0
- **Phụ trách:** Codex · **Ước lượng:** 1.5–2 ngày
- **Phụ thuộc:** ML-03
- **Tiêu chí hoàn thành:** PID reuse/critical/foreground/denial/savedprofilechanges, unsaved data/cancel/multi-instance, CPU vs working set/commit, Win10/11, user acceptance có trace.
- **Bằng chứng:** artifacts\readiness-20261011-020956-50571223\readiness.json; docs/verification/task-release-tests.json; docs/verification/task-ui-tests.json
- **Ghi chú / bước tiếp theo:** Có local Windows11 evidence; không suy ra Win10/VM/CLI parity/human save-dialog/window adversarial race acceptance. Full phase còn thiếu.
- **Cập nhật:** 2026-10-11

#### HO-12 — Handoff triển khai Memory ba mức

- **Trạng thái:** Đang làm · **Ưu tiên:** P0
- **Phụ trách:** Codex · **Ước lượng:** 0.25 ngày
- **Phụ thuộc:** ML-SCOPE, ML-01, ML-02, ML-03, ML-04
- **Tiêu chí hoàn thành:** docs/handoffs/PHASE-12-HANDOFF.md theo template, mọi gates/tasks/evidence trước done.
- **Bằng chứng:** docs/handoffs/PHASE-12-HANDOFF.md; artifacts\readiness-20261011-020956-50571223\readiness.json; docs/verification/portable-build.json (55 files, packaged WPF/native smoke + ZIP SHA256 entries Passed); source 57fb2d2 main + GitHub Actions 38106638093 success, docs/verification/github-actions-portable.json
- **Ghi chú / bước tiếp theo:** Draft cập nhật 2026-10-11.1; backend/UI QA và chuẩn bị bộ portable, phase12 chưa complete. Bộ portable preview 2026.10.11.1 đã build; shortcut Desktop readback verified, chưa launch GUI từ shortcut; không là full release acceptance. Publication/CI verified; status phase/full release không đổi vì các dependency/nghiệm thu còn thiếu.
- **Cập nhật:** 2026-10-11
