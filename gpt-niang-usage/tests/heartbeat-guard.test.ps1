$ErrorActionPreference='Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'runtime\supervisor-task.ps1')
$now=1800000000000L
$process=[pscustomobject]@{Id=123;PrivateMemorySize64=200MB;StartTime=[DateTimeOffset]::FromUnixTimeMilliseconds($now-120000).UtcDateTime}
$state=@{}
$null=Get-WidgetResourceFault $process @{pid=123;at=$now} $now $state
foreach($gap in @(2000,4000,6000)){
  if(Get-WidgetResourceFault $process $null ($now+$gap) $state){throw 'Three unreadable heartbeat snapshots killed a GUI whose last confirmed heartbeat is only six seconds old.'}
}
if(Get-WidgetResourceFault $process @{pid=456;at=$now+9000} ($now+9000) $state){throw 'An unrelated PID erased a valid cached heartbeat.'}
if((Get-WidgetResourceFault $process $null ($now+30001) $state)-ne 'heartbeat-timeout'){throw 'A cached heartbeat must expire after thirty seconds.'}
if(Get-WidgetResourceFault $process @{pid=123;at=$now+31000} ($now+31000) $state){throw 'A fresh heartbeat did not clear the expired state.'}
$process.PrivateMemorySize64=513MB
if((Get-WidgetResourceFault $process $null ($now+32000) $state)-ne 'memory-limit'){throw 'Heartbeat caching bypassed the memory limit.'}
$process.PrivateMemorySize64=200MB
$new=[pscustomobject]@{Id=123;PrivateMemorySize64=200MB;StartTime=$process.StartTime.AddSeconds(1)}
if(Get-WidgetResourceFault $new $null ($now+33000) $state){throw 'The first missing read of a new process must receive an observation window.'}
if((Get-WidgetResourceFault $new $null ($now+63001) $state)-ne 'heartbeat-timeout'){throw 'A reused PID incorrectly inherited the previous process heartbeat.'}
$missing=@{}
if(Get-WidgetResourceFault $process @{pid=999;at=$now} $now $missing){throw 'The initial unreadable/mismatched heartbeat must not immediately trip the guardian.'}
if((Get-WidgetResourceFault $process $null ($now+30001) $missing)-ne 'heartbeat-timeout'){throw 'A never-seen valid heartbeat must still time out.'}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('widget-heartbeat-'+[Guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($fixture)
$file=Join-Path $fixture 'presence.json';$temp=Join-Path $fixture 'next.json'
[IO.File]::WriteAllText($file,'{"pid":123,"at":1800000000000}')
$held=Open-WidgetSupervisorStateStream $file
try{
  [IO.File]::WriteAllText($temp,'{"pid":123,"at":1800000001000}')
  [IO.File]::Replace($temp,$file,[Management.Automation.Language.NullString]::Value)
  $fresh=Read-WidgetSupervisorPresence $fixture
  if($fresh.at-ne 1800000001000L){throw 'The sharing-safe heartbeat reader did not observe the replaced file.'}
}finally{$held.Dispose()}
'PASS: transient missing reads, cached-heartbeat expiry, invalid PID, process reuse, recovery, memory cap and nonblocking atomic replacement'
