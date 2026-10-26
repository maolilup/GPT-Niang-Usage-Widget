param(
  [string]$WidgetPath=(Join-Path (Split-Path $PSScriptRoot -Parent) 'widget.ps1'),
  [switch]$CheckOnly,
  [switch]$Preview
)
$ErrorActionPreference='Stop'
$widgetFile=[IO.Path]::GetFullPath($WidgetPath)
$source=[IO.File]::ReadAllText($widgetFile,[Text.Encoding]::UTF8)
. (Join-Path $PSScriptRoot 'diagnostics.ps1')
$entryLog=$null
if(!$CheckOnly -and !$Preview){
  try{
    $entryConfig=Get-Content -LiteralPath (Join-Path ([IO.Path]::GetDirectoryName($widgetFile)) 'installation.json') -Raw -Encoding UTF8|ConvertFrom-Json
    $entryLog=New-WidgetDiagnosticLog $entryConfig.dataDir 'widget'
    Write-WidgetDiagnostic $entryLog 'entry-start' @{sourceVersion=(Get-FileHash -LiteralPath $widgetFile -Algorithm SHA256).Hash} -Force
  }catch{}
}
try{
  & ([scriptblock]::Create($source)) -AppDir ([IO.Path]::GetDirectoryName($widgetFile)) -CheckOnly:$CheckOnly -Preview:$Preview
  Write-WidgetDiagnostic $entryLog 'entry-exit' @{reason='returned'} -Force
}catch{
  if($entryLog){Write-WidgetDiagnosticError $entryLog 'entry-fatal' $_ 'entrypoint'}
  throw
}finally{if($entryLog){Close-WidgetDiagnosticLog $entryLog}}
