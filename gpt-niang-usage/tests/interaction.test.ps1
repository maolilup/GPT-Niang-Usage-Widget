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
foreach($name in @('Switch-Scene','Apply-Scene','Show-Quota','Hide-Quota')){
  $definition=$ast.Find({param($node)$node-is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name-eq $name},$true)
  . ([ScriptBlock]::Create($definition.Extent.Text))
}
$script:window=[Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText((Join-Path $appDir 'widget.xaml'),[Text.Encoding]::UTF8))
$script:ui=@{}
foreach($name in @('Girl','QuoteText','SceneText','Bubble','Tail','TailNear','QuotaText','Refresh','LiveDot')){$script:ui[$name]=$script:window.FindName($name)}
$script:status=$null;$script:sceneRevision=0;$script:sceneTimer=$null;$script:collapsed=$true;$script:bubbleMode='quota'
$script:dialogues=[Collections.Generic.Queue[string]]::new()
foreach($text in @('Ciallo～ 今天也请多关照。','小小的成功，也值得开心一下。','休息一下，灵感也要充电。','真当我是便宜货啊...','不会也没关系，从一个例子开始。')){$script:dialogues.Enqueue($text)}
function Get-WidgetBubbleQuote($data){return $script:dialogues.Dequeue()}
function Fit-QuoteText {$script:ui.QuoteText.Tag=$script:ui.QuoteText.Text;$script:ui.QuoteText.Text=$script:ui.QuoteText.Text.Replace('，',",`n")}
function Animate-Value {}
function Set-AnimatedValue {}
function Set-WidgetSceneLayout {$script:appliedMode=$script:bubbleMode}
function Update-BubbleTooltip {}
function Save-Settings {}
function Request-Refresh {Invoke-WidgetExpressionEvent 'refresh'}
function Set-BubbleState {}
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
$script:status=@{ok=$true;queryOk=$true;observedAt=$now;windows=@(@{remaining=10;resetsAt=[Math]::Floor($now/1000)+3600})}
foreach($expected in @('worried','wave','worried','cheer','worried','sleepy')){
  Invoke-WidgetExpressionEvent 'press'
  Invoke-WidgetExpressionEvent 'release'
  $before=$script:expressionCurrent
  $wasCollapsed=$script:collapsed
  Click-Character
  if(!$wasCollapsed){Assert-Equal $script:expressionCurrent $before 'Starting a transition does not flash a new sprite'}
  Wait-SceneRender
  Assert-Equal $script:expressionCurrent $expected 'Rendered dialogue uses its paired gesture; quota uses its own reminder'
}
Assert-Equal $script:ui.QuoteText.Tag '休息一下，灵感也要充电。' 'Pairing uses the original text before layout inserts line breaks'
Click-Character # Return to the independent low-quota reminder.
Wait-SceneRender
Click-Character # Pending pout dialogue is cancelled before it is shown.
Click-Character
Wait-SceneRender
Assert-Equal $script:bubbleMode quota 'Rapid cancellation ends on quota'
Assert-Equal $script:appliedMode quota 'Only the latest scene timer presents content'
Assert-Equal $script:expressionCurrent worried 'A cancelled dialogue cannot change the quota reminder'
Click-Character
Wait-SceneRender
Assert-Equal $script:expressionCurrent comfort 'A reassuring dialogue replaces the low-quota reminder while it is visible'
Hide-Quota
Assert-Equal $script:expressionCurrent worried 'The production close handler immediately restores the quota reminder'
$script:status=@{ok=$true;queryOk=$true;observedAt=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();windows=@(@{remaining=80;resetsAt=[Math]::Floor($now/1000)+3600})}
Update-WidgetExpression
Assert-Equal $script:expressionCurrent neutral 'After quota recovers a closed dialogue does not leak its expression'
if($script:sceneTimer){$script:sceneTimer.Stop()}
if($script:closeTimer){$script:closeTimer.Stop()}
$script:window.Close()
Write-Output 'PASS: quota/dialogue cycle, independent low-quota reminder, paired dialogue gestures, scene close, canonical text and cancelled rapid transitions'
