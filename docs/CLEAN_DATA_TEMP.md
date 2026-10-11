# Dọn Temp có duyệt — capability giới hạn

Cập nhật 2026-10-10. Portable Windows PowerShell 5.1, quyền user hiện tại. Đây là bộ thực thi riêng, không bật quyền xóa của scanner/finder/app-data.

## Cách dùng

Mở app, vào tab Disk, chọn mức rồi nhấn **Dọn Temp có duyệt...**. Cửa sổ quét riêng, không sử dụng lựa chọn/risk label của bảng scanner. Mức 1 và 2 giữ file mới hơn 7 ngày; mức 3 giữ file mới hơn 3 ngày. Mục hệ thống tiếp tục qua **Dọn bằng Windows**.

Chỉ liệt kê file `.tmp`/`.log` ngay trong `LocalApplicationData\Temp` do Windows xác định cho tài khoản hiện tại. Không quét thư mục con. File hơn 64 MiB, read-only/hidden/system, reparse/cloud/offline, hardlink, sai owner hoặc không mở độc quyền được sẽ giữ lại. Tuổi và đuôi file chỉ là điều kiện xét duyệt, không chứng minh rác an toàn.

Mọi ứng viên trong capability này là **Review**: có thể mất log chẩn đoán hoặc dữ liệu tạm phục vụ khôi phục/cài đặt. Bước 1 chọn từng file hoặc chọn tất cả sau khi đọc tác động. Bước 2 chấp nhận xóa vĩnh viễn danh sách đã cố định. Không có Undo/backup trong capability này. Quay lại lập phiên mới và xóa mọi chấp thuận. Không áp dụng rule Safe giả để tránh cảnh báo cho file chưa chứng minh tái tạo được.

## Contract

- Policy/schema: `app/temp-cleanup-policy.json`, `app/temp-cleanup-policy.schema.json`; giới hạn 100 mục, 5000 entry, ngân sách quét 15 giây, TTL 600 giây. Ngân sách được kiểm tra giữa file; một lần hash native đang chạy có thể vượt mốc 15 giây. Token hủy kiểm tra trong vòng đọc 64 KiB.
- Backend: `TempCleanup.psm1`, phiên process-local shared runspace, frozen snapshot/nội dung SHA256/SID/policy/context/TTL, không nhận quyền xóa từ checkbox hoặc risk label GUI. Cùng SID mutex với giao dịch Disk fixture; phiên tiêu thụ một lần.
- Native: `OwnTempRoot/ValidateOwnTemp/ExecuteOwnTemp` trong `FileInventory.cs`. Root không do caller tùy chọn; owner kiểm bằng security descriptor của handle. Hỗ trợ SID user local/domain và SID `S-1-12-1-*` quan sát trên host này. Session 0, token admin và dịch vụ bị từ chối. Không đổi ACL/owner, không nâng quyền, không đóng process để mở khóa file.
- Trước commit giữ ancestors không share-delete và nguồn read/delete/read-control độc quyền; kiểm FileID/ancestor/time/size/link/attributes/owner, hash trên cùng handle rồi disposition trên handle đó. Không recursive delete, không force-delete, không overwrite, không tự retry/resume.
- Nhật ký create-new `.data/temp-operation-<id>.jsonl`, giữ ancestors và file handle, mỗi record sequence/hash-chain được flush trước commit. SourceLocked/DeleteStarted/Committed/Finished phân biệt ý định, commit và kết thúc. Hash-chain local không phải chữ ký hoặc bảo đảm chống người có cùng quyền user. Mất điện/thiếu Finished không chứng minh hoàn tất. Chưa có viewer/recovery authority production cho các journal này.
- UI: WPF worker/DispatcherTimer, checkbox một click/two-way; shared RAM/Disk lock, X/N, elapsed/endtime, Dừng tại ranh giới file. Đóng khi đang chạy yêu cầu hủy và chờ worker kết thúc. Kết quả báo allocated của file đã xóa; không gọi đó là số free-disk đo được. Lỗi/locked/changed có thể tạo Partial; không báo thành công toàn bộ.

Đây là lớp bảo vệ ứng dụng, không phải security boundary trước chương trình khác chạy cùng tài khoản hoặc admin. File không mở được độc quyền được giữ lại; các tình huống mapped writer/filter driver/power-loss vẫn chưa được chứng minh.

## Kiểm chứng

Trên Windows11 Client build26200/25H2, PS5.1.26100.9444, đã chạy:

`powershell -File "E:\SourceCode\NEW_APPLICATION\MemoryClear\scripts\Verify-OwnTemp.ps1"`

12/12 check đạt: chỉ file QA tên GUID mới tạo, chọn scope chính xác, hai bước, native owner/age/type/root, commit/journal/no replay, content change, locked file, cancel. Report `docs/verification/temp-cleanup-tests.json`. Không xóa dữ liệu có sẵn. Các file QA còn lại được liệt kê và giữ để kiểm tra; không tự dọn Temp sau test.

`powershell -STA -File "E:\SourceCode\NEW_APPLICATION\MemoryClear\tests\Check-TempUI.ps1"`

7/7 check đạt: worker/DispatcherTimer thật, checkbox template click cập nhật source hai chiều, Back bỏ approval, shared lock, native QA deletion/end status và render content. Report `docs/verification/temp-ui-tests.json`, ảnh `artifacts/temp-ui-preview.png` đã xem. Chưa thay thế nghiệm thu thao tác người dùng/keyboard/DPI.

Guard-only/CI dùng `Check-TempCleanup.ps1` không có switch, ghi `temp-cleanup-guard-tests.json`; không coi guard-only là chứng cứ đã xóa Temp thật. `Verify-Readiness.ps1 -OwnTempSelfTest` bật đúng hai suite QA riêng. Windows10 chưa test; user chỉ có host Windows11. Không giả định đây là VM.

Nguồn API: [Known Folders của Microsoft](https://learn.microsoft.com/en-us/windows/win32/shell/known-folders) khuyến nghị .NET `Environment.GetFolderPath` cho ứng dụng .NET. Native metadata/handle/disposition dựa trên API Win32 hiện có của dự án.

## Còn lại

Không triển khai trong capability này: xóa thư mục cache trình duyệt/app, data của app đã gỡ, file cá nhân lớn, Windows.old/WinSxS/installer, backup/restore production khác volume. Những mục đó không được mở quyền chỉ vì Temp đã chạy đạt. Nhận diện uninstall/vendor, authority riêng và provider backup vẫn thuộc CD-02/04/05. Memory mức 3 còn profile và safety dependencies riêng.
