import fs from 'node:fs';
import assert from 'node:assert/strict';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const read=p=>JSON.parse(fs.readFileSync(path.join(root,p),'utf8').replace(/^\uFEFF/,''));
const validate=(s,v)=>{
 for(const k of Object.keys(s))assert(['$schema','type','additionalProperties','required','properties','const','enum','items','minItems','maxItems','minimum','maximum','minLength'].includes(k),`unsupported ${k}`);
 if(s.type){const type=Array.isArray(v)?'array':v===null?'null':typeof v;assert(s.type==='integer'?Number.isInteger(v):type===s.type,`type ${s.type}`);}
 if('const' in s)assert.deepEqual(v,s.const);if(s.enum)assert(s.enum.includes(v));
 if(s.minimum!==undefined)assert(v>=s.minimum);if(s.maximum!==undefined)assert(v<=s.maximum);if(s.minLength!==undefined)assert(v.length>=s.minLength);
 if(s.type==='object'){for(const k of s.required||[])assert(Object.hasOwn(v,k),`missing ${k}`);for(const k of Object.keys(v)){if(s.additionalProperties===false)assert(Object.hasOwn(s.properties,k),`unknown ${k}`);if(s.properties?.[k])validate(s.properties[k],v[k]);}}
 if(s.type==='array'){if(s.minItems!==undefined)assert(v.length>=s.minItems);if(s.maxItems!==undefined)assert(v.length<=s.maxItems);for(const x of v)validate(s.items,x);}
};
const pairs=[['app/disk-execution-policy.json','app/disk-execution-policy.schema.json'],['app/windows-cleanup-providers.json','app/windows-cleanup-providers.schema.json'],['app/temp-cleanup-policy.json','app/temp-cleanup-policy.schema.json'],['app/memory-task-policy.json','app/memory-task-policy.schema.json']];
const results=[];for(const [config,schema] of pairs){validate(read(schema),read(config));results.push({name:config,status:'passed'});}
const execution=read(pairs[0][0]);assert.throws(()=>validate(read(pairs[0][1]),{...execution,productionExecutionEnabled:true}));assert.throws(()=>validate(read(pairs[0][1]),{...execution,unknownField:true}));results.push({name:'production toggle and unknown fields rejected',status:'passed'});
const providers=read(pairs[1][0]);providers.providers[0].uri='cmd.exe';assert.throws(()=>validate(read(pairs[1][1]),providers));results.push({name:'non-Settings URI rejected',status:'passed'});
assert.equal(read('app/clean-data-policy.json').executionEnabled,false);assert.equal(read('app/disk-review-policy.json').executionEnabled,false);results.push({name:'general finder/app-data cleanup stays disabled; Temp is a separate reviewed capability',status:'passed'});
const temp=read(pairs[2][0]),tempSchema=read(pairs[2][1]);for(const change of [{allowElevation:true},{recursive:true},{permanentRequiresTwoSteps:false},{extensions:['.exe']},{minimumDays:[0,0,0]}])assert.throws(()=>validate(tempSchema,{...temp,...change}));results.push({name:'Temp unsafe policy expansion rejected',status:'passed'});
const task=read(pairs[3][0]),taskSchema=read(pairs[3][1]);for(const change of [{executionEnabled:true},{forceEnabled:true},{autoForceAfterTimeout:true},{foregroundBlocked:false}])assert.throws(()=>validate(taskSchema,{...task,...change}));results.push({name:'Memory3 preview cannot enable task execution or force fallback',status:'passed'});
fs.writeFileSync(path.join(root,'docs/verification/runtime-policy-checks.json'),JSON.stringify({timestamp:new Date().toISOString(),passed:results.length,results,scope:'local config schemas; no native actions'},null,2)+'\n');
console.log(`PASS ${results.length} runtime policy checks`);
