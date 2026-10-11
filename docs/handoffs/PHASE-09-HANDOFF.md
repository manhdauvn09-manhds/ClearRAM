# Handoff — Phase 09 · Clean Data — thiết kế

- Ngày cập nhật: 2026-10-09 (Asia/Tokyo)
- Người thực hiện: Codex
- Trạng thái bàn giao: Hoàn tất thiết kế — chưa triển khai bộ dọn thật
- Task handoff: HO-09
- Phiên bản kế hoạch: 2026-10-09.2 (bổ sung risk/finder; lịch sử kiểm tra09.1 giữ ở ghi chú)
- Branch / commit: main; nền local HEAD 0f44426052d6077da171d464b9feb9a32113a480. Thay đổi phase 09 chưa commit/push; không có CI mới.

## 1. Mục tiêu và phạm vi đã chốt

Người dùng yêu cầu thiết kế tab Clean data ổ Windows bên cạnh RAM/CPU, có ba mức, tìm temp/cache/log/bộ cài cũ/app data còn sót, HTML plan và prototype để chốt. Phạm vi hiện tại là tài liệu và mô phỏng, **không dọn/xóa thật và chưa tích hợp tab vào WPF**. Dùng nền PowerShell 5.1/WPF Windows 10/11 x64 đã chọn. Admin xin UAC hợp lệ; không bypass quyền, takeown, sửa ACL, SYSTEM/TrustedInstaller hay kill app.

Đề xuất retention, backup destination và privileged-helper trust chưa được người dùng chốt. Câu hỏi async về external backup vs permanent deletion chưa nhận trả lời; khuyến nghị external backup, prototype mặc định cách ly cùng ổ với reclaim=0. Không coi tick/checklist mặc định là quyết định của người dùng.

## 2. Kết quả theo task

| Task ID | Trạng thái | Kết quả thực tế | Bằng chứng |
|---|---|---|---|
| CD-DES01 | done | Ba mức, 15 nhóm mẫu, ownership/manifest/revalidate/UAC/backup/restore/metrics và gate | docs/CLEAN_DATA_ARCHITECTURE.md; plan/clean-data-design.json + schema |
| CD-DES02 | done | Hai HTML offline: plan và prototype scan/review/backup/progress/cancel/history/export mẫu | MemoryClear-CleanData-Plan.html; MemoryClear-CleanData-Prototype.html; builder/templates |
| CD-DES03 | done | 13 checks ở09.1;18/18 hiện tại sau redesign; tracker và PS5 parser đạt | docs/verification/clean-data-design-checks.json; plan/check-clean-data.mjs |
| CD-DES04 | done | Risk safe/review/danger/blocked; app removed cache/empty vs mixed userdata; large finder | docs/CLEAN_DATA_ARCHITECTURE.md mục9; config v2 + schema |
| CD-DES05 | done | Prototype safe no-popup, dangerous scope gate và large file filter; 18/18 và tracker đạt | docs/verification/clean-data-design-checks.json |
| HO-09 | done | Handoff thiết kế đủ task/evidence/giới hạn; phase 10 chưa triển khai | Tài liệu này; plan/tasks.json |

## 3. Thay đổi và điểm vào để tiếp tục

| File / module | Thay đổi | Người tiếp nhận cần biết |
|---|---|---|
| docs/CLEAN_DATA_ARCHITECTURE.md | Product architecture, pipeline, scope, trust/race/backup/metrics | Rule là đề xuất; không chứa executor |
| plan/clean-data-design.json + schema | Config product_runtime design_only, executionEnabled=false, ba mức/15 fixtures | Không là inventory máy thật/manifest thực thi |
| plan/clean-data-*.template.html | Nguồn layout/giao diện HTML đẹp, responsive, offline | Sửa template rồi rebuild; không sửa riêng generated HTML |
| plan/build-clean-data.mjs | Build hai HTML, trạng thái roadmap từ tasks.json | Không thư viện bên ngoài, không telemetry |
| plan/check-clean-data.mjs | Schema/model + DOM-fixture event tests, trace 13 checks | DOM fixture không phải browser acceptance; không xóa FS |
| plan/tasks.json | Thêm phase 09 (4 docs), phase 10 (10 gated implementation tasks) | Giữ status cũ; CD-SCOPE decision, runtime todo |
| plan/build-plan.mjs, plan/check-plan.mjs | Cross-link Clean Data; số handoff theo số phase | Không hardcode 9 phase cũ; tracker vẫn là nguồn quản lý |
| MemoryClear-Plan.html, IMPLEMENTATION_PLAN.md | Dựng lại tracker theo revision mới | RAM phase 03 vẫn review, không claim xong toàn app |
| Handoff.md | NOW/NEXT/OPEN/AVOID cho phiên tiếp nhận | Không xóa handoff phase cũ: đó là deliverable/evidence của workflow |

## 4. Cách chạy và kiểm chứng

- Môi trường: Windows hiện tại; Node runtime ghi trong JSON trace. HTML standalone, không cần npm install/network. PowerShell app source không thay đổi.
- `node plan/build-clean-data.mjs`: đạt, sinh hai HTML từ template/config/tasks.
- `node plan/check-clean-data.mjs`: **13/13 passed**, gồm schema phản ví dụ, protected/risk defaults, admin/busy, review, same-volume gain 0, external/permanent fixture, unknown provider, expiry/tamper/settings, no native/network bridge, roadmap và event scan/progress/cancel/typed confirmation.
- `node plan/build-plan.mjs` / `node plan/check-plan.mjs`: **đạt** trên revision 2026-10-09.1; 58 tasks; source/embedded sync, IDs/JS, status/dependency/done gates, escaping/filter, JSON import/export/migration, rollback/storage. Dựng lại sau chốt status; không phải visual QA.
- Trace: `docs/verification/clean-data-design-checks.json`; browser denial record: `docs/verification/clean-data-browser-qa.json`; không chứa real file inventory.
- Browser QA: `cua.createBrowserTab` mở `file://...Prototype.html` bị browser security policy từ chối vì chỉ http/https. Không thử server/alternate browser để vòng chính sách. **Chưa verify layout/screenshot/tương tác browser thật**. Code-level DOM fixture đã kiểm chứng handlers; không thay thế visual QA.
- Chưa chạy: actual scanner/delete/UAC/backup/restore; VM Windows10/11, race filesystem, benchmark, signing/install trust. CI repo cũ không là evidence module mới.

Operator có `scripts/Open-CleanData-Design.ps1` tự cd root, verify fixture flags/file existence và mở HTML bằng trình duyệt mặc định, không build/dọn/UAC. Lệnh: `powershell -NoProfile -File "E:\SourceCode\NEW_APPLICATION\MemoryClear\scripts\Open-CleanData-Design.ps1"`. Script được parse bằng **Windows PowerShell 5.1.26100.9444**, 0 parser errors; chưa execute mở browser. Thao tác UI mở file vẫn operator thực hiện, không giả là agent đã xem layout.

## 5. Quyết định kỹ thuật và lý do

1. Tiêu chuẩn / Chuyên sâu / Tối đa có duyệt tăng catalogue, giữ protections. AppData thiếu uninstall key chưa đủ; unknown/portable/shared giữ lại.
2. OS adapters có capability và rule hỗ trợ; DISM không ResetBase, không tự xóa WinSxS/Installer/SoftwareDistribution. Windows.old cleanup delegated khi không có API đã kiểm chứng.
3. UAC helper tách khỏi GUI, action allowlist/caller/manifest revalidation. Helper/policy user-writable không là security boundary; ký/cài protected là quyết định phase 10.
4. Same-volume quarantine=0 reclaim; external copy/hash verify trước xóa. Unknown provider size không cộng như zero-known; free delta không attribution tuyệt đối.
5. HTML dùng fixture, CSP connect-src none, không FS/native bridge. Simulated progress/GB không phải measured result máy người dùng. Không đổi GUI PS đang chạy.

## 6. Tồn tại, rủi ro và điểm chặn

| Vấn đề | Ảnh hưởng | Task xử lý / người phụ trách | Bước tiếp theo |
|---|---|---|---|
| Browser file:// bị policy chặn | Visual QA chưa được quan sát | CD-DES03 giới hạn đã ghi; CD-03 browser/operator | Operator mở HTML review; không giả screenshot đạt |
| Backup destination/retention/helper trust chưa chốt | Chưa đủ contract để triển khai deletion | CD-SCOPE / user + Codex | Chốt phương án cụ thể sau xem plan |
| FS races/UAC/restore chưa triển khai/test | Không phát hành bộ dọn thật từ bản thiết kế | CD-01/04/05/07 | Scanner readonly → guard fixtures → executor VM |
| AppData orphan inference không chắc chắn | Có thể mất settings/save/database | CD-02 | Evidence owner + user review, unknown giữ |
| RAM phase 03 còn review | App tổng chưa release MVP | UI-01/CLEAR-01/QA-01/HO-03 | Giữ gate/evidence cũ; không đóng vì thiết kế Clean Data |

## 7. Hướng dẫn người / chat tiếp nhận

1. Đọc IMPLEMENTATION_PLAN.md, plan/tasks.json, Handoff.md và tài liệu này; đối chiếu user-exported progress JSON nếu được cung cấp mới. Không có export mới được cung cấp trong lượt này.
2. Xem plan/prototype; tài liệu đầy đủ ở docs/CLEAN_DATA_ARCHITECTURE.md, config ở plan/clean-data-design.json.
3. Chốt CD-SCOPE sau HO-09: retention, external backup destination/policy và protected/signed helper vs OS-delegated actions.
4. Code bắt đầu CD-01 readonly scanner sau CD-SCOPE/HO-02. Chưa được bỏ qua CD-04/05 trước deletion. Kiểm tra disposable VM, không xóa dữ liệu công việc thật.
5. Sửa tasks.json; rebuild cả plan/build-plan.mjs và plan/build-clean-data.mjs, check cả hai. Mỗi phase mới có HO-XX. Không bypass UAC, không claim max cleaning an toàn tuyệt đối.

## 8. Checklist kết thúc phase

- [x] Task thiết kế bắt buộc đạt tiêu chí và có evidence, với giới hạn visual QA công bố rõ.
- [x] Handoff phản ánh đúng mã/tài liệu hiện tại và giới hạn rõ.
- [x] Kiểm tra 13 checks và giới hạn browser/runtime được ghi rõ.
- [x] Vấn đề tồn tại có hướng xử lý, không giấu blocker.
- [x] tasks.json/HO-09 cập nhật hoàn tất; HTML/Markdown dựng lại.
- [x] Kiểm tra kế hoạch đạt; link handoff được đưa trong trả lời kết thúc phase.

## 9. Bổ sung theo yêu cầu user — risk/finder + Memory chung (09.2)

Người dùng yêu cầu mục an toàn không cảnh báo, file nguy hiểm warn/confirm nhiều bước hoặc block; app đã gỡ còn cache/empty được dọn, file lớn/cũ show thêm; plan/giao diện cả hai phần để confirm. Prototype hiện có cả Memory và Disk; **app thật vẫn giữ hai mức trim**, không Clean/Close/Delete thật.

- Disk fixture config v2, **22** groups/files: added verified removed-cache/empty, ISO/video/VHD và cloud/source blocked. Age/size không suy ra không quan trọng. Large finder opt-in, filter512 MB/display sort, không auto chọn personal. Same-volume quarantine gain0.
- Safe direct0popup; review final scoped approval; permanent appdata/VM/Windows.old danger2 bước (item review + final ack/phrase). Protected/locked/ownership unknown deny/no override. Modal chỉ liệt kê risky selected; button safe-only rõ loại risky khỏi lượt chạy.
- `node plan/check-clean-data.mjs`: **18/18 passed** (trace hiện tại thay snapshot13 cũ), gồm 10 base checks + safe direct/progress/cancel/quarantine/permanent gate/removed cache-empty/large discovery/filter/safe-only.
- `node plan/check-memory-design.mjs`: **13/13 passed**, handoff phase11. Hai tabs shared operation lock, history/progress riêng; không native trim/kill.
- Build HTML sinh3 artifact: MemoryClear-Memory-Plan.html + Disk plan + prototype chung. Master plan UI overview ba mức hai tab, tasks09.2 thêm CD-DES04/05, CD-09 finder, phase11/12 Memory gated. Tracker 71 tasks/25 done; phase09/11 chỉ thiết kế. Build/check-plan revision09.2 đạt, không VM/runtime evidence.
- Script launcher nay verify cả hai config executionEnabled=false rồi mở3 HTML, agent chưa chạy browser. Browser visual restriction trước đó vẫn unverified, no workaround; runtime/VM guards chưa được chứng minh.
- Decision tiếp theo CD-SCOPE/ML-SCOPE: backup/retention/helper trust và user app profiles/permissions. User chưa confirm bằng hành động xem ambient tab; không suy ra consent xóa/kill thật.
