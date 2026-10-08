import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const dir=path.dirname(fileURLToPath(import.meta.url));
const filename=path.join(dir,'tasks.json');
const plan=JSON.parse(fs.readFileSync(filename,'utf8'));
if(plan.tasks.some(t=>t.id==='HO-00')){console.log('Handoff tasks already present; no changes.');process.exit(0);}
plan.previousRevision=plan.revision;
plan.previousTaskIds=plan.tasks.map(t=>t.id);
plan.revision='2026-10-07.2';
plan.handoffPolicy='Cuối mỗi phase bắt buộc tạo docs/handoffs/PHASE-XX-HANDOFF.md theo TEMPLATE.md, cập nhật evidence của HO-XX và gửi link cho người dùng. Phase chỉ hoàn tất khi task và handoff đã hoàn tất. Nếu dừng giữa chừng, viết bản nháp và giữ trạng thái chưa hoàn tất.';
const phases=[...new Set(plan.tasks.map(t=>t.phase))];
const tasks=[];
for(let i=0;i<phases.length;i++){
  const phase=phases[i],num=String(i).padStart(2,'0'),prev='HO-'+String(i-1).padStart(2,'0');
  const items=plan.tasks.filter(t=>t.phase===phase);
  for(const t of items){if(i>0&&!t.deps.includes(prev))t.deps.push(prev);tasks.push(t);}
  const handoffPath=`docs/handoffs/PHASE-${num}-HANDOFF.md`;
  tasks.push({id:'HO-'+num,phase,scope:items[0].scope,title:`Tạo tài liệu handoff và kết thúc phase ${num}`,priority:'P0',status:i===0?'done':i===8?'later':'todo',deps:items.map(t=>t.id),owner:i===0?'Codex':'Người hoàn tất phase',estimate:i===0?'Đã làm':'0.25–0.5 ngày',acceptance:`Tạo ${handoffPath} theo TEMPLATE.md: kết quả/task IDs, quyết định, file thay đổi, lệnh và kết quả kiểm tra, tồn tại, bước tiếp theo. Cập nhật status/evidence; gửi link bàn giao. Không đóng phase nếu task bắt buộc chưa đạt.`,evidence:i===0?`${handoffPath}; node plan/build-plan.mjs và node plan/check-plan.mjs kiểm tra liên kết, phụ thuộc và logic bảng tiến độ.`:'',notes:i===0?'Bàn giao tài liệu đề xuất; chưa triển khai app. Kiểm tra hiển thị trình duyệt vẫn chưa chạy được vì lỗi sandbox.':'Nếu tạm dừng trước khi xong phase, viết handoff nháp và giữ doing/review. Không cần xin phép riêng để tạo tài liệu handoff.',updated:'2026-10-07'});
}
plan.tasks=tasks;
fs.writeFileSync(filename,JSON.stringify(plan,null,2)+'\n');
console.log(`Added ${phases.length} handoff tasks; total ${tasks.length}.`);
