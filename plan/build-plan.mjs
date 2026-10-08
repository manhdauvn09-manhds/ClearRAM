import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const dir = path.dirname(fileURLToPath(import.meta.url));
const root = path.dirname(dir);
const data = JSON.parse(fs.readFileSync(path.join(dir, 'tasks.json'), 'utf8'));
const labels = {todo:'Chưa bắt đầu',decision:'Chờ chốt',doing:'Đang làm',blocked:'Bị chặn',review:'Chờ kiểm tra',done:'Hoàn tất',later:'Để sau'};
const ids = new Set(data.tasks.map(t => t.id));
if (ids.size !== data.tasks.length) throw Error('Duplicate task IDs');
for (const t of data.tasks) {
  if (!labels[t.status] || t.deps.some(id => !ids.has(id))) throw Error('Invalid task: ' + t.id);
  if (t.status === 'done' && !t.evidence.trim()) throw Error('Missing evidence: ' + t.id);
  if (t.status === 'done' && t.deps.some(id => data.tasks.find(x => x.id === id).status !== 'done')) throw Error('Incomplete dependency: ' + t.id);
  if (t.status === 'blocked' && !t.notes.trim()) throw Error('Missing blocker reason: ' + t.id);
}
const visiting = new Set(), visited = new Set();
function visit(id) { if (visiting.has(id)) throw Error('Dependency cycle: ' + id); if (visited.has(id)) return; visiting.add(id); data.tasks.find(t => t.id === id).deps.forEach(visit); visiting.delete(id); visited.add(id); }
ids.forEach(visit);
for (const phase of new Set(data.tasks.map(t => t.phase))) {
  const number = phase.slice(0,2), handoff = data.tasks.find(t => t.id === 'HO-' + number);
  if (!handoff || data.tasks.some(t => t.phase === phase && t.id !== handoff.id && !handoff.deps.includes(t.id))) throw Error('Missing phase handoff coverage: ' + phase);
  if (handoff.status === 'done' && !fs.existsSync(path.join(root,'docs','handoffs',`PHASE-${number}-HANDOFF.md`))) throw Error('Missing handoff document: ' + phase);
}

const css = `<style id="tracker-css">
.tracker-kpis{display:grid;grid-template-columns:repeat(4,1fr);gap:14px;margin:22px 0}.tracker-kpi{background:white;border:1px solid var(--line);border-radius:15px;padding:19px}.tracker-kpi strong{font-size:29px;letter-spacing:-1px;display:block}.tracker-kpi span{font-size:12px;color:var(--muted)}.tracker-tools{display:flex;flex-wrap:wrap;gap:10px;margin:20px 0;align-items:center}.tracker-tools input,.tracker-tools select{padding:10px 12px;border:1px solid var(--line);border-radius:9px;background:white;color:var(--ink);max-width:100%}.tracker-tools input{flex:1;min-width:180px}.tracker-tools label{font-size:12px}.tracker-phase{margin-top:25px}.tracker-phase h3{font-size:20px;margin-bottom:12px}.tracker-task{background:white;border:1px solid var(--line);border-radius:13px;margin:9px 0;overflow:hidden}.tracker-task summary{cursor:pointer;display:grid;grid-template-columns:78px 1fr 115px;align-items:center;gap:12px;padding:16px 18px;list-style:none}.tracker-task summary::-webkit-details-marker{display:none}.tracker-task summary:after{content:none}.task-id{font-size:11px;font-weight:700;color:var(--green)}.task-title{font-size:14px;font-weight:650}.task-meta{display:block;font-size:11px;color:var(--muted);font-weight:400;margin-top:5px}.task-status{font-size:11px;padding:5px 9px;border-radius:7px;text-align:center;background:#eef1ed;color:#586b61}.task-status.done{background:#dff0d5;color:#2e662e}.task-status.decision,.task-status.blocked{background:#fbecd2;color:#866021}.task-status.doing{background:#e0ecfa;color:#365c87}.task-status.review{background:#eee5f7;color:#745597}.task-status.later{background:#f1f1f1;color:#747474}.task-details{padding:0 20px 20px;border-top:1px solid var(--line)}.task-details p{font-size:13px;margin-top:12px}.task-editor{display:grid;grid-template-columns:1fr 1fr;gap:13px;margin-top:16px}.task-editor label{font-size:11px;font-weight:600;color:var(--muted);display:block}.task-editor input,.task-editor textarea,.task-editor select{width:100%;margin-top:5px;border:1px solid var(--line);border-radius:7px;padding:9px;background:#fafbf8;color:var(--ink)}.task-editor textarea{min-height:72px;resize:vertical}.task-editor .wide{grid-column:1/-1}.tracker-message{font-size:12px;color:var(--green);min-height:22px}.tracker-legend{display:flex;gap:8px;flex-wrap:wrap;margin-top:16px}.tracker-guide{font-size:13px;color:var(--muted)}.tracker-guide ol{padding-left:20px}.tracker-log{max-height:230px;overflow:auto;padding:0 20px}.tracker-log li{font-size:12px;border-bottom:1px solid var(--line);padding:9px 0}.tracker-empty{padding:20px;color:var(--muted)}.tracker-note{font-size:12px;color:var(--muted);margin-top:10px}.task-print-state{display:none}.tracker-progress{height:6px;background:#e4ebdf;border-radius:5px;margin-top:10px;overflow:hidden}.tracker-progress>span{height:100%;display:block;background:var(--green)}
@media(max-width:650px){.tracker-kpis{grid-template-columns:1fr 1fr}.tracker-task summary{grid-template-columns:65px 1fr;gap:8px}.task-status{grid-column:2;justify-self:start}.task-editor{grid-template-columns:1fr}.task-editor .wide{grid-column:auto}.tracker-tools{align-items:stretch}.tracker-tools select{width:100%}}
@media print{.tracker-tools,.tracker-message,.task-editor,.tracker-export{display:none}.tracker-kpis{gap:8px}.tracker-kpi{padding:12px}.tracker-task{break-inside:avoid}.tracker-task summary{padding:12px}.task-print-state{display:block;white-space:pre-wrap;font-size:10px;overflow-wrap:anywhere}.tracker-task .task-details{display:block}.tracker-kpi strong{font-size:22px}.tracker-log{max-height:none}.tracker-phase{margin-top:17px}.tracker-task summary .task-meta{font-size:10px}}
</style>`;
const section = `<section id="execution-plan"><div class="section-head"><div><div class="eyebrow">06B — Kế hoạch thực thi · ${data.revision}</div><h2>Từ đề xuất đến bản chạy được.</h2></div><p>Trạng thái tài liệu và triển khai được theo dõi riêng. Mở từng đầu việc để xem tiêu chí, phụ thuộc và cập nhật tiến độ.</p></div>
<div class="note"><strong>Phạm vi đang dùng để lập kế hoạch:</strong> ${data.assumption} Ước lượng là ngày công tham khảo cho một người, gồm thực hiện và kiểm tra cục bộ; không phải lịch hẹn. Không cộng phần mở rộng hoặc thời gian chờ quyết định vào cam kết MVP.</div>
<div id="tracker-kpis" class="tracker-kpis"></div>
${data.revision === '2026-10-08.1' ? '<div class="note"><strong>Bản thử nghiệm đã có:</strong> Chạy <code>Start-MemoryClear.cmd</code> trong thư mục dự án. <a href="README.md">Hướng dẫn dùng</a> · <a href="artifacts/MemoryClear-PowerShell-preview.zip">Gói portable ZIP</a>. Có theo dõi RAM/CPU, bảo vệ, đóng/force kill thủ công và đóng khẩn cấp theo allowlist. Phase 03 còn chờ nghiệm thu UI/overhead; Windows 10, dữ liệu chưa lưu và VM pressure chưa được xác minh.</div>' : ''}
<div class="note"><strong>Bắt buộc bàn giao cuối mỗi phase:</strong> Tạo <code>docs/handoffs/PHASE-XX-HANDOFF.md</code>, ghi kết quả, bằng chứng kiểm tra, tồn tại và bước tiếp theo; cập nhật task <strong>HO-XX</strong> và gửi link cho người dùng. Phase chỉ hoàn tất sau handoff; phase tiếp theo phụ thuộc handoff này. Nếu dừng giữa chừng, viết bản nháp và giữ trạng thái chưa hoàn tất. <a href="docs/handoffs/TEMPLATE.md">Mẫu handoff</a> · <a href="docs/handoffs/PHASE-00-HANDOFF.md">Handoff phase 00</a>.</div>
<div class="tracker-legend">${Object.entries(labels).map(([k,v])=>`<span class="task-status ${k}">${v}</span>`).join('')}</div>
<div class="tracker-tools"><input id="task-search" type="search" aria-label="Tìm đầu việc" placeholder="Tìm mã, tên, tiêu chí hoặc ghi chú..."><select id="task-status-filter" aria-label="Lọc trạng thái"><option value="all">Mọi trạng thái</option>${Object.entries(labels).map(([k,v])=>`<option value="${k}">${v}</option>`).join('')}</select><select id="task-scope-filter" aria-label="Lọc phạm vi"><option value="all">Toàn bộ kế hoạch</option><option value="mvp">MVP Windows</option><option value="docs">Tài liệu</option><option value="later">Mở rộng sau MVP</option></select><label><input id="task-ready" type="checkbox" style="min-width:0"> Chỉ việc sẵn sàng</label></div>
<div id="tracker-message" class="tracker-message" role="status" aria-live="polite"></div><div id="tracker-list"></div><noscript><p>Bật JavaScript để chỉnh trạng thái; có thể đọc đầy đủ bản tĩnh tại <a href="IMPLEMENTATION_PLAN.md">IMPLEMENTATION_PLAN.md</a>.</p></noscript>
<div class="tracker-tools tracker-export"><button id="task-export" type="button" class="btn primary">Xuất tiến độ JSON ↓</button><button id="task-import" type="button" class="btn">Nhập tiến độ JSON ↑</button><input id="task-file" type="file" accept="application/json,.json" hidden><span id="tracker-storage" class="tracker-note"></span></div>
<div class="two-col"><div class="card tracker-guide"><h3>Quy ước cập nhật</h3><ol><li>Chuyển sang <strong>Đang làm</strong> khi thực sự triển khai; ghi người phụ trách.</li><li><strong>Chờ kiểm tra</strong> khi đã làm xong phần code/tài liệu nhưng chưa đủ bằng chứng nghiệm thu.</li><li><strong>Hoàn tất</strong> cần ghi bằng chứng: file, commit, lệnh kiểm tra hoặc biên bản; phụ thuộc phải xong trước.</li><li><strong>Bị chặn</strong> phải nêu nguyên nhân và điều cần giải quyết trong ghi chú. Chưa đến lượt không đồng nghĩa bị chặn.</li></ol></div><div class="card tracker-guide"><h3>Cách lưu để dùng về sau</h3><p>Thay đổi được lưu tạm trong trình duyệt nếu localStorage khả dụng. File <code>file://</code>, đổi trình duyệt/đường dẫn hoặc xóa dữ liệu có thể làm mất bản lưu này.</p><p><strong>Cuối mỗi buổi: xuất JSON.</strong> HTML không tự ghi đè file nguồn trên ổ đĩa. Khi tiếp tục qua chat, gửi JSON mới nhất để cập nhật <code>plan/tasks.json</code> và dựng lại tài liệu.</p><p>Tiến độ là số task hoàn tất, không phải phần trăm thời gian. Bảng này chưa chứng minh ứng dụng đã được triển khai.</p></div></div>
<details style="margin-top:20px"><summary>Nhật ký cập nhật trạng thái / ghi chú</summary><ul id="tracker-log" class="tracker-log"></ul></details></section>`;

function trackerApp() {
  'use strict';
  const base = JSON.parse(document.getElementById('plan-data').textContent);
  const labels = {todo:'Chưa bắt đầu',decision:'Chờ chốt',doing:'Đang làm',blocked:'Bị chặn',review:'Chờ kiểm tra',done:'Hoàn tất',later:'Để sau'};
  const fields = ['status','owner','evidence','notes','updated'];
  const key = 'memoryclear-plan-' + base.revision;
  const $ = id => document.getElementById(id);
  const esc = s => String(s).replace(/[&<>"']/g, c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const today = () => new Intl.DateTimeFormat('sv-SE',{timeZone:'Asia/Tokyo',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
  let tasks = structuredClone(base.tasks), history = [], storageOK = true;
  function validate(payload) {
    if (payload && payload.project === base.project && payload.schemaVersion === 1 && payload.revision === base.previousRevision) {
      const oldIds = base.previousTaskIds;
      if (!Array.isArray(payload.tasks) || payload.tasks.length !== oldIds.length || oldIds.some(id => payload.tasks.filter(t => t && t.id === id).length !== 1)) throw Error('Bản tiến độ cũ thiếu hoặc trùng task.');
      const merged = base.tasks.map(t => {const incoming=payload.tasks.find(x=>x.id===t.id);return incoming && incoming.updated >= t.updated ? incoming : t;}).map(t => ({...t}));
      // New mandatory gates may invalidate a previously completed phase: retain evidence for review.
      let changed = true;
      while (changed) { changed = false; for (const t of merged) { const original = base.tasks.find(x => x.id === t.id); if (t.status === 'done' && original.deps.some(id => merged.find(x => x.id === id).status !== 'done')) { t.status = 'review'; t.notes = (typeof t.notes === 'string' ? t.notes : '') + '\nCần kiểm tra lại sau khi bổ sung handoff bắt buộc; bằng chứng cũ được giữ.'; changed = true; } } }
      payload = {...payload, revision:base.revision, tasks:merged};
    }
    if (!payload || payload.schemaVersion !== 1 || payload.project !== base.project || payload.revision !== base.revision || !Array.isArray(payload.tasks) || payload.tasks.length !== base.tasks.length) throw Error('Không đúng project, phiên bản kế hoạch hoặc số lượng task.');
    const seen = new Set();
    const next = base.tasks.map(t => {
      const candidates = payload.tasks.filter(x=>x && x.id === t.id);
      if (candidates.length !== 1) throw Error('Thiếu/trùng task ' + t.id);
      const incoming = candidates[0]; seen.add(incoming.id);
      for (const field of fields) if(typeof incoming[field] !== 'string' || incoming[field].length > 6000) throw Error('Trường không hợp lệ: ' + t.id + '/' + field);
      if (!Object.hasOwn(labels,incoming.status) || !/^\d{4}-\d{2}-\d{2}$/.test(incoming.updated)) throw Error('Trạng thái/ngày không hợp lệ: ' + t.id);
      if (incoming.status === 'done' && !incoming.evidence.trim()) throw Error('Hoàn tất cần bằng chứng: ' + t.id);
      if (incoming.status === 'blocked' && !incoming.notes.trim()) throw Error('Bị chặn cần ghi lý do: ' + t.id);
      return {...t, ...Object.fromEntries(fields.map(f=>[f,incoming[f]]))};
    });
    for (const t of next) if(t.status==='done' && t.deps.some(id=>next.find(x=>x.id===id).status!=='done')) throw Error('Task hoàn tất nhưng phụ thuộc chưa xong: '+t.id);
    const log = Array.isArray(payload.history) ? payload.history : [];
    if (log.length > 1000 || log.some(x=>!x || typeof x.at!=='string' || typeof x.task!=='string' || typeof x.message!=='string' || x.message.length>13000 || x.at.length>100 || x.task.length>100)) throw Error('Nhật ký không hợp lệ.');
    return {tasks:next, history:log};
  }
  function payload(){return {...base,updated:today(),tasks,history};}
  function save(){try{localStorage.setItem(key,JSON.stringify(payload()));storageOK=true;}catch{storageOK=false;} $('tracker-storage').textContent=storageOK?'Đã lưu tạm trong trình duyệt · Xuất JSON để giữ bản chính.':'Không lưu được trong trình duyệt · Hãy xuất JSON trước khi đóng.';}
  try { const stored=localStorage.getItem(key) || (base.previousRevision ? localStorage.getItem('memoryclear-plan-'+base.previousRevision) : null); if(stored){const restored=validate(JSON.parse(stored));tasks=restored.tasks;history=restored.history;} } catch {storageOK=false; $('tracker-message').textContent='Không đọc được bản lưu trình duyệt; đang dùng trạng thái trong HTML. Có thể nhập bản JSON đã xuất.';}
  const pending = t => t.deps.filter(id=>tasks.find(x=>x.id===id).status!=='done');
  const ready = t => t.scope!=='later' && t.status==='todo' && pending(t).length===0;
  function stats(){
    const group = scope => {const items=tasks.filter(t=>t.scope===scope);return [items.filter(t=>t.status==='done').length,items.length];};
    const docs=group('docs'), mvp=group('mvp');
    $('tracker-kpis').innerHTML=[['Tài liệu hoàn tất',docs.join(' / '),100*docs[0]/docs[1]],['Task MVP hoàn tất',mvp.join(' / '),100*mvp[0]/mvp[1]],['Chờ chốt / bị chặn',tasks.filter(t=>['decision','blocked'].includes(t.status)).length,null],['Task sẵn sàng',tasks.filter(ready).length,null]].map(([label,value,pct])=>`<div class="tracker-kpi"><span>${label}</span><strong>${value}</strong>${pct===null?'':`<div class="tracker-progress"><span style="width:${pct}%"></span></div>`}</div>`).join('');
  }
  function logView(){const list=$('tracker-log');list.replaceChildren();const entries=history.slice().reverse();if(!entries.length)entries.push({at:'',task:'',message:'Chưa có cập nhật trong phiên bản kế hoạch này.'});for(const entry of entries){const li=document.createElement('li');li.textContent=[entry.at,entry.task,entry.message].filter(Boolean).join(' · ');list.append(li);}}
  function render(){
    stats();logView();const search=$('task-search').value.toLocaleLowerCase('vi'),status=$('task-status-filter').value,scope=$('task-scope-filter').value;
    const filtered=tasks.filter(t=>(status==='all'||t.status===status)&&(scope==='all'||t.scope===scope)&&(!$('task-ready').checked||ready(t))&&[t.id,t.title,t.acceptance,t.notes,t.owner,t.evidence].join(' ').toLocaleLowerCase('vi').includes(search));
    const phases=[...new Set(filtered.map(t=>t.phase))];
    $('tracker-list').innerHTML=phases.map(phase=>`<div class="tracker-phase"><h3>${esc(phase)} <span class="pill">${tasks.find(t=>t.id==='HO-'+phase.slice(0,2))?.status==='done'?'Đã bàn giao':'Chưa kết thúc phase'}</span></h3>${filtered.filter(t=>t.phase===phase).map(t=>{
      const waiting=pending(t);const suffix=waiting.length?'Chờ phụ thuộc: '+waiting.join(', '):ready(t)?'Sẵn sàng khi được giao triển khai':'Phụ thuộc đã đủ / không có';
      return `<details class="tracker-task" data-task="${t.id}"><summary><span class="task-id">${t.id} ▾</span><span class="task-title">${esc(t.title)}<span class="task-meta">${t.priority} · ${esc(t.owner)} · ${esc(t.estimate)} · ${esc(suffix)}</span></span><span class="task-status ${t.status}">${labels[t.status]}</span></summary><div class="task-details"><p><strong>Tiêu chí hoàn thành:</strong> ${esc(t.acceptance)}</p><p><strong>Phụ thuộc:</strong> ${esc(t.deps.join(', ')||'Không có')} · <strong>Cập nhật:</strong> ${esc(t.updated)} (ngày Nhật Bản)</p><div class="task-editor"><label>Trạng thái<select aria-label="Trạng thái ${t.id}" data-field="status">${Object.entries(labels).map(([k,v])=>`<option value="${k}" ${k===t.status?'selected':''}>${v}</option>`).join('')}</select></label><label>Phụ trách<input aria-label="Phụ trách ${t.id}" data-field="owner" maxlength="300" value="${esc(t.owner)}"></label><label class="wide">Bằng chứng nghiệm thu<textarea aria-label="Bằng chứng ${t.id}" data-field="evidence" maxlength="6000">${esc(t.evidence)}</textarea></label><label class="wide">Ghi chú / nguyên nhân bị chặn / bước tiếp theo<textarea aria-label="Ghi chú ${t.id}" data-field="notes" maxlength="6000">${esc(t.notes)}</textarea></label></div><p class="task-print-state">Trạng thái: ${labels[t.status]}\nPhụ trách: ${esc(t.owner)}\nBằng chứng: ${esc(t.evidence||'Chưa có')}\nGhi chú: ${esc(t.notes||'—')}</p></div></details>`;
    }).join('')}</div>`).join('')||'<p class="tracker-empty">Không có đầu việc khớp bộ lọc.</p>';
  }
  function message(text){$('tracker-message').textContent=text;}
  $('tracker-list').addEventListener('change',event=>{
    const input=event.target,field=input.dataset.field;if(!fields.includes(field)||field==='updated')return;
    const id=input.closest('[data-task]').dataset.task,t=tasks.find(x=>x.id===id),old=t[field],value=input.value.trim();if(value===old)return;
    const candidate={...t,[field]:value};
    if (candidate.status==='doing' && pending(candidate).some(id=>id.startsWith('HO-'))) { input.value=old;message(id+': cần hoàn tất handoff phase trước khi bắt đầu.');return; }
    if(candidate.status==='done'&&(!candidate.evidence.trim()||pending(candidate).length)){input.value=old;message(id+': cần bằng chứng và hoàn tất các phụ thuộc trước khi đánh dấu xong.');return;}
    if(candidate.status==='blocked'&&!candidate.notes.trim()){input.value=old;message(id+': hãy ghi nguyên nhân bị chặn trước.');return;}
    if(field==='status'&&old==='done'&&value!=='done'&&tasks.some(x=>x.status==='done'&&x.deps.includes(id))){input.value=old;message('Hãy mở lại các task phụ thuộc đã hoàn tất trước khi mở lại '+id+'.');return;}
    const opened=[...document.querySelectorAll('.tracker-task[open]')].map(el=>el.dataset.task);
    t[field]=value;t.updated=today();history.push({at:new Date().toISOString(),task:id,message:field+': '+old+' → '+value});history=history.slice(-1000);save();render();for(const openedId of opened){const el=document.querySelector(`[data-task="${openedId}"]`);if(el)el.open=true;}message('Đã cập nhật '+id+'. '+(storageOK?'Đã lưu tạm; xuất JSON cuối buổi.':'Cần xuất JSON để giữ tiến độ.'));
  });
  for(const id of ['task-search','task-status-filter','task-scope-filter','task-ready'])$(id).addEventListener('input',render);
  $('task-export').addEventListener('click',()=>{const blob=new Blob([JSON.stringify(payload(),null,2)+'\n'],{type:'application/json;charset=utf-8'}),url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download='MemoryClear-Progress-'+today()+'.json';document.body.append(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),1000);message('Đã yêu cầu tải tiến độ JSON; giữ file để nhập lại hoặc gửi vào chat.');});
  $('task-import').addEventListener('click',()=>$('task-file').click());
  $('task-file').addEventListener('change',async event=>{const file=event.target.files[0];if(!file)return;try{if(file.size>2000000)throw Error('File vượt giới hạn 2 MB.');const incoming=validate(JSON.parse((await file.text()).replace(/^\uFEFF/,'')));if(!window.confirm('Thay toàn bộ trạng thái và ghi chú hiện tại bằng file này? Nếu cần giữ bản hiện tại, chọn Hủy rồi xuất JSON trước.'))return;tasks=incoming.tasks;history=incoming.history;history.push({at:new Date().toISOString(),task:'PLAN',message:'Nhập tiến độ JSON.'});history=history.slice(-1000);save();render();message('Đã nhập tiến độ. Nội dung task và tiêu chí giữ theo phiên bản kế hoạch này.');}catch(error){message('Không nhập được: '+error.message+' Dữ liệu hiện tại được giữ nguyên.');}finally{event.target.value='';}});
  let printState=[];window.addEventListener('beforeprint',()=>{printState=[...document.querySelectorAll('.tracker-task')].map(el=>[el,el.open]);for(const [el]of printState)el.open=true;});window.addEventListener('afterprint',()=>{for(const [el,open]of printState)el.open=open;});
  render();$('tracker-storage').textContent=storageOK?'Tiến độ có thể lưu tạm trong trình duyệt; xuất JSON cuối mỗi buổi.':'Không đọc được lưu trữ trình duyệt; dùng xuất/nhập JSON.';
}

let html = fs.readFileSync(path.join(root,'MemoryClear-Plan.html'),'utf8');
html = html.replace(/<!-- TRACKER START -->[\s\S]*?<!-- TRACKER END -->\s*/g,'');
const embedded = JSON.stringify(data).replace(/</g,'\\u003c');
const block = `<!-- TRACKER START -->\n${css}\n${section}\n<script id="plan-data" type="application/json">${embedded}</script>\n<script>(${trackerApp.toString()})();</script>\n<!-- TRACKER END -->\n`;
html = html.replace('<section id="decision"',block+'\n<section id="decision"');
html = html.replace('<a href="#roadmap">Lộ trình</a>','<a href="#roadmap">Lộ trình</a><a href="#execution-plan">Tiến độ</a>');
// Keep the builder idempotent when rebuilding the page.
html = html.replace(/(<a href="#execution-plan">Tiến độ<\/a>){2,}/g,'<a href="#execution-plan">Tiến độ</a>');
html = html.replace('· v0.1</span>','· v0.2</span>');
html = html.replace('Bản đề xuất: v0.1 / 07.10.2026','Bản đề xuất: v0.2 / 07.10.2026');
fs.writeFileSync(path.join(root,'MemoryClear-Plan.html'),html);
let md=`# MemoryClear — Kế hoạch triển khai\n\nPhiên bản: ${data.revision}. Cập nhật: ${data.updated} (Asia/Tokyo).\n\n${data.assumption}\n\n## Trạng thái tổng quan\n\n`;
md += `**Quy định bắt buộc:** ${data.handoffPolicy}\n\nMẫu: [TEMPLATE.md](docs/handoffs/TEMPLATE.md). Bàn giao hiện có: [Phase 00](docs/handoffs/PHASE-00-HANDOFF.md). Quy trình tiếp tục: [AGENTS.md](AGENTS.md). Các phase chưa hoàn thành chỉ có task handoff; không tạo báo cáo giả cho công việc chưa làm.\n\n`;
for(const [scope,name]of [['docs','Tài liệu'],['mvp','MVP Windows'],['later','Mở rộng']]){const items=data.tasks.filter(t=>t.scope===scope);md+=`- ${name}: ${items.filter(t=>t.status==='done').length}/${items.length} task hoàn tất.\n`;}
md+=`\nTiến độ tính theo số task, không phải theo thời gian. Ngày công là khoảng tham khảo cho một người; chưa có lịch phát hành cam kết.\n\n## Cập nhật sau mỗi buổi làm\n\n1. Đọc file này và \`plan/tasks.json\` trước khi triển khai. Chỉ thực hiện trong phạm vi người dùng đã chốt.\n2. Khi bắt đầu: đặt status=doing và ghi owner. Khi xong code nhưng chưa kiểm tra: review.\n3. Chỉ đặt done khi đạt tiêu chí và có evidence (đường dẫn, commit, lệnh/biên bản nghiệm thu). Task phụ thuộc phải hoàn tất.\n4. blocked cần ghi nguyên nhân và bước gỡ chặn; decision là đang chờ lựa chọn của người dùng. Không coi chưa đến lượt là blocked.\n5. Cập nhật updated theo ngày Asia/Tokyo, evidence và notes. Chưa biết kết quả thì không ghi đã đạt.\n6. Chạy \`node plan/build-plan.mjs\` để dựng lại HTML và Markdown. Không chỉnh tay trạng thái trong HTML.\n7. Nếu đã sửa trên trình duyệt: xuất JSON và đối chiếu/nhập vào tasks.json trước khi dựng lại; HTML không tự sửa file trên ổ đĩa. Bản localStorage của cùng revision có thể ghi đè trạng thái hiển thị, vì vậy nhập JSON mới nhất hoặc đổi revision khi cập nhật nguồn.\n\n## Các cổng nghiệm thu\n\n- G0: DEC-01…03 — chốt nền tảng, bảo vệ, chỉ tiêu đo.\n- G1: QA-01 — số liệu đúng và overhead đạt ngân sách.\n- G2: SAFE-04 + QA-02 — policy và thao tác thủ công đã kiểm chứng bằng VM.\n- G3: QA-03 — khẩn cấp, hủy và điều kiện dừng đạt tiêu chí.\n- G4: REL-02 + REL-03 — ma trận tương thích, tài liệu và người dùng nghiệm thu.\n\n## Rủi ro cần theo dõi\n\n| Rủi ro | Biện pháp / task chịu trách nhiệm |\n|---|---|\n| Kill nhầm hệ thống hoặc PID tái sử dụng | SAFE-01, SAFE-03, SAFE-04; fail closed khi không đủ thông tin |\n| Mất dữ liệu chưa lưu | ACT-01, ACT-02; không tự force sau timeout |\n| RAM giảm trên biểu đồ nhưng app chậm hơn | QA-01, QA-03; theo dõi available RAM và phản hồi, không purge cache |\n| Công cụ tự tốn tài nguyên | DEC-03, QA-01, REL-02; lấy mẫu thích ứng và benchmark |\n| Quyền nâng cao bị lạm dụng | ACT-03; helper tối thiểu, kiểm tra caller/policy |\n| Linux/Windows build khác nhau | DEC-01, REL-02, EXT-01/02; capability và ma trận kiểm thử |\n\n## Danh sách công việc\n`;
for(const phase of new Set(data.tasks.map(t=>t.phase))){md+=`\n### ${phase}\n\n`;for(const t of data.tasks.filter(t=>t.phase===phase)){md+=`#### ${t.id} — ${t.title}\n\n- **Trạng thái:** ${labels[t.status]} · **Ưu tiên:** ${t.priority}\n- **Phụ trách:** ${t.owner} · **Ước lượng:** ${t.estimate}\n- **Phụ thuộc:** ${t.deps.join(', ')||'Không có'}\n- **Tiêu chí hoàn thành:** ${t.acceptance}\n- **Bằng chứng:** ${t.evidence||'Chưa có'}\n- **Ghi chú / bước tiếp theo:** ${t.notes||'—'}\n- **Cập nhật:** ${t.updated}\n\n`;}}
fs.writeFileSync(path.join(root,'IMPLEMENTATION_PLAN.md'),md.trimEnd()+'\n');
console.log(JSON.stringify({tasks:data.tasks.length,done:data.tasks.filter(t=>t.status==='done').length,outputs:['MemoryClear-Plan.html','IMPLEMENTATION_PLAN.md'],dependencyValidation:'passed'}));
