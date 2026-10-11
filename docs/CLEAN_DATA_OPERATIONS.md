# Giao dịch, lịch sử và phục hồi — trạng thái thực tế

Cập nhật 2026-10-10 (Asia/Tokyo). Revision10.2. Bộ thực thi này chỉ nhận **file mẫu trong workspace có marker**, không cấp quyền xóa file cá nhân. `productionExecutionEnabled=false` là cổng còn đóng; không có helper nâng quyền. Giao diện production quét/phân tích/xem lý do giữ; nút **Dọn bằng Windows** mở Storage để Windows xử lý phần hệ thống.

## Các phần đã triển khai

- `Operations.psm1`: plan được giữ trong process, trả snapshot riêng cho GUI; worker chỉ nhận ID/context. Policy độc lập phân loại `.tmp` Safe, `.log` Review, `.db` Danger **trong fixture**; tên/nhãn GUI không cấp authority. Unknown/marker/journal/restore evidence luôn giữ. Rule này không áp dụng vào AppData thật.
- Plan gắn SID, scan RunId, context, policy fingerprint, TTL600s và tối đa100 items/8 sessions. Chọn mode mới tạo plan mới và bỏ approvals. Executor chỉ nhận Approved, kiểm lại trước giao dịch, kiểm lại consumed dưới mutex, không replay.
- Snapshot có FileID, ancestor identity, logical/allocated size, attributes, link count, timestamp **và SHA-256 nội dung**. Giữ timestamp/size mà đổi byte vẫn bị phát hiện. Native mở cùng source handle độc quyền, kiểm hash đã duyệt ngay trên handle trước copy/delete. Mapped writers/filter-driver/power-loss vẫn cần ma trận riêng.
- Backup mặc định: CREATE_NEW → copy64KB → flush → SHA-256 source/destination → journal BackupVerified/DeleteStarted → same-handle delete. Backup fixture hiện cùng volume, gain metadata0. **External backup chưa có provider thực thi và kiểm thử**, không suy diễn từ copy cùng ổ.
- Nhật ký schema3: header chứa plan cố định, SID/policy, per-item stages/receipt và Finished riêng; từng dòng sequence/hash/Flush(true), file tạo mới và không ghi đè. Nhật ký phục hồi riêng ghi RestoreStarted trước thao tác, Restored sau commit. Commit rồi lỗi log báo RestoredJournalIncomplete/DeletedJournalIncomplete.
- Phục hồi chỉ khi backup identity/hash đúng, nguồn hiện thiếu, original ancestors vẫn đúng. Copy vào partial file riêng, flush/hash rồi rename **handle đang giữ** với ReplaceIfExists=false. File mới ở đích làm restore bị chặn. Backup được giữ. Partial có thể còn khi ngắt; không tự xóa hay tự retry.
- Nguồn được báo thiếu chỉ khi native xác minh parent đang giữ hợp lệ và nhận mã file-not-found. Parent không đọc được không bị coi là đích trống; parent đổi identity làm CanRestore=false trước khi xác nhận.
- Lịch sử gần đây tối đa200 rows,2000 directories/10s; chỉ metadata được liệt kê. Dòng Uninspected không báo success. Đọc journal/kiểm backup mới có trạng thái; verified prefix không chứng minh đuôi đầy đủ hoặc chống người cùng quyền sửa code/hash.
- WPF có background worker thật cho Run/Inspect/Restore/History, progress X/N, elapsed và thời điểm kết thúc, Cancel và shared RAM/Disk lock. Đang chạy thì không đổi mode/đóng cửa sổ; bấm đóng yêu cầu dừng và chờ kết quả. Cửa sổ modal có flag riêng để coordinator không tự nhả khóa khi queue RAM rỗng.

## Thử giao dịch và phục hồi

Trong app: tab Disk → **Thử giao dịch / phục hồi**. Hoặc script tự cd/tạo mẫu/mở cửa sổ:

```powershell
powershell -NoProfile -STA -File "E:\SourceCode\NEW_APPLICATION\MemoryClear\scripts\Preview-DiskOperations.ps1"
```

Giữ Backup mặc định, đánh dấu Đã đọc cho log/database, duyệt cuối và gõ phrase riêng của phiên, rồi Chạy trên file mẫu. Tab Nhật ký và phục hồi: kiểm tra journal, chọn đích, xác nhận đúng đích rồi phục hồi. Safe-only không yêu cầu cảnh báo rủi ro; Blocked không override.

Agent đã chạy WPF offscreen với **DispatcherTimer thật** để hoàn tất worker; chưa chạy phiên interactive cho operator. `artifacts/disk-operation-preview.png` đã xem và sửa cột tác động để đọc được. Dữ liệu mẫu/backups/logs giữ lại để kiểm tra, không tự xóa đệ quy.

## Windows xử lý nhóm hệ thống

Provider catalog/schema chỉ cho Storage, Installed apps và Windows Update. Build lấy từ registry có provenance; URI cố định đã đối chiếu [Microsoft Launch Settings](https://learn.microsoft.com/en-us/windows/apps/develop/launch/launch-settings). Storage có các nhóm temporary/system cleanup theo [Microsoft Storage](https://support.microsoft.com/en-us/windows/experience/storage-filemanagement/storage-settings-in-windows). Chọn file cá nhân/Downloads hoặc bản Windows cũ trong Windows cần đọc tác động tại đó.

Không gọi DISM/ResetBase, xóa WinSxS/Installer, takeown/ACL hay dừng Windows Update. Mở Settings thành công chỉ là **Delegated**, dung lượng xóa giữ unknown; không tự biến thành Completed. Test prepare/catalog không chứng minh Settings đã mở hoặc dọn xong trên mọi build.

## Kiểm chứng và giới hạn

Trace `docs/verification/disk-operations-tests.json`, `disk-operation-ui-tests.json`, `disk-crash-tests.json`, `windows-provider-tests.json`; tổng thực tế và lệnh ở handoff10. Crash test chạy child PowerShell riêng và abrupt exit77 sau BackupVerified, DeleteStarted, Committed. Trước delete: nguồn còn/hash đúng; sau commit: backup đúng và phục hồi được, journal thiếu Finished báo InterruptedUnproven. Đây là process crash thật, không là mất điện/storage flush guarantee.

Chưa hoàn tất: independent **production** owner/risk authority, external backup/full disk/disconnect, Windows10/11 VM matrix, mapped writers/filter drivers, multi-instance, keyboard/DPI/operator acceptance. AppData lifecycle/history chỉ hỗ trợ nhận diện, không chứng minh uninstall. Memory runtime vẫn Normal/Strong; mức3 Close/Force còn dependencies/profile permission riêng trong phase12. Vì vậy phase10/12 và release **chưa thể ghi done**.

## Nghiệm thu một lệnh

Script sau tự cd, chạy13 Disk suites + RAM/core + plan/design/parser, ghi transcript/evidence/hash source. Không cần đứng trong project. Không tự mở GUI/đóng gói nếu không truyền switch.

```powershell
powershell -NoProfile -File "E:\SourceCode\NEW_APPLICATION\MemoryClear\scripts\Verify-Readiness.ps1"
```

Trong VM Windows10/11 riêng, dùng lần lượt `-ExpectedFamily Windows10 -DisposableVM` hoặc `-ExpectedFamily Windows11 -DisposableVM`; VM flag là lời khai operator, được ghi provenance, không giả là đã độc lập xác minh. Báo cáo của một máy không đại diện máy còn lại. `-Package` đóng gói source preview và xác minh entries/checksum; `-OpenApp` mở GUI sau checks. Script không mở cổng production chỉ vì tests local đạt.
