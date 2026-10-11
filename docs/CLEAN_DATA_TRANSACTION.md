# Clean Data — transaction và nhật ký fixture

Cập nhật 2026-10-09 (Asia/Tokyo). Contract đã triển khai cho **dữ liệu mẫu do test tạo**, không phải quyền xóa dữ liệu cá nhân. `FixtureExecutor.psm1` không được import bởi GUI. Policy production vẫn `executionEnabled=false`.

## Phạm vi và transaction

`ExecuteFixture` chỉ chấp nhận file dưới `artifacts/disk-fixture-*` có marker. Marker/nhật ký được bảo vệ. Executor kiểm lại root, item/root consistency, SID, TTL, mode, risk và run ID; digest cục bộ chỉ phát hiện sửa nhầm. Người có quyền sửa code/digest vẫn có thể sửa policy: không coi đây là security boundary hoặc production authority.

Native giữ ancestor chain bằng handle không share-delete, so với ancestor IDs đã quét. Nguồn mở bằng cùng handle độc quyền có READ/DELETE; so FileID, đường dẫn thực, LastWriteTime, logical/allocated bytes, số hardlink và trạng thái pending/directory. File bị khóa được bỏ qua, không kill app/force unlock.

Backup tạo file mới bằng CREATE_NEW dưới `disk-backup-fixture-*` có marker. Ancestor ID của destination được đóng băng trước transaction. Buffer 64KB; sao chép, `Flush(true)`, đọc lại nguồn/destination cùng handle để so SHA-256 và kích thước; giữ handle destination và ancestors đến sau khi nguồn đóng. Ghi và flush DeleteStarted trước khi đặt disposition xóa trên chính source handle. Hủy/lỗi trước commit giữ nguồn; bản backup chưa hoàn tất có thể còn lại để kiểm tra, không tự xóa bằng catch.

Receipt có backup identity/ancestor/hash/bytes và trạng thái commit. `Deleted` mô tả disposition đã được chấp nhận và source handle đã đóng; không chứng minh cluster đã trả cho volume. `KnownAllocatedBytes` là metadata đã biết, không phải số free-disk đo được. Backup cùng volume báo gain0. Cleanup warning/final journal failure sau commit báo Partial, không giả là nguồn được giữ hay retry-delete.

API/runtime tham khảo: [FileStream và SafeFileHandle](https://learn.microsoft.com/en-us/dotnet/api/system.io.filestream?view=netframework-4.8), [Flush(Boolean)](https://learn.microsoft.com/en-us/dotnet/api/system.io.filestream.flush?view=netframework-4.8), [SetFileInformationByHandle](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-setfileinformationbyhandle). Đây là thiết kế transaction của ứng dụng, không phải bảo đảm từ các API về mọi filesystem/filter driver hoặc mất điện.

## Nhật ký v2 và đọc sau gián đoạn

Run tạo journal mới bằng CREATE_NEW, giữ stream không share-write/delete, append từng dòng và Flush(true). Payload gồm schema version2, thời gian UTC, run ID, input digest, source identity/path/root, stage và backup receipt. Envelope gồm sequence tăng liên tục, previous hash và SHA-256 của previous hash + newline + nguyên văn payload. Không tái sử dụng/ghi đè journal của run cũ.

Các stage: Revalidated → SourceLocked → BackupFlushed → BackupVerified → DeleteStarted → DeletedFixture. Permanent không có ba stage backup. BackupVerified/DeleteStarted đã chứa receipt **trước** commit, nên thiếu dòng cuối vẫn có căn cứ kiểm tra bản sao.

`Read-MCDiskFixtureJournal` chỉ kiểm tra: không replay-delete, không tự restore/ghi đè. Nó mở journal qua snapshot/handle có scope và size bound16MB; xác minh sequence/hash/scope, kiểm tra nguồn hiện tại và backup ID/hash bằng handle. `VerifiedAtInspection` chỉ đúng tại thời điểm kiểm tra, không phải quyền restore sau này.

- `VerifiedPrefix`: các dòng hiện có hợp lệ. **Không chứng minh đuôi nhật ký đầy đủ**; không có trusted external anchor. Tail bị bỏ nguyên dòng hoặc chuỗi được người cùng quyền tính lại không thể phát hiện chắc chắn.
- `InvalidOrTruncated`: dòng lỗi hoặc sequence/hash/scope sai; mọi kết quả phải duyệt.
- `EmptyUnproven`: chưa có sự kiện; không hiển thị thành cleanup thành công.
- Nguồn có thể PresentSameIdentity, PresentDifferentIdentity, MissingAtInspection hoặc Unknown. Missing không chứng minh công cụ là bên đã xóa. DeleteStarted thiếu DeletedFixture yêu cầu kiểm tra, tuyệt đối không retry tự động.

Nhật ký cũ không có envelope v2 bị từ chối là định dạng chưa xác minh; không tự migration để resume. Test sửa/cắt nhật ký chỉ tác động fixture mới, không xóa evidence thực của các lần chạy trước.

## Kiểm chứng và việc còn thiếu

`tests/Check-DiskFixtureExecutor.ps1`: 17/17 trên Windows PowerShell5.1.26100.9444; trace `docs/verification/disk-fixture-executor-tests.json`. Competing runspace kiểm tra write/rename khi source đang giữ handle. Cancel sau backup flush, destination tồn tại/thay parent, journal fault trước delete, modified/truncated journal, receipt/hash và replay protection có fixture evidence.

Chưa kiểm chứng mất điện/kill process giữa transaction, external disk disconnect/full disk, pre-existing writable memory mappings, ReFS/network/filter-driver matrix, disk-free delta, restore conflict và production independent authority. Không dùng local hash-chain để quảng cáo nhật ký không thể sửa. Cần CD-02/03/04/05/06/07/08 gates và VM trước phát hành; không bật production deletion từ các test này.
