$ErrorActionPreference='Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'runtime\supervisor-task.ps1')
# Accelerate only the startup grace; process identity and heartbeat I/O stay real.
$classify=(Get-Command Get-WidgetResourceFault).ScriptBlock
function Get-WidgetResourceFault($Process,$Presence,[long]$Now,$State=$null){
  $pastStartup=[pscustomobject]@{Id=$Process.Id;PrivateMemorySize64=$Process.PrivateMemorySize64;StartTime=$Process.StartTime.AddMinutes(-2)}
  & $classify $pastStartup $Presence $Now $State
}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('widget-heartbeat-recheck-'+[Guid]::NewGuid().ToString('N'))
$data=Join-Path $fixture 'state';$null=[IO.Directory]::CreateDirectory($data)
$scriptFile=Join-Path $fixture 'widget.ps1'
[IO.File]::WriteAllText($scriptFile,'Start-Sleep -Seconds 30')
[IO.File]::WriteAllText((Join-Path $fixture 'installation.json'),(@{appDir=$fixture;dataDir=$data}|ConvertTo-Json))
$child=Start-Process (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList @('-NoProfile','-WindowStyle','Hidden','-File',('"'+$scriptFile+'"')) -WindowStyle Hidden -PassThru
try{
  $now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  Write-WidgetSupervisorJson (Join-Path $data 'presence.json') @{pid=$child.Id;at=$now}
  $stale=@{pid=$child.Id;at=$now-90000}
  if(Stop-WidgetResourceFault $child $fixture $data 'heartbeat-timeout' $stale){throw 'The guardian terminated a fixture after its heartbeat had already recovered.'}
  if($child.HasExited -or (Test-Path (Join-Path $data 'supervisor-disabled.flag')) -or (Test-Path (Join-Path $data 'resource-fault.json'))){throw 'A cancelled stale decision changed the live process or persisted a false fault.'}
  'PASS: a real verified child with a recovered heartbeat survives a stale termination decision; no false fault or disabled flag'
}finally{if(!$child.HasExited){$child.Kill();$null=$child.WaitForExit(3000)};$child.Dispose()}
