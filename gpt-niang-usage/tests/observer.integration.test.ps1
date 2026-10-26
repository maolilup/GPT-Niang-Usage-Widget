$ErrorActionPreference='Stop'
$source=Split-Path $PSScriptRoot -Parent
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('widget-observer-'+[Guid]::NewGuid().ToString('N'))
$app=Join-Path $fixture 'app';$data=Join-Path $fixture 'state';$runtime=Join-Path $app 'runtime'
$null=[IO.Directory]::CreateDirectory($runtime);$null=[IO.Directory]::CreateDirectory($data)
foreach($name in @('supervisor-task.ps1','supervisor.ps1','diagnostics.ps1')){Copy-Item (Join-Path $source ('runtime\'+$name)) (Join-Path $runtime $name)}
$observer=[IO.File]::ReadAllText((Join-Path $source 'runtime\observe.ps1'))
$query='@([GptWidgetSupervisorNative]::Hosts())'
if(!$observer.Contains($query)){throw 'Observer discovery injection point changed.'}
# Replace discovery only. The recorder, retained handles, exit codes and files
# are real; no running Codex or widget is stopped or configured by this test.
$observer=$observer.Replace($query,'@((Get-Content -LiteralPath (Join-Path $info.DataDir ''host-fixture.json'') -Raw|ConvertFrom-Json))')
$observer=$observer.Replace('Local\GPTNiangObserver-','Local\GPTNiangObserver-Test-'+[Guid]::NewGuid().ToString('N')+'-')
[IO.File]::WriteAllText((Join-Path $runtime 'observe.ps1'),$observer)
[IO.File]::WriteAllText((Join-Path $app 'installation.json'),(@{appDir=$app;dataDir=$data}|ConvertTo-Json))
$shell=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$child=$null;$recorder=$null
try{
  $child=Start-Process $shell -ArgumentList @('-NoProfile','-Command','"Start-Sleep -Seconds 9; exit 37"') -WindowStyle Hidden -PassThru
  [IO.File]::WriteAllText((Join-Path $data 'host-fixture.json'),(@{pid=$child.Id;started=$child.StartTime.ToUniversalTime().Ticks;handle=1L;visible=$true}|ConvertTo-Json))
  $recorder=Start-Process $shell -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',('"'+(Join-Path $runtime 'observe.ps1')+'"'),'-DurationSeconds','20') -WindowStyle Hidden -PassThru
  if(!$recorder.WaitForExit(35000)){throw 'Independent observer did not respect its bounded lifetime.'}
  if($recorder.ExitCode-ne 0){throw ('Observer failed. Inspect '+$fixture)}
  $rows=@(Get-Content (Join-Path $data 'logs\observer.jsonl')|ForEach-Object{$_|ConvertFrom-Json})
  if(!($rows|Where-Object{$_.event-eq 'host-running' -and $_.data.childPid-eq $child.Id})){throw 'Observer missed the live process.'}
  if(!($rows|Where-Object{$_.event-eq 'host-exited' -and $_.data.childPid-eq $child.Id -and $_.data.exitCode-eq 37})){throw 'Observer lost the process exit code after termination.'}
  if(($rows|Where-Object{$_.event-eq 'exit'}).data.reason-ne 'duration-complete'){throw 'Observer did not record why it stopped.'}
  'PASS: real independent recorder retained the observed exit code and stopped at its duration limit; discovery fixture only'
}finally{foreach($process in @($child,$recorder)){if($process){if(!$process.HasExited){$process.Kill();$null=$process.WaitForExit(3000)};$process.Dispose()}}}
