import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const html=fs.readFileSync(path.join(root,'MemoryClear-Plan.html'),'utf8');
const base=JSON.parse(fs.readFileSync(path.join(root,'plan/tasks.json'),'utf8'));
const embedded=JSON.parse(html.match(/<script id="plan-data" type="application\/json">([\s\S]*?)<\/script>/)[1]);
assert.deepEqual(embedded,base);
const ids=[...html.matchAll(/\bid="([^"]+)"/g)].map(x=>x[1]);
assert.equal(ids.length,new Set(ids).size,'HTML IDs must be unique');
const scripts=[...html.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/g)].map(x=>x[1]);
for(const source of scripts)if(!source.trim().startsWith('{'))new vm.Script(source);
const tracker=scripts.find(s=>s.includes('function trackerApp'));
assert(tracker);
const fixture=structuredClone(base);
for(const task of fixture.tasks){if(task.scope!=='docs'){task.status=task.scope==='later'?'later':'todo';task.evidence='';}}
for(const id of ['DEC-01','DEC-02'])fixture.tasks.find(t=>t.id===id).status='decision';
function harness({stored=null,denyStorage=false}={}){
  const elements=new Map(),memory=new Map(),windowHandlers={};
  let lastBlob=null;
  if(stored)memory.set('memoryclear-plan-'+base.revision,JSON.stringify(stored));
  function element(id){if(!elements.has(id))elements.set(id,{value:'',checked:false,innerHTML:'',textContent:'',handlers:{},dataset:{},files:[],addEventListener(type,fn){this.handlers[type]=fn;},replaceChildren(){this.children=[];},append(child){(this.children??=[]).push(child);},click(){this.clicked=true;},remove(){}});return elements.get(id);}
  for(const id of ids)element(id);
  element('plan-data').textContent=JSON.stringify(fixture);
  element('task-status-filter').value='all';element('task-scope-filter').value='all';
  const document={getElementById:element,querySelectorAll:()=>[],querySelector:()=>null,createElement:()=>element('temp-'+Math.random()),body:{append(){}}};
  const localStorage={getItem(k){if(denyStorage)throw Error('denied');return memory.get(k)||null;},setItem(k,v){if(denyStorage)throw Error('denied');memory.set(k,v);}};
  const context=vm.createContext({document,localStorage,structuredClone,Intl,Date,console,Blob,URL:{createObjectURL(blob){lastBlob=blob;return 'blob:test';},revokeObjectURL(){}},setTimeout(fn){fn();},window:{addEventListener(k,v){windowHandlers[k]=v;},confirm:()=>true}});
  vm.runInContext(tracker,context);
  function change(id,field,value){const input={value,dataset:{field},closest:()=>({dataset:{task:id}})};element('tracker-list').handlers.change({target:input});return input;}
  function state(){return JSON.parse(memory.get('memoryclear-plan-'+base.revision));}
  async function importData(data){const event={target:{files:[{size:1000,text:async()=>JSON.stringify(data)}],value:'file'}};await element('task-file').handlers.change(event);}
  return {element,change,state,importData,blob:()=>lastBlob};
}
const h=harness();
assert(h.element('tracker-list').innerHTML.includes('REL-03'));
assert(h.element('tracker-kpis').innerHTML.includes('0 / '+base.tasks.filter(t=>t.scope==='mvp').length),'MVP must start at zero completed tasks');
assert.equal(base.tasks.filter(t=>t.id.startsWith('HO-')).length,9);
for(const phase of new Set(base.tasks.map(t=>t.phase))){const handoff=base.tasks.find(t=>t.id==='HO-'+phase.slice(0,2));assert(handoff);for(const t of base.tasks.filter(t=>t.phase===phase&&t.id!==handoff.id))assert(handoff.deps.includes(t.id));}
assert.equal(h.change('BASE-01','status','doing').value,'todo','Phase start requires previous handoff');
// Evidence and dependencies are enforced before done.
assert.equal(h.change('BASE-01','status','done').value,'todo');
h.change('BASE-01','evidence','Test evidence');
assert.equal(h.change('BASE-01','status','done').value,'todo');
h.change('BASE-01','notes','<img src=x onerror=alert(1)>');
assert(h.element('tracker-list').innerHTML.includes('&lt;img'));
assert(!h.element('tracker-list').innerHTML.includes('<img src=x'));
h.change('DEC-01','evidence','Decision recorded in test only');
h.change('DEC-01','status','done');
for(const id of ['DEC-02','DEC-03','HO-01']) {h.change(id,'evidence','Fixture evidence for phase gate test');h.change(id,'status','done');}
h.change('BASE-01','status','done');
assert.equal(h.state().tasks.find(t=>t.id==='BASE-01').status,'done');
assert.equal(h.change('DEC-01','status','todo').value,'done','Completed dependency cannot reopen while dependent is done');
h.change('BASE-03','notes','');
assert.equal(h.change('BASE-03','status','blocked').value,'todo');
h.change('BASE-03','notes','Waiting for decision');
h.change('BASE-03','status','blocked');
assert.equal(h.state().tasks.find(t=>t.id==='BASE-03').status,'blocked');
// Filters update without changing the actual task set.
h.element('task-search').value='no-such-task-xyz';h.element('task-search').handlers.input();
assert(h.element('tracker-list').innerHTML.includes('Không có đầu việc'));
h.element('task-search').value='';h.element('task-search').handlers.input();
h.element('task-scope-filter').value='later';h.element('task-scope-filter').handlers.input();
assert(h.element('tracker-list').innerHTML.includes('EXT-01'));
assert(!h.element('tracker-list').innerHTML.includes('DOC-01'));
// Export/import round trip; rejected import is transactional.
h.element('task-export').handlers.click();const exported=JSON.parse(await h.blob().text());
const restored=harness();await restored.importData(exported);
assert.deepEqual(restored.state().tasks,h.state().tasks);
const previous=JSON.stringify(restored.state().tasks);
const invalid=structuredClone(exported);invalid.tasks[0].status='bogus';
await restored.importData(invalid);
assert.equal(JSON.stringify(restored.state().tasks),previous);
assert(restored.element('tracker-message').textContent.includes('Không nhập được'));
const revision=structuredClone(exported);revision.revision='unknown';await restored.importData(revision);
assert.equal(JSON.stringify(restored.state().tasks),previous);
const reload=harness({stored:exported});
assert(reload.element('tracker-list').innerHTML.includes('&lt;img'));
const legacy={...fixture,revision:base.previousRevision,tasks:fixture.tasks.filter(t=>base.previousTaskIds.includes(t.id)).map(t=>({...t}))};
legacy.tasks.find(t=>t.id==='BASE-01').notes='Preserved legacy note';
legacy.tasks.find(t=>t.id==='BASE-01').status='done';
legacy.tasks.find(t=>t.id==='BASE-01').evidence='Legacy evidence';
const migrated=harness();await migrated.importData(legacy);
assert.equal(migrated.state().tasks.find(t=>t.id==='BASE-01').status,'review');
assert(migrated.state().tasks.find(t=>t.id==='BASE-01').notes.includes('Preserved legacy note'));
assert.equal(migrated.state().tasks.filter(t=>t.id.startsWith('HO-')).length,9);
const unavailable=harness({denyStorage:true});unavailable.change('BASE-01','notes','test');
assert(unavailable.element('tracker-storage').textContent.includes('Không lưu được'));
console.log('PASS: source/embedded sync, unique IDs, JS syntax, initial status, done/dependency/block gates, escaping, filters, export/import, invalid import rollback, storage reload/failure. Browser visual rendering not tested by this harness.');
