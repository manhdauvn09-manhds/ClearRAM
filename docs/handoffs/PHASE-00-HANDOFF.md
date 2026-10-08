# Handoff — Phase 00 · Tài liệu

- Ngày cập nhật: 2026-10-07 (Asia/Tokyo)
- Người thực hiện: Codex
- Trạng thái bàn giao: Hoàn tất phần tài liệu; chưa triển khai ứng dụng
- Task handoff: HO-00
- Phiên bản kế hoạch: 2026-10-07.2
- Branch / commit: Không có commit được tạo trong công việc này.

## 1. Mục tiêu và phạm vi

Người dùng yêu cầu đề xuất app xem RAM/CPU, đóng/force kill app để giải phóng RAM, lập kế hoạch trước khi triển khai, lưu HTML đẹp và theo dõi status. Yêu cầu bổ sung đã chốt: **kết thúc từng phase phải tạo tài liệu handoff**.

Windows 10/11 trước, C# + Avalonia, portable GUI + CLI, Linux sau là **phương án đề xuất chưa được chốt**. Chưa có câu trả lời về cấu hình máy, mức tự động và app tuyệt đối cần giữ. Không suy diễn yêu cầu lập kế hoạch thành cho phép chạy kill process hoặc triển khai toàn app.

## 2. Kết quả theo task

| Task | Trạng thái | Kết quả / bằng chứng |
|---|---|---|
| DOC-01 | Hoàn tất | Đề xuất kỹ thuật, bảo vệ process và mockup trong `MemoryClear-Plan.html`. |
| DOC-02 | Hoàn tất | HTML offline, có in/PDF và form xuất lựa chọn. |
| DOC-03 | Hoàn tất | Bảng task, phụ thuộc, status, evidence, import/export; `IMPLEMENTATION_PLAN.md` và `plan/tasks.json`. |
| HO-00 | Hoàn tất | Tài liệu này, mẫu handoff và quy tắc trong `AGENTS.md`; thêm HO-00…HO-08. |

## 3. File và điểm vào

| File | Vai trò |
|---|---|
| `MemoryClear-Plan.html` | Tài liệu và bảng tiến độ mở trực tiếp trong browser; dữ liệu được nhúng khi build. |
| `plan/tasks.json` | Nguồn chính của 43 task, gồm 9 task handoff. |
| `IMPLEMENTATION_PLAN.md` | Bản kế hoạch tĩnh được sinh lại từ JSON. |
| `plan/build-plan.mjs` | Kiểm tra dữ liệu/phụ thuộc, dựng HTML và Markdown. |
| `plan/check-plan.mjs` | Kiểm tra logic bảng bằng Node VM và DOM giả lập. |
| `plan/upgrade-handoffs.mjs` | Migration một lần từ kế hoạch cũ; chạy lại không thêm task trùng. |
| `docs/handoffs/TEMPLATE.md` | Mẫu bàn giao bắt buộc. |
| `AGENTS.md` | Hướng dẫn tiếp tục và bắt buộc handoff cuối phase. |

## 4. Cách chạy và kiểm chứng

Môi trường thực hiện: Windows, Node.js có sẵn trong PATH. Từ thư mục gốc dự án:

```text
node plan/build-plan.mjs
node plan/check-plan.mjs
```

Kết quả: build kiểm tra mã task, phụ thuộc và chu trình; kiểm thử kiểm tra đồng bộ JSON/HTML, ID HTML duy nhất, cú pháp JS, trạng thái, gates, escape, bộ lọc, export/import, lưu/khôi phục và trường hợp storage lỗi. Kiểm tra mở rộng bao gồm đầy đủ 9 handoff, cổng phase và chuyển dữ liệu tiến độ phiên bản cũ.

Giới hạn: chưa xác minh lại hiển thị trực quan bằng trình duyệt; công cụ UI bị lỗi sandbox Windows (`helper_sandbox_lock_failed`). Kiểm thử DOM giả lập không thay thế kiểm thử layout, tải file và localStorage thực trên mọi browser. Không có test của app MemoryClear vì app chưa được viết.

## 5. Quyết định thiết kế cần giữ

- Bảo vệ process bằng nhiều tín hiệu và revalidate danh tính; không chỉ dựa vào tên/PID.
- Đóng bình thường trước; không tự force kill khi hộp thoại lưu đang chờ.
- Không purge cache hàng loạt hoặc hứa lượng RAM thu hồi chắc chắn.
- Status tài liệu tách khỏi triển khai. Hiện 4/4 task tài liệu hoàn tất, 0/34 task MVP, 5 task mở rộng để sau.
- Phase sau phụ thuộc handoff của phase trước. Handoff nháp khi tạm dừng không có nghĩa phase đã hoàn tất.
- Tiến độ sửa trên HTML chỉ lưu tạm trong browser và xuất JSON; không tự ghi vào `plan/tasks.json`. Cần đối chiếu bản xuất mới nhất trước khi cập nhật nguồn.

## 6. Tồn tại và điểm cần chốt

| Vấn đề | Bước xử lý |
|---|---|
| Nền tảng/stack chưa duyệt | DEC-01: lấy lựa chọn của người dùng. |
| Quyền tự động và app bảo vệ chưa biết | DEC-02: chốt với người dùng. |
| Chưa có ngân sách overhead và ma trận nghiệm thu | DEC-03: đặt mục tiêu dựa trên máy tham chiếu. |
| Layout chưa kiểm tra lại | Kiểm tra browser khi công cụ hoạt động; không claim đã QA trực quan. |

## 7. Hướng dẫn tiếp nhận

1. Đọc `AGENTS.md`, tài liệu này và `IMPLEMENTATION_PLAN.md`.
2. Kiểm tra xem người dùng có JSON tiến độ mới hơn hoặc quyết định mới trong chat hay không.
3. Tiếp tục phase 01, bắt đầu DEC-01 và DEC-02; DEC-03 theo sau. Không chọn công nghệ thay người dùng nếu họ chưa chốt.
4. Khi các task phase 01 đạt tiêu chí, tạo `docs/handoffs/PHASE-01-HANDOFF.md`, cập nhật HO-01 và gửi link.
5. Chưa được coi phase 01 hoàn tất hoặc bắt đầu phase 02 theo kế hoạch khi HO-01 chưa xong.

## 8. Checklist bàn giao

- [x] Tài liệu, task IDs và trạng thái hiện tại được ghi rõ.
- [x] Có template và quy tắc handoff trong hướng dẫn dự án.
- [x] Lệnh kiểm tra và giới hạn kiểm tra được nêu rõ.
- [x] Các quyết định chưa chốt có task tiếp tục cụ thể.
- [x] JSON, HTML và Markdown được đồng bộ và kiểm tra logic.
- [x] Link handoff được đưa vào phản hồi kết thúc phase tài liệu.
