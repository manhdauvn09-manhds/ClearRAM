# MemoryClear — Handoff hiện tại

Một bản duy nhất (C15). Các bản 2026-10-10.4 / 2026-10-11.1 / 2026-10-11 cũ đã được gộp vào đây ngày 2026-11-23; bản gốc xem git history (`git log -p -- Handoff.md`). Chi tiết từng phase: `docs/handoffs/PHASE-*.md`; tiến độ thật: `plan/tasks.json` (revision 2026-10-11.2, 71 task / 28 done).

## NOW — 2026-11-23 (Asia/Tokyo)

**Vị trí & git**
- Dự án chỉ còn ở `E:\Develop\OthersApplication\MemoryClear` (clone từ https://github.com/manhdauvn09-manhds/ClearRAM, nhánh main duy nhất, không worktree). Thư mục cũ `E:\SourceCode\NEW_APPLICATION\MemoryClear` đã xóa; đường dẫn cũ trong `docs/handoffs/PHASE-*` và evidence JSON là lịch sử.
- Đã chép sang các file gitignore cục bộ: `.data/` (101 file), `.harness/local/`, `.harness/portal-sync.key`. Không chép `artifacts/` cũ (fixture, ZIP 2026-10-11, trace `artifacts\readiness-*`).

**Runtime (không đổi kể từ 57fb2d2)**
- Clear Normal/Strong (`app/clear-policy.json`) và Dọn Temp có duyệt (.tmp/.log top-level, [7,7,3] ngày, ≤64MiB, không đệ quy, không elevate, hai bước) chạy thật trên Win11.
- Memory mức 3: executor graceful-only đã có; `app/memory-task-policy.json` executionEnabled=false, forceEnabled=false, max10, TTL60s, close timeout 20s. Disk production delete khóa (`productionExecutionEnabled=false`); FixtureExecutor chỉ cho fixture có marker.
- CI source 57fb2d2: [run 38106638093](https://github.com/manhdauvn09-manhds/ClearRAM/actions/runs/38106638093) success (`docs/verification/github-actions-portable.json`). Commit sau đó chỉ đổi docs/plan/harness/workflow — CI của các commit này chưa quan sát từ đây.

**Bộ chạy portable (build lại 2026-11-26, có cửa sổ Lịch sử thao tác)**
- Folder: `E:\Develop\OthersApplication\MemoryClearrtifactseleases61126-134228-32c5a6\MemoryClear\Start-MemoryClear.cmd`; ZIP `MemoryClear-2026.10.11.1-preview.zip` cùng thư mục cha, 199478 bytes, 58 file, SHA256 10D796A2…6E72 (khớp sidecar). Packaged WPF smoke + ZIP entry hashes Passed; có JournalHistory/HistoryView; không có .data/.git/.harness; CLI `History` trong gói chạy exit 0. Proof `docs/verification/portable-build.json`; ReleaseAcceptance=Unverified.
- Desktop: `MemoryClear.lnk` → source; `MemoryClear Portable 2026-10-11.lnk` vẫn trỏ bản 20261123 (cũ). Shortcut cho bản 20261126 chưa tạo (ghi Desktop nằm ngoài thư mục dự án → operator chạy `Create-DesktopShortcut.ps1` trong gói; tên mới `MemoryClear Portable 2026.10.11.1-preview.lnk`).

**Audit bảo mật 2026-11-23** — report local `docs/security/Security-Report-2026-11-23.html` (untracked; Ops/OPS-MCP-80 đã review, bản Ops ở `E:\Develop\ClaudeMCPServer\docs\Security\ops-review-20261123.md` mục B).
- Code sản phẩm: 0 Critical/High/Medium; Low còn lại ở OPEN; workflow đã có `permissions: contents: read` (9b2d8b4).
- CyberAlert (bảng 21/11): Git 2.56.1, Node 24.22.3, Chrome 158 đã vá; Starlette Python 3.14 nâng lên 1.10.0 (fastapi 0.165.0) theo lựa chọn operator.
- Máy dev: hardening do operator chạy `docs/security/Harden-RdpSmb.ps1` (admin), assistant đo lại xong 23/11. 2 cảnh báo Defender là fixture test của Ops và SecAegis (đã xác nhận) — dương tính giả.
- Docs/HTML đồng bộ lại (9b2d8b4): đường dẫn mới, README, danh sách handoff tự sinh, Memory L3 max10. Checks 23/11: check-plan PASS, clean-data 18/18, memory-design 13/13, runtime-policies 9/9.

**CD-04 lịch sử journal 2026-11-26** — `app/CleanData/JournalHistory.psm1` + `MemoryClear.Cli.ps1 -Command History` (chỉ đọc): kiểm chuỗi hash journal Temp/Memory trong `.data`, tóm tắt Completed/Partial/Cancelled/Interrupted. `tests/Check-JournalHistory.ps1` 15/15, Run-Tests 14/14. Đọc 109 journal thật: 93 Valid, 16 `NotChain` (journal `{"Kind":"TestOnly"}` do `Check-TempCleanup` ghi vào `.data` thật), 0 Broken; không đổi byte nào. GUI: nút **Lịch sử thao tác...** ở tab Clean dữ liệu (`app/CleanData/HistoryView.*`), `tests/Check-HistoryUI.ps1` 10/10 offscreen, Check-DiskUI cập nhật 30 control. Portable cần build lại mới có các file này.

**SAFE-04 2026-11-26** — thêm 4 test âm tính vào `tests/Check-TaskRelease.ps1` (process biến mất sau duyệt → Skipped; exe cùng tên ngoài đường dẫn opt-in/đường dẫn giả → không eligible; PID không mở được (4) / không tồn tại → fail closed; đóng parent đã duyệt không đụng descendant chưa duyệt). Suite 17/17, `tests/Run-Tests.ps1` 14/14 (PS 5.1); không còn process QA sót. SAFE-04 → doing trong `plan/tasks.json` (rev 2026-11-26.1); executor vẫn `executionEnabled=false`.

**Office 2026-11-26** — operator chạy `docs/security/Update-Office.ps1` (local); đo `VersionToReport` 16.0.20625.20108 → 16.0.20625.20142. Bản vá CVE Outlook KEV cho Current Channel là 2610 build 20527.20196 (nguồn thứ cấp) → đã vá; report local mục 6 cập nhật.

**Harness 2026-11-25** — bundle standard-governance 1.8.36 / harnessd 0.3.3 (HarnessAIToolKIT release c32bb41) commit vào repo; `harnessd.py` khớp SHA1 nguồn toolkit (d1ad936…), `tests/policy/test_harnessd_root_and_shutdown.py` của toolkit 7/7 pass; untrack 12 file telemetry/ledger/context (vẫn trên đĩa). Đã gộp `.new`: `casan-policies.yaml` (+worktrees/write_scope/daemon port 47631, không mất dòng nào) và `token-pricing.json` (+model 5.5) lấy bản mới, pass schema; `contracts/project.yaml` giữ bản dự án. Checks plan/clean-data/memory-design/runtime-policies PASS 25/11.

## NEXT

1. Ưu tiên sản phẩm: mở Memory3 graceful-only cần ML-01 + SAFE-04 + QA-02. Chuỗi đang chặn ở nghiệm thu người dùng: UI-01/CLEAR-01/QA-01 (review) → HO-03 → SAFE-02/SAFE-03 → SAFE-04 nghiệm thu → QA-02 (kịch bản ghi "máy ảo"; user chỉ có Win11 — cần chốt QA-02 làm trên app QA cô lập ở Win11 hay giữ chờ). Phần SAFE-04 còn tự làm được: thiếu quyền với process elevated thật (cần UAC, operator chạy), race cửa sổ. Song song: CD04 production journal/history, CD05 backup khác volume/restore no-overwrite/fault QA.
2. Khi muốn trace readiness ở vị trí mới: `powershell -NoProfile -STA -File "E:\Develop\OthersApplication\MemoryClear\scripts\Verify-Readiness.ps1" -ExpectedFamily Windows11 -OwnTempSelfTest`.

## OPEN

- `docs/security/` (report + Harden-RdpSmb.ps1) chỉ ở local. until: operator chọn giữ local hoặc commit.
- Security log (4624/4625) chưa đọc được (cần admin). until: operator chạy kiểm Security log elevated (Get-WinEvent Security 4624 type 10 / 4625, 72h).
- Shortcut Desktop (source + portable) chưa launch thử. until: user mở GUI từ từng shortcut và xác nhận.
- Trace readiness ở vị trí mới chưa có. until: chạy Verify-Readiness (NEXT 3) và có `artifacts\readiness-*\readiness.json` mới.
- Memory3 rollout. until: ML01 nonempty/revalidate + SAFE-04/QA-02 và human/nonempty checks đạt; execution=false, không force fallback.
- Appdata/orphan production + backup. until: verified vendor/version/root/dependency authority, backup khác volume và fault matrix (full disk/disconnect/power-loss/mapped-writer) đạt; không suy uninstall từ thiếu key.
- Windows10/VM/DPI/keyboard/races/soak. until: có trace môi trường thật; user chỉ có Win11, không hỏi lại VM; không coi host này là disposable VM.
- CLEAR-01/UI-01/QA-01 (phase03 review). until: báo cáo áp lực RAM/foreground/cancel/progress Normal/Strong và phản hồi app sau trim; checkbox10.1 từng fail lần đầu (thiếu service inventory) rồi pass — giữ cả hai sự kiện.
- Danh sách app đóng một chạm. until: user cung cấp và duyệt; mặc định trống, không suy ra từ CPU thấp.
- Nhiều instance cùng ghi settings/log/cooldown. until: có kiểm thử multi-instance.
- Visual QA các trang HTML. until: operator xem trực quan; DOM fixture không thay visual QA, không vòng chặn file:// bằng server/browser khác.
- `tests/Check-TempCleanup.ps1` (check "Journal create-new…") ghi journal thử nghiệm vào `.data` thật (16 file `NotChain`). until: test chuyển sang project root fixture, hoặc chấp nhận và ghi rõ.
- Low còn lại: journal hash không khóa (đổi chữ "tamper-evident" hoặc HMAC/DPAPI); giới hạn 64MiB hardcode ở FileInventory.cs:310 thay vì policy JSON (C2). until: chọn sửa hoặc chấp nhận ghi rõ.

## AVOID

- Không `git add -A`; commit cập nhật harness tách riêng khỏi việc app; không stage `.data`, `artifacts`, telemetry/ledger.
- Không bật gate (executionEnabled/productionExecutionEnabled) để né dependencies; không import FixtureExecutor vào GUI; không auto Close→Force, kill tree, UAC/ACL/TrustedInstaller bypass.
- Không thử Clear/Close/Kill/cleanup trên app hoặc dữ liệu thật để QA; fixture luôn cô lập, chỉ dọn PID/file do test tạo.
- Không coi tên/CPU/RAM/size/tuổi/thiếu uninstall key là bằng chứng rác hoặc app không cần; không cộng size unknown/quarantine cùng ổ vào reclaim.
- Không hứa dọn toàn bộ RAM; trim không decommit, không giảm CPU chắc chắn.
- Không biến unverified thành green: giữ trace failed, ghi "chưa kiểm được" khi không đo được (C12/C14). Firewall: đọc ActiveStore (GPO), đừng báo tắt theo local store.
- Không đưa chi tiết lỗ hổng chưa vá hay cấu hình bảo mật máy dev vào repo (public): auto-mode chặn push; giữ trong `docs/security/` local, Handoff chỉ ghi chung.
- Sửa text có đường dẫn `E:\…` hoặc tiếng Việt: `sed` trong Git Bash không khớp backslash và heredoc Python lỗi Unicode — dùng file script Python trong `.harness/tmp/` chạy với `python -X utf8`, hoặc Edit tool.
- Giữ UTF-8 BOM cho .ps1 có tiếng Việt; test bằng `powershell.exe` 5.1, không thay bằng `pwsh`.
