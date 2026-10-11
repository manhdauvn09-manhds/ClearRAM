import vm from 'node:vm';
// Development DOM fixture only. No browser/native UI, rendering or filesystem operations.
export function uiHarness(html,{bothTabs=false}={}){
 const elements=new Map(),timers=new Map();let nextTimer=0;
 function el(id){if(!elements.has(id)){const classes=new Set();elements.set(id,{id,value:'',checked:false,disabled:false,textContent:'',innerHTML:'',dataset:{},handlers:{},classList:{toggle(k,on){if(on===undefined)on=!classes.has(k);if(on)classes.add(k);else classes.delete(k);},add(k){classes.add(k);},remove(k){classes.delete(k);},contains:k=>classes.has(k)},addEventListener(k,f){this.handlers[k]=f;},removeAttribute(k){delete this[k];},showModal(){this.open=true;},close(){this.open=false;},click(){this.clicked=true;}});}return elements.get(id);}
 for(const m of html.matchAll(/\bid="([^"]+)"/g))el(m[1]);
 for(const id of ['cleanup-design','memory-design'])el(id).textContent=html.match(new RegExp('<script id="'+id+'" type="application/json">([\\s\\S]*?)</script>'))[1];
 el('backup').value='same';el('browser-running').checked=true;el('filter-kind').value='all';el('min-size').value='512';
 const document={getElementById:el,createElement:()=>el('download')};
 const ctx=vm.createContext({document,location:{hash:''},console,Date,Blob,URL:{createObjectURL:()=> 'blob:fixture',revokeObjectURL(){}},setInterval(fn){const id=++nextTimer;timers.set(id,fn);return id;},clearInterval(id){timers.delete(id);},setTimeout(fn){fn();}});
 for(const m of html.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/g)){if(m[1].includes('function createCleanupModel')||(bothTabs&&m[1].includes('function createMemoryModel')))vm.runInContext(m[1],ctx);}
 const event=(id,type='click',target)=>{const e=el(id);if(type==='click'&&e.disabled)throw Error('UI disabled '+id);if(!e.handlers[type])throw Error('No handler '+id+'/'+type);e.handlers[type]({target:target||e});};
 const tick=(n=1)=>{for(let i=0;i<n;i++)for(const fn of [...timers.values()])fn();};
 return {el,event,tick,timers,ctx};
}
