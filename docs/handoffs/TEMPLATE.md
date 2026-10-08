# Handoff — Phase XX · [Tên phase]

- Ngày cập nhật: YYYY-MM-DD (Asia/Tokyo)
- Người thực hiện: [tên]
- Trạng thái bàn giao: Nháp / Chờ kiểm tra / Hoàn tất
- Task handoff: HO-XX
- Phiên bản kế hoạch: [revision trong plan/tasks.json]
- Branch / commit: [nếu có; nếu không có thì ghi rõ]

## 1. Mục tiêu và phạm vi đã chốt

[Mục tiêu phase; quyết định của người dùng và giới hạn cần giữ. Phân biệt đề xuất với quyết định đã chốt.]

## 2. Kết quả theo task

| Task ID | Trạng thái | Kết quả thực tế | Bằng chứng |
|---|---|---|---|
| ... | ... | ... | Đường dẫn / commit / log |

## 3. Thay đổi và điểm vào để tiếp tục

| File / module | Thay đổi | Người tiếp nhận cần biết |
|---|---|---|
| ... | ... | ... |

## 4. Cách chạy và kiểm chứng

- Môi trường / OS / runtime: [...]
- Chuẩn bị cần thiết: [...]
- Lệnh kiểm tra chính xác và kết quả: [...]
- Bằng chứng/log: [...]
- Những kiểm tra chưa chạy hoặc không thể chạy: [...]

Không coi build thành công là đủ nghiệm thu. Ghi đúng phạm vi kiểm thử; không chứa secret hoặc dữ liệu nhạy cảm trong log bàn giao.

## 5. Quyết định kỹ thuật và lý do

[Các lựa chọn quan trọng, đánh đổi, contract, cấu hình hoặc migration ảnh hưởng phase sau.]

## 6. Tồn tại, rủi ro và điểm chặn

| Vấn đề | Ảnh hưởng | Task xử lý / người phụ trách | Bước tiếp theo |
|---|---|---|---|
| ... | ... | ... | ... |

Nếu không có vấn đề đã biết thì ghi rõ; không bỏ trống mục này. Nếu task bắt buộc còn dang dở, handoff giữ trạng thái nháp/chờ kiểm tra và phase chưa hoàn tất.

## 7. Hướng dẫn người / chat tiếp nhận

1. Đọc: [...]
2. Kiểm tra trạng thái workspace và tiến độ mới nhất: [...]
3. Bắt đầu từ task: [...], sau khi phụ thuộc [...] hoàn tất.
4. Bước tiếp theo cụ thể: [...]
5. Không thực hiện: [những thao tác ngoài phạm vi hoặc cần quyết định còn thiếu].

## 8. Checklist kết thúc phase

- [ ] Task bắt buộc trong phase đạt tiêu chí và có evidence.
- [ ] Handoff phản ánh đúng mã/tài liệu hiện tại và không còn placeholder.
- [ ] Lệnh kiểm tra, kết quả và giới hạn được ghi rõ.
- [ ] Vấn đề tồn tại đã có hướng xử lý và không che giấu blocker.
- [ ] `plan/tasks.json` và HO-XX được cập nhật; HTML/Markdown đã dựng lại.
- [ ] Đã chạy kiểm tra kế hoạch và trả link handoff cho người dùng.
