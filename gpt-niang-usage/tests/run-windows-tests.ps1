param([switch]$WidgetOnly,[switch]$InteractiveDesktop,[string]$PreviewDirectory)
$ErrorActionPreference='Stop'
if($WidgetOnly){
  $source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'widget.test.ps1'),[Text.Encoding]::UTF8)
  & ([ScriptBlock]::Create($source)) -TestRoot $PSScriptRoot -PreviewDirectory $PreviewDirectory
  return
}
$powerShell=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
if($InteractiveDesktop){
  & $powerShell -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'host-foreground.test.ps1')
  if($LASTEXITCODE-ne 0){throw "Foreground desktop tests failed ($LASTEXITCODE)"}
}
foreach($name in @('diagnostic-stages.test.ps1','diagnostics.test.ps1','installation.test.ps1','lifecycle.test.ps1','entrypoint.test.ps1','expression.test.ps1','resource-budget.test.ps1','heartbeat-guard.test.ps1','resource-watchdog.test.ps1','resource-recovery.test.ps1','resource-probe.test.ps1','host-isolation.test.ps1','interaction.test.ps1','headpat.test.ps1','low-quota.test.ps1','dialogue-config.test.ps1','ambient-dialogue.test.ps1','quote-layout.test.ps1','adaptive.test.ps1','size.test.ps1')){
  & $powerShell -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $name)
  if($LASTEXITCODE-ne 0){throw "$name failed ($LASTEXITCODE)"}
}
$widgetTestArgs=@('-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',$PSCommandPath,'-WidgetOnly')
if($PreviewDirectory){$widgetTestArgs+=@('-PreviewDirectory',$PreviewDirectory)}
& $powerShell @widgetTestArgs
if($LASTEXITCODE-ne 0){throw "Widget tests failed ($LASTEXITCODE)"}
