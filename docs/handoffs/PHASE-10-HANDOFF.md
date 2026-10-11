# Handoff — Phase 10 · Clean Data — triển khai

- Ngày cập nhật: 2026-10-10 (Asia/Tokyo)
- Người thực hiện: Codex
- Trạng thái bàn giao: **Nháp — đang triển khai, chưa kết thúc phase**
- Task handoff: HO-10 (doing)
- Phiên bản kế hoạch: 2026-10-10.4
- Branch / commit: main, nền0f44426052d6077da171d464b9feb9a32113a480; thay đổi chưa commit/push. CI bổ sung chưa chạy server-side.

**Checkpoint hiện tại10.4 — 2026-10-10:** Dọn Temp có duyệt đã chạy thật trên exact QA files mới tạo trong Temp của user: backend12/12 + WPF7/7, native owner/root/SID/hash/same-handle/permanent hai bước/no Undo, .tmp/.log top-level≥7/7/3days, ≤64MiB/file, non-elevated, no recursion/force. File mới/locked/linked/protected/unknown giữ lại. GUI progress/cancel/endtime/journal/shared lock. Không xóa file có sẵn. Finder/appdata không được cấp authority; orphan/vendor authority và production backup khác volume còn thiếu. Windows system delegation không claim cleanup bytes. User chỉ có Win11; Win10/VM/fault/DPI/release chưa kiểm chứng. User đã chốt Memory3 Cho đóng gấp opt-in:3cards/readonly preview, policy/UI11 checks và Clear12 regression đạt; task executor chưa mở theo SAFE-04/QA-02 và ML01 validation. Scope task ML-SCOPE mới done; toànrepo71/28done. HO10/HO12 draft. Không commit/push/package/CI mới. Các10.2/10.1/09.x phía sau là lịch sử; nhận xét production disabled trước10.3 không áp dụng cho Temp capability mới.

Files mới: TempCleanup/TempView/temp-policy/schema, Native OwnTemp/TempLedger; MemoryClear.Tasks/MemoryTaskView/memory-task-policy/schema/3cards. Docs CLEAN_DATA_TEMP/MEMORY_TASK_RUNTIME, tests Temp12/UI7/Memory11, Verify-OwnTemp và readiness option -OwnTempSelfTest, schema checks/CI/package source config. Commands tự cd/PS5: powershell -File "E:\SourceCode\NEW_APPLICATION\MemoryClear\scripts\Verify-OwnTemp.ps1"; powershell -STA -File "E:\SourceCode\NEW_APPLICATION\MemoryClear\tests\Check-TempUI.ps1"; powershell -STA -File "E:\SourceCode\NEW_APPLICATION\MemoryClear\tests\Check-MemoryLevels.ps1". Evidence reports tương ứng và temp-session-verification.json.

Open/next: CD04 production journal readonly integrity/history, scoped cache/orphan authority; CD05 backup volume/source-retain/restore no-overwrite/fault QA. Memory tiếp ML01 nonempty profile/exe/setting/SID/foreground/TTL invalidation, rồi SAFE04/QA02 dependencies trước ML03 close/timeout/save prompt. AVOID: UAC/ACL bypass, recursive Temp cleanup, age/name=trash, existing-user-file deletion/app kills for QA, auto-force/replay, overwrite backups, fake VM/CI/release proof.

**Final verification10.4:** full readiness14steps đạt tại `artifacts/readiness-20261010-114058-39b783ae/readiness.json`;14 baseline Disk suites194 + ownTemp12/UI7 =213 checks/16suites, Clear12/Core14/checkbox/Memorylevel11, Diskdesign18/Memorydesign13/runtimepolicy9/PS5parser/plan đạt. Sau checkpoint đã sửa riêng TempCleanup/TempView để ghi Outcome/lý do skip và hiển thị kết quả từng file; hai suite Temp12/UI7 đã rerun sau sửa và đạt. Full suite không rerun sau hai thay đổi nhỏ này; public summary ghi chính xác2 source hash differences và current hashes/post-change timestamps. Lệnh node build/check plan/design/schema và git diff --check đạt cuối lượt. Evidence `docs/verification/temp-session-verification.json`. Không commit/push/package/CI/VM/release proof.

## 1. Mục tiêu và phạm vi đã chốt

User yêu cầu triển khai lần lượt, cuối phase cập nhật handoff/status. Hai trả lời trực tiếp chốt: **portable quyền user + Windows xử lý mục hệ thống**, **cho xóa vĩnh viễn app data sau hai bước duyệt**. Không cần hỏi lại phương án này; không có quyền tự xóa dữ liệu thật khi chạy test. Không cài elevated helper, không bypass UAC/ACL; giữ exact scope/two-step trước production permanent.

Hiện app có tab Disk thật **chỉ đọc**, ba retention levels, finder chỉnh MB/tuổi/đuôi file và chọn thư mục con cá nhân KnownFolders trên OS volume, search/paging/background/progress/cancel. File lớn/cũ không tự chọn. Native same-handle backup/hash/delete và journal v2 recovery inspection chỉ thử trong workspace artifacts có marker; production policy `executionEnabled=false`, nút dọn bị khóa. Memory còn Normal/Strong, phase12 chưa mở vì dependency/gates chưa hoàn tất.

## 2. Kết quả theo task

**Lịch sử10.2:** CD-SCOPE/CD-01 đã done từ trước; CD-02/03/04/05/06/07/08/09 review; HO10doing. Không có task whole-phase mới đạt mọi tiêu chí, giữ71/27done. Đã hoàn tất các hạng mục con fixture authority/content hash/transaction/restore/history/UI/timer/crash/Windows delegation/scripts; còn production owner/external/VM/operator gates.

| Task ID | Trạng thái | Kết quả thực tế | Bằng chứng |
|---|---|---|---|
| CD-SCOPE | done | User chốt portable/delegated và permanent hai bước; giữ retention proposal | User async replies; app/clean-data-policy.json |
| CD-01 | done | Native FileID/ancestor/allocated, streaming/paging, filters trước paging/totals, cloud/reparse/hardlink/permission/cancel/budget | Check-DiskInventory.ps1 18/18; disk-inventory-tests.json |
| CD-02 | review | Registry/MSIX metadata + process/service/task collector; installed/shared/referenced/unknown states; catalog readonly ba app + dataClass/lifecycle candidate; lịch sử quan sát SID/catalog/root + UTC/source/entry/version; chưa verified uninstall/version proofs | Ownership.ps1; ownership13/13 + profiles16/16 + history17/17 fixtures; CLEAN_DATA_APP_PROFILES.md |
| CD-03 | review | WPF26 controls/2 tabs; thêm review tên/path/tác động, hai bước/phrase/back/reset/selection/shared lock. Production all Blocked, preview không xóa | DiskUI30 + Review15 + ReviewUI16 PASS; hai PNG review đã xem; CLEAN_DATA_REVIEW.md |
| CD-04 | review | Stable handle fixture guard + competing thread write/rename denial, destination ID guard | Guard9/9 + Executor17/17; chưa production authority |
| CD-05 | review | Same-handle backup/hash/delete, pre-commit receipt, flushed hash-chain journal/recovery inspection/no replay | Executor17/17; CLEAN_DATA_TRANSACTION.md |
| CD-09 | review | Finder chỉnh MB/age/type/local subfolder; filters trước page, preview invalidation; không delete authority | Inventory18 + WPF30; CD-02/VM chưa đạt |
| CD-06 | review | Catalog/schema/module + GUI Windows Storage/apps, fixed URIs, build provenance, Prepared/Delegated/Unavailable/Failed, no bytes claim | WindowsProviders5 PASS prepare-only; launch/cleanup completion chưa interactive |
| CD-07 | review | Readiness currentWin11 host và actual fixture crash/timer workers đã chạy; ma trận VM chưa chạy | operations-session-verification.json; VMDeclared=false |
| CD-08 | review | PS5 readiness/preview/package-entry verification và runbook đã có; package/operator release chưa chạy | Verify-Readiness.ps1 parser/execution trace; Package-Preview.ps1 parse-only |
| HO-10 | doing | Draft handoff; không mark phase done | Tài liệu này/tasks.json |

## 3. Thay đổi và điểm vào để tiếp tục

10.2: thêm Operations.psm1, OperationView.xaml/.ps1, WindowsProviders.psm1, execution/provider JSON+schemas, Check-DiskOperations/Crash/OperationUI/WindowsProviders + fixtures/Disk-CrashWorker.ps1, Preview-DiskOperations.ps1/Verify-Readiness.ps1, CLEAN_DATA_OPERATIONS.md, record-disk-operations.mjs/check-runtime-policies.mjs. FileInventory.cs thêm process-local concurrent session store, frozen hash held-source API, verified restore partial-copy/rename; main modal coordinator flag fix. Verify-Phase10/CI gồm13 suites; Package-Preview bổ sung plans/modules/policies/scripts. Old FixtureExecutor không import GUI; Operations mới chỉ accept marked fixtures.

Lượt10.1 thêm `Review.psm1` (snapshot phiên, TTL/SID/context/policy/metadata, state machine), `ReviewView.xaml/.ps1` (cửa sổ WPF), `disk-review-policy.json` + schema, `Check-DiskReview.ps1`, `Check-DiskReviewUI.ps1`, `Preview-DiskReview.ps1`, `CLEAN_DATA_REVIEW.md`. Sửa `DiskView.xaml/.ps1` và `MemoryClear.ps1` để nối selection/shared lock; Verify-Phase10 và CI thêm hai suites. `plan/record-disk-review.mjs` ghi revision từ evidence; tasks.json vẫn là nguồn status. Không import FixtureExecutor vào GUI.

| File / module | Thay đổi | Người tiếp nhận cần biết |
|---|---|---|
| app/CleanData/FileInventory.cs | Native readonly directory probe absent/empty/present/unavailable, snapshots/filtered page; ExecuteFixture backup/hash/delete cùng handle, HashSnapshot/ReadSnapshotText | Source/destination/ancestor handles giữ đến commit; no production authority |
| app/CleanData/MemoryClear.Disk.psm1 | Validated readonly policy, KnownFolders/cloud/OS-volume scope, registry/MSIX inventory, unknown owner | Vendor rule list trống; không Win32_Product, không infer orphan từ key thiếu |
| app/clean-data-policy.json + schema | product_runtime/read-only budgets/3 levels | Production writes disabled; no elevated helper |
| app/CleanData/DiskView.xaml/.ps1 | WPF tab/worker/search/page/progress/shared lock | FixtureRoots hook chỉ nhận marker trong artifacts, user mode không dùng fixture |
| app/MainWindow.xaml, MemoryClear.ps1 | TabControlMemory/Disk, operation/cancel/shutdown coordination | RAM Clear không đổi policy; Clear12/12 regression pass |
| app/CleanData/FixtureExecutor.psm1 | Fixture manifest/independent scope, journal v2 sequence/hash/input digest/receipt + inspection | **GUI không import**; digest/hash-chain local không adversarial boundary; không tự replay/restore |
| docs/CLEAN_DATA_TRANSACTION.md | Contract transaction, journal v2, commit ambiguity và missing gates | Legacy journal không tự migrate/resume; verified prefix không proof tail đầy đủ |
| app/CleanData/Ownership.ps1; app/owner-analysis-policy.json + schema | Readonly metadata/dependency classifier and collector; policy/source budgets | Collector tests dùng injected CIM, chưa live coverage; no command-line/removal inference/deletion authority |
| docs/CLEAN_DATA_OWNERSHIP.md | Four owner states, provenance, freshness/unknown, GUI worker | Metadata/reference là lý do giữ, không disposable proof |
| app/CleanData/AppProfiles.ps1; app/disk-app-profiles.json + schema | Catalog default Chrome/Edge/VSCode, cache/personal/unknown, residual candidate lifecycle | Candidate never deletion authority; no historical verified uninstall/version proof |
| docs/CLEAN_DATA_APP_PROFILES.md; tests/Check-DiskAppProfiles.ps1 | Provenance/limits and16 fixture assertions | No real app data read/deleted; unknown custom/portable remains outside coverage |
| app/CleanData/OwnerHistory.ps1; owner-history-policy/schema + payload schema | Bounded local observation history + provenance, SID/catalog/root binding, expiration | Not uninstall proof; own .data only; current reference/unknown precedence |
| FileInventory.ObservationStore | Exclusive source/ancestor lease, checksum wrapper, bounded metadata file | Flush but NOT atomic/crash-safe; corrupt/locked/SID mismatch do not auto-reset; no privileged boundary |
| docs/CLEAN_DATA_OWNER_HISTORY.md; Check-DiskOwnerHistory.ps1 | Contract/format/failure semantics and17 fixture checks | Native fixture persistence only; no real user data/history changes |
| AGENTS.md | User yêu cầu hỏi hướng tiếp tục khi kết thúc lượt | Đề xuất cụ thể + lý do; không hỏi lại authorization/phạm vi đã chốt |
| tests/Check-Disk*.ps1 | Native/inventory/guard/executor/WPF fixtures | Paths có marker dưới project artifacts; không xóa fixture đệ quy tự động |
| scripts/Verify-Phase10.ps1 | PS5 self-contained operator checks | Tự cd root; không build/deploy hoặc clean user data |
| .github/workflows/verify.yml | Thêm design checks + Disk fixture gates | Chưa push/chưa quan sát CI chạy; không coi là green |
| docs/verification/disk-*.json | Trace executed local PS5 gates | Public fixture data only; số WS không benchmark GUI whole-machine/soak |

## 4. Cách chạy và kiểm chứng

**Kết quả mới nhất10.2, thay thế mọi snapshot cũ bên dưới:** Windows11 client build26200/25H2 từ HKLM CurrentBuildNumber/InstallationType/DisplayVersion, PS5.1.26100.9444. `powershell -NoProfile -File "E:\SourceCode\NEW_APPLICATION\MemoryClear\scripts\Verify-Readiness.ps1" -ExpectedFamily Windows11` executed11 steps PASS. Disk **189/189**/13suites =18+13+16+17+9+17+30+15+16+17+3+13+5; Clear12/12; core14/14; checkbox PASS; build/check-plan/build-clean-data/Disk18/Memory13/runtime-policies5 và toàn bộ PS5 sources parse PASS. Readiness artifacts/readiness-20261010-094026-2c5c13f5/readiness.json; public summary operations-session-verification.json có code hashes/OS provenance. Source WS snapshots mới đọc trong disk-ui/inventory reports, không budget/soak proof.

Readiness lần đầu artifacts/readiness-20261010-091850-780c1aab/readiness.json FAILED vì testReviewUI còn expected26controls sau thêm3nút; source có review control. Đã sửa expectation29, giữ failed trace và fullrerun đạt. Runtime reverse policy không sửa/không bỏ safety check để làm xanh. Actual child exit77 tại BackupVerified/DeleteStarted/Committed: predelete nguồn còn đúng hash, postcommit backup xác minh/phục hồi đúng; missing Finished báo InterruptedUnproven. Đây chưa là power loss/full disk/external loss/VM proof.

`powershell -NoProfile -STA -File "E:\SourceCode\NEW_APPLICATION\MemoryClear\scripts\Preview-DiskOperations.ps1"` tự cd/tạo mẫu/mở giao dịch; parser PASS, agent chưa launch interactive. WPF actual DispatcherTimer/Run/Inspect/Restore/History trên fixtures13 assertions PASS; Plan PNG đã xem, cột tác động sửa đọc được. Windows providers5 prepare checks PASS, không launch Settings hoặc claim cleanup completion. Package script parse/entry list đã sửa; chưa chạy ZIP/build/deploy. CI mới chưa push/run server-side. Git diff --check cuối lượt ghi trong trace final, không giả CI.

**Kết quả hiện tại10.1, thay thế số snapshot ở các baseline bên dưới:** `powershell -NoProfile -File "E:\SourceCode\NEW_APPLICATION\MemoryClear\scripts\Verify-Phase10.ps1"` chạy9 suites **151/151 PASS**: inventory18 + ownership13 + profiles16 + history17 + guard9 + executor17 + DiskUI30 + Review15 + ReviewUI16. PowerShell5.1.26100.9444. DiskUI26controls, WS172.2MB; inventory101.5MB snapshot, không benchmark. Trace `docs/verification/disk-*-tests.json`, UTC2026-10-09T22:34–22:38 tương ứng ngày10/10 Asia/Tokyo. Review step1/2 PNG đã xem; offscreen WPF không là interactive/DPI nghiệm thu.

Clear12/12 PASS lượt này. Checkbox lần đầu FAIL `Service inventory unavailable`; lệnh chẩn đoán riêng đọc được304 services, chạy lại cùng test không sửa code PASS. Chưa xác minh nguyên nhân lần lỗi đầu; không kết luận provider luôn ổn định và không bỏ guard. Trace tổng hợp `docs/verification/review-session-verification.json`; kết quả mới nhất `artifacts/checkbox-tests.json`. UI review không gọi process action.

`powershell -NoProfile -STA -File "E:\SourceCode\NEW_APPLICATION\MemoryClear\scripts\Preview-DiskReview.ps1"`: script mẫu tự cd/tạo fixture/mở review/kiểm hash sau đóng. PS5 parser PASS; agent chưa chạy interactive. GUI thật chỉ hiện blocked do production authority chưa đạt. Scripts thử nghiệm giữ fixture, không tự xóa đệ quy.

Plan10.1 đã dựng/kiểm tra: `node plan/build-plan.mjs`, `node plan/check-plan.mjs` PASS71tasks/27done; `node plan/build-clean-data.mjs`, `node plan/check-clean-data.mjs` PASS18/18; `node plan/check-memory-design.mjs` PASS13/13; `git diff --check` PASS. Trace tổng hợp `docs/verification/review-session-verification.json`. CI mới chưa push/chạy server-side; Win10/11 VM/crash/restore/DPI chưa nghiệm thu. Các số09.6/09.7 dưới đây là lịch sử, không phải kết quả lượt này.

Môi trường: Windows hiện tại, Windows PowerShell **5.1.26100.9444**, x64. Native Add-Type là test/module runtime compilation, không release packaging/deploy. Lệnh từ root:

- `powershell -NoProfile -ExecutionPolicy Bypass -File "E:\SourceCode\NEW_APPLICATION\MemoryClear\tests\Check-DiskInventory.ps1"`:18/18 PASS; fixture process working set **90.4MB** snapshot cuối. Longpath đọc được hoặc report skip; denied fixture ACL được khôi phục; age/type trước paging/totals. Không soak benchmark.
- `powershell -NoProfile -ExecutionPolicy Bypass -File "E:\SourceCode\NEW_APPLICATION\MemoryClear\tests\Check-DiskOwnership.ps1"`:13/13 PASS; installed/shared/reference/unknown, stale/boundary/parser/no arguments, injected CIM providers/fixtures/cancel. Không claim đã gọi live native inventory hay chứng minh orphan-cache safe.
- `powershell -NoProfile -ExecutionPolicy Bypass -File "E:\SourceCode\NEW_APPLICATION\MemoryClear\tests\Check-DiskAppProfiles.ps1"`:16/16 PASS; exact catalog/protected data/residual-unverified/stale/reference/native empty-absent-junction/cancel/hash unchanged; only marked fixtures.
- `powershell -NoProfile -ExecutionPolicy Bypass -File "E:\SourceCode\NEW_APPLICATION\MemoryClear\tests\Check-DiskOwnerHistory.ps1"`:17/17 PASS; local seen/missing/corrupt/catalog/SID/future/expired/root-change/lock/hardlink/junction/cancel/scope and untouched app data. Only marked fixtures.
- `powershell -NoProfile -ExecutionPolicy Bypass -File "E:\SourceCode\NEW_APPLICATION\MemoryClear\tests\Check-DiskGuard.ps1"`:9/9 PASS; chỉ native delete fixture do test tạo. Held-source write/ancestor rename từ competing runspace có trong executor tests; chưa toàn bộ VM race matrix.
- `powershell -NoProfile -ExecutionPolicy Bypass -File "E:\SourceCode\NEW_APPLICATION\MemoryClear\tests\Check-DiskFixtureExecutor.ps1"`:17/17 PASS; same-handle backup/hash/restore fixture, cancel sau flush/destination swap/journal failure/recovery inspection/tail tamper/replay. Không actual power-loss/external full disk/crash replay proof.
- `powershell -NoProfile -STA -ExecutionPolicy Bypass -File "E:\SourceCode\NEW_APPLICATION\MemoryClear\tests\Check-DiskUI.ps1"`:30 assertions PASS;25 controls/2 tabs, native finder worker + injected inventory owner worker/Partial/owner search/shared lock/reset, no selection/delete; render offscreen đã xem, WS **162.8MB**. Không live inventory/operator folder-dialog click/Windows10/DPI/keyboard/soak.
- `powershell -NoProfile -STA -ExecutionPolicy Bypass -File "E:\SourceCode\NEW_APPLICATION\MemoryClear\tests\Check-Clear.ps1"`:12/12 PASS baseline09.6, không chạy lại09.7 vì RAM không đổi; real trim chỉ fixture test-owned.
- `powershell -NoProfile -STA -ExecutionPolicy Bypass -File "E:\SourceCode\NEW_APPLICATION\MemoryClear\tests\Check-Checkboxes.ps1"`:PASS baseline09.6, không chạy lại09.7; multi-select/refresh/saved allow-close/protection, no process actions.
- Revision09.7: node plan/build-plan.mjs/check-plan.mjs PASS71tasks/27done/source/embedded/gates/migration; build-clean-data.mjs PASS, check-clean-data.mjs18/18 và check-memory-design.mjs13/13 PASS, git diff --check PASS. Disk120 checks aggregate đã chạy và đạt; không coi rendering/unit/CI cũ là production deletion gate.

Operator dùng **một script tự cd project**: `powershell -NoProfile -File "E:\SourceCode\NEW_APPLICATION\MemoryClear\scripts\Verify-Phase10.ps1"`. Nó chạy bộ Disk tests trên fixtures, giữ artifacts để kiểm tra. Chạy app: `powershell -NoProfile -STA -ExecutionPolicy Bypass -File "E:\SourceCode\NEW_APPLICATION\MemoryClear\MemoryClear.ps1"`; script tự cd. Desktop shortcut cũ trỏ cùng source, nên mở lại app sẽ lấy tab mới; agent không tự mở thêm visible app.

Baseline09.6 theo ưu tiên user: chọn Cache / dữ liệu app còn sót, Quét chỉ đọc rồi Phân tích ứng dụng. Catalog xác định loại dữ liệu; lifecycle không suy ra đã gỡ từ absence. EmptyAtObservation là quan sát có identity, không authority xóa folder. Dữ liệu custom/portable ngoài ba root mặc định chưa bao phủ. Baseline đó chạy6 suites/100 assertions; reports và PNG đã kiểm tra. Không commit/push lượt này.

Lượt09.7: Verify-Phase10 chạy7 suites/120 assertions đạt (UI30/history17). Native own-metadata store chỉ ghi fixture trong tests; production lưu .data khi user phân tích AppData. Đã xem PNG WPF lịch sử. Không live uninstall event/native inventory coverage/VM/crash/multi-user proof. Thêm nguồn entry/package ID và version vào collector; observation history là supporting evidence, không delete authority. Không commit/push.

## 5. Quyết định kỹ thuật và lý do

10.2 giữ production writes disabled theo gates đã chốt. Fixture operations authority dựa process-local plan tự phân loại và immutable JSON payload/SHA256; không GUI flags hay preview approval từ Review module. Consume checked under shared SID mutex, context/TTL/SID/policy/file verified. Native hash cùng source handle trước commit; same-volume backup gain0. Restore source backup giữ nguyên, original ancestry/current absent destination, temporary CREATE_NEW + hash/flush + held-handle rename ReplaceIfExists=false; no overwrite/replay. Separate restore log và committed-journal-incomplete status honest. Local hash/state không privileged boundary. External provider chưa triển khai, không claim rollback/mất điện guarantee.

Review10.1 đóng băng payload, tối đa100 mục/8 phiên/TTL600s, từng lần chuyển bước kiểm scope/SID/policy. Fixture kiểm lại FileID/ancestor/size/time/attributes/links; không full content hash hay held handle đến execution. Back xóa mọi approvals; invalid/cancel không hồi sinh. Safe-only fixture không final warning; Review cần ack; Danger cần ack+phrase. Mọi mục production vẫn Blocked. Modal giữ parent/shared lock; synchronous revalidation có giới hạn nhưng latency I/O chưa đo, chưa countdown. Đây là review UX/state validation, không độc lập cấp quyền xóa.

1. Scanner phase có thể nghiệm thu readonly riêng; deletion không mở chỉ vì age/type/file size. SafeCandidate là **ứng viên**, không authority; unknown user data giữ lại.
2. Root authority: current KnownFolders/temp, OS volume, cloud inventory fail closed, source/Windows/ProgramFiles blocked; không scan toàn volume hoặc UNC/ADS. Reparse/offline/recall flags/hardlinks skip. Native handles bảo vệ ancestor chain, metadata allocated khác logical.
3. Paging quét lại với run ID mới; file có thể đổi giữa pages. UI không giữ selection để xóa từ page cũ, production chưa có manifest. Max1000 rows/page,50000 entries/30s, skipped/truncated báo Partial.
4. Production portable không elevated helper. Native fixture guard được cô lập theo artifacts/marker, không chứng minh local code/digest là security boundary. User hai-step quyết định permanent nhưng cụ thể file/app vẫn cần scope approval lúc thao tác.
5. Fixture transaction giữ source handle cùng destination/ancestors trong copy/hash/flush/delete; callback phải flush pre-commit journal thành công. Recovery chỉ inspect prefix/state/hash, không replay-delete hay overwrite restore. Local chain không trusted anchor, tail truncation nguyên dòng chưa xác minh. Backup cùng ổ gain0. Production còn authority/vendor scope/restore/external interruption/full disk/power-loss/mappings/VM gates.
6. Chưa đi phase12/enableMemoryL3 hoặc mark phase10done: planned owner/production guards/OS adapters/VM/release còn thiếu.

## 6. Tồn tại, rủi ro và điểm chặn

**OPEN10.2:** production owner/risk authority và external backup provider còn implementation; Win10/11 disposable VM, full disk/disconnect/power loss/mapped writers/filter drivers/multi-instance/DPI/keyboard/interactive Settings/package acceptance còn unverified. until: có code/provider/gate traces đúng scope mới done/enable cleanup. Phát hiệncommand Get-VM/VBoxManage/vmrun không có trong command lookup; Dell physical model + HypervisorPresent không chứng minh có guest hoặc VM dùng riêng test. Đã hỏi async môi trường, không suy diễn answer. Memory runtime2levels, phase12/profile/safety gates chưa hoàn tất; chưa chuyển phase để bỏ dependencies.

| Vấn đề | Ảnh hưởng | Task xử lý / người phụ trách | Bước tiếp theo |
|---|---|---|---|
| Catalog Chrome/Edge/VSCode nhận diện ứng viên có; lịch sử quan sát local có; verified uninstall/version/no-live-dependency chưa proof | Không auto xóa orphan app data | CD-02 | Independent uninstall evidence + verified vendor version/no-live-dependency proof; live coverage/cancel latency/VM; unknown giữ |
| Fixture authority không production manifest | Chưa mở delete thật | CD-04/05 | Independent scope/two-step/permanent validation, journal/root identity/owner/trust |
| Same-handle fixture đã có, production authority/restore/interruptions chưa đủ | Không dùng trên dữ liệu thật | CD-05 | Crash/full disk/disconnect/mapped-writer/restore-conflict tests; trusted production scope/risk/backup |
| Review hai bước preview đã có; backup/history/restore/OS delegation UI còn thiếu | CD-03/CD-06 chưa done | CD-03/06 | Complete UI/capability/Delegated statuses sau guard gates |
| Một lần RAM checkbox bị chặn do service inventory unavailable, rerun đạt | Live provider ổn định chưa chứng minh | QA-01/CD-02 | Đo lỗi/latency CIM theo nhiều mẫu, giữ fail closed |
| VM/keyboard/DPI/soak chưa có evidence | Không release/close phase | CD-07/08 | Disposable Win10/Win11 scripts/matrix, user acceptance và artifact |
| Competing-thread write/rename test có; matrix/multi-instance chưa đầy đủ | Không claim full TOCTOU/session protection | CD-04/07 | VM/filter-driver/mapped-writer/multi-instance and actual process crash tests |

## 7. Hướng dẫn người / chat tiếp nhận

1. Đọc IMPLEMENTATION_PLAN.md/tasks.json/Handoff.md/CLEAN_DATA_TRANSACTION.md/CLEAN_DATA_OWNERSHIP.md/CLEAN_DATA_REVIEW.md và tài liệu này. Không có user-export progress JSON mới; revision10.1 giữ migration từ09.7.
2. Không hỏi lại portable/permanent hai-step đã trả lời. Retention giữ approved plan defaults; exact target apps/destination/data scope chưa được auto cấp quyền.
3. Tiếp CD-02/04 production owner/risk/scope authority; fixture authority/SHA256/restore/crash3/timer đã đạt, không làm lại từ đầu. CD-05 external backup provider + full disk/disconnect/power-loss/mapped-writer matrix, CD-07 Windows10/11 disposable VM + operator keyboard/DPI/Settings/package evidence. Dùng readiness self-cd và hỏi môi trường thiếu; không hỏi lại chọn hạng mục đã được user yêu cầu làm hết. Không mở production/phase12 khi deps chưa đạt.
4. UI thật vào Disk scan/read-only; bước debug dùng Verify-Phase10 script. No real user scan/delete in tests, only marked artifacts. Module FixtureExecutor không ship/import GUI.
5. Update tasks.json và handoff draft nếu dừng; build-plan/check-plan + build-clean-data/design checks. Chỉ hoàn tất HO-10 sau mọi tasks/gates rồi mới chuyển phase12.
6. Khi kết thúc lượt còn việc: đề xuất bước tiếp theo cụ thể, lý do và hỏi user ưu tiên hướng nào. User đã yêu cầu điều này; không coi là phải duyệt lại portable/permanent/current implementation scope.

## 8. Checklist kết thúc phase

- [x] Decision và readonly scanner có evidence.
- [x] Draft handoff phản ánh files/status/commands/limits.
- [x] Existing RAM Clear regression đã chạy.
- [x] OPEN/AVOID và precise next steps ghi rõ.
- [ ] Toàn bộ task phase10 đạt; production/VM/OS/acceptance còn thiếu.
- [ ] HO-10 done và phase kết thúc. Hiện phải giữ **doing**.

## Hồi quy native journal — 2026-10-11

TempLedger thêm prefix memory-operation, temp-operation cũ giữ nguyên. Full Disk/OwnTemp/UI readiness đạt: artifacts\readiness-20261011-020325-f5b9e55a\readiness.json. General finder/appdata deletion vẫn khóa. Phase10 giữ draft và các OPEN/AVOID cũ còn hiệu lực.

## Hồi quy native journal — 2026-10-11

TempLedger thêm prefix memory-operation, temp-operation cũ giữ nguyên. Full Disk/OwnTemp/UI readiness đạt: artifacts\readiness-20261011-020956-50571223\readiness.json. General finder/appdata deletion vẫn khóa. Phase10 giữ draft và các OPEN/AVOID cũ còn hiệu lực.

## GitHub publication — 2026-10-11

- Source commit: [57fb2d2](https://github.com/manhdauvn09-manhds/ClearRAM/commit/57fb2d2638ab9c10f579aacaa49bf2dd42c42c17), 143 file; đã push main của manhdauvn09-manhds/ClearRAM. git ls-remote và GitHub commit API khớp local SHA.
- Source CI: [run 38106638093](https://github.com/manhdauvn09-manhds/ClearRAM/actions/runs/38106638093) completed/success; mọi step plan/Disk fixture/policy/WPF/Clear/checkbox được quan sát success. Evidence docs/verification/github-actions-portable.json.
- Đây là CI của source commit trên; không suy ra full Windows10/VM/release hoặc mở Memory3. Task child13/UI6 là local Win11 trace, không là step native task execution trên server.
- .data, ZIP/artifacts, harness riêng và các file user không thuộc app không được commit. GitHub Download ZIP chứa source chạy bằng Start-MemoryClear.cmd; portable ZIP local chưa publish thành GitHub Release.
- Commit tiếp theo chỉ ghi publication/CI evidence và plan/handoff; không đổi runtime.
