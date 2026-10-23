param([string]$TestRoot=$PSScriptRoot,[switch]$Integration)
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path $TestRoot -Parent) 'runtime\supervisor-task.ps1')
if(!(Get-Command Get-WidgetResourceFault -ErrorAction SilentlyContinue)){throw 'Independent supervisor has no resource/heartbeat circuit breaker.'}
$now=1800000000000L
function Assert-Fault($Private,$Age,$RuntimeAge,$Expected){
  $process=[pscustomobject]@{Id=123;PrivateMemorySize64=$Private;StartTime=[DateTimeOffset]::FromUnixTimeMilliseconds($now-$RuntimeAge).UtcDateTime}
  $presence=@{pid=123;at=$now-$Age}
  $actual=Get-WidgetResourceFault $process $presence $now
  if($actual-ne $Expected){throw "Resource watchdog: expected '$Expected', got '$actual'"}
}
Assert-Fault 200MB 1000 120000 ''
Assert-Fault 512MB 1000 120000 ''
Assert-Fault (512MB+1) 1000 120000 'memory-limit'
Assert-Fault 3GB 1000 120000 'memory-limit'
Assert-Fault 100MB 30000 120000 ''
Assert-Fault 100MB 30001 120000 'heartbeat-timeout'
Assert-Fault 100MB 90000 20000 ''
$process=[pscustomobject]@{Id=123;PrivateMemorySize64=100MB;StartTime=[DateTimeOffset]::FromUnixTimeMilliseconds($now-120000).UtcDateTime}
if((Get-WidgetResourceFault $process @{pid=456;at=$now} $now)-ne 'heartbeat-timeout'){throw 'An old PID heartbeat masked a stalled new widget.'}
if((Get-WidgetResourceFault $process @{pid=123;at=$now+1} $now)-ne 'heartbeat-timeout'){throw 'Future heartbeat must not be healthy.'}
if((Get-WidgetResourceFault $process $null $now)-ne 'heartbeat-timeout'){throw 'Missing heartbeat must not mask a stalled GUI.'}
if((Get-WidgetResourceFault $process @{pid=123;at='invalid'} $now)-ne 'heartbeat-timeout'){throw 'Malformed heartbeat bypassed the guardian.'}
'PASS: 512 MiB boundary, stale/missing/wrong/future heartbeat and startup grace'
if($Integration){
  $fixture=Join-Path (Split-Path (Split-Path $TestRoot -Parent) -Parent) ('test-temp\resource-guard-'+[Guid]::NewGuid().ToString('N'))
  $data=Join-Path $fixture 'state';$null=[IO.Directory]::CreateDirectory($data)
  [IO.File]::WriteAllText((Join-Path $fixture 'installation.json'),(@{appDir=$fixture;dataDir=$data}|ConvertTo-Json))
  [IO.File]::WriteAllText((Join-Path $fixture 'widget.ps1'),'Start-Sleep -Seconds 30')
  $child=Start-Process -FilePath (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList @('-NoProfile','-WindowStyle','Hidden','-File',('"'+(Join-Path $fixture 'widget.ps1')+'"')) -WindowStyle Hidden -PassThru
  try{
    if(Stop-WidgetResourceFault $child ($fixture+'-other') $data 'memory-limit'){throw 'Guardian accepted a foreign installation path.'}
    if($child.HasExited){throw 'Guardian ended a process belonging to another installation.'}
    if(!(Stop-WidgetResourceFault $child $fixture $data 'memory-limit')){throw 'Guardian did not stop the verified fixture.'}
    if(!$child.WaitForExit(3000)){throw 'Verified faulted GUI survived the guardian.'}
    if(!(Test-Path (Join-Path $data 'supervisor-disabled.flag'))){throw 'Guardian would restart the faulted GUI in a loop.'}
    $fault=Get-Content (Join-Path $data 'resource-fault.json') -Raw|ConvertFrom-Json
    if($fault.pid-ne $child.Id -or $fault.reason-ne 'memory-limit'){throw 'Guardian did not preserve a fault record.'}
    'PASS: actual child process stopped, foreign path protected, restart disabled and fault recorded'
  }finally{if(!$child.HasExited){$child.Kill()};$child.Dispose()}
}
