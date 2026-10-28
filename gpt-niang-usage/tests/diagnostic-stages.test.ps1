$ErrorActionPreference='Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'runtime\diagnostics.ps1')
if(!(Get-Command New-WidgetDiagnosticStage -ErrorAction SilentlyContinue)){throw 'Slow UI updates do not identify the blocking stage or exclude system sleep.'}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('widget-stage-log-'+[Guid]::NewGuid().ToString('N'))
$log=New-WidgetDiagnosticLog $fixture 'widget'
try{
  $state=New-WidgetDiagnosticStage 'worker-health' 100
  Set-WidgetDiagnosticStage $log $state 'window-position' 200
  if(Test-Path $log.path){throw 'Fast stages should not generate per-tick disk writes.'}
  Set-WidgetDiagnosticStage $log $state 'quota-render' 1300
  Set-WidgetDiagnosticStage $log $state 'complete' 6300
  $rows=@(Get-Content $log.path|ForEach-Object{$_|ConvertFrom-Json})
  if($rows.Count-ne 2 -or $rows[0].data.stage-ne 'window-position' -or $rows[0].data.elapsedMs-ne 1100 -or $rows[1].data.stage-ne 'quota-render' -or $rows[1].data.elapsedMs-ne 5000){throw 'Stage duration or identification is inaccurate.'}
  if($state.activeMs-ne 6200){throw 'Total active tick duration did not use the active clock.'}
  $before=[GptWidgetDiagnosticClock]::ActiveMilliseconds
  Start-Sleep -Milliseconds 30
  $after=[GptWidgetDiagnosticClock]::ActiveMilliseconds
  if($before-le 0 -or $after-lt $before){throw 'The Windows active-time clock is unavailable or non-monotonic.'}
  $inner=[IO.IOException]::new('PRIVATE INNER CONTENT')
  $outer=[Exception]::new('PRIVATE OUTER CONTENT',$inner)
  Write-WidgetDiagnosticError $log 'stage-error' $outer 'heartbeat-write'
  $raw=[IO.File]::ReadAllText($log.path)
  $last=([IO.File]::ReadAllLines($log.path)[-1]|ConvertFrom-Json)
  if($last.data.errorType-ne 'System.IO.IOException' -or $last.data.hresult-ne $inner.HResult -or $raw-match 'PRIVATE'){throw 'Wrapped exceptions must preserve the root error code without payload text.'}
  'PASS: fast stages stay silent, slow-stage attribution and active durations are accurate, native active clock works, inner error type/code retained without private messages'
}finally{Close-WidgetDiagnosticLog $log}
