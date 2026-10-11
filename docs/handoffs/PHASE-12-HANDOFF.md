# Handoff — Phase 12 · Memory ba mức — triển khai

- Ngày cập nhật: 2026-10-11 (Asia/Tokyo)
- Người thực hiện: Codex
- Trạng thái bàn giao: **Nháp — phase chưa hoàn tất**
- Task handoff: HO-12 (doing)
- Kế hoạch: 2026-10-11.2
- Branch / source commit: main / 57fb2d2638ab9c10f579aacaa49bf2dd42c42c17; push và source CI verified. Publication evidence follow-up chỉ đổi docs/plan.
- Publication đã xác minh theo yêu cầu user 2026-10-11; phase vẫn draft, CI không thay full nghiệm thu.

## 1. Mục tiêu và phạm vi đã chốt

PowerShell5.1/WPF portable Windows11 hiện có. Mức3 chỉ saved Cho đóng gấp opt-in, mặc định trống, graceful-only, giữ app khi hỏi lưu/timeout. Không tự force, không suy ra rác từ tên/CPU/RAM. User yêu cầu hoàn thiện và build portable; build được ủy quyền trực tiếp. Không có Windows10 VM.

## 2. Kết quả theo task

| Task | Status | Kết quả / evidence |
|---|---|---|
| ML-SCOPE | done | User đã chốt opt-in |
| ML-01 | doing | Frozen PID/start/SID/session/window/thread/exe metadata+SHA256/settings/policy/TTL/context; 13 QA child checks, thiếu full gate |
| ML-02 | todo — code chuẩn bị | 6 real worker/DispatcherTimer/ack/rescan/cancel/close checks; human/DPI/nonempty GUI còn thiếu |
| ML-03 | todo — code chuẩn bị, rollout khóa | Graceful executor, journal trước thao tác, verified exit/held timeout/cancel; SAFE-04/QA-02 chưa đủ |
| ML-04 | todo | Local Win11 regression có trace; full Win10/VM/CLI matrix chưa đạt |
| HO-12 | doing | Draft này; chưa mark phase complete |

## 3. Thay đổi và điểm vào để tiếp tục

- app/MemoryClear.Tasks.psm1: frozen one-use plan, confirm, stable native handle, fresh service/foreground/policy/path/SID, exe fingerprint recheck, max10/TTL60/timeout20s, cancel, no force.
- app/Native.cs: shared in-process task session store; visible caption/main window and owner/thread check before WM_CLOSE. Không broadcast, không chọn hidden utility window. Window check không atomic; không claim hết races.
- app/MemoryClear.Core.psm1: fresh service PID-only CIM query, timeout5; failure giữ ServicesKnown=false.
- app/CleanData/FileInventory.cs: TempLedger prefix allowlist temp-operation/memory-operation; create-new journal/hash-chain/flushed. Local ledger không là server-enforced security boundary.
- app/MemoryTaskView.xaml/.ps1: ack/rescan/run worker, real timer, progress X/N, elapsed, final outcomes/time/journal, cancel and close cleanup. Shipped policy giữ executionEnabled=false.
- tests/Check-TaskRelease.ps1, Check-TaskUI.ps1; Verify-Readiness thêm suites. scripts/Build-Portable.ps1: curated runtime ZIP, SHA256 manifest, packaged WPF smoke; loại personal settings/harness/test fixtures.

## 4. Cách chạy và kiểm chứng

PS5.1 / Win11 build 26200. Lệnh: powershell -NoProfile -STA -File "E:\SourceCode\NEW_APPLICATION\MemoryClear\scripts\Verify-Readiness.ps1" -ExpectedFamily Windows11 -OwnTempSelfTest.

16 bước readiness đã đạt; trace artifacts\readiness-20261011-020956-50571223\readiness.json. Task release 13/13; Task UI 6/6; toàn bộ source hashes trong report. Own Temp tests chỉ xóa file QA mới tạo, task tests chỉ đóng executable QA tự biên dịch. Foreground/service/opt-in/policy providers của test child là synthetic và private; không sửa settings thực. Offscreen dispatcher QA không thay nghiệm thu con người.

Các lần fail được giữ ở artifacts/task-release-first-failed.json, task-release-service-unavailable.json, task-release-cancel-timing-failed.json, task-release-foreground-unavailable.json. Hidden WinForms/utility window và timed cancellation đã làm fixture không đúng; fixture mới offscreen no-activate, cancel khi nhận WaitingForExit. Positive child tests dùng foreground provider riêng; production vẫn Native foreground và unknown fail closed. Không xóa trace lỗi.

Build: powershell -NoProfile -File "E:\SourceCode\NEW_APPLICATION\MemoryClear\scripts\Build-Portable.ps1". Chỉ khi docs/verification/portable-build.json ghi Passed mới coi package đạt. User chạy Start-MemoryClear.cmd trong toàn bộ folder đã giải nén.

Chưa kiểm chứng: Windows10/VM, human save-dialog/keyboard/DPI, adversarial window races, full historical safety/action/CLI gates, release signing/server CI source mới. General appdata deletion chưa mở.

## 5. Quyết định kỹ thuật và lý do

Giữ product gate false cho đến khi đủ SAFE-04/QA-02; source backend pass trên child riêng không đủ mở rollout. Không sửa dependency hoặc báo phase complete để né gate. Normal/Strong trim và Temp cleanup vẫn hoạt động. Settings/history không sao chép vào bộ mới; opt-in mới trống. Build thành công không đồng nghĩa nghiệm thu release.

## 6. Tồn tại, rủi ro và điểm chặn

| Open | until / next |
|---|---|
| Memory3 rollout khóa | until SAFE-04/QA-02 trace và dependencies đạt; không toggle flag thủ công |
| ML01/02/04 acceptance | until native/service/CLI/human matrix và mọi tiêu chí phase đạt |
| Win10/DPI/races | until có môi trường/trace thực, không suy diễn từ Win11 |
| Disk appdata production | until verified removal authority và protected/backup/delete matrix đạt; chỉ Temp narrow hiện khả dụng |

## 7. Hướng dẫn người / chat tiếp nhận

1. Đọc IMPLEMENTATION_PLAN.md, tasks.json, Handoff.md, phase10/12; không hỏi lại opt-in/VM scope đã chốt.
2. Kiểm tra portable-build.json và SHA256, chạy bộ mới bằng launcher; không đóng app user để test.
3. Ưu tiên hoàn tất SAFE-04/QA-02 theo dependencies trước mở Memory3. CLI/human/nonempty modal còn thiếu.
4. Tiếp Disk appdata sau removal authority; không suy ra uninstall từ tên/absence/age/size.
5. Không enable auto force, UAC bypass, task tree, delete system/appdata ngoài scope; không claim commit/CI chưa quan sát.

## 8. Checklist kết thúc phase

- [x] Handoff và task evidence phản ánh scope/trace/limits hiện tại.
- [x] Local Win11 suites có trace và source hashes.
- [ ] Mọi task/dependency trong phase đạt; hiện chưa hoàn tất.
- [ ] Full safety/action/human/Win10 acceptance.
- [ ] Phase12 complete — giữ draft.

## Bộ chạy đã build — 2026-10-11

- ZIP: E:\SourceCode\NEW_APPLICATION\MemoryClear\artifacts\releases\20261011-111149-936015\MemoryClear-2026.10.11.1-preview.zip
- Folder chạy: E:\SourceCode\NEW_APPLICATION\MemoryClear\artifacts\releases\20261011-111149-936015\MemoryClear; launcher Start-MemoryClear.cmd.
- 55 file, 192168 bytes ZIP; manifest entry hashes và packaged WPF/native compilation smoke Passed. SHA256 B9914C4DFF4B48837E261B60F3E5A10E4FBEB35F2DB4EF97AE68333BFE6B9AD7. Checksum sidecar cùng ZIP.
- Desktop MemoryClear Portable 2026-10-11.lnk đã trỏ đúng folder mới và readback verified; chưa launch qua shortcut. Proof artifacts/portable-desktop-shortcut.json. Bản package trước bị supersede; chỉ dùng đường dẫn này.
- Runtime source hashes sau build khớp latest readiness; docs/verification/portable-session-verification.json. Memory3 execution gate vẫn false; full phase/release chưa complete. Không kèm settings/history cá nhân.

## GitHub publication — 2026-10-11

- Source commit: [57fb2d2](https://github.com/manhdauvn09-manhds/ClearRAM/commit/57fb2d2638ab9c10f579aacaa49bf2dd42c42c17), 143 file; đã push main của manhdauvn09-manhds/ClearRAM. git ls-remote và GitHub commit API khớp local SHA.
- Source CI: [run 38106638093](https://github.com/manhdauvn09-manhds/ClearRAM/actions/runs/38106638093) completed/success; mọi step plan/Disk fixture/policy/WPF/Clear/checkbox được quan sát success. Evidence docs/verification/github-actions-portable.json.
- Đây là CI của source commit trên; không suy ra full Windows10/VM/release hoặc mở Memory3. Task child13/UI6 là local Win11 trace, không là step native task execution trên server.
- .data, ZIP/artifacts, harness riêng và các file user không thuộc app không được commit. GitHub Download ZIP chứa source chạy bằng Start-MemoryClear.cmd; portable ZIP local chưa publish thành GitHub Release.
- Commit tiếp theo chỉ ghi publication/CI evidence và plan/handoff; không đổi runtime.
