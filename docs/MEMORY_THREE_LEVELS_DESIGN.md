# Memory ba mức + policy cảnh báo chung

2026-10-09 · Thiết kế để người dùng confirm, chưa đổi app PowerShell/clear-policy đang chạy. Config fixture: `plan/memory-design.json` + schema. Prototype chung với Disk: `MemoryClear-CleanData-Prototype.html#memory`. Trạng thái nguồn `plan/tasks.json`, thiết kế phase11, triển khai phase12.

## Ba mức Memory

| Mức | Thao tác | UX / tác động |
|---|---|---|
| Tiêu chuẩn | Normal policy hiện có: ≥64 MB, CPU≤0.1%, tối đa12/30s, cooldown60s | Clear trực tiếp, không popup cảnh báo; giữ tiến trình, RAM có thể nạp lại |
| Chuyên sâu | Strong policy hiện có: ≥32 MB, CPU≤1%, tối đa32/60s, cooldown120s | Clear trực tiếp, không popup cảnh báo; giữ bảo vệ/foreground/identity, có thể thêm page faults khi dùng lại |
| Giải phóng tác vụ | Trim + graceful exit task đã có profile/allowlist và điều kiện đủ; tối đa8 close/force,60s,cooldown120s đề xuất | Disposable đã duyệt chạy trực tiếp; app có tác động cần duyệt; force riêng từng app, hai bước, không tự fallback |

CPU không phải vùng nhớ để xóa. Trim giảm working set, không bảo đảm giảm CPU/commit. Close/Kill có thể giảm CPU/private allocation khi tiến trình **thật sự thoát**, nhưng RAM/CPU toàn máy thay đổi bởi workload khác. Không cộng toàn working set/shared/private để cam kết thu hồi. [Working Set](https://learn.microsoft.com/en-us/windows/win32/memory/working-set).

## Bốn nhãn dùng chung cho Memory và Disk

| Nhãn | Memory | Disk | Xác nhận |
|---|---|---|---|
| An toàn theo rule | Trim đủ điều kiện; disposable graceful-exit có profile đã duyệt, không dữ liệu/child/service đang dùng | Cache tái tạo được đã kiểm chứng, closed/stable, empty folder hoặc cache của app đã gỡ có owner xác minh | Không popup; summary inline, progress, kết quả/cancel |
| Cần duyệt | App giải trí/launcher dừng âm thanh/thông báo; graceful exit chưa rõ người dùng còn cần | Bộ cài, log/dump cần giữ, dev cache phải restore, dữ liệu có backup verify | Bỏ tick; xem tác động, chọn phạm vi và xác nhận lượt dọn |
| Nguy hiểm | Force kill process cụ thể có thể mất dữ liệu đang ghi | Database/save/profile, Windows.old mất rollback, ảnh đĩa/VM quan trọng xóa vĩnh viễn | Bước1 duyệt mục cụ thể + hậu quả; bước2 final ack và gõ tên app (Memory) / phrase + danh sách file cụ thể (Disk). Đổi scope hủy cả hai |
| Bị chặn | Critical/session/security/service, foreground, unknown owner/dependency hoặc PID/start-time đổi | Installer/repair store, protected Windows, cloud/source, app đang dùng, identity/ownership/path không xác minh | Không nút override; nhiều confirm hay admin không bỏ chặn |

Không dùng popup cho mọi mục để người dùng phải click bỏ qua. Tác động bình thường vẫn ghi inline. "An toàn" là đánh giá có điều kiện tại scan; revalidate không đạt thì skip/held, không gán success. Popup chỉ xuất hiện nếu **mục đã chọn** có rủi ro; scan/tìm file lớn không cần confirm. Batch trộn safe/risky: warning chỉ liệt kê mục rủi ro, safe vẫn xuất hiện trong summary; nút "Chỉ xử lý an toàn" rõ ràng loại risky khỏi lượt đó.

## Định nghĩa task không cần thiết

Không suy ra từ tên `.exe`, RAM lớn, CPU thấp/cao, chạy nền hoặc không có cửa sổ. Phân loại theo OS critical/service inventory + current user/session + executable identity/start time + vendor/dependency evidence + user profile.

- Allowlist bản thật mặc định **trống**. Fixture ExampleDisposableTray là task giả có profile đã duyệt, không là app cài trên máy người dùng.
- Profile lưu quyền trim / close / force riêng, identity/vendor/version và effects chấp nhận. Approval invalidated khi executable/ownership/dependencies thay đổi. Saved close approval không tự cấp force permission.
- Disposable auto-close chỉ khi vendor graceful exit có contract không chứa user data, không job/download/install/sync chạy, không child đang dùng. Không chứng minh được thì chuyển Cần duyệt hoặc Bị chặn.
- IDE, terminal, node, database, download, sync, browser foreground mặc định giữ; user cần cung cấp app cụ thể và tác động chấp nhận. Không blanket kill `node`, `chrome`, `svchost` hoặc process tree.

## Luồng mức 3

`Scan → policy/effects → select/profile → review nếu cần → snapshot PID/start-time/exe/SID/session → revalidate → graceful close → verify exit → measure`

Request close có thể bị từ chối hoặc mở save prompt. Giữ trạng thái AwaitingUserSave/StillRunning, gain=0, chờ người dùng; không tự force khi timeout. Microsoft mô tả CloseMainWindow đóng theo luồng của ứng dụng và Kill có thể làm mất dữ liệu: [Process.CloseMainWindow](https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.process.closemainwindow?view=net-5.0).

Force là **plan mới** có PID/start time mới revalidate, exact per-app authority, bước1 review tác động, bước2 gõ đúng tên task và final ack; không kill con/service/user khác, không tự admin nếu access denied. Với service/system/unknown, chặn thay vì thêm confirm. Production handle phải check critical/identity ngay trước action; việc đó vẫn thuộc SAFE-04/QA-02/ML-03, không được chứng minh bằng pure fixture tests.

## Giao diện chung

Hai tab Memory và Disk dùng ba card level lớn: số/mục đích/action/effect, active border xanh; mức3 amber chỉ gợi ý có thao tác cần duyệt, không popup khi chuyển mức. Mỗi row hiện RAM/private/CPU hoặc allocated/logical/age, nhãn bốn mức, lý do chọn/bỏ, "Nếu thực hiện sẽ…". Search/filter không ẩn mất số task đã chọn.

Memory có Clear mục đã chọn, chỉ Clear an toàn, xem plan inline, dừng; force không nằm trong default selection. Disk có Dọn mục đã chọn, chỉ dọn an toàn, preview inline, tìm file lớn; cả hai progress/elapsed/timestamp/history riêng, khóa chung một operation. Không đặt cùng số GB reclaim Disk và RAM hoặc cộng vào một tổng.

## Gate và trạng thái

Phase11 chỉ thiết kế/model/HTML, HO-11 bắt buộc; phase12 (ML-SCOPE/01–04/HO-12) chưa triển khai. Không đổi trạng thái UI-01/CLEAR-01/QA-01/HO-03 đang review. ML-03 phải phụ thuộc SAFE-04 + QA-02 trước executor close/force thật; VM data survival/PID reuse/denial/cancel/saved permissions/no forced fallback là evidence release. C#/Linux để sau; product_runtime config không đọc .harness.
