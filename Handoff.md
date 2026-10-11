# MemoryClear — Handoff hiện tại

## NOW — 2026-10-11 (Asia/Tokyo)

- User yêu cầu đưa bản mới lên GitHub trong lượt này. Đã xác minh origin ClearRAM/default main/push permission và remote HEAD0f44426052d6077da171d464b9feb9a32113a480. Chuẩn bị commit source/app/tests/plan/evidence; publication/CI mới chưa coi là pass trước khi quan sát. Không stage harness/local data.

- Plan 2026-10-11.1; phase10/12 còn draft, không giả complete. 16 readiness steps pass, trace artifacts\readiness-20261011-020956-50571223\readiness.json; task child 13 / UI 6 checks. Native/core/Temp journal source hồi quy đầy đủ.
- Memory3 executor graceful-only đã chuẩn bị; shipped executionEnabled=false vì SAFE-04/QA-02 chưa đủ. Không force fallback. Clear Normal/Strong + reviewed Temp thực thi được.
- User đã ủy quyền build portable. scripts/Build-Portable.ps1 tạo curated folder/ZIP/manifest/checksum và packaged controls/native smoke. Kết quả chỉ theo docs/verification/portable-build.json, không fake build trước khi chạy. Source chưa commit/push; server CI source mới chưa quan sát.

## NEXT

Ưu tiên full safety/action/CLI/nonempty GUI acceptance theo dependencies rồi mới mở Memory3; tiếp removal authority/appdata production sau đó. Bộ chạy mới không kèm personal .data; user opt-in mặc định trống.

## OPEN

- Memory3 rollout: until SAFE-04/QA-02/dependencies và human/nonempty checks đạt.
- Windows10/VM/DPI/races: until có trace thực; user chỉ có Win11, không hỏi lại VM.
- Disk appdata/delete/backup: until verified uninstall authority/backup khác volume và fault matrix đạt.
- Package delivery: đã đạt; proof docs/verification/portable-build.json + shortcut readback. Windows10/full release vẫn chưa nghiệm thu.

## AVOID

Không toggle gate để né dependencies; không real user app kill/cleanup QA; không auto force/tree/UAC bypass; không stage harness/user changes hoặc .data; không dùng old ZIP làm bản mới. Giữ trace failed, không biến unverified thành green.

## Bộ chạy đã build — 2026-10-11

- ZIP: E:\SourceCode\NEW_APPLICATION\MemoryClear\artifacts\releases\20261011-111149-936015\MemoryClear-2026.10.11.1-preview.zip
- Folder chạy: E:\SourceCode\NEW_APPLICATION\MemoryClear\artifacts\releases\20261011-111149-936015\MemoryClear; launcher Start-MemoryClear.cmd.
- 55 file, 192168 bytes ZIP; manifest entry hashes và packaged WPF/native compilation smoke Passed. SHA256 B9914C4DFF4B48837E261B60F3E5A10E4FBEB35F2DB4EF97AE68333BFE6B9AD7. Checksum sidecar cùng ZIP.
- Desktop MemoryClear Portable 2026-10-11.lnk đã trỏ đúng folder mới và readback verified; chưa launch qua shortcut. Proof artifacts/portable-desktop-shortcut.json. Bản package trước bị supersede; chỉ dùng đường dẫn này.
- Runtime source hashes sau build khớp latest readiness; docs/verification/portable-session-verification.json. Memory3 execution gate vẫn false; full phase/release chưa complete. Không kèm settings/history cá nhân.

---

Các ghi chú dưới là lịch sử; NOW/NEXT/OPEN/AVOID phía trên là trạng thái hiện tại.


# MemoryClear — Handoff hiện tại

## NOW — 2026-10-11 (Asia/Tokyo)

- Plan 2026-10-11.1; phase10/12 còn draft, không giả complete. 16 readiness steps pass, trace artifacts\readiness-20261011-020325-f5b9e55a\readiness.json; task child 12 / UI 6 checks. Native/core/Temp journal source hồi quy đầy đủ.
- Memory3 executor graceful-only đã chuẩn bị; shipped executionEnabled=false vì SAFE-04/QA-02 chưa đủ. Không force fallback. Clear Normal/Strong + reviewed Temp thực thi được.
- User đã ủy quyền build portable. scripts/Build-Portable.ps1 tạo curated folder/ZIP/manifest/checksum và packaged controls/native smoke. Kết quả chỉ theo docs/verification/portable-build.json, không fake build trước khi chạy. Source chưa commit/push; server CI source mới chưa quan sát.

## NEXT

Ưu tiên full safety/action/CLI/nonempty GUI acceptance theo dependencies rồi mới mở Memory3; tiếp removal authority/appdata production sau đó. Bộ chạy mới không kèm personal .data; user opt-in mặc định trống.

## OPEN

- Memory3 rollout: until SAFE-04/QA-02/dependencies và human/nonempty checks đạt.
- Windows10/VM/DPI/races: until có trace thực; user chỉ có Win11, không hỏi lại VM.
- Disk appdata/delete/backup: until verified uninstall authority/backup khác volume và fault matrix đạt.
- Package delivery: until portable-build.json Passed/ZIP exists/checksum matches.

## AVOID

Không toggle gate để né dependencies; không real user app kill/cleanup QA; không auto force/tree/UAC bypass; không stage harness/user changes hoặc .data; không dùng old ZIP làm bản mới. Giữ trace failed, không biến unverified thành green.

---

# MemoryClear — Handoff

Cập nhật 2026-10-10 (Asia/Tokyo), Codex. Kế hoạch nguồn: `plan/tasks.json`, revision 2026-10-10.4. Repository source: https://github.com/manhdauvn09-manhds/ClearRAM, branch main. Chưa phát hành MVP; thiết kế/triển khai Disk mới chưa commit/push.

**Final verification10.4:** full readiness14steps đạt tại `artifacts/readiness-20261010-114058-39b783ae/readiness.json`;14 baseline Disk suites194 + ownTemp12/UI7 =213 checks/16suites, Clear12/Core14/checkbox/Memorylevel11, Diskdesign18/Memorydesign13/runtimepolicy9/PS5parser/plan đạt. Sau checkpoint đã sửa riêng TempCleanup/TempView để ghi Outcome/lý do skip và hiển thị kết quả từng file; hai suite Temp12/UI7 đã rerun sau sửa và đạt. Full suite không rerun sau hai thay đổi nhỏ này; public summary ghi chính xác2 source hash differences và current hashes/post-change timestamps. Lệnh node build/check plan/design/schema và git diff --check đạt cuối lượt. Evidence `docs/verification/temp-session-verification.json`. Không commit/push/package/CI/VM/release proof.

## NOW

**Checkpoint hiện tại10.4 — 2026-10-10:** Dọn Temp có duyệt đã chạy thật trên exact QA files mới tạo trong Temp của user: backend12/12 + WPF7/7, native owner/root/SID/hash/same-handle/permanent hai bước/no Undo, .tmp/.log top-level≥7/7/3days, ≤64MiB/file, non-elevated, no recursion/force. File mới/locked/linked/protected/unknown giữ lại. GUI progress/cancel/endtime/journal/shared lock. Không xóa file có sẵn. Finder/appdata không được cấp authority; orphan/vendor authority và production backup khác volume còn thiếu. Windows system delegation không claim cleanup bytes. User chỉ có Win11; Win10/VM/fault/DPI/release chưa kiểm chứng. User đã chốt Memory3 Cho đóng gấp opt-in:3cards/readonly preview, policy/UI11 checks và Clear12 regression đạt; task executor chưa mở theo SAFE-04/QA-02 và ML01 validation. Scope task ML-SCOPE mới done; toànrepo71/28done. HO10/HO12 draft. Không commit/push/package/CI mới. Các10.2/10.1/09.x phía sau là lịch sử; nhận xét production disabled trước10.3 không áp dụng cho Temp capability mới.

Files mới: TempCleanup/TempView/temp-policy/schema, Native OwnTemp/TempLedger; MemoryClear.Tasks/MemoryTaskView/memory-task-policy/schema/3cards. Docs CLEAN_DATA_TEMP/MEMORY_TASK_RUNTIME, tests Temp12/UI7/Memory11, Verify-OwnTemp và readiness option -OwnTempSelfTest, schema checks/CI/package source config. Commands tự cd/PS5: powershell -File "E:\SourceCode\NEW_APPLICATION\MemoryClear\scripts\Verify-OwnTemp.ps1"; powershell -STA -File "E:\SourceCode\NEW_APPLICATION\MemoryClear\tests\Check-TempUI.ps1"; powershell -STA -File "E:\SourceCode\NEW_APPLICATION\MemoryClear\tests\Check-MemoryLevels.ps1". Evidence reports tương ứng và temp-session-verification.json.

Open/next: CD04 production journal readonly integrity/history, scoped cache/orphan authority; CD05 backup volume/source-retain/restore no-overwrite/fault QA. Memory tiếp ML01 nonempty profile/exe/setting/SID/foreground/TTL invalidation, rồi SAFE04/QA02 dependencies trước ML03 close/timeout/save prompt. AVOID: UAC/ACL bypass, recursive Temp cleanup, age/name=trash, existing-user-file deletion/app kills for QA, auto-force/replay, overwrite backups, fake VM/CI/release proof.


**Checkpoint hiện tại10.4 — 2026-10-10:** Dọn Temp có duyệt đã chạy thật trên exact QA files mới tạo trong Temp của user: backend12/12 + WPF7/7, native owner/root/SID/hash/same-handle/permanent hai bước/no Undo, .tmp/.log top-level≥7/7/3days, ≤64MiB/file, non-elevated, no recursion/force. File mới/locked/linked/protected/unknown giữ lại. GUI progress/cancel/endtime/journal/shared lock. Không xóa file có sẵn. Finder/appdata không được cấp authority; orphan/vendor authority và production backup khác volume còn thiếu. Windows system delegation không claim cleanup bytes. User chỉ có Win11; Win10/VM/fault/DPI/release chưa kiểm chứng. User đã chốt Memory3 Cho đóng gấp opt-in:3cards/readonly preview, policy/UI11 checks và Clear12 regression đạt; task executor chưa mở theo SAFE-04/QA-02 và ML01 validation. Scope task ML-SCOPE mới done; toànrepo71/28done. HO10/HO12 draft. Không commit/push/package/CI mới. Các10.2/10.1/09.x phía sau là lịch sử; nhận xét production disabled trước10.3 không áp dụng cho Temp capability mới.

Files mới: TempCleanup/TempView/temp-policy/schema, Native OwnTemp/TempLedger; MemoryClear.Tasks/MemoryTaskView/memory-task-policy/schema/3cards. Docs CLEAN_DATA_TEMP/MEMORY_TASK_RUNTIME, tests Temp12/UI7/Memory11, Verify-OwnTemp và readiness option -OwnTempSelfTest, schema checks/CI/package source config. Commands tự cd/PS5: powershell -File "E:\SourceCode\NEW_APPLICATION\MemoryClear\scripts\Verify-OwnTemp.ps1"; powershell -STA -File "E:\SourceCode\NEW_APPLICATION\MemoryClear\tests\Check-TempUI.ps1"; powershell -STA -File "E:\SourceCode\NEW_APPLICATION\MemoryClear\tests\Check-MemoryLevels.ps1". Evidence reports tương ứng và temp-session-verification.json.

Open/next: CD04 production journal readonly integrity/history, scoped cache/orphan authority; CD05 backup volume/source-retain/restore no-overwrite/fault QA. Memory tiếp ML01 nonempty profile/exe/setting/SID/foreground/TTL invalidation, rồi SAFE04/QA02 dependencies trước ML03 close/timeout/save prompt. AVOID: UAC/ACL bypass, recursive Temp cleanup, age/name=trash, existing-user-file deletion/app kills for QA, auto-force/replay, overwrite backups, fake VM/CI/release proof.


- **Hiện tại10.2:** đã nối independent fixture operations/backup/restore/history +27control WPF worker/DispatcherTimer thật, Disk29controls, modal coordinator giữ khóa. SHA256 nội dung cả preview và held-source transaction; journal3 + riêng restore log, create-new rename/no overwrite/backup retained, recent Uninspected≤200 rows. Actual child crash3 checkpoints đạt. Windows Storage/apps delegation chỉ mở Windows, không claim cleanup bytes. Readiness current Windows11 client26200/25H2 đạt11steps: Disk189/13suites + Clear12/core14/checkbox + plan/design/schema/parser. Trace artifacts/readiness-20261010-094026-2c5c13f5/readiness.json và operations-session-verification.json. First readiness FAILED outdated26controls assertion, sửa29 rồi fullrerun đạt; không bỏ failed evidence. Production authority/external backup chưa triển khai; MemoryL3 chưa mở theo deps. Handoff10draft,71tasks/27done, no commit/push/newCI/VM/release proof. Các10.1/09.x bên dưới là lịch sử.

- **Hiện tại10.1:** WPF review preview hai bước đã nối selection/shared lock; tên/path/tác động, per-item ack, Danger phrase, Back reset. Phiên frozen payload/SID/context/policy/TTL, native metadata revalidation fixture; không full content hash/production authority. Production all Blocked,0deletion. Disk151/151 PASS9suites; Review15 + UI16, DiskUI26controls/WS172.2MB, inventory101.5MB snapshot. Clear12/12 PASS; checkbox lần đầu FAIL service inventory unavailable, standaloneCIM304services rồi rerun cùng test PASS, root cause chưa rõ. Evidence docs/verification/review-session-verification.json và disk-*.json; review PNG đã xem. Preview-DiskReview.ps1 parser PASS, interactive chưa chạy. CD-03/04review, HO10doing/draft;71tasks/27done. Các09.x bên dưới là lịch sử. Không commit/push/newCI/VM proof.

- **Hiện tại09.7:** Đã nối lịch sử quan sát vào owner worker; UTC/source/entry ID/version, SID/catalog/root identity/age. History own .data bounded exclusive store, checksum/corrupt/lock/SID/future/expiry guards; not atomic/crash-safe and not trusted uninstall/deletion proof. GUI installed→missing displays previous observation/provenance but keeps deletion disabled. Disk120 tests PASS (18+13+16+17+9+17+30), PS5.1.26100.9444; WPF25controls/WS162.8MB, inventory90.4MB snapshots; PNG đã xem. Docs CLEAN_DATA_OWNER_HISTORY.md và disk-owner-history-tests.json. CD-02/03review, HO10draft/doing. No user-data/history writes during tests; newCI/VM/live coverage unproven; no commit/push.

- **Baseline09.6:** User chọn ưu tiên nhận diện cache/app. App thật có checkbox Cache / dữ liệu app còn sót, scan AppData mặc định Chrome/Edge/VSCode và dataClass + lifecycle chỉ đọc. Catalog/schema + AppProfiles.ps1; native directory probe phân biệt absent/empty/unavailable, junction blocked. Không có lịch sử uninstall verified; residual candidate không safe/removed proof. CD-02/03review, HO10doing/draft. Disk100 assertions PASS (18+13+16+9+17+27), RAMClear12/12 + checkbox PASS; WPF25controls, PNG đã xem, WS166MB snapshot; inventory99.1MB. Evidence docs/verification/disk-*.json; docs/CLEAN_DATA_APP_PROFILES.md. Build-plan/check-plan/build-clean-data/check-clean-data18/check-memory13 và diff checks ghi trong HO10; không user cleanup, không newCI proof, không commit/push.

- User đã yêu cầu **triển khai lần lượt**, cập nhật handoff/status từng phase. Đã trả lời trực tiếp: portable quyền user + Windows xử lý system; permanent appdata sau hai bước duyệt. Không hỏi lại các quyết định này. Phase10 triển khai thực tế: CD-SCOPE/CD-01 done, CD-02/03/04/05/09 review, HO-10 doing/draft; không mark entire phase done. Tổng71/27 done; phase12 chưa mở theo deps.
- App thật **đã có tab Disk readonly**: ba retention levels, finder default512MB chỉnh MB/tuổi/đuôi file/chọn local personal subfolder trên OS volume; search/paging1000/background/cancel/elapsed/shared lock RAM/Disk. Scope changes bỏ preview, finder không auto-select. MainWindow.xaml/MemoryClear.ps1 đã sửa để tích hợp; RAM policy Normal/Strong không đổi. Prod delete `app/clean-data-policy.json` executionEnabled=false và nút dọn khóa.
- Native FileInventory.cs FileID/ancestor/allocated, skip reparse/cloud/ADS/UNC/full-volume/hardlinks, streaming/dedupe/budget/paging/issues; age/type trước page/totals. Inventory18/18 PS5.1.26100.9444, latest fixture WS90.4MB. WPF30 assertions PASS25controls/2tabs/native finder/appdata/injected owner worker/Partial/owner search/reset/shared lock; offscreen PNG đã xem, WS162.8MB. Snapshot không Windows10/11 matrix/soak benchmark.
- Native **fixture-only** guard9/9; FixtureExecutor17/17 PASS same-source-handle backup/hash/delete, destination held đến source close, cancellation/destination replacement/journal fault, competing thread write/rename denial. Journal v2 flushed sequence/hash/input digest/pre-commit receipt, readonly inspection không replay; prefix không tail completeness/authority. docs/CLEAN_DATA_TRANSACTION.md ghi contract/limits. GUI không import executor; production risk/owner/manifest/restore/power-loss/external disk/mapped writers/VM còn thiếu.
- RAM Clear regression12/12 PASS sau thêm Disk. Evidence `docs/verification/disk-*.json`; CI mới được cấu hình nhưng chưa push/run observed. Desktop shortcut vẫn trỏ source hiện tại, chưa tự launch visible GUI. Handoff10draft ở `docs/handoffs/PHASE-10-HANDOFF.md`, scriptoperator `scripts/Verify-Phase10.ps1` tự cd và chỉ kiểm fixture.
- Lượt tiếp tục09.4: Disk60 checks PASS (inventory18/guard9/executor17/WPF16), Clear12/12 + checkbox PASS sau finder/shared-lock thay đổi. Build-plan/check-plan/build-clean-data/check-clean-data18/check-memory13 và git diff --check PASS. 71tasks/27done; HO10doing/draft, không tự commit/push. Evidence snapshot ngày09/10/2026, không fake VM/CI.
- Lượt09.5: Phân tích ứng dụng readonly trên GUI; Ownership13/13 + WPF22 PASS. Disk79 checks PASS aggregate18+13+9+17+22, Clear12/12 + checkbox regression PASS. Plan/design builders/check-plan/clean-data18/memory13 và diff --check PASS. New product policy/schema budgets/freshness/no commandline/no absence inference; CIM collector code chưa live verify (test providers synthetic). Unknown/shared/metadata/ref không được xóa; vendor removed cache/history/VM còn thiếu. CD-02/03review, HO10doing/draft.
- User yêu cầu **mỗi khi dừng phải đề xuất và hỏi hướng tiếp tục**. Đã lưu ở AGENTS.md; hỏi ưu tiên concrete options, không hỏi lại authorization đã có. Lượt sau tiếp phase10, không nhảyphase12/gates.

### Historical design baseline (09.2; không là trạng thái runtime hiện tại)

- Yêu cầu mới để user confirm trước: cả Memory và Disk có ba mức; safe không popup, review có effects, danger hai bước có scope, protected/unknown không override. Disk thêm verified app-removed cache/empty safe và large finder readonly; mixed data/size/age không chứng minh rác. Memory L1 Tiêu chuẩn/L2 Chuyên sâu giữ Normal/Strong trim, L3 Giải phóng tác vụ thêm close theo profile, force riêng/no fallback. App thật vẫn hai mức trim, không sửa MemoryClear.ps1/app policies/runtime.
- Artifact hiện tại: `MemoryClear-Memory-Plan.html`, `MemoryClear-CleanData-Plan.html`, prototype chung `MemoryClear-CleanData-Prototype.html` (#memory mở Memory). Master `MemoryClear-Plan.html` đã thay mockup bằng overview ba mức hai tab và links. Architecture `docs/MEMORY_THREE_LEVELS_DESIGN.md` + `docs/CLEAN_DATA_ARCHITECTURE.md` mục9; config/schema design_only/executionEnabled=false. 22 Disk groups/files và9 process fixtures là mẫu, không inventory máy.
- `node plan/check-clean-data.mjs` **18/18** + `node plan/check-memory-design.mjs` **13/13** đạt: schema/model/HTML/DOM fixture handlers, risk/TTL/backup/safe no-popup/large filters/no-autoselect, close-save held gain0/force reviewed-name/fresh identity/shared lock/cancel. Trace ở `docs/verification/*design-checks.json`. **Visual QA chưa kiểm chứng**: file:// browser policy restriction trước đó vẫn ghi rõ, không retry server/alternate browser để vòng policy. Chưa có native Windows scanner/delete/UAC/close/force/restore/VM/performance redesign.
- Kế hoạch09.2 **71 tasks/25 done**. Phase09 (6 docs) và phase11 (4 docs) hoàn tất thiết kế/handoff; phase10/12 giữ decision/todo, RAM phase03 giữ review. Build/check-plan đạt source/gates/import/export; runtime release chưa đạt. Handoffs `docs/handoffs/PHASE-09-HANDOFF.md` và `PHASE-11-HANDOFF.md`. CD-SCOPE chốt backup/retention/helper trust; ML-SCOPE cần app/profile effects và close/force permissions riêng, allowlist production mặc định trống. User chưa confirm thực thi chỉ bằng xem ambient browser.
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

- Ưu tiên ML01 native nonempty profile/invalidation + SAFE04/QA02 để mở graceful-only L3 sau gates; tiếp CD04/05 production history/backup. Scope opt-in đã chốt, không hỏi lại.

- Ưu tiên ML01 native nonempty profile/invalidation + SAFE04/QA02 để mở graceful-only L3 sau gates; tiếp CD04/05 production history/backup. Scope opt-in đã chốt, không hỏi lại.

- Tiếp CD-02/04 production owner/risk/scope authority (fixture authority đã đạt), CD-05 external backup provider và full disk/disconnect/mapped-write/power-loss matrix; cần môi trường Win10 VM/ổ phụ. Script Verify-Readiness.ps1 tự cd đã chạy currentWin11; không coi host này là disposable VM. Sau gates mới chốt HO10/phase12 profile Close/Force và runtime3levels. User đã yêu cầu làm liền mạch; chỉ hỏi thông tin môi trường thiếu, không hỏi lại chọn phần triển khai.

0. **Ưu tiên phase10 đang triển khai:** đọc handoff10draft và CLEAN_DATA_TRANSACTION.md. Tiếp owner/vendor positive rules (CD-02), independent production scope/risk/approval authority (CD-04), actual interruption/restore-conflict/crash recovery (CD-05), UI review/history/restore (CD-03), WindowsDelegated providers (CD-06) sau deps, VM gates (CD-07/08). Same-handle fixture đã có; không mở productiondelete/HO10/phase12 từ fixture pass.
1. Đọc IMPLEMENTATION_PLAN, tasks.json, handoff09/11 cho thiết kế Disk/Memory và phase03 cho runtime RAM. Nếu có progress JSON user mới, reconcile trước rebuild; chưa có export mới trong lượt redesign. Build-plan dựng master/MD; build-clean-data dựng cả hai plans/prototype.
2. CD-SCOPE đã chốt portable/system delegated/permanent hai-step. ML-SCOPE còn app/profile cụ thể, close/force permission riêng; allowlist production mặc định trống, safe disposable fixture không là apps thật. Không coi user chốt permanent là quyền auto-delete unknown appdata.
3. Code Disk CD-01 readonly scanner → CD-02 owner + CD-09 finder → UI/guards/backup/native providers/VM theo deps. Code Memory ML-01 sau ML-SCOPE/HO-02; ML-03 executor chỉ sau SAFE-04 + QA-02 + planner/UI gates. Không auto Force từ Close timeout, không auto chọn file to/cũ hoặc app đã gỡ chứa userdata.
4. Tiếp tục nghiệm thu RAM phase03: Normal/Strong trong VM, progress/foreground/cancel/timeout/page faults, phản hồi app sau trim và UI/DPI/keyboard/idle/minimized/soak. Handoff/HO-03 chỉ done khi đủ task/evidence rồi đi phase04–06.
5. Operator mở Memory plan, Disk plan và prototype chung bằng `powershell -NoProfile -File "E:\SourceCode\NEW_APPLICATION\MemoryClear\scripts\Open-CleanData-Design.ps1"`; script tự cd root, verify hai config executionEnabled=false rồi mở3 HTML. PS5.1.26100.9444 parser đã đạt, agent chưa execute mở browser. Không dọn/UAC/build.
6. Operator nạp GUI RAM bằng `powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "E:\SourceCode\NEW_APPLICATION\MemoryClear\MemoryClear.ps1"`. Script tự cd project. ZIP mới: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "E:\SourceCode\NEW_APPLICATION\MemoryClear\scripts\Package-Preview.ps1"`.

## OPEN

- Memory3: until nonempty profile/revalidate/native safety/action traces đạt; task execution=false, no force fallback.
- Appdata/orphan production: until verified vendor/version/root/dependency authority; không infer uninstall từ key missing.
- Backup external/Win10/release: until có trace môi trường thật, không đoán VM/CI.

- Memory3: until nonempty profile/revalidate/native safety/action traces đạt; task execution=false, no force fallback.
- Appdata/orphan production: until verified vendor/version/root/dependency authority; không infer uninstall từ key missing.
- Backup external/Win10/release: until có trace môi trường thật, không đoán VM/CI.

- until: production authority + external backup provider + Windows10/11 disposable VM/storage fault + user keyboard/DPI nghiệm thu. Operations10.2 chỉ marked fixtures; backup hiện cùng volume gain0. Recent history/journal prefix không trusted anchor; partial restore files giữ để kiểm tra.
- until: có môi trường VM/ổ phụ khả dụng và được xác nhận dùng riêng test. Không tìm thấy Get-VM/VBoxManage/vmrun trong command lookup; HypervisorPresent=true trên Dell không là proof guest/disposable VM. Async question môi trường đã gửi; chưa dùng answer giả.

- until: CD-03 production UI/backup/history/restore và Win10/11 keyboard/DPI/latency acceptance có evidence. Review10.1 chỉ preview; synchronous100item revalidation chưa latency benchmark, TTL kiểm khi bấm nút chứ chưa timer.
- until: QA-01/CD-02 có chẩn đoán live CIM theo nhiều mẫu. Checkbox10.1 fail lần đầu thiếu service inventory, rerun PASS; giữ cả hai sự kiện, không bỏ guard hoặc claim nguyên nhân đã sửa.

- until: independent uninstall/vendor-version/live coverage + Windows10/11 crash/power-loss/multi-user tests có evidence. History09.7 local chỉ supporting observation; corrupt file cần xử lý có chủ đích, không silently reset, không dựa checksum để cấp quyền xóa.

- Catalog09.6 chỉ ba default stable app roots, không historical verified uninstall/custom/portable/version proof. **until:** CD-02 có evidence độc lập và test provider/live/VM; giữ production delete disabled và không label residual là rác chắc chắn.

- until: owner live CIM/registry/MSIX coverage, cancellation latency, vendor/history/no-live-dependency proof và VM đạt. Ownership classifier có positive metadata và reference fixtures, không là orphan-safe proof; không dùng absence/metadata để cấp deletion authority.

- until: CD-02/03/04/05/09 hoàn thiện production, CD-06/07/08 có gates/evidence và HO-10done. Scanner readonly hoạt động, dọn thật khóa; fixture modules không đủ authority/backup safety cho user data.
- until: Windows10/11 VM/filter-driver/mapped-writer/multi-instance/soak/DPI/keyboard/actual crash/full disk/external removal/restore matrix chạy. Local fixture competing-thread/source/destination guards có, không đủ toàn bộ race/production matrix.
- until: user review/confirm Memory ba mức và ML-SCOPE app/profile/permissions cụ thể. Chỉ prototype/model, chưa đổi runtime/allowlist; critical/foreground/unknown giữ.
- until: ML-01/02/03/04/HO-12 cùng SAFE-04/QA-02 có native/VM/acceptance evidence. Fixture identity/held/force gates không chứng minh Windows runtime safety hoặc release.
- retired: CD-SCOPE quyết địnhportable/Windows-delegated/permanent hai-step đã được user trả lời trực tiếp09.3. Backup destination chỉ cần khi chọn backup mode; không chặn readonly development.
- until: operator review HTML visual / CD-03 và ML-02 WPF acceptance có evidence. Browser file:// bị policy chặn, DOM fixture không thay visual QA.
- until: CD-01/04/05/06/07/08 + HO-10 đạt. Chưa có bộ dọn FS thật; UAC/TOCTOU/backup restore/Win10-11 VM/performance chưa kiểm chứng; không có release Cleanup.
- until: người dùng mở GUI từ Desktop và xác nhận hoạt động. Shortcut đã xác minh cấu trúc; nếu di chuyển project phải chạy lại script tạo shortcut từ vị trí mới.
- until: CLEAR-01 có báo cáo VM áp lực RAM/foreground/cancel/progress Normal/Strong và hiệu năng khi dùng lại app. Hiện fixture/native API/worker/progress/UI state được kiểm chứng; chưa chạy Clear lên process công việc thật.
- until: UI-01/QA-01/CLEAR-01 và handoff đạt tiêu chí. Phase 03 giữ review; Windows 10/DPI/keyboard/GUI overhead/soak còn thiếu.
- until: người dùng cung cấp và duyệt danh sách app đóng một chạm. Không có cách suy ra “chắc chắn không cần” từ CPU thấp hoặc chạy nền; Clear hiện giữ process.
- until: QA-02/03 và REL-02 có kết quả VM/ma trận. Close/Kill/emergency preview chưa đủ nghiệm thu phát hành; process restart/PID reuse/access denied/dữ liệu chưa lưu còn cần ma trận.
- until: operator chạy script package và xác minh artifact mới. ZIP cũ không chứa Clear; không gửi nó như bản mới.
- until: có kiểm thử nhiều instance. Settings/log cùng ghi và cooldown giữa instance chưa được bảo đảm.

## AVOID

- Không import FixtureExecutor vào GUI hoặc bật production delete chỉ vì guard/scanner test pass. Native fixture deletion chỉ artifacts có marker; digest không security boundary. Giữ HO10draft/doing khi còn tasks/gates thiếu, không chuyển phase12 bỏ deps.
- User đã cho triển khai app thật theo phases; vẫn không auto Delete/Close/Kill từ lựa chọn plan. Safe không popup, warning chỉ selected-risk; confirm/UAC không bỏ blocked. Task tên/CPU/RAM và file to/cũ/app removed không chứng minh disposable/userdata vô giá trị.
- Không auto Close→Force, không kill tree hoặc ngầm cấp force permission từ saved close profile. App hỏi lưu/không thoát gain0, fresh identity đổi skip; L1/L2 trim không hứa giảm CPU/commit.
- Không đọc/xóa dữ liệu C: thật để thử prototype, không bypass UAC/TrustedInstaller/takeown/ACL, không tự kill app hoặc xóa repair cache/WinSxS/SoftwareDistribution thủ công. Thiếu uninstall key chưa chứng minh AppData rác; cloud/source/profile unknown giữ lại.
- Không tính quarantine cùng ổ là đã thu hồi dung lượng, không cộng size unknown vào reclaim, không coi elapsed/progress/GB fixture là số đo thật. Không coi helper chạy từ folder user-writable là security boundary.
- Không vòng browser policy file:// bằng server/alternate browser/tool. Giữ giới hạn QA trung thực; operator có thể tự mở HTML đã tạo.
- Không chạy Clear/Kill thử trên app công việc, không dựa vào tên/PID/CPU để quyết định đóng; fixture test luôn cô lập dữ liệu và chỉ dọn PID do test tạo.
- Không hứa dọn toàn bộ RAM, không gán biến động available RAM toàn máy cho riêng trim. Trim không decommit, RAM có thể nạp lại; commit gần giới hạn cần lưu/đóng app.
- Không purge cache, tắt pagefile/security, suspend để quảng cáo dọn RAM hoặc tự nâng admin/force kill. Giữ quyền đóng khẩn cấp riêng và có xác nhận.
- Không đánh dấu phase hoàn tất khi handoff/tasks còn review. Không bỏ gate bảo vệ/VM vì render hoặc unit test đã đạt.
- Giữ UTF-8 BOM cho PowerShell có tiếng Việt để Windows PowerShell 5.1 đọc đúng. Test cũng phải dùng `powershell.exe`, không thay bằng `pwsh` rồi claim đã kiểm chứng 5.1.
