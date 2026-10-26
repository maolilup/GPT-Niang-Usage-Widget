param([switch]$Stop,[ValidateRange(5,86400)][int]$DurationSeconds=3600)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'supervisor-task.ps1')
$info=Get-WidgetSupervisorInfo (Split-Path $PSScriptRoot -Parent)
if($Stop){
  $null=[IO.Directory]::CreateDirectory($info.DataDir)
  [IO.File]::WriteAllText((Join-Path $info.DataDir 'diagnostics-stop.flag'),[Guid]::NewGuid().ToString('N'))
  Write-Output 'Observer stop requested. Widget and plugin settings were not changed.'
  return
}
$shell=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$observer=Start-Process -FilePath $shell -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',('"'+(Join-Path $PSScriptRoot 'observe.ps1')+'"'),'-DurationSeconds',[string]$DurationSeconds) -WindowStyle Hidden -PassThru
try{[pscustomobject]@{requestedObserverPid=$observer.Id;logs=(Join-Path $info.DataDir 'logs');durationSeconds=$DurationSeconds;changesWidgetState=$false;note='Read-only observer. Does not enable or launch the widget/plugin.'}|ConvertTo-Json}finally{$observer.Dispose()}
