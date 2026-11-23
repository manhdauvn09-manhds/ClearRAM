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

**Bộ chạy portable (build lại 2026-11-23)**
- Folder: `E:\Develop\OthersApplication\MemoryClear\artifacts\releases\20261123-012134-a2d615\MemoryClear\Start-MemoryClear.cmd`; ZIP `MemoryClear-2026.10.11.1-preview.zip` cùng thư mục cha, 192596 bytes, 55 file, SHA256 1C42AAC4…E16E (khớp sidecar). Packaged WPF smoke + ZIP entry hashes Passed; không có .data/.git/.harness. Proof `docs/verification/portable-build.json`; ReleaseAcceptance=Unverified.
- Desktop: `MemoryClear.lnk` → source mới; `MemoryClear Portable 2026-10-11.lnk` → folder portable trên. Cả hai COM readback Verified, Launched=false.
- `scripts/Create-PortableShortcut.ps1` (sửa 2026-11-23) giờ đặt tên shortcut theo version trong `package-manifest.json` → lần build sau sẽ tạo `MemoryClear Portable 2026.10.11.1-preview.lnk`; bản trong ZIP 20261123 vẫn là script cũ (tên 2026-10-11).

**Audit 2026-11-23** — report `docs/security/Security-Report-2026-11-23.html` (chỉ local, chưa commit: auto-mode chặn push vì chứa chi tiết lỗ hổng harness chưa vá; đã gửi OPS-MCP-80 review).
- Code sản phẩm: 0 Critical/High/Medium. Low: journal hash không khóa (Operations.psm1:140, FileInventory.cs:334), `-ExecutionPolicy Bypass` + Add-Type lúc chạy. Low thứ ba (workflow thiếu `permissions:`) đã sửa: `permissions: contents: read`.
- CyberAlert (bảng cập nhật 21/11): Git 2.56.1, Node 24.22.3, Chrome 158.0.8127.36 đã vá; Edge/Windows/PS5.1/.NET không có mục. Không có dấu hiệu xâm nhập trong nguồn đã xem (Defender, cổng, tài khoản local).
- Docs/HTML đã đồng bộ lại 2026-11-23: đổi đường dẫn live trong README + 6 docs; ghi chú "lịch sử" ở 5 file PHASE-*; README bỏ ZIP cũ và đánh dấu mục "chỉ quét" 2026-10-09 là lịch sử; `plan/build-plan.mjs` sinh danh sách handoff từ `docs/handoffs/`; `plan/memory-design.json` mức 3 maxProcesses 8→10 khớp runtime; CLEAN_DATA_ARCHITECTURE ghi rõ 2 script dự kiến chưa tạo.
- Checks chạy 2026-11-23 (node v24.22.3): check-plan PASS, check-clean-data 18/18, check-memory-design 13/13, check-runtime-policies 9/9 (evidence JSON trong `docs/verification/` được ghi lại).

**Ops review (OPS-MCP-80, 2026-11-23)** — bản đầy đủ `E:\Develop\ClaudeMCPServer\docs\Security\ops-review-20261123.md` mục B; đã đưa vào report mục 5.
- Ops không đo PC nên không xác nhận "không xâm nhập". Một số cổng remote/chia sẻ của máy dev cần siết lại (chi tiết trong report local) ⇒ owner tự làm. Script đã soạn, CHƯA chạy: `docs/security/Harden-RdpSmb.ps1` (local, untracked).
- Cả 2 cảnh báo Defender (21/11, 23/11) là dương tính giả: fixture có chủ đích của Ops (`ops/test_ops_residue.py`) và SecAegis (`agent/test_secaegis_agent.py`, đã đổi sang ghép chuỗi ở commit 4a7dccf). Còn file transcript .jsonl của SecAegis bị Defender đánh dấu — operator tự quyết xóa/khôi phục/loại trừ.
- Starlette 0.41.3 (Py3.14): không dịch vụ server nào dùng ⇒ P3. Outlook: Ops không có nguồn bản vá kênh M365 ⇒ owner Update Now.
- H1/H2 Medium hợp lý; người sửa là team HarnessAIToolKIT — đã chuyển chi tiết cho session HarnessAIToolKIT.

## NEXT

1. Operator: xác nhận Office đã cập nhật (Outlook → File → Office Account → Update Now). Hardening máy dev đã xong 23/11 và assistant đã đo lại; chi tiết trong report local `docs/security/Security-Report-2026-11-23.html` mục 6.
2. Ưu tiên sản phẩm (không đổi): ML01 nonempty profile/identity/TTL invalidation + SAFE-04/QA-02 → mới mở Memory3 graceful-only; tiếp CD04 production journal/history, CD05 backup khác volume/restore no-overwrite/fault QA.
3. Khi muốn trace readiness ở vị trí mới: `powershell -NoProfile -STA -File "E:\Develop\OthersApplication\MemoryClear\scripts\Verify-Readiness.ps1" -ExpectedFamily Windows11 -OwnTempSelfTest`.

## OPEN

- Harness update đang nằm chưa commit trong working tree (harnessd http hooks, write-scope, installer…; không do các phiên MemoryClear tạo). Có 2 phát hiện Medium (H1, H2) trong `harnessd.py`, đã verify; chi tiết chỉ nằm trong report local, không ghi vào repo. until: người duy trì harness sửa và tự commit; phiên app chỉ commit file của mình (`git commit -- <paths>`).
- Security report + Harden-RdpSmb.ps1 chỉ ở local (`docs/security/`, untracked), Ops review đã xong. until: operator chọn giữ local hoặc commit (push từng bị auto-mode chặn vì chứa chi tiết lỗ hổng chưa vá).
- CyberAlert: Office update đã kích hoạt 23/11. until: đo lại build sau khi cập nhật. Starlette (Python 3.14, không liên quan app) đã vá 23/11.
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
- Low còn lại: journal hash không khóa (đổi chữ "tamper-evident" hoặc HMAC/DPAPI); giới hạn 64MiB hardcode ở FileInventory.cs:310 thay vì policy JSON (C2). until: chọn sửa hoặc chấp nhận ghi rõ.

## AVOID

- Không `git add -A` / commit bản harness đang chờ cùng việc app; không stage `.data`, `artifacts`, telemetry/ledger.
- Không bật gate (executionEnabled/productionExecutionEnabled) để né dependencies; không import FixtureExecutor vào GUI; không auto Close→Force, kill tree, UAC/ACL/TrustedInstaller bypass.
- Không thử Clear/Close/Kill/cleanup trên app hoặc dữ liệu thật để QA; fixture luôn cô lập, chỉ dọn PID/file do test tạo.
- Không coi tên/CPU/RAM/size/tuổi/thiếu uninstall key là bằng chứng rác hoặc app không cần; không cộng size unknown/quarantine cùng ổ vào reclaim.
- Không hứa dọn toàn bộ RAM; trim không decommit, không giảm CPU chắc chắn.
- Không biến unverified thành green: giữ trace failed, ghi "chưa kiểm được" khi không đo được (C12/C14). Firewall: đọc ActiveStore (GPO), đừng báo tắt theo local store.
- Giữ UTF-8 BOM cho .ps1 có tiếng Việt; test bằng `powershell.exe` 5.1, không thay bằng `pwsh`.
