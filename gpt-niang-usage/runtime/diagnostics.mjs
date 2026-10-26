import fs from 'node:fs';
import path from 'node:path';
import {randomUUID} from 'node:crypto';

const fields=new Set('privateBytes workingSetBytes managedBytes handles cpuMs threads uptimeMs stage state reason action hostPid host widget visible hostVisible foreground owner topmost displayScale scale spriteBytes spriteCount spriteDecodes followEvents positionChanges tickMs heartbeatAgeMs faultSamples childPid parentPid exitCode signal ok queryOk errorCode errorType hresult stack elapsedMs method requestId pending queryId eventId recordId provider observedUtc osError changed count nextLaunchMs processStartedAt policy version sourceVersion enabled paused mainWindows busy hostEvents frameWidth frameHeight remainingMinutes'.split(' '));
// The quota-worker lock guarantees one writer. Never write to MCP stdout.
export function createDiagnosticLog(dataDir,component='worker',{maxBytes=1024*1024}={}){
  if(component!=='worker')throw new Error('Unknown diagnostic component');
  const directory=path.join(dataDir,'logs'),file=path.join(directory,component+'.jsonl');
  const session=randomUUID(),started=performance.now(),last=new Map();
  maxBytes=Math.max(4096,maxBytes);
  let retryAt=0,suppressed=0;
  return (event,data={},force=false)=>{
    const now=performance.now();
    if(now<retryAt || !/^[a-z][a-z0-9-]{0,63}$/.test(event))return;
    if(!force && now-(last.get(event)??-Infinity)<1000){suppressed++;return;}
    try{
      const safe={};
      for(const [key,value] of Object.entries(data)){
        if(!fields.has(key))continue;
        if(value===null || typeof value==='boolean' || (typeof value==='number' && Number.isFinite(value)))safe[key]=value;
        else if(typeof value==='string')safe[key]=value.slice(0,key==='stack'?1536:256);
      }
      const line=JSON.stringify({schema:1,utc:new Date().toISOString(),pid:process.pid,component,session,elapsedMs:Math.round(now-started),event,suppressed,data:safe})+'\n';
      const size=Buffer.byteLength(line);
      if(size>maxBytes)return;
      fs.mkdirSync(directory,{recursive:true});
      if(fs.existsSync(file) && fs.statSync(file).size+size>maxBytes){
        const old=path.join(directory,component+'.2.jsonl'),previous=path.join(directory,component+'.1.jsonl');
        if(fs.existsSync(old))fs.unlinkSync(old);
        if(fs.existsSync(previous))fs.renameSync(previous,old);
        fs.renameSync(file,previous);
      }
      fs.appendFileSync(file,line);
      if(last.size<64 || last.has(event))last.set(event,now);
      suppressed=0;
    }catch{retryAt=now+5000;suppressed++;}
  };
}
