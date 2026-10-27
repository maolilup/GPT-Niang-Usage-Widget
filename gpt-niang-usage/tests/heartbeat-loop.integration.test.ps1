$ErrorActionPreference='Stop'
$source=Split-Path $PSScriptRoot -Parent
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('widget-heartbeat-loop-'+[Guid]::NewGuid().ToString('N'))
$app=Join-Path $fixture 'app';$data=Join-Path $fixture 'state';$runtime=Join-Path $app 'runtime'
$null=[IO.Directory]::CreateDirectory($runtime);$null=[IO.Directory]::CreateDirectory($data)
foreach($name in @('supervisor-task.ps1','start-widget.ps1','diagnostics.ps1')){Copy-Item (Join-Path $source ('runtime\'+$name)) (Join-Path $runtime $name)}
$guardian=[IO.File]::ReadAllText((Join-Path $source 'runtime\supervisor.ps1'))
$query='$hosts=@([GptWidgetSupervisorNative]::Hosts())'
if(!$guardian.Contains($query)){throw 'Guardian discovery injection point changed.'}
$guardian=$guardian.Replace($query,'$hosts=@([pscustomobject]@{handle=1L;pid=1;started=1L;visible=$true})')
$guardian=$guardian.Replace('Local\GPTNiangSupervisor-','Local\GPTNiangSupervisor-Heartbeat-Test-'+[Guid]::NewGuid().ToString('N')+'-')
$injection=@'
$script:realPresenceReader=(Get-Command Read-WidgetSupervisorPresence).ScriptBlock
$script:realFaultClassifier=(Get-Command Get-WidgetResourceFault).ScriptBlock
$script:firstHeartbeat=$false;$script:missingReads=0
function Read-WidgetSupervisorPresence([string]$DataDir){
  $value=& $script:realPresenceReader $DataDir
  if(!$script:firstHeartbeat -and $value){$script:firstHeartbeat=$true;return $value}
  if($script:firstHeartbeat -and $script:missingReads-lt 3){
    $script:missingReads++;[IO.File]::WriteAllText((Join-Path $DataDir 'injected-reads.txt'),[string]$script:missingReads)
    return $null
  }
  return $value
}
function Get-WidgetResourceFault($Process,$Presence,[long]$Now,$State=$null){
  # Accelerate startup grace only. The real 30-second expiry remains in force.
  $pastStartup=[pscustomobject]@{Id=$Process.Id;PrivateMemorySize64=$Process.PrivateMemorySize64;StartTime=$Process.StartTime.AddMinutes(-2)}
  & $script:realFaultClassifier $pastStartup $Presence $Now $State
}
'@
$marker=". (Join-Path `$PSScriptRoot 'supervisor-task.ps1')"
$guardian=$guardian.Replace($marker,$marker+[Environment]::NewLine+$injection)
[IO.File]::WriteAllText((Join-Path $runtime 'supervisor.ps1'),$guardian)
[IO.File]::WriteAllText((Join-Path $app 'installation.json'),(@{appDir=$app;dataDir=$data}|ConvertTo-Json))
$gui=@'
param([string]$AppDir)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
. (Join-Path $AppDir 'runtime\supervisor-task.ps1')
$data=(Get-Content (Join-Path $AppDir 'installation.json') -Raw|ConvertFrom-Json).dataDir
$form=[Windows.Forms.Form]::new();$handle=$form.Handle # Never shown or activated.
$self=Get-Process -Id $PID
try{$started=$self.StartTime.ToUniversalTime().ToString('o')}finally{$self.Dispose()}
Write-WidgetSupervisorJson (Join-Path $data 'runtime.json') @{pid=$PID;widget=$handle.ToInt64();processStartedAt=$started;startedAt=[DateTime]::UtcNow.ToString('o')}
$timer=[Windows.Forms.Timer]::new();$timer.Interval=200
$timer.Add_Tick({if(!(Test-Path (Join-Path $data 'freeze-heartbeat.flag'))){Write-WidgetSupervisorJson (Join-Path $data 'presence.json') @{pid=$PID;at=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()}}})
try{$timer.Start();[Windows.Forms.Application]::Run()}finally{$timer.Dispose();$form.Dispose()}
'@
[IO.File]::WriteAllText((Join-Path $app 'widget.ps1'),$gui)
$process=$null;$child=$null
try{
  $shell=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $process=Start-Process $shell -ArgumentList @('-NoProfile','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File',('"'+(Join-Path $runtime 'supervisor.ps1')+'"')) -WindowStyle Hidden -PassThru
  $deadline=[DateTime]::UtcNow.AddSeconds(25)
  do{
    if(Test-Path (Join-Path $data 'injected-reads.txt')){if([IO.File]::ReadAllText((Join-Path $data 'injected-reads.txt'))-eq '3'){break}}
    if($process.HasExited){throw ('Guardian exited during the transient-read fixture: '+$fixture)}
    Start-Sleep -Milliseconds 250
  }while([DateTime]::UtcNow-lt $deadline)
  if(!(Test-Path (Join-Path $data 'injected-reads.txt')) -or [IO.File]::ReadAllText((Join-Path $data 'injected-reads.txt'))-ne '3'){throw 'Did not exercise three consecutive missing reads.'}
  Start-Sleep -Seconds 3
  $record=Get-Content (Join-Path $data 'runtime.json') -Raw|ConvertFrom-Json
  $child=Get-Process -Id ([int]$record.pid) -ErrorAction Stop
  $null=$child.Handle
  if($process.HasExited -or $child.HasExited -or (Test-Path (Join-Path $data 'resource-fault.json'))){throw 'A live GUI was terminated for transient read failures.'}
  [IO.File]::WriteAllText((Join-Path $data 'freeze-heartbeat.flag'),'test')
  $last=Get-Content (Join-Path $data 'presence.json') -Raw|ConvertFrom-Json
  if(!$process.WaitForExit(45000)){throw ('A genuinely stale heartbeat did not stop the guardian: '+$fixture)}
  if(!$child.WaitForExit(3000)){throw 'The genuinely stalled fixture survived the watchdog.'}
  $fault=Get-Content (Join-Path $data 'resource-fault.json') -Raw|ConvertFrom-Json
  $age=[DateTimeOffset]::Parse($fault.at).ToUnixTimeMilliseconds()-[long]$last.at
  if($fault.reason-ne 'heartbeat-timeout' -or $age-lt 30000 -or $age-gt 43000 -or !(Test-Path (Join-Path $data 'supervisor-disabled.flag'))){throw 'Heartbeat expiry boundary or persistent disable was lost.'}
  [pscustomobject]@{ok=$true;transientReads=3;transientAction='continued';actualStallAgeMs=$age;stallAction='disabled';fixture=$fixture}|ConvertTo-Json
}finally{
  if(!$child -and (Test-Path (Join-Path $data 'runtime.json'))){try{$record=Get-Content (Join-Path $data 'runtime.json') -Raw|ConvertFrom-Json;$child=Get-Process -Id ([int]$record.pid);if($child.StartTime.ToUniversalTime()-ne ([DateTime]$record.processStartedAt).ToUniversalTime()){$child.Dispose();$child=$null}}catch{}}
  foreach($item in @($process,$child)){if($item){if(!$item.HasExited){$item.Kill();$null=$item.WaitForExit(3000)};$item.Dispose()}}
}
