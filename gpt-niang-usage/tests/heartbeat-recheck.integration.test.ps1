$ErrorActionPreference='Stop'
$source=Split-Path $PSScriptRoot -Parent
. (Join-Path $source 'runtime\supervisor-task.ps1')
. (Join-Path $source 'runtime\diagnostics.ps1')
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('widget-heartbeat-recheck-'+[Guid]::NewGuid().ToString('N'))
$data=Join-Path $fixture 'state';$null=[IO.Directory]::CreateDirectory($data)
$scriptFile=Join-Path $fixture 'widget.ps1'
[IO.File]::WriteAllText($scriptFile,'Start-Sleep -Seconds 30')
[IO.File]::WriteAllText((Join-Path $fixture 'installation.json'),(@{appDir=$fixture;dataDir=$data}|ConvertTo-Json))
$child=Start-Process (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList @('-NoProfile','-WindowStyle','Hidden','-File',('"'+$scriptFile+'"')) -WindowStyle Hidden -PassThru
try{
  $now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $clock=Get-WidgetHeartbeatClock
  $ticks=$child.StartTime.ToUniversalTime().Ticks
  $stale=@{pid=$child.Id;at=$now-31000;activeAt=$clock.activeMs-31000;processStartTicks=$ticks}
  $state=@{}
  $null=Get-WidgetResourceFault $child $stale $now $state $clock
  $state.startupUntil=$clock.activeMs
  if((Get-WidgetResourceFault $child $stale $now $state $clock)-ne 'heartbeat-timeout'){throw 'Fixture did not establish a real timeout decision.'}
  Write-WidgetSupervisorJson (Join-Path $data 'presence.json') @{pid=$child.Id;at=$now;activeAt=$clock.activeMs;processStartTicks=$ticks}
  if(Stop-WidgetResourceFault $child $fixture $data 'heartbeat-timeout' $stale $state){throw 'The guardian terminated a fixture after its heartbeat had already recovered.'}
  if($child.HasExited -or (Test-Path (Join-Path $data 'supervisor-disabled.flag')) -or (Test-Path (Join-Path $data 'resource-fault.json'))){throw 'A cancelled stale decision changed the live process or persisted a false fault.'}
  'PASS: a real verified child with a recovered heartbeat survives a stale termination decision; no false fault or disabled flag'
}finally{if(!$child.HasExited){$child.Kill();$null=$child.WaitForExit(3000)};$child.Dispose()}
