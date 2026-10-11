# Lịch sử quan sát ứng dụng — supporting evidence, không xác nhận uninstall

Cập nhật 2026-10-09 (Asia/Tokyo), revision 2026-10-09.7. Đã nối vào **Phân tích ứng dụng** sau quét phạm vi **Cache / dữ liệu app còn sót**. Không chạy installer/uninstaller, không đọc nội dung file cá nhân. Chỉ ghi metadata của MemoryClear vào `.data/disk-owner-history.json`; không gửi ra mạng.

## Hành vi thực tế

- Lần thấy app: lưu UTC, nguồn registry/MSIX, định danh entry/package và version được nguồn cung cấp. Nếu không có nguồn/định danh hợp lệ thì không tạo bằng chứng đã từng cài.
- Lần sau không khớp inventory: chỉ khi inventory hiện tại đầy đủ, snapshot tham chiếu còn mới/đầy đủ và không có tham chiếu thì bổ sung nhãn **“từng thấy cài, hiện thiếu metadata · chưa chứng minh gỡ”**. Không gọi trạng thái này là “uninstalled” hay “safe”.
- Có process/service/task hoặc metadata cài đặt hiện tại vẫn ưu tiên bảo vệ. Inventory thiếu/cũ/future không được lịch sử nâng thành kết luận app đã mất.
- Chi tiết file hiển thị UTC lần thấy metadata, source/entry ID/version và giới hạn. OwnerLabel vẫn tìm kiếm được. Shared RAM/Disk lock, cancellation và progress dùng worker hiện có.
- Lịch sử bắt đầu từ lúc sử dụng tính năng này. App đã gỡ trước đó không được dựng lịch sử giả; máy có app portable/custom profile ngoài catalog cũng chưa được bao phủ.

## Liên kết dữ liệu và thời hạn

Payload schema 1: `Sid`, SHA256 catalog đã parse, `UpdatedUtc`, tối đa20 Records theo profile. Mỗi record có path chuẩn, FileID/volume của root, `LastObservedUtc`, lần thấy metadata cài gần nhất và tối đa8 source/entry/version. Chỉ giữ lần quan sát gần nhất và lần thấy cài gần nhất, không phải log đầy đủ mọi sự kiện. App Inventory đã bổ sung `InstallationId` và `Version`; không lấy CommandLine hoặc file contents.

Root được native probe lại khi phân tích và so identity với preview. Root đổi/không đọc được báo Partial, không dùng history cho root đó. Lần quét mới gặp identity khác bắt đầu căn cứ mới. Profile không xuất hiện trong trang hiện tại không được coi là app đã gỡ; bản ghi cũ được giữ trong giới hạn catalog.

Catalog đổi: bắt đầu baseline mới và báo CatalogReset. SID khác: không sử dụng và không ghi đè lịch sử của user kia. Thời gian future/format hỏng: Unavailable. Lần thấy cài quá180 ngày có thể hiện trong chi tiết nhưng không nâng nhãn thành PreviouslyObservedMissingProtected. Đây là cửa sổ hỗ trợ suy luận, không phải cam kết dữ liệu lịch sử được xóa sau180 ngày.

Policy: `app/owner-history-policy.json` + schema, `governs=product_runtime`, execution disabled; file tối đa262144 bytes, profile20/matches8/age180 ngày. Payload shape ở `app/owner-history-payload.schema.json`; runtime cũng kiểm tra shape, path, unique IDs, budget, quan hệ timestamps và checksum.

## Lưu file và xử lý lỗi

`FileInventory.ObservationStore` chỉ mở tên `.data/disk-owner-history.json` cố định dưới root MemoryClear được caller chọn. Giữ ancestor handles trong suốt read/validate/write, mở file exclusive, xác minh final path, không reparse/cloud/hardlink/directory/delete-pending và có giới hạn kích thước. Không cho process khác ghi/rename qua share mode khi đang giữ handle. Native helper không phải privileged service hoặc security boundary chống người có quyền sửa code.

JSON envelope có SHA256 của chuỗi payload để phát hiện lỗi ghi/chỉnh sửa vô ý. SHA256 local không chống giả mạo bởi người có thể viết lại file/checksum; mọi nhãn đều chỉ supporting evidence, **không cấp deletion authority**.

Ghi cùng handle rồi Flush(true), **không tuyên bố atomic/crash-safe**. Crash/power loss có thể làm file hỏng; lần đọc sau từ chối JSON/checksum sai. File hỏng, đang khóa, không đủ quyền hoặc SID sai được giữ, báo Unavailable/Partial; không âm thầm reset thành “không có app”. History trống chưa có metadata không tạo lịch sử đã cài. Khi hủy trước commit, không ghi nội dung mới; một store trống có thể đã được tạo nếu cancel tới sau khi mở. Kiểm thử pre-cancel không tạo file.

Mọi row và lịch sử vẫn `DeletionAllowed=false`; production Clean còn khóa. Nếu history lỗi, phân tích metadata hiện tại vẫn có thể hiển thị nhưng kết quả không báo đầy đủ.

## Kiểm chứng và giới hạn

`tests/Check-DiskOwnerHistory.ps1` kiểm tra fixtures native/synthetic metadata: seen→missing, no-history, incomplete/reference overrides, corrupt/future/SID/catalog/root identity/expired, exclusive lock/hardlink/junction, cancellation/scope và giữ nguyên dữ liệu. `Check-DiskUI.ps1` thực hiện hai lượt phân tích nền trên fixture (có metadata rồi thiếu), hiển thị trạng thái và provenance, vẫn khóa nút xóa. Báo cáo kết quả đã chạy nằm trong `docs/verification/disk-owner-history-tests.json`, `disk-ui-tests.json`; số mới nhất ở handoff phase10.

Tái lập bằng script tự cd project: `powershell -NoProfile -File "E:\SourceCode\NEW_APPLICATION\MemoryClear\scripts\Verify-Phase10.ps1"`.

Chưa chứng minh live registry/CIM/MSIX coverage, sự kiện uninstall thật, ngữ nghĩa cache theo vendor version, crash/power-loss/multi-user Windows10/11. Việc lưu version không tự xác nhận cache của version đó disposable. Không dùng lịch sử local như gate xóa app data. CD-02 và phase10 chưa hoàn tất.

Tiếp theo: màn hình duyệt phạm vi/tác động, preview bất biến và hai bước duyệt trên fixtures; sau đó independent production authority/restore/VM theo dependencies trước khi mở Clean thật.
