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
  Assert-Equal ($script:events -join ',') 'expression:click,show:quota,expression:click,switch:quote,expression:click,switch:quota,expression:click,switch:quote,expression:click,switch:quota,expression:click,switch:quote' 'Each click records activity before alternating the content'
  $script:collapsed=$true
  Click-Character
  Assert-Equal $script:bubbleMode quota 'After the bubble closes, the next click starts with quota'
}
# Exercise the real scene timer and expression adapter, including cancelled rapid transitions.
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$appDir=Split-Path $TestRoot -Parent
. ([ScriptBlock]::Create([IO.File]::ReadAllText((Join-Path $appDir 'runtime\expressions.ps1'),[Text.Encoding]::UTF8)))
$definition=$ast.Find({param($node)$node-is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name-eq 'Switch-Scene'},$true)
. ([ScriptBlock]::Create($definition.Extent.Text))
$script:ui=@{Girl=[Windows.Controls.Image]::new();QuoteText=[Windows.Controls.TextBlock]::new();SceneText=[Windows.Controls.Border]::new()}
$script:status=$null;$script:sceneRevision=0;$script:sceneTimer=$null;$script:collapsed=$true;$script:bubbleMode='quota'
$script:dialogues=[Collections.Generic.Queue[string]]::new()
foreach($text in @('Ciallo～ 今天也请多关照。','小小的成功，也值得开心一下。','休息一下，灵感也要充电。','真当我是便宜货啊...')){$script:dialogues.Enqueue($text)}
function Get-WidgetBubbleQuote($data){return $script:dialogues.Dequeue()}
function Fit-QuoteText {$script:ui.QuoteText.Tag=$script:ui.QuoteText.Text;$script:ui.QuoteText.Text=$script:ui.QuoteText.Text.Replace('，',",`n")}
function Animate-Value {}
function Apply-Scene {$script:appliedMode=$script:bubbleMode}
function Restart-SceneTtl {}
function Wait-SceneRender {
  $frame=[Windows.Threading.DispatcherFrame]::new()
  $stop=[Windows.Threading.DispatcherTimer]::new();$stop.Interval=[TimeSpan]::FromMilliseconds(180)
  $stop.Add_Tick({param($timer,$event)$timer.Stop();$frame.Continue=$false}.GetNewClosure())
  $stop.Start();[Windows.Threading.Dispatcher]::PushFrame($frame)
}
$now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
Initialize-WidgetExpressions $appDir ($now-12000)
Update-WidgetExpression $now
Assert-Equal $script:expressionCurrent happy 'Begin with a visible ambient smile'
foreach($expected in @('happy','wave','wave','cheer','cheer','sleepy')){
  Invoke-WidgetExpressionEvent 'press'
  Invoke-WidgetExpressionEvent 'release'
  $before=$script:expressionCurrent
  Click-Character
  Assert-Equal $script:expressionCurrent $before 'Starting a transition does not flash a new sprite'
  Wait-SceneRender
  Assert-Equal $script:expressionCurrent $expected 'Only rendered dialogue changes the sprite to its paired gesture'
}
Assert-Equal $script:ui.QuoteText.Tag '休息一下，灵感也要充电。' 'Pairing uses the original text before layout inserts line breaks'
Click-Character # Return to quota and keep sleepy.
Wait-SceneRender
Click-Character # Pending pout dialogue is cancelled before it is shown.
Click-Character
Wait-SceneRender
Assert-Equal $script:bubbleMode quota 'Rapid cancellation ends on quota'
Assert-Equal $script:appliedMode quota 'Only the latest scene timer presents content'
Assert-Equal $script:expressionCurrent sleepy 'A cancelled dialogue cannot change the visible sprite'
if($script:sceneTimer){$script:sceneTimer.Stop()}
Write-Output 'PASS: quota/dialogue cycle, paired dialogue gestures, retained quota expressions, canonical text and cancelled rapid scene transitions'
