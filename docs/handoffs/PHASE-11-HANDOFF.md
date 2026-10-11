# Handoff — Phase 11 · Memory ba mức — thiết kế

- Ngày cập nhật: 2026-10-09 (Asia/Tokyo)
- Người thực hiện: Codex
- Trạng thái bàn giao: Hoàn tất thiết kế/model/prototype — chưa thay runtime
- Task handoff: HO-11
- Phiên bản kế hoạch: 2026-10-09.2
- Branch / commit: main; thay đổi thiết kế trong working tree, chưa commit/push. Không có CI mới cho thiết kế này.

## 1. Mục tiêu và phạm vi đã chốt

Người dùng yêu cầu **add vào plan và giao diện cả Memory/Disk để confirm trước**: Memory ba mức, mức3 dọn/đóng tác vụ không quan trọng có effects rõ; Disk safe không popup, dangerous warn/confirm nhiều bước hoặc block, app đã gỡ dọn residual phù hợp, tìm file lớn/cũ. Phạm vi chỉ thiết kế/model/HTML, không sửa GUI/policy/runtime PS thật, không scan/xóa ổ C:, trim/close/kill thật hay UAC.

Normal và Strong hiện có được ánh xạ thành Tiêu chuẩn/Chuyên sâu; mức3 Giải phóng tác vụ là đề xuất: graceful close theo profile, force chọn riêng. Critical/service/foreground/unknown chặn. Không giả có cách chắc chắn suy ra task không quan trọng từ CPU/RAM/tên. Allowlist production mặc định trống, Example* chỉ là fixture. Chờ user confirm thiết kế và app/profile cụ thể ở ML-SCOPE.

## 2. Kết quả theo task

| Task ID | Trạng thái | Kết quả thực tế | Bằng chứng |
|---|---|---|---|
| MB-DES01 | done | Ba mức Memory, risk/authority/Close/Force/CPU/commit và gate | docs/MEMORY_THREE_LEVELS_DESIGN.md; plan/memory-design.json + schema |
| MB-DES02 | done | Plan Memory HTML, prototype chung hai tab, effects, typed force, shared lock | MemoryClear-Memory-Plan.html; MemoryClear-CleanData-Prototype.html; templates/js/builder |
| MB-DES03 | done | 13/13 fixture/schema/HTML/DOM handlers tests và tracker checks đạt | docs/verification/memory-design-checks.json; plan/check-memory-design.mjs |
| HO-11 | done | Handoff/template/task/evidence/limits đầy đủ; runtime phase12 pending | Tài liệu này; plan/tasks.json |

## 3. Thay đổi và điểm vào để tiếp tục

| File / module | Thay đổi | Người tiếp nhận cần biết |
|---|---|---|
| docs/MEMORY_THREE_LEVELS_DESIGN.md | Ba mức, risk chung, identity/profile/action contract | Trust/native safety chưa chứng minh bằng fixture |
| plan/memory-design.json + schema | 3 profiles, 9 process fixtures, executionEnabled=false | Không process inventory/allowlist thật |
| plan/memory-prototype.fragment.html + memory-prototype.js | Tab Memory và pure model/UI simulation | Safe direct, review scoped, force name gate, held save prompt, progress/history/cancel |
| plan/memory-plan.template.html | Plan HTML mới từ tasks/config/shared stylesheet | Chỉnh template rồi build, không sửa generated riêng |
| plan/clean-data-prototype.template.html | Chung tab/lock, Disk risk gate và large finder | Giữ URL HTML trước đây; #memory mở tab Memory |
| plan/prototype-test-harness.mjs | Shared code-level DOM fixture | Không browser/native automation hoặc render proof |
| plan/check-memory-design.mjs | 13 checks có positive/negative gates | Trace JSON fixture, không máy thật |
| plan/build-clean-data.mjs | Sinh Memory plan + Disk plan + prototype chung | Build-plan riêng vẫn dựng tracker/IMPLEMENTATION_PLAN |
| MemoryClear-Plan.html | Mockup legacy thay bằng overview ba mức hai tab và links | Master tracker vẫn canonical source tasks.json |
| scripts/Open-CleanData-Design.ps1 | Verify flags, tự cd root, mở ba HTML | Operator chạy; agent không dùng để vòng browser policy |
| plan/tasks.json, Handoff.md | Phase11 thiết kế/phase12 implementation gate | RAM phase03 giữ review; không claim bản thật đổi level |

## 4. Cách chạy và kiểm chứng

Môi trường Windows, Node v24.16.0 theo trace. Root `E:\SourceCode\NEW_APPLICATION\MemoryClear`. Không npm install/network.

- `node plan/build-clean-data.mjs`: đạt, ba HTML, không unresolved tokens.
- `node plan/check-memory-design.mjs`: **13/13 passed**, schema contract noautoKill/noFallback/noTree; exact embedded config/IDs/scripts/roadmap; L1/L2 trim-only; L3 safe disposable; critical/foreground/unknown/nonallowlist blocked; forced review+name+ack; manifest TTL/tamper/PID-start-time; per-step identity skip; save-prompt gain0; CPU trim unchanged; safe no-popup; UI force gate; shared lock/cancel.
- `node plan/check-clean-data.mjs`: **18/18 passed**, config/risk/large/default/review/backup plus Disk event handlers; companion handoff phase09.
- `node plan/build-plan.mjs` + `node plan/check-plan.mjs`: **đạt** revision09.2; source/embedded sync, IDs/JS, gates/deps, imports/exports/migration/storage. 71 tasks; 25 done sau final status. Không visual QA.
- Trace: `docs/verification/memory-design-checks.json` / `clean-data-design-checks.json`; không real inventory.
- Visual browser QA **chưa kiểm chứng**: policy trước đây chặn file:// (`clean-data-browser-qa.json`), không retry alternate/server/browser để vòng policy. DOM fixture không là layout/screenshot proof. User đang xem plan ở browser không là bằng chứng agent đã kiểm chứng layout.
- Chưa chạy real trim/close/kill, Win10/11 VM native critical/dependency detection/PID races, saved approvals/multi-instance/performance, WPF DPI/keyboard cho redesign. CI cũ không là evidence redesign.

Operator mở plan/prototype qua `powershell -NoProfile -File "E:\SourceCode\NEW_APPLICATION\MemoryClear\scripts\Open-CleanData-Design.ps1"`. Script tự cd root và verify flags trước mở. Không build/dọn/UAC. Agent chỉ parse script bằng PS5.1, không execute browser.

## 5. Quyết định kỹ thuật và lý do

1. Safe không popup, effects inline. Review/danger chỉ cảnh báo mục đã chọn; blocked không override bằng admin hoặc confirm nhiều lần.
2. L1/L2 cùng API trim hiện có; L3 thêm request close có điều kiện/profile. Force authority riêng, typed exact task name, fresh identity; không auto Close→Force.
3. Close chưa thoát/save prompt giữ task và gain0; per-step identity đổi skip. CPU khác RAM/commit; không hứa trim giảm CPU.
4. Shared coordinator lock RAM/Disk; progress/elapsed/timestamp/history riêng, không cộng reclaim hai loại tài nguyên.
5. Pure model+DOM fixture thể hiện contract nhưng không security boundary/native safety proof; level3 executor gated SAFE-04/QA-02/VM trước release.

## 6. Tồn tại, rủi ro và điểm chặn

| Vấn đề | Ảnh hưởng | Task xử lý / người phụ trách | Bước tiếp theo |
|---|---|---|---|
| Chưa có app/profile thật và confirm | Không thể bật auto close an toàn trên máy người dùng | ML-SCOPE / user | Xem prototype, chốt app và effects/authority cụ thể |
| Native identity/critical/dependency/unsaved state chưa triển khai mức3 | Không coi fixture là safe force release | ML-01/03/04 + SAFE-04/QA-02 | Scanner/planner → guards → VM action tests |
| Visual/browser bị giới hạn | Layout/tương tác thật chưa có evidence | MB-DES03 documented; ML-02 | Operator review HTML, WPF acceptance sau code |
| RAM phase03/VM/overhead còn review | App tổng vẫn chưa release | UI-01/CLEAR-01/QA-01/HO-03 | Tiếp tục gate trước đó; không đóng từ prototype |

## 7. Hướng dẫn người / chat tiếp nhận

1. Đọc IMPLEMENTATION_PLAN.md, tasks.json, Handoff.md, handoff phase09/11 và docs/MEMORY_THREE_LEVELS_DESIGN.md. Không có progress JSON mới do user cung cấp trong lượt này.
2. Review MemoryClear-Memory-Plan.html, MemoryClear-CleanData-Plan.html và prototype tab Memory/Disk. Revision nguồn09.2; không dùng old browser localStorage để override mà không reconcile.
3. Chốt ML-SCOPE: mức3 graceful close theo profile opt-in, app cụ thể, permissions close/force riêng; mặc định không force/không allowlist production. CD-SCOPE chốt backup/retention/helper trust cho Disk.
4. Triển khai ML-01 sau ML-SCOPE/HO-02; ML-03 chỉ sau SAFE-04 + QA-02 + ML-01/02. Không chạy lên process công việc thật để test. Disk theo phase10 riêng, finderCD-09 readonly trước deletion.
5. Rebuild cả hai builders và check-plan/check-clean-data/check-memory-design khi nguồn thay đổi. Kết thúc phase12 có HO-12; mọi runtime test chưa chạy phải giữ honest status.

## 8. Checklist kết thúc phase

- [x] Design tasks và handoff có status/evidence cuối.
- [x] Thiết kế/phạm vi/changed files/limitations ghi rõ.
- [x] Memory13 và Disk18 checks có trace.
- [x] OPEN/next steps, native/visual safety chưa verify không che giấu.
- [x] Tracker/HTML/Markdown dựng lại và kiểm tra.
- [x] Link handoff đưa trong completion reply.
