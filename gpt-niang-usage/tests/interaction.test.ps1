param([string]$TestRoot=$PSScriptRoot)
$ErrorActionPreference='Stop'
$source=[IO.File]::ReadAllText((Join-Path (Split-Path $TestRoot -Parent) 'widget.ps1'),[Text.Encoding]::UTF8)
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors|Out-String)}
$definition=$ast.Find({param($node)$node-is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name-eq 'Click-Character'},$true)
. ([ScriptBlock]::Create($definition.Extent.Text))
function Assert-Equal($actual,$expected,[string]$message){if($actual-ne $expected){throw "$message : expected '$expected', got '$actual'"}}
# Isolate presentation side effects; exercise the production click handler and its state transitions.
function Invoke-WidgetExpressionEvent($kind){$script:events+=('expression:'+ $kind)}
function Show-Quota {$script:collapsed=$false;$script:bubbleMode='quota';$script:events+='show:quota'}
function Switch-Scene($mode){$script:bubbleMode=$mode;$script:events+=('switch:'+ $mode)}
function Next-Bubble {throw 'Character clicks must not use the bubble close cycle'}
function Restart-SceneTtl {throw 'Character clicks must alternate instead of only extending the quota'}
foreach($legacyPreference in @($false,$true)){
  $script:bubbleTapAdvance=$legacyPreference
  $script:collapsed=$true;$script:bubbleMode='quote';$script:events=@()
  foreach($expected in @('quota','quote','quota','quote','quota','quote')){
    Click-Character
    Assert-Equal $script:collapsed $false 'Repeated clicks keep the content visible'
    Assert-Equal $script:bubbleMode $expected 'Character clicks alternate quota and dialogue'
  }
  Assert-Equal ($script:events -join ',') 'expression:click,show:quota,expression:click,switch:quote,expression:click,switch:quota,expression:click,switch:quote,expression:click,switch:quota,expression:click,switch:quote' 'Each click starts one stable reaction before changing content'
  $script:collapsed=$true
  Click-Character
  Assert-Equal $script:bubbleMode quota 'After the bubble closes, the next click starts with quota'
}
Write-Output 'PASS: character clicks alternate quota/dialogue, preserve visibility, restart with quota after close and ignore the obsolete opt-in setting'
