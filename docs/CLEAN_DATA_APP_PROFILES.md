# Nhận diện cache và dữ liệu ứng dụng — bản đầu, chỉ đọc

Cập nhật 2026-10-09, revision 2026-10-09.7. Người dùng chọn ưu tiên nhận diện app/cache trước màn hình duyệt xóa. Đã triển khai trong app thật: **Cache / dữ liệu app còn sót → Quét chỉ đọc → Phân tích ứng dụng**. Không cần admin, không đọc nội dung file và không xóa dữ liệu thật.

## Phạm vi hiện có

| App / thư mục mặc định của user hiện tại | Nhánh được gắn CacheCandidate | Dữ liệu được giữ riêng |
|---|---|---|
| Chrome stable: LocalAppData/Google/Chrome/User Data | Default hoặc Profile N: Cache, Code Cache, GPUCache | Cookie, login, bookmark, history, sessions, Network, IndexedDB, Local Storage, Service Worker/offline |
| Edge stable: LocalAppData/Microsoft/Edge/User Data | Cùng hình dạng profile Chromium ở trên | Giữ dữ liệu cá nhân/offline như Chrome |
| VS Code stable: RoamingAppData/Code | Cache, Code Cache, GPUCache, CachedData tại gốc | Toàn bộ User (settings, snippets, history, workspaceStorage), Backups và dữ liệu web lưu bền |

Nhánh cache phải là **thư mục tổ tiên đúng vị trí**, không khớp theo tên file/đuôi hoặc substring: `Default/Downloads/Cache`, `Cache-old`, file có tên `Cache`, profile custom đều không đủ. Nhánh chưa biết được giữ. Catalog hiện chỉ có ba app stable, không quét toàn AppData hay mọi phần mềm đã gỡ. Không tự dò đường dẫn policy, command line, portable/custom profile hoặc thư mục extensions của VS Code. Những phần ngoài phạm vi không được báo là đã sạch.

`app/disk-app-profiles.json` và schema chứa rule/provenance, `governs=product_runtime`, `executionEnabled=false`. Validator runtime kiểm tra field/budget/layout/path; không đọc cấu hình harness. Catalog là cấu hình local cho **preview**, không là nguồn thẩm quyền để xóa.

## Hai loại bằng chứng riêng

1. **Loại dữ liệu:** CacheCandidate, ProtectedUserData hoặc UnknownAppData. Nhận dạng đường dẫn không kiểm chứng cache có thể xóa trên phiên bản ứng dụng cụ thể. Mọi dòng vẫn `Risk=Blocked`, `DeletionEnabled=false`.
2. **Tình trạng ứng dụng:** exact display name + publisher trong inventory → InstalledCatalogProtected. Tên executable tương ứng trong snapshot process/service/task còn mới → PossibleReferenceProtected; chỉ là căn cứ giữ, không proof executable đó sở hữu dữ liệu. Metadata thiếu hoặc snapshot thiếu/cũ/future → UnknownLifecycleProtected. Chỉ khi các nguồn đầy đủ và không khớp mới hiển thị ResidualCandidateUnverified: **có thể còn sót, chưa chứng minh đã gỡ**.

Đã có [lịch sử quan sát local](CLEAN_DATA_OWNER_HISTORY.md): UTC/source/entry ID/version gắn SID/catalog/root identity. Đây chưa phải lịch sử sự kiện cài/gỡ được xác minh; thiếu metadata hiện tại vẫn không chứng minh uninstall. Không biến absence hoặc empty directory thành quyền xóa. Chứng cứ InstallLocation/shared/reference có trước vẫn ưu tiên hơn catalog. App đã gỡ thật vẫn có thể để lại database/save giá trị; cần phân loại và duyệt theo chính sách đã chốt.

## Quét và giao diện

- AppData là phạm vi riêng, loại trừ finder file lớn/cũ; đổi phạm vi xóa preview cũ. Không áp MB/tuổi/đuôi của finder lên catalog rồi làm người dùng hiểu nhầm là đã quét hết cache.
- KnownFolders thực tế của user, chỉ volume Windows; cloud, Windows, ProgramFiles, source root và phạm vi chưa biết bị loại. Root excluded/unavailable báo Partial.
- Native `ProbeDirectory` giữ ancestor handles khi quan sát, phân biệt Absent, Present, EmptyAtObservation, Unavailable. Thư mục mặc định không tồn tại là trạng thái bình thường; lỗi quyền/reparse không được diễn giải là không tồn tại. EmptyAtObservation không chứng minh vẫn rỗng sau khi trả về và không cấp quyền xóa folder.
- Quét vẫn dùng native FileID/ancestor/allocated, không theo junction/reparse/cloud, bỏ hardlink; 1000 dòng/trang, 50000 entries/30 giây scan. Quan sát root và phân tích ownership riêng có chi phí bổ sung; không hứa deadline cứng cho I/O. Probe tối đa theo catalog (hiện ba roots).
- Worker nền, elapsed/progress/cancel/shared RAM lock giữ nguyên. Chi tiết/effect nói tác động; không popup cảnh báo khi chỉ quét. GUI không import FixtureExecutor.
- Kết quả phân trang là quan sát lại, không manifest đóng băng. Byte tổng là metadata, không dung lượng chắc chắn thu hồi.

## Nguồn và mức chắc chắn

- [Chromium user data directory](https://chromium.googlesource.com/chromium/src/+/HEAD/docs/user_data_dir.md) xác định gốc mặc định và việc profile chứa nhiều loại trạng thái cá nhân. Đây không phải giấy phép xóa toàn profile.
- [Edge UserDataDir](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/userdatadir) và [DiskCacheDir](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/diskcachedir) mô tả đường dẫn/policy có thể tùy biến. Bản đầu không khám phá các override.
- [VS Code uninstall](https://code.visualstudio.com/docs/setup/uninstall), [settings](https://code.visualstudio.com/docs/configure/settings) và [portable](https://code.visualstudio.com/docs/setup/portable) hỗ trợ phân biệt user data/default/portable; xóa để clean uninstall không đồng nghĩa dữ liệu vô giá trị.
- Danh sách nhánh cache trong catalog là **quy tắc nhận diện ứng viên của MemoryClear dựa trên layout sản phẩm**, cần đối chiếu phiên bản thực tế. Nguồn root không tự chứng minh từng nhánh disposable; Edge theo layout Chromium là suy luận được ghi rõ, chưa production-safe. Không lấy tên `Cache` ở thư mục bất kỳ làm bằng chứng.

## Kiểm chứng và phần còn lại

`tests/Check-DiskAppProfiles.ps1`: 16/16 trên PS5.1.26100.9444, marked fixtures, inventory/dependency synthetic. Có exact boundary/protected data, stale/unknown, portable possible reference, absent/empty/junction, cancelled/scope, native scan + analysis và hash dữ liệu trước/sau. `Check-DiskUI.ps1`: 30 assertions/25 controls; worker AppData thật trên fixture, mode switching/shared lock/no selection/no deletion và offscreen render. Evidence: `docs/verification/disk-app-profile-tests.json`, `disk-ui-tests.json`.

Lệnh tái lập tự cd đúng project: `powershell -NoProfile -File "E:\SourceCode\NEW_APPLICATION\MemoryClear\scripts\Verify-Phase10.ps1"`.

CD-02/03 vẫn review: đã lưu provenance/phiên bản quan sát; còn cần bằng chứng gỡ độc lập và kiểm chứng ngữ nghĩa cache theo version; kiểm tra native coverage/cancellation trên máy/VM; UI frozen manifest/two-step/restore và production safety trước khi mở xóa. Không có live inventory/Windows10/11 VM proof hay CI mới trong lượt này.
