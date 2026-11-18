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

$active=500000L
$startedTicks=$process.StartTime.Ticks
$before=@{pid=123;at=$now-1933;activeAt=$active-1933;processStartTicks=$startedTicks}
$rollback=@{}
$null=Get-WidgetResourceFault $process $before $now $rollback @{activeMs=$active;suspendMs=0}
foreach($gap in @(809,2747,4744)){
  $wall=$now+$gap-9416
  $clock=@{activeMs=$active+$gap;suspendMs=0}
  $fresh=@{pid=123;at=$wall-200;activeAt=$clock.activeMs-200;processStartTicks=$startedTicks}
  if(Get-WidgetResourceFault $process $fresh $wall $rollback $clock){throw 'A Windows clock rollback cannot turn a fresh heartbeat into a timeout.'}
}
if($rollback.heartbeatAgeMs-ne 200){throw 'Diagnostic heartbeat age must use the same clock as the guard.'}
$wrongInstance=@{pid=123;at=$now+3600000;activeAt=$active+31000;processStartTicks=$startedTicks-1}
if((Get-WidgetResourceFault $process $wrongInstance ($now+3600000) $rollback @{activeMs=$active+45000;suspendMs=0})-ne 'heartbeat-timeout'){throw 'A different process instance or a jump forward masked an expired heartbeat.'}

$sleep=@{}
$null=Get-WidgetResourceFault $process $before $now $sleep @{activeMs=$active;suspendMs=0}
$wakeWall=$now+7200000L
$wakeClock=@{activeMs=$active+500;suspendMs=7200000L}
if(Get-WidgetResourceFault $process $before $wakeWall $sleep $wakeClock){throw 'Two hours of sleep must not count toward timeout.'}
if(Get-WidgetResourceFault $process $before ($wakeWall+106454) $sleep @{activeMs=$wakeClock.activeMs+106454;suspendMs=$wakeClock.suspendMs}){throw 'Wake grace ended before the recorded 106-second recovery could finish.'}
$process.PrivateMemorySize64=513MB
if((Get-WidgetResourceFault $process $before ($wakeWall+107000) $sleep @{activeMs=$wakeClock.activeMs+107000;suspendMs=$wakeClock.suspendMs})-ne 'memory-limit'){throw 'Wake grace bypassed the memory limit.'}
$process.PrivateMemorySize64=200MB
if((Get-WidgetResourceFault $process $before ($wakeWall+120001) $sleep @{activeMs=$wakeClock.activeMs+120001;suspendMs=$wakeClock.suspendMs})-ne 'heartbeat-timeout'){throw 'Wake grace must stay bounded when no new heartbeat arrives.'}
$fresh=@{pid=123;at=$wakeWall+120100;activeAt=$wakeClock.activeMs+120100;processStartTicks=$startedTicks}
if(Get-WidgetResourceFault $process $fresh ($fresh.at+1) $sleep @{activeMs=$fresh.activeAt+1;suspendMs=$wakeClock.suspendMs}){throw 'A recovered heartbeat must cancel a pending timeout.'}
if((Get-WidgetResourceFault $process $fresh ($fresh.at+30001) $sleep @{activeMs=$fresh.activeAt+30001;suspendMs=$wakeClock.suspendMs})-ne 'heartbeat-timeout'){throw 'An awake stall must still time out after 30 seconds.'}

$resumed=@{}
$null=Get-WidgetResourceFault $process $before $now $resumed @{activeMs=$active;suspendMs=0}
$null=Get-WidgetResourceFault $process $before $wakeWall $resumed $wakeClock
$pulse=@{pid=123;at=$wakeWall+900;activeAt=$wakeClock.activeMs+900;processStartTicks=$startedTicks}
if(Get-WidgetResourceFault $process $pulse ($pulse.at+100) $resumed @{activeMs=$pulse.activeAt+100;suspendMs=$wakeClock.suspendMs}){throw 'A new heartbeat during wake grace must be accepted.'}
if((Get-WidgetResourceFault $process $pulse ($pulse.at+30001) $resumed @{activeMs=$pulse.activeAt+30001;suspendMs=$wakeClock.suspendMs})-ne 'heartbeat-timeout'){throw 'A new heartbeat must end wake grace, so a new awake stall is detected normally.'}

$sameTick=@{}
$atSuspend=@{pid=123;at=$now;activeAt=$active;processStartTicks=$startedTicks}
$null=Get-WidgetResourceFault $process $atSuspend $now $sameTick @{activeMs=$active;suspendMs=0}
$null=Get-WidgetResourceFault $process $atSuspend $wakeWall $sameTick @{activeMs=$active;suspendMs=$wakeClock.suspendMs}
if(Get-WidgetResourceFault $process $atSuspend ($wakeWall+30001) $sameTick @{activeMs=$active+30001;suspendMs=$wakeClock.suspendMs}){throw 'The last heartbeat before sleep cannot end wake grace when the active clock still shows the same tick.'}

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
'PASS: transient reads, clock rollback/forward, sleep grace and recovery, true timeout, process identity, memory cap and atomic replacement'
