import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {createDiagnosticLog} from '../runtime/diagnostics.mjs';
import {readUsage} from '../runtime/usage.mjs';
import {EventEmitter} from 'node:events';
import {PassThrough} from 'node:stream';

test('diagnostics rotate within a fixed budget and ignore private payload fields',()=>{
  const root=fs.mkdtempSync(path.join(os.tmpdir(),'widget-log-'));
  const log=createDiagnosticLog(root,'worker',{maxBytes:4096});
  for(let i=0;i<140;i++)log('sample',{privateBytes:i,stage:'x'.repeat(120),email:'PRIVATE',token:'SECRET',text:'DIALOGUE'},true);
  const dir=path.join(root,'logs'),files=fs.readdirSync(dir);
  assert.equal(files.length,3);
  const raw=files.map(file=>{assert.ok(fs.statSync(path.join(dir,file)).size<=4096);return fs.readFileSync(path.join(dir,file),'utf8');}).join('');
  assert.doesNotMatch(raw,/PRIVATE|SECRET|DIALOGUE/);
  const rows=fs.readFileSync(path.join(dir,'worker.jsonl'),'utf8').trim().split('\n').map(JSON.parse);
  assert.equal(rows.at(-1).data.privateBytes,139);
  assert.ok(rows.at(-1).session && rows.at(-1).utc);
});

test('diagnostic filesystem failures never change quota results or throw',async()=>{
  const root=fs.mkdtempSync(path.join(os.tmpdir(),'widget-log-block-'));
  fs.writeFileSync(path.join(root,'logs'),'not a directory');
  const log=createDiagnosticLog(root,'worker');
  assert.doesNotThrow(()=>log('sample',{ok:true},true));
  const events=[];
  const result=await readUsage('missing-widget-test-executable',{timeoutMs:200,log:(event,data)=>events.push({event,data})});
  assert.equal(result.ok,false);
  assert.ok(events.some(row=>row.event==='query-start'));
  assert.ok(events.some(row=>row.event==='query-finish' && row.data.ok===false));
  assert.ok(events.some(row=>row.event==='child-error'));
  const throwing=await readUsage('missing-widget-test-executable',{timeoutMs:200,log:()=>{throw new Error('diagnostic storage failed');}});
  assert.equal(throwing.errorCode,result.errorCode);
});

test('one quota query retains every protocol phase with one correlation id',async()=>{
  const root=fs.mkdtempSync(path.join(os.tmpdir(),'widget-query-log-'));
  const proc=new EventEmitter();proc.pid=12345;
  proc.stdin=new PassThrough();proc.stdout=new PassThrough();proc.stderr=new PassThrough();
  proc.kill=()=>setImmediate(()=>proc.emit('close',0,null));
  let pending='';
  proc.stdin.on('data',chunk=>{
    pending+=chunk;
    while(pending.includes('\n')){
      const end=pending.indexOf('\n'),request=JSON.parse(pending.slice(0,end));pending=pending.slice(end+1);
      if(!request.id)continue;
      const result=request.id===1?{}:request.id===2?{account:{type:'chatgpt',email:'private-query@example.test',planType:'plus'}}:{rateLimits:{primary:{windowDurationMins:300,usedPercent:20}}};
      setImmediate(()=>proc.stdout.write(JSON.stringify({id:request.id,result})+'\n'));
    }
  });
  const result=await readUsage('fixture',{spawnProcess:()=>proc,log:createDiagnosticLog(root)});
  assert.equal(result.ok,true);
  await new Promise(resolve=>setImmediate(resolve));
  const raw=fs.readFileSync(path.join(root,'logs','worker.jsonl'),'utf8'),rows=raw.trim().split('\n').map(JSON.parse);
  assert.deepEqual(rows.filter(row=>row.event==='rpc-send').map(row=>row.data.method),['initialize','initialized','account/read','account/rateLimits/read']);
  assert.equal(new Set(rows.map(row=>row.data.queryId)).size,1);
  assert.ok(rows.some(row=>row.event==='query-finish' && row.data.ok));
  assert.ok(rows.some(row=>row.event==='child-exit' && row.data.reason==='cleanup-requested'));
  assert.doesNotMatch(raw,/private-query@example|usedPercent|accountKey/);
});
