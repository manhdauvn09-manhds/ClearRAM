# Clean Data — thiết kế tab dọn ổ Windows

Cập nhật yêu cầu risk/large-file 2026-10-09 · Windows 10/11 x64 · PowerShell 5.1 + WPF hiện có. Đây là thiết kế và prototype HTML, **chưa có bộ xóa thật**. Linux để sau. Dò volume chứa Windows khi chạy; C: chỉ là tên trong giao diện mẫu. `plan/tasks.json` là nguồn trạng thái; `plan/clean-data-design.json` là danh mục product_runtime cho thiết kế, không phải manifest được phép thực thi.

## 1. Mục tiêu và ba mức

Thu hồi nhiều dung lượng bằng **độ phủ provider và khả năng nhận diện**, không bằng bỏ quyền bảo vệ. CPU không phải dữ liệu lưu trữ để xóa; tab RAM/CPU tiếp tục tách riêng. Không có cách đảm bảo toàn bộ AppData cũ không còn giá trị. Rule mới: cache/empty folder của app đã gỡ được chứng minh có thể dọn trực tiếp; user data/mixed cần duyệt.

| Mức | Phạm vi | Mặc định | Điều kiện / tác động |
|---|---|---|---|
| 1 · Tiêu chuẩn | User temp ≥7 ngày, log rotate ≥30 ngày, disk cache browser có rule | Chọn nhóm tái tạo được, đủ điều kiện | Bỏ file khóa/đang ghi; bỏ profile app đang mở; cache có thể tải lại |
| 2 · Chuyên sâu | Thêm Windows temp, WER/crash dump cũ, Delivery Optimization, dev cache và component store | Nhóm an toàn đủ quyền; dev cache/servicing phải duyệt | Log ≥14 ngày; admin qua UAC; không update/build đang chạy; có thể cần tải package lại |
| 3 · Tối đa có duyệt | Thêm bộ cài tải về cũ, app data còn sót, Recycle Bin user, Windows.old | Nhóm dữ liệu cá nhân/rollback luôn bỏ tick | Temp ≥3 ngày, log ≥7 ngày; duyệt file/app, chọn sao lưu hoặc xóa vĩnh viễn; mất rollback nếu xóa Windows.old |

Tuổi chỉ là điều kiện bổ sung, không là bằng chứng file rác. LastAccessTime không dùng để suy ra app không dùng. Quy tắc retention là đề xuất cần chốt ở CD-SCOPE. Mức 3 không tự chọn thêm dữ liệu cá nhân. Có thể dùng thao tác một nút cho các nhóm đề xuất sau khi đã lưu profile được duyệt; summary inline có sẵn nhưng không ép popup cảnh báo cho nhóm safe. Không thêm lịch dọn tự động trong MVP.

## 2. Catalogue và ranh giới

- **Temp / log / dump:** Known Folder đúng user và volume; rule vendor cho log rotate; thời điểm ghi gần nhất ổn định, file đã đóng. Có nút giữ log đang điều tra. Không xóa Event Log, log bảo mật hay toàn bộ file `*.log` trên C:.
- **Browser:** chỉ Cache/Code Cache được nhận diện theo phiên bản/profile; không Cookies, History, Login Data, session, extension hay profile root. App đang chạy: bỏ qua và đề nghị người dùng đóng, không kill tự động.
- **Dev cache:** phát hiện SDK và cache root từ CLI vendor; kiểm tra build/restore; chạy adapter chính thức khi phù hợp. Không xóa source, environment, node_modules hoặc package đang được dự án tham chiếu chỉ vì cũ. [NuGet cache](https://learn.microsoft.com/nuget/consume-packages/managing-the-global-packages-and-cache-folders).
- **OS cache:** Delivery Optimization qua cmdlet nếu OS có capability; không tự xóa SoftwareDistribution, dừng service hay reset Windows Update. Component store qua DISM AnalyzeComponentStore và StartComponentCleanup; không tính WinSxS bằng tổng file hard link và không bật ResetBase trong MVP. [DO provider](https://learn.microsoft.com/en-us/powershell/module/deliveryoptimization/delete-deliveryoptimizationcache?view=windowsserver2025-ps), [servicing hỗ trợ](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/clean-up-the-winsxs-folder?view=windows-11).
- **Windows.old:** chỉ provider Windows hỗ trợ; báo mất quay lui; không `Remove-Item` đệ quy thủ công. Nếu không có API/provider kiểm chứng cho phiên bản OS, mở Cleanup recommendations/Storage để operator thao tác; trạng thái **Delegated**, không claim app đã dọn. [Cleanup Windows](https://support.microsoft.com/en-us/windows/experience/storage-filemanagement/free-up-drive-space-in-windows).
- **Bộ cài cũ:** Downloads không phải thư mục rác. Tuổi/extension chỉ gợi ý, preview từng file, hash/identity, giữ bộ cài offline khi chưa duyệt. Không lấy cache sửa chữa của ứng dụng làm ứng viên. **C:\Windows\Installer** và vendor Package Cache được bảo vệ, kể cả admin. [Installer cache](https://learn.microsoft.com/en-us/troubleshoot/windows-client/application-management/missing-windows-installer-cache).
- **Recycle Bin:** chỉ SID hiện tại, volume mục tiêu; xem lại nội dung/tuổi. Provider Shell giữ đúng metadata; không dọn dữ liệu user khác.
- **AppData còn sót:** đối chiếu inventory HKLM/HKCU 32/64-bit, MSIX/Store, executable identity, service/task liên quan và rule vendor; phân biệt portable/shared runtime với app đã gỡ. Không gọi Win32_Product để tránh kích hoạt repair. Thiếu uninstall key chỉ tạo **ứng viên chưa chắc chắn**. Folder không xác định chủ sở hữu: bảo vệ. App chưa gỡ: dùng uninstaller chính thức theo thao tác riêng, không xóa Program Files. Database/settings/save game chỉ dọn sau duyệt từng app và phương án bảo toàn.
- **Cloud / dữ liệu cá nhân:** Desktop/Documents/Downloads chung, source, save game, sync root và placeholder không được auto-clean. Không hydrate file để tính hash; link OneDrive Free up space là thao tác riêng. Xóa file đồng bộ có thể lan lên cloud. [OneDrive](https://support.microsoft.com/en-us/onedrive/save-disk-space-with-onedrive-files-on-demand-for-windows).
- **Loại khỏi MVP:** registry cleaner, pagefile/hiberfil, recovery partition, restore points, driver store, Prefetch, antivirus data, user khác, forced-unlock, takeown/ACL, quyền SYSTEM/TrustedInstaller, tự tắt hibernation. Restore point không thay thế backup file.

## 3. Kiến trúc đề xuất

`WPF tab → Coordinator → Discovery/providers → Policy/ownership → Immutable preview manifest → Executor → Journal + measurement`

| Thành phần | Trách nhiệm / contract |
|---|---|
| WPF CleanData tab | Scope, ba mức, category/file preview, lý do giữ/bỏ, filter/sort, UAC, backup, tiến trình, history/restore; không tự gọi lệnh xóa |
| Coordinator runspace | Một lượt RAM Clear hoặc Disk Clean tại một thời điểm; token hủy, stage events, bounded queue; GUI không block |
| Scanner | Stream danh mục, không quét đệ quy toàn C: mặc định; phân trang kết quả. Mục tiêu 2 workers, ≤150 MB working set scanner — chưa đo |
| Provider interface | Discover / Analyze / BuildPlan / Revalidate / Execute / Measure / Recover; capability chưa biết thì từ chối hoặc Delegated |
| Policy + identity guard | Config product_runtime + JSON schema; root allowlist, vendor rules/version, retention, app owner, current user, file/volume identity |
| User executor | Thực thi danh sách cố định đủ quyền user; không nhận wildcard/glob/file mới sau preview |
| Elevated helper | Helper riêng, UAC `runas`; chỉ provider/action được allowlist, độc lập kiểm tra lại manifest/identity/conditions |
| Store | Manifest immutable + append journal JSONL trước từng side effect; bounded history; preview lớn phân trang. Không ghi full user path vào export mặc định |
| Recovery | Backup inventory, hash/copy verification, restore preview/collision handling; mỗi mục biết recoverable hay permanent |

Dự kiến `app/CleanData/*.psm1`, `app/clean-data-policy.json` + schema, Native FileIdentity helper C#/.NET Framework tương thích PS5.1, `app/CleanDataView.xaml`, `scripts/Run-CleanData-Acceptance.ps1`, `tests/Check-CleanData.ps1`. Đây là cấu trúc đề xuất; chưa tạo executor. Không đọc `.harness/` cho product.

## 4. Scan / preview không tạo false positive

1. Lấy SystemRoot, OS volume identity/serial, current SID và Known Folders từ OS. Không hardcode C: hoặc suy ra profile từ tên thư mục. Quét registry chỉ metadata cần thiết, không xuất toàn registry.
2. Quét từng root allowlist bằng iterator có giới hạn, không follow reparse points/junction/symlink/mount; bỏ UNC, sync roots, placeholders, inaccessible. Ghi số skipped/access denied; không biến thiếu quyền thành zero dung lượng. [Reparse points](https://learn.microsoft.com/en-us/windows/win32/fileio/reparse-points).
3. Snapshot Volume ID + File ID + parent chain + timestamps + logical/allocated size + link count. Dedupe file ID giữa provider; hard link ngoài scope hoặc link count >1 không xóa bằng adapter tùy ý. Chỉ tính allocated bytes có thể thu hồi, không hứa logical size = free disk. [Hard links](https://learn.microsoft.com/en-us/windows/win32/fileio/hard-links-and-junctions).
4. Ghi provenance: vendor rule/version, owner confidence, installation evidence, condition app closed, age. File chưa rõ → protected/needs review; không gắn nhãn chắc chắn.
5. Dựng manifest: run ID, policy hash/version, current SID, OS volume ID, identity snapshot, action/provider ID, backup destination, effects, expiry 10 phút. Đổi level/quyền/backup/selection → vô hiệu hóa preview. Không thêm file mới tìm thấy sau preview.
6. Preview hiển thị: logical size, estimated reclaim, unknown provider, recoverable/permanent, required UAC, app đang dùng, excluded count. Nhóm safe chạy trực tiếp từ scope/summary; chỉ risky cần approval thêm trước execution thật.

## 5. Thực thi, quyền và chống race

Quyền admin **không được bypass**. GUI mặc định asInvoker; chỉ helper cần admin xin UAC, từ chối thì giữ scan và xử lý user scope đã duyệt, ghi AdminDenied. Windows cấp quyền qua cơ chế UAC: [Running with administrator privileges](https://learn.microsoft.com/en-us/windows/win32/secbp/running-with-administrator-privileges).

Helper bind caller SID/run ID/nonce/plan hash, channel ACL; không nhận raw shell command từ GUI. Independently validate action ID, root, destination và từng file, không tin plan JSON do user sửa. Helper/policy dùng để bảo vệ privileged operation phải được ký và cài ở vị trí chỉ admin sửa; bản portable user-writable **không phải security boundary**. Quyết định trust/deployment này là gate CD-SCOPE/CD-04, không quảng cáo PowerShell tự bảo đảm isolation.

Revalidate trước mỗi thao tác: expiry, identity, parent chain, canonical root theo boundary separator, reparse state, lock/write changes, app đang chạy, servicing state. String `StartsWith` riêng không ngăn TOCTOU. Implementation phải dùng stable handles/native identity và ràng buộc parent chain; kiểm thử swap junction giữa preview và delete. Nếu không chứng minh handle/path còn trong scope thì bỏ qua. Không chiếm owner, sửa ACL, mở quyền backup để lách policy, unlock file hoặc đóng ứng dụng tự động.

Write-ahead journal `Planned → Revalidated → BackupVerified → DeleteStarted → Deleted/Skipped/Failed`, flush trước side effect. Chỉ xóa nguồn sau copy **hash-verified**, space preflight, destination identity khác volume nguồn nếu cần reclaim. Copy fail/missing destination → giữ nguồn. Sau crash, entry DeleteStarted chưa rõ không được coi success; scan lại file IDs và backup.

Hủy tại ranh giới file/provider; không kill DISM/servicing giữa chừng. App hiện “Đang hoàn tất bước Windows hiện tại”, không giả hủy ngay. Locked/changed/admin denied → skipped có lý do. Một provider lỗi không nuốt exception rồi báo xanh; kết quả Partial / Failed / Delegated rõ ràng. Không đảm bảo transaction/rollback cho deletion vĩnh viễn.

## 6. Backup, phục hồi và số liệu

- **Cách ly cùng C:** có thể phục hồi, 0 byte reclaim tức thời. Sau 14 ngày chỉ nhắc duyệt purge, không tự xóa trong MVP.
- **Sao lưu ổ khác (đề xuất cho AppData):** người dùng chọn destination, đủ chỗ, ổ đang sẵn sàng, không sync root; copy/verify rồi xóa nguồn. Restore giữ ACL phù hợp owner, hash và path preview; không ghi đè dữ liệu app mới nếu chưa duyệt.
- **Xóa vĩnh viễn:** riêng từng app/file rủi ro, xác nhận phạm vi + tác động; không ngụ ý có Undo. Windows.old/native cleanup thường không phục hồi qua app.

Hiển thị tách bốn số: candidates (bao gồm chưa đủ điều kiện), planned eligible reclaim, known allocated bytes đã xử lý và free-volume before/after. Free delta toàn volume có hoạt động khác, không gán toàn bộ cho Clean. Unknown estimate giữ chữ **chưa định lượng**, không zero/green. Backups cùng volume trừ gain; sparse/compressed/hardlink và open file handles có thể trì hoãn physical reclaim. Kết quả có timestamp/run ID, successful/partial/skipped/failed/delegated counters và restart-required nếu OS báo.

## 7. Trạng thái và prototype

`Idle → Scanning (indeterminate, elapsed/count) → Ready → Reviewing → WaitingForUAC → Revalidating → Cleaning → Completed/Partial/Cancelled/Failed/Delegated`.

Prototype HTML mô phỏng level/conditions, scan, giữ nhóm protected, review riêng, backup mode, TTL manifest, confirm, determinate progress, cancel, history và export JSON có cờ simulated. Không đọc FS, không UAC thật, không gọi executor. Tab RAM/CPU là điều hướng minh họa. Scan/progress giả lập không phải benchmark máy người dùng. Rule/log/disk numbers trong fixtures không là inventory thực tế.

## 8. Kế hoạch triển khai và gate nghiệm thu

Phase 09 chỉ hoàn tất **thiết kế**, có HO-09. Phase 10 giữ todo/decision cho code thật, HO-10 chưa hoàn tất. Task status chỉ sửa ở tasks.json; dựng cả hai HTML sau cập nhật.

| Gate / task | Điều kiện kết thúc |
|---|---|
| CD-SCOPE | Chốt retention, backup destination/policy, native delegation, trust helper ký/cài protected; không cần chốt mới để hoàn thành bản thiết kế |
| CD-01 scanner | Fixture tests và readonly scan; UNC/reparse/cloud/permission/long-path; không xóa FS, no false orphan, streamed/paged memory số đo |
| CD-02 ownership | HKCU/HKLM 32/64, MSIX/portable/shared/vendor; unknown protected; metadata inventory không trigger repair |
| CD-03 WPF | Tab tích hợp, keyboard/DPI, progress/cancel, khóa operation; không cho GUI thread chạy recursion |
| CD-04 helper/guard | UAC denied/cancel, plan tamper/stale/caller mismatch, parent swap/junction/TOCTOU, file replacement; fail closed và có log |
| CD-05 backup/executor | Temp VM fixtures, full disk/dest disconnected/hash fail/restore collision/crash journal/cancel; giữ nguồn khi backup fail |
| CD-06 OS adapters | Win10/Win11 supported capability; native locked/update/reboot, no ResetBase, Delegated khi không automate được |
| CD-07 QA | Ma trận trên disposable VM + restore; estimate/allocated/free delta tách đúng; không test xóa trên dữ liệu làm việc |
| CD-08 acceptance | Operator script PS5.1 self-contained/idempotent, package/signature trust, user acceptance và docs; measured gates trước release |
| HO-10 | Handoff/template/evidence đầy đủ; phase chỉ done sau mọi task đạt |

Không phải gate nào cũng đã chạy. Đến revision09.4 có scanner/guard/transaction/WPF local fixtures:18/9/17/16 checks đạt trên PS5.1, gồm same-handle backup/hash/delete và readonly journal inspection; không production deletion, crash/power-loss hoặc VM Windows10/11 proof. Contract/giới hạn ở [CLEAN_DATA_TRANSACTION.md](CLEAN_DATA_TRANSACTION.md), status nguồn ở tasks.json và handoff10. User chọn portable user + Windows xử lý system, không cài elevated helper. Ước lượng 10–18 ngày công cho MVP đã QA là tham khảo, không lịch cam kết. Deletion runtime chỉ mở sau production ownership/authority/UI/backup và VM gates; fixture pass chưa đủ.

## 9. Yêu cầu mới — cảnh báo theo risk và file lớn

Revision 2026-10-09.2, config thiết kế v2. Contract nhãn chung và UI Memory/Disk ở `docs/MEMORY_THREE_LEVELS_DESIGN.md`.

- Safe=0 popup; review=1 final approval sau xem chi tiết; danger=2 bước có ý nghĩa (item review + final typed confirmation); blocked=deny, không override. Warning chỉ mục risky đã chọn, không toàn catalogue. Cách ly/app data external backup: review; xóa vĩnh viễn mixed data: danger. File/system state đổi trước action: skip, không hạ nhãn vì user đã confirm.
- App gỡ: vendor owner + multi-inventory + không process/service/task/portable/shared dependency; cache tái tạo/empty folder xác minh thì safe. Empty folder đổi/child mới: skip, không recursive-delete. App đã gỡ không đồng nghĩa database/save/settings không còn giá trị; mixed user data review/backup. Unknown ownership vẫn protected.
- Large finder readonly tách discovery khỏi delete authority, opt-in. Known Folders/user-selected roots trên OS volume, threshold đề xuất512MB, size/age/type/path filter, sort descending. Kiểm tra allocated/logical/hardlink/dedupe File ID; LastWriteTime là tuổi ghi, không là bằng chứng không sử dụng. Không hydrate cloud, không recurse vào source/system/reparse roots; no full-volume blind scan.
- Gợi ý large/old ISO/installer/video/VM/backup có effect và importance=unknown; chỉ show, không auto select hoặc gọi là rác. UI mở property/folder (triển khai sau), move/backup sang khác volume nếu user muốn giữ; deletion qua cùng manifest/identity guards. Category và file explorer có thể overlap: inventory dùng canonical File ID để không cộng/xóa trùng; prototype các IDs là fixtures riêng biệt, không chứng minh native dedupe.
- Finder filter chỉ đổi hiển thị và giữ selection/count; đổi scan roots/capability/level/backup invalidates manifest. Production cached inventory có generation ID; selected hidden-by-filter vẫn hiện ở summary, không xóa bất ngờ.
- CD-DES04/05 bàn giao redesign; CD-09 triển khai finder, CD-02 owner/cache-empty, CD-03 risk UI, CD-05 executor independently checks approvals; CD-07 VM gates. Native safety/visual QA chưa chạy.
