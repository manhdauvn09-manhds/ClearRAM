# Handoff — Phase 01 · Chốt phạm vi

- Ngày: 2026-10-08 (Asia/Tokyo). Người thực hiện: Codex.
- Trạng thái: Hoàn tất phạm vi bản thử nghiệm PowerShell.
- Task: DEC-01, DEC-02, DEC-03, HO-01.
- Revision: 2026-10-08.1. Không tạo commit.

## 1. Phạm vi và quyết định

Người dùng yêu cầu làm tiếp và trả lời **“Làm script PowerShell có GUI trước”**. Chọn Windows 10/11 x64, Windows PowerShell 5.1 + WPF, thư mục portable kèm launcher CMD và CLI. Không cần .NET SDK hoặc Avalonia cho bản này; Native.cs là adapter Win32 được Add-Type biên dịch bằng runtime có sẵn.

Chế độ mặc định do người triển khai chọn để tiếp tục an toàn: thủ công, close trước, force kill xác nhận riêng, không tự kill nền; hệ thống/service/critical/user khác/unknown được bảo vệ. Người dùng chưa cung cấp danh sách app cá nhân, nên ProtectedPaths và AllowClosePaths ban đầu trống; quyền đóng khẩn cấp phải được đặt trong UI. Đây không phải tuyên bố người dùng đã chọn app cụ thể hoặc bật tự động.

## 2. Kết quả và bằng chứng

| Task | Kết quả | Bằng chứng |
|---|---|---|
| DEC-01 | Phương án PowerShell đã được người dùng chọn | Câu trả lời trong chat; README.md, docs/ARCHITECTURE.md |
| DEC-02 | Đã ghi defaults và cách thêm app cần giữ | Get-MCSettings, policy, GUI Protect/AllowClose; chưa có custom list |
| DEC-03 | Có máy tham chiếu, ngân sách ban đầu và ma trận cần test | docs/ARCHITECTURE.md, artifacts/monitor-baseline.json |
| HO-01 | Bàn giao phạm vi cho phase nền tảng | Tài liệu này |

## 3. Thay đổi / điểm vào

`docs/ARCHITECTURE.md` và `README.md` là contract hiện tại. `plan/tasks.json` cập nhật phương án PowerShell và trạng thái. Đề xuất C# trước đó trong phase 00 được giữ như lịch sử; lựa chọn mới trong chat có ưu tiên cao hơn.

## 4. Kiểm chứng

- Windows 11 Pro build 26200, 12 logical CPU (i5-1345U), tổng RAM OS 15.69 GiB.
- Windows PowerShell 5.1.26100.8875 có sẵn; smoke WPF nạp 19 control và đọc process thật.
- `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/Measure-Monitor.ps1`: RAM total khớp CIM, available RAM nằm trong cửa sổ quan sát/tolerance; collector 1.23% CPU toàn máy, 97.6 MB working set qua 4 mẫu ngắn.
- Mục tiêu ban đầu: GUI idle CPU ≤2%, working set ≤250 MB; thu nhỏ 10 giây/mẫu, ngân sách ≤200 MB nếu framework cho phép. Chưa nghiệm thu toàn GUI theo các mục tiêu này.

## 5. Lý do kỹ thuật

WPF đáp ứng lựa chọn script GUI và có trên Windows. Query/execute dùng cùng policy, không nội suy tên process vào shell. Windows 10 22H2 và Windows 11 24H2/25H2 x64 là mục tiêu ma trận, không phải các bản đã được test đầy đủ.

## 6. Tồn tại

Custom protected apps chưa được cung cấp; người dùng có thể bổ sung qua UI. Linux, auto kill và Avalonia để sau. Ngưỡng overhead là mục tiêu kỹ thuật ban đầu, chưa phải bảo đảm hiệu năng.

## 7. Tiếp nhận

Đọc `docs/ARCHITECTURE.md`. Tiếp tục BASE-01…03 bằng Windows PowerShell 5.1; không cài .NET SDK. Mọi thay đổi quyền tự động cần người dùng chọn rõ. Sau foundation phải có HO-02.

## 8. Checklist

- [x] Quyết định và defaults được phân biệt rõ.
- [x] Có cấu hình máy tham chiếu và tiêu chí nghiệm thu.
- [x] File/bằng chứng/giới hạn được ghi rõ.
- [x] Cập nhật task và dựng lại kế hoạch.
- [x] Link handoff được cung cấp trong phản hồi cuối.
