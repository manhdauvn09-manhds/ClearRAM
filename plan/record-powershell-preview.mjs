import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const dir=path.dirname(fileURLToPath(import.meta.url)),root=path.dirname(dir),file=path.join(dir,'tasks.json');
const plan=JSON.parse(fs.readFileSync(file,'utf8'));
const results=JSON.parse(fs.readFileSync(path.join(root,'artifacts/tests/results.json'),'utf8').replace(/^\uFEFF/,''));
if(results.Failed!==0)throw Error('Cannot record a passing preview while tests failed.');
if(plan.revision!=='2026-10-08.1'){plan.previousRevision=plan.revision;plan.previousTaskIds=plan.tasks.map(t=>t.id);plan.revision='2026-10-08.1';}
plan.updated='2026-10-08';
plan.assumption='Đã chốt theo trả lời người dùng ngày 2026-10-08: PowerShell có GUI trước; Windows 10/11 x64, Windows PowerShell 5.1 + WPF, portable folder + CLI. Mặc định kỹ thuật: thủ công, force kill xác nhận riêng, auto kill tắt; danh sách app cá nhân chưa được cung cấp. C#/Avalonia và Linux để sau.';
function update(id,values){Object.assign(plan.tasks.find(t=>t.id===id),values,{updated:plan.updated,owner:'Codex'});}
update('DEC-01',{status:'done',evidence:'Người dùng trả lời: “Làm script PowerShell có GUI trước”. README.md; docs/ARCHITECTURE.md; Windows PowerShell 5.1.26100.8875 + WPF smoke đạt.',notes:'Chọn PowerShell/WPF portable GUI + CLI. Windows 10/11 x64 là mục tiêu kiểm thử, mới xác minh trên Win11 build 26200.'});
update('DEC-02',{status:'done',evidence:'docs/ARCHITECTURE.md; Get-MCSettings defaults; policy tests đạt.',notes:'Người triển khai chọn defaults an toàn để tiếp tục yêu cầu: thủ công, close trước, force xác nhận, auto tắt; protected/allowlist cá nhân trống. Không tuyên bố người dùng đã chọn app hoặc quyền tự động.'});
update('DEC-03',{status:'done',evidence:'docs/ARCHITECTURE.md; artifacts/monitor-baseline.json có máy tham chiếu và số đo.',notes:'Ngân sách ban đầu: GUI ≤2% CPU toàn máy, ≤250 MB working set; thu nhỏ 10s/mẫu. Mục tiêu nghiệm thu, chưa claim GUI đã đạt. Ma trận Win10/11/DPI/VM còn phải chạy.'});
update('HO-01',{status:'done',evidence:'docs/handoffs/PHASE-01-HANDOFF.md',notes:'Handoff ghi rõ lựa chọn người dùng, defaults và giới hạn.'});
update('BASE-01',{status:'done',title:'Khởi tạo cấu trúc PowerShell/WPF và kiểm tra nguồn',acceptance:'Tách module core, adapter Win32, XAML/GUI, CLI và tests; không dependency tải ngoài; có lệnh kiểm tra local và CI workflow.',evidence:'app/, MemoryClear.ps1, MemoryClear.Cli.ps1, tests/, .github/workflows/verify.yml. 17/17 tests local.',notes:'CI workflow đã viết nhưng chưa chạy trên GitHub. Không cần .NET SDK.'});
update('BASE-02',{status:'done',acceptance:'Có Identity PID/start time/path/SID/session/critical, Snapshot/Row và ActionResult; unknown/thiếu quyền được biểu diễn rõ; capability Win32 giới hạn theo thao tác.',evidence:'docs/ARCHITECTURE.md; app/Native.cs; app/MemoryClear.Core.psm1; snapshot/policy/stale identity tests.',notes:'Contract PSObject + native handle; CPU null ở mẫu đầu, RAM working set và private riêng.'});
update('BASE-03',{status:'done',evidence:'Get/Save-MCSettings, Write-MCEvent; test round-trip, safe fallback và audit 205→200 event đạt.',notes:'Schema 1; không auto kill; settings/log cục bộ. Đồng thời nhiều GUI/CLI writer chưa nghiệm thu.'});
update('HO-02',{status:'done',evidence:'docs/handoffs/PHASE-02-HANDOFF.md; artifacts/tests/results.json 17/17.',notes:'Foundation script đã có; các phase nghiệm thu action vẫn chưa hoàn tất.'});
for(const id of ['MON-01','MON-02','MON-03'])update(id,{status:'done',evidence:'app/MemoryClear.Core.psm1, app/Native.cs; snapshot/policy tests, artifacts/monitor-baseline.json.',notes:id==='MON-03'?'Fallback danh sách process; chưa gộp app/tab. CPU delta chuẩn hóa, một snapshot trước nên history hữu hạn.':'Số đo native và dữ liệu process thật; unknown/permission errors không làm hỏng vòng quét.'});
update('UI-01',{status:'review',evidence:'app/MainWindow.xaml; MemoryClear.ps1; WPF smoke 19 control; artifacts/gui-preview.png.',notes:'GUI đã render offscreen. Còn kiểm tra tương tác thật, DPI, keyboard và selection/sort trong refresh.'});
update('QA-01',{status:'review',evidence:'artifacts/monitor-baseline.json: 4 mẫu, total/available RAM đối chiếu CIM; collector 1.23% CPU, 97.6 MB working set.',notes:'Chưa phải overhead toàn GUI/soak, tải/thu nhỏ hoặc Windows 10; phase chưa đủ nghiệm thu.'});
update('HO-03',{status:'review',evidence:'docs/handoffs/PHASE-03-HANDOFF.md (nháp)',notes:'Chờ UI-01/QA-01; không đánh dấu phase 03 hoàn tất.'});
for(const id of ['SAFE-01','SAFE-02','SAFE-03','SAFE-04','ACT-01','ACT-02','ACT-03','ACT-04','EMG-01','EMG-02','EMG-03']){
 const t=plan.tasks.find(t=>t.id===id);t.notes+=' Source preview đã có trong module/GUI/CLI, chưa coi là nghiệm thu phase; tiếp tục theo gate khi HO-03 hoàn tất.';
}
update('ACT-03',{title:'Giới hạn quyền người dùng và đánh giá nhu cầu helper',acceptance:'GUI chạy user thường; target thiếu quyền bị chặn, không bypass OS protection. Nếu scope sau cần helper: xác thực caller/target và policy, helper thoát khi xong.',notes:'Bản PowerShell không có helper/admin; thiếu quyền trả Denied. Nghiệm thu quyền trên môi trường user thường vẫn còn.'});
fs.writeFileSync(file,JSON.stringify(plan,null,2)+'\n');
let html=fs.readFileSync(path.join(root,'MemoryClear-Plan.html'),'utf8');
html=html.replace('Portable · Desktop + CLI','PowerShell 5.1 · WPF + CLI');
html=html.replace('<article class="card tech recommended"><span class="recommend-ribbon">ĐỀ XUẤT</span><div class="kicker">Phương án B · Dùng lâu dài</div>','<article class="card tech"><div class="kicker">Phương án B · Mở rộng về sau</div>');
html=html.replace('<article class="card tech"><div class="kicker">Phương án A · Thử nghiệm nhanh</div>','<article class="card tech recommended"><span class="recommend-ribbon">ĐÃ CHỐT</span><div class="kicker">Phương án A · Bản đang triển khai</div>');
html=html.replace('Chọn nếu ưu tiên script trước','Người dùng đã chọn ngày 08.10.2026');
html=html.replace('Mặc định đề xuất: Windows trước · C# + Avalonia · portable GUI + CLI · thao tác thủ công · Linux sau. Các lựa chọn bên dưới chỉ giúp soạn bản trả lời, chưa khởi động triển khai.','Đã chốt PowerShell có GUI trước. Đã có bản thử nghiệm Windows/WPF + CLI; thủ công và auto kill tắt. Bạn có thể bổ sung app cần bảo vệ; các lựa chọn dưới đây giúp soạn yêu cầu điều chỉnh.');
html=html.replace('· v0.2</span>','· v0.3</span>');
fs.writeFileSync(path.join(root,'MemoryClear-Plan.html'),html);
console.log('Recorded PowerShell preview; phases 01/02 complete, 03 in review.');
