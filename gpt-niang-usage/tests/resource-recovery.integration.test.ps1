param([string]$TestRoot=$PSScriptRoot)
$ErrorActionPreference='Stop'
$source=Split-Path $TestRoot -Parent
$fixture=Join-Path (Split-Path $source -Parent) ('test-temp\resource-recovery-loop-'+[guid]::NewGuid().ToString('N'))
$app=Join-Path $fixture 'app';$data=Join-Path $fixture 'state';$runtime=Join-Path $app 'runtime'
$null=[IO.Directory]::CreateDirectory($runtime);$null=[IO.Directory]::CreateDirectory($data)
foreach($name in @('supervisor-task.ps1','start-widget.ps1','diagnostics.ps1')){Copy-Item -LiteralPath (Join-Path $source ('runtime\'+$name)) -Destination (Join-Path $runtime $name)}
$guardian=[IO.File]::ReadAllText((Join-Path $source 'runtime\supervisor.ps1'),[Text.Encoding]::UTF8)
$hostQuery='$hosts=@([GptWidgetSupervisorNative]::Hosts())'
if(!$guardian.Contains($hostQuery)){throw 'Supervisor fixture host injection point changed.'}
# Only discovery and the resource probe are injected. The real loop, identity
# validation, fault persistence, process stopping and relaunch path are retained.
$guardian=$guardian.Replace($hostQuery,'$hosts=@([pscustomobject]@{handle=1L;pid=1;started=1L;visible=$true})')
$guardian=$guardian.Replace("'Local\GPTNiangSupervisor-'",("'Local\GPTNiangSupervisor-Test-"+[guid]::NewGuid().ToString('N')+"-'"))
$injection=@'
function Get-WidgetResourceFault($Process,$Presence,[long]$Now){
  if($Presence -and $Presence.pid-eq $Process.Id -and $Now-[long]$Presence.at-ge 0 -and $Now-[long]$Presence.at-lt 1000){return 'memory-limit'}
  return ''
}
'@
$import=". (Join-Path `$PSScriptRoot 'supervisor-task.ps1')"
$guardian=$guardian.Replace($import,$import+[Environment]::NewLine+$injection)
[IO.File]::WriteAllText((Join-Path $runtime 'supervisor.ps1'),$guardian,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $app 'installation.json'),(@{appDir=$app;dataDir=$data}|ConvertTo-Json))
$gui=@'
param([string]$AppDir)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
. (Join-Path $AppDir 'runtime\supervisor-task.ps1')
$data=(Get-Content (Join-Path $AppDir 'installation.json') -Raw|ConvertFrom-Json).dataDir
$form=[Windows.Forms.Form]::new();$form.ShowInTaskbar=$false;$form.Opacity=0;$form.Show()
$p=Get-Process -Id $PID
try{$started=$p.StartTime.ToUniversalTime().ToString('o')}finally{$p.Dispose()}
Write-WidgetSupervisorJson (Join-Path $data 'runtime.json') @{pid=$PID;widget=$form.Handle.ToInt64();processStartedAt=$started;startedAt=[DateTime]::UtcNow.ToString('o')}
[IO.File]::AppendAllText((Join-Path $data 'launches.jsonl'),(@{pid=$PID;started=$started}|ConvertTo-Json -Compress)+[Environment]::NewLine)
$timer=[Windows.Forms.Timer]::new();$timer.Interval=200
$timer.Add_Tick({try{Write-WidgetSupervisorJson (Join-Path $data 'presence.json') @{pid=$PID;at=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()}}catch{}})
try{$timer.Start();[Windows.Forms.Application]::Run()}finally{$timer.Dispose();$form.Dispose()}
'@
[IO.File]::WriteAllText((Join-Path $app 'widget.ps1'),$gui,[Text.UTF8Encoding]::new($false))
$process=$null
try{
  $process=Start-Process -FilePath (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',('"'+(Join-Path $runtime 'supervisor.ps1')+'"')) -WindowStyle Hidden -PassThru
  $deadline=[DateTime]::UtcNow.AddSeconds(70)
  do{
    if($process.HasExited){break}
    Start-Sleep -Milliseconds 250
  }while([DateTime]::UtcNow-lt $deadline)
  if(!$process.HasExited){throw ('Supervisor did not finish the bounded recovery scenario. Fixture: '+$fixture)}
  if($process.ExitCode-ne 0){throw ('Supervisor fixture failed: '+[IO.File]::ReadAllText((Join-Path $data 'supervisor-error.txt')))}
  $launches=@(Get-Content (Join-Path $data 'launches.jsonl')|ForEach-Object{$_|ConvertFrom-Json})
  if($launches.Count-ne 3 -or @($launches.pid|Select-Object -Unique).Count-ne 3){throw 'Expected the initial GUI and exactly two automatic GUI recoveries.'}
  $fault=Get-Content (Join-Path $data 'resource-fault.json') -Raw|ConvertFrom-Json
  if($fault.action-ne 'disabled-until-manual-open' -or @($fault.restarts).Count-ne 2){throw 'The third incident did not trip the persisted recovery budget.'}
  if(!(Test-Path (Join-Path $data 'supervisor-disabled.flag'))){throw 'Repeated faults did not disable automatic relaunch.'}
  [pscustomobject]@{ok=$true;launches=$launches.pid;automaticRecoveries=2;thirdIncident='disabled';supervisorExited=$true;faultInjection='resource probe and host discovery; isolated mutex; real GUI handles and supervisor lifecycle';fixture=$fixture}|ConvertTo-Json
}finally{
  if($process){if(!$process.HasExited){$process.Kill();$null=$process.WaitForExit(3000)};$process.Dispose()}
  # Stop only fixture GUIs whose exact script path and process start still match.
  $launchFile=Join-Path $data 'launches.jsonl'
  if(Test-Path $launchFile){
    foreach($record in @(Get-Content $launchFile|ForEach-Object{$_|ConvertFrom-Json})){
      $child=Get-CimInstance Win32_Process -Filter ('ProcessId='+[int]$record.pid)
      if($child -and $child.CommandLine -and $child.CommandLine.Contains('"'+(Join-Path $app 'widget.ps1')+'"') -and [Math]::Abs(($child.CreationDate.ToUniversalTime()-([DateTime]$record.started).ToUniversalTime()).TotalMilliseconds)-lt 1){Stop-Process -Id ([int]$record.pid)}
    }
  }
}
