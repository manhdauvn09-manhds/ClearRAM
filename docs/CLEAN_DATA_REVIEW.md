# Duyệt phạm vi và tác động — cửa sổ WPF, chưa thực thi xóa

Cập nhật 2026-10-10 (Asia/Tokyo), revision 2026-10-10.1. Trong tab Disk, chọn các dòng rồi bấm **Duyệt danh sách...** để xem đúng phạm vi và tác động. Không tự chọn file. Các mục thật hiện vẫn bị chặn vì production policy/owner/backup/VM chưa đủ điều kiện. Nút xác nhận không mở khóa mục bị chặn.

## Luồng đã triển khai

1. **Bước 1:** tên file, đường dẫn đầy đủ qua tooltip, allocated MB, loại xử lý và hậu quả/lý do chặn. Mục rủi ro trong fixture có checkbox Đã đọc riêng từng dòng. Mục bị chặn không cho tick và không cộng vào tổng dung lượng trong kế hoạch.
2. **Bước 2:** giữ nguyên danh sách, xác nhận đã đọc hậu quả; mục Danger cần gõ cụm từ riêng cho phiên. Review không có Danger vẫn cần acknowledgment cuối nhưng không cần phrase. Safe-only fixture đi thẳng đến kết quả xem trước, không bắt acknowledgment/cụm từ rủi ro.
3. **Kết quả:** “Duyệt thử hoàn tất”, 0 file/0 byte đã xóa, execution disabled. Không gọi executor và không tạo quyền xóa thật. Không replay xác nhận trên phiên đã hoàn tất.
4. **Quay lại:** xóa checkbox đã đọc, acknowledgment cuối và phrase. **Đóng:** bỏ phiên khỏi bộ nhớ; mở lại tạo phiên mới. Muốn thay danh sách thì đóng cửa sổ, chọn lại, duyệt lại.

Đây là cửa sổ xem trước do người dùng chủ động mở, không phải popup bắt buộc cho mọi thao tác dọn an toàn. Chưa có production cleanup để nghiệm thu đường chạy safe không popup. Luồng hai bước có thể thử với script mẫu bên dưới; GUI thường chỉ cho xem lý do chặn.

## Snapshot và kiểm tra lại

`Review.psm1` serialize danh sách sang payload riêng để không giữ tham chiếu có thể đổi từ hàng WPF. Mỗi lần lấy state trả bản deserialize mới. Phiên gắn RunId, SID, context token (phạm vi/level/finder options/selection), policy fingerprint và TTL. Policy `app/disk-review-policy.json` + schema: `product_runtime`, `PreviewOnly`, `executionEnabled=false`, tối đa100 mục/phiên,8 phiên trong process, TTL600 giây.

Trước chuyển bước hoặc xác nhận, kiểm tra context/SID/thời hạn/policy. Với mục fixture đủ điều kiện, đọc lại native snapshot và so FileID, ancestor identity, size, allocated size, timestamp, link count, attributes. Thay đổi những metadata này làm phiên Invalidated; quay lại không hồi sinh phiên. Đây **không phải hash nội dung**: thay byte mà giữ nguyên metadata có thể không được phát hiện. Không giữ handle từ preview đến execution; executor thật sau này vẫn phải tự revalidate tại thời điểm xóa.

Hash policy/snapshot trong process là cơ chế phát hiện thay đổi, không phải security boundary chống người có quyền sửa local code/state. Dữ liệu từ GUI không cấp authority. GUI production không truyền fixture risk overrides; test/example chỉ được dùng file dưới root `artifacts/disk-fixture-*` có marker. Không import hoặc gọi FixtureExecutor từ Review/View.

## Giao diện và phối hợp

Nút duyệt chỉ bật khi có selection hiện tại và không có operation RAM/Disk. Cửa sổ mở modal trên cửa sổ chính, giữ shared operation lock; parent không cho đổi scope/selection trong khi duyệt. Đóng hoặc lỗi mở trả khóa trong `finally`. Luồng core vẫn kiểm tra context để caller khác không dùng scope cũ. Scan/reset làm mất selection và tắt nút duyệt.

UI hiển thị thời điểm hết hạn; kiểm tra hết hạn diễn ra khi bấm chuyển bước/xác nhận, chưa có countdown hoặc tự đóng theo timer. Revalidation fixture hiện chạy đồng bộ, giới hạn100 mục; latency với I/O chậm chưa benchmark. Màu/nút không thể thay kiểm tra core.

## Thử trực tiếp bằng dữ liệu mẫu

Script tự cd tới project, tạo hai file mới trong root fixture riêng, mở cửa sổ duyệt, rồi kiểm tra hash và sự tồn tại của các file sau khi đóng. Không xóa, không yêu cầu admin, không tự dọn fixture.

```powershell
powershell -NoProfile -STA -File "E:\SourceCode\NEW_APPLICATION\MemoryClear\scripts\Preview-DiskReview.ps1"
```

Agent đã parse script bằng PowerShell và kiểm tra cùng luồng qua WPF offscreen; **chưa chạy phiên interactive cho operator**. Không coi ảnh render/test sự kiện là bằng chứng đã bấm trên máy người dùng.

Tái lập bộ kiểm tra tự cd:

```powershell
powershell -NoProfile -File "E:\SourceCode\NEW_APPLICATION\MemoryClear\scripts\Verify-Phase10.ps1"
```

## Bằng chứng và phần còn lại

- `Check-DiskReview.ps1`:15 checks về blocked production, per-item review, phrase/ack, safe-only, review-only, totals, snapshot detached, context/policy/TTL, back/cancel/closed session, native metadata change, no execution.
- `Check-DiskReviewUI.ps1`:16 assertions WPF offscreen; checkbox binding thực sự cập nhật model, dòng blocked không tick, các nút chuyển bước/back/final, nút duyệt gắn selection/shared lock/reset. Ảnh `artifacts/disk-review-step1.png` và `disk-review-step2.png` đã xem.
- Trace chạy ở `docs/verification/disk-review-tests.json` và `disk-review-ui-tests.json`; các số tổng mới nhất ở handoff phase10. CI được cấu hình nhưng không suy ra đã chạy server.

CD-03 vẫn review: chưa có backup destination/history/restore UI, authority và executor production, Win10/11 keyboard/DPI/operator/latency acceptance. Tiếp CD-04 kiểm tra độc lập phạm vi/rủi ro/approval tại điểm thực thi và CD-05 recovery/restore theo dependencies; chỉ nối Clean thật khi các gate đạt.
