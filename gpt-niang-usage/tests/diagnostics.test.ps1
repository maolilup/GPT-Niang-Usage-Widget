$ErrorActionPreference='Stop'
$source=Split-Path $PSScriptRoot -Parent
if(!(Test-Path (Join-Path $source 'runtime\diagnostics.ps1'))){throw 'Missing bounded diagnostic logger and independent process-exit recorder.'}
. (Join-Path $source 'runtime\diagnostics.ps1')
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('widget-diagnostics-'+[Guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($fixture)
function Assert($Condition,[string]$Message){if(!$Condition){throw $Message}}
$log=New-WidgetDiagnosticLog $fixture 'observer' -MaxBytes 4096
try{
  for($i=0;$i-lt 140;$i++){Write-WidgetDiagnostic $log 'sample' @{privateBytes=$i;stage=('x'*120);email='private@example.test';text='PRIVATE DIALOGUE';token='SECRET'} -Force}
  $files=@(Get-ChildItem -LiteralPath (Join-Path $fixture 'logs') -Filter 'observer*.jsonl')
  Assert ($files.Count-eq 3) 'Log rotation must retain exactly three bounded files.'
  foreach($file in $files){Assert ($file.Length-le 4096) 'A log segment exceeded its byte limit.'}
  $raw=($files|ForEach-Object{[IO.File]::ReadAllText($_.FullName)})-join ''
  Assert ($raw-notmatch 'PRIVATE DIALOGUE|private@example|SECRET') 'Diagnostic logs must not copy account, dialogue or token fields.'
  $rows=@([IO.File]::ReadAllLines($log.path)|ForEach-Object{$_|ConvertFrom-Json})
  Assert ($rows[-1].data.privateBytes-eq 139 -and $rows[-1].session -and $rows[-1].utc) 'Latest record must carry session identity and UTC time.'
  $locked=[IO.File]::Open($log.path,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
  try{
    $clock=[Diagnostics.Stopwatch]::StartNew()
    for($i=0;$i-lt 100;$i++){Write-WidgetDiagnostic $log 'locked' @{stage='test'} -Force}
    Assert ($clock.ElapsedMilliseconds-lt 1000) 'A locked diagnostic file must never block or throw into the UI.'
  }finally{$locked.Dispose()}
  $log.retryAt=0
  Write-WidgetDiagnostic $log 'unlocked' @{ok=$true} -Force
  Assert (([IO.File]::ReadAllLines($log.path)[-1]|ConvertFrom-Json).event-eq 'unlocked') 'Logger must recover after a sharing conflict.'
  $shell=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $child=Start-Process $shell -ArgumentList @('-NoProfile','-Command','"Start-Sleep -Seconds 2; exit 37"') -WindowStyle Hidden -PassThru
  try{
    $null=$child.Handle
    $alive=Get-WidgetDiagnosticProcessState $child
    Assert ($alive.state-eq 'running' -and $alive.privateBytes-gt 0) 'Independent recorder must capture live process memory.'
    Assert ($child.WaitForExit(10000)) 'Fixture child did not finish.'
    $exited=Get-WidgetDiagnosticProcessState $child
    Assert ($exited.state-eq 'exited' -and $exited.exitCode-eq 37) 'Recorder must retain exit status after the observed process has gone.'
    Write-WidgetDiagnostic $log 'host-exit' $exited -Force
    Assert (([IO.File]::ReadAllLines($log.path)[-1]|ConvertFrom-Json).data.exitCode-eq 37) 'Process exit must be persisted immediately.'
  }finally{if(!$child.HasExited){$child.Kill()};$child.Dispose()}
  Write-Output 'PASS: bounded rotation, field allowlist, nonblocking sharing failure, recovery and independently observed process exit code'
}finally{Close-WidgetDiagnosticLog $log}
