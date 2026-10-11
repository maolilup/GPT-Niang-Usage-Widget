param([string]$TestRoot=$PSScriptRoot)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$app=Split-Path $TestRoot -Parent
$source=[IO.File]::ReadAllText((Join-Path $app 'widget.ps1'),[Text.Encoding]::UTF8)
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors|Out-String)}
foreach($name in @('Get-AmbientQuoteDelay','Reset-AmbientQuoteTimer','Tick-AmbientQuote')){
  $definition=$ast.Find({param($node)$node-is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name-eq $name},$true)
  if(!$definition){throw ('Missing automatic dialogue function: '+$name)}
  . ([ScriptBlock]::Create($definition.Extent.Text))
}
. ([ScriptBlock]::Create([IO.File]::ReadAllText((Join-Path $app 'runtime\expressions.ps1'),[Text.Encoding]::UTF8)))
function Assert-Equal($actual,$expected,[string]$message){if($actual-ne $expected){throw "$message : expected '$expected', got '$actual'"}}
$draws=@{}
foreach($i in 1..1000){$delay=Get-AmbientQuoteDelay;$draws[$delay]=$true;if($delay-lt 45000 -or $delay-gt 90000){throw 'Automatic dialogue interval escaped its 45-90 second bounds'}}
if($draws.Count-lt 2){throw 'Automatic dialogue interval must vary rather than use a fixed delay'}
function Get-AmbientQuoteDelay {return 60000L}
$now=1800000000000L
$script:autoDialogueEnabled=$true;$script:ambientQuoteState=$null
$script:expressionState=New-WidgetExpressionState $now
$script:window=[pscustomobject]@{IsVisible=$true}
$script:context=[pscustomobject]@{IsOpen=$false}
$script:quoteEditor=$null;$script:colorTriggerEditor=$null;$script:drag=$null
$script:collapsed=$true;$script:sceneOrigin='manual';$script:status=$null
$script:opens=0;$script:closes=0
function Show-AmbientQuote {$script:opens++;$script:collapsed=$false;$script:sceneOrigin='ambient'}
function Hide-Quota {$script:closes++;$script:collapsed=$true;$script:sceneOrigin='manual'}
Tick-AmbientQuote $now $true $true
Assert-Equal $script:ambientQuoteState.nextAt ($now+60000) 'First automatic dialogue waits for its randomized deadline'
Tick-AmbientQuote ($now+59999) $true $true
Assert-Equal $script:opens 0 'No early dialogue'
Tick-AmbientQuote ($now+60000) $true $true
Assert-Equal $script:opens 1 'Idle deadline opens one dialogue'
Assert-Equal $script:ambientQuoteState.count 1 'Opening is counted once'
Tick-AmbientQuote ($now+120000) $true $true
Assert-Equal $script:opens 1 'An open dialogue cannot be overwritten by another automatic dialogue'

# Every pause resumes with a fresh interval rather than a burst of missed messages.
foreach($reason in @('hidden','inactive','window','menu','drag','press','editor','colorEditor','bubble','refresh','low','disabled')){
  $script:collapsed=$true;$script:sceneOrigin='manual';$script:status=$null;$script:drag=$null
  $script:expressionState=New-WidgetExpressionState $now
  $script:autoDialogueEnabled=$true;$script:window.IsVisible=$true;$script:context.IsOpen=$false
  $script:quoteEditor=$null;$script:colorTriggerEditor=$null;$script:ambientQuoteState=$null
  Reset-AmbientQuoteTimer $now
  $visible=$true;$active=$true
  switch($reason){
    hidden {$visible=$false}
    inactive {$active=$false}
    window {$script:window.IsVisible=$false}
    menu {$script:context.IsOpen=$true}
    drag {$script:drag=@{active=$true}}
    press {$script:expressionState.pressed=$true}
    editor {$script:quoteEditor=[pscustomobject]@{IsVisible=$true}}
    colorEditor {$script:colorTriggerEditor=[pscustomobject]@{IsVisible=$true}}
    bubble {$script:collapsed=$false}
    refresh {$script:expressionState.refreshAt=$now}
    low {$script:status=@{ok=$true;queryOk=$true;observedAt=$now+60000;windows=@(@{remaining=10;resetsAt=$null})}}
    disabled {$script:autoDialogueEnabled=$false}
  }
  $before=$script:opens
  Tick-AmbientQuote ($now+60000) $visible $active
  Assert-Equal $script:opens $before ('Blocked automatic dialogue: '+$reason)
  Assert-Equal $script:ambientQuoteState.nextAt 0 ('Paused timer has no pending catch-up: '+$reason)
  $script:collapsed=$true;$script:status=$null;$script:drag=$null;$script:expressionState.pressed=$false;$script:expressionState.refreshAt=0L
  $script:autoDialogueEnabled=$true;$script:window.IsVisible=$true;$script:context.IsOpen=$false;$script:quoteEditor=$null;$script:colorTriggerEditor=$null
  Tick-AmbientQuote ($now+60001) $true $true
  Assert-Equal $script:ambientQuoteState.nextAt ($now+120001) ('Resuming starts a fresh interval: '+$reason)
}
$script:expressionState.lastActiveAt=$now+60002
Tick-AmbientQuote ($now+120000) $true $true
Assert-Equal $script:ambientQuoteState.nextAt ($now+180000) 'Recent character activity restarts the interval'
$script:collapsed=$false;$script:sceneOrigin='ambient'
$script:status=@{ok=$true;queryOk=$true;observedAt=$now+120001;windows=@(@{remaining=0;resetsAt=$null})}
Tick-AmbientQuote ($now+120001) $true $true
Assert-Equal $script:closes 1 'New low quota closes an automatic dialogue to restore the reminder'
$script:collapsed=$false;$script:sceneOrigin='manual'
Tick-AmbientQuote ($now+120002) $true $true
Assert-Equal $script:closes 1 'Low quota never closes a manually requested dialogue'

# The production opener starts directly with a paired quote and five seconds of reading time.
foreach($name in @('Show-WidgetScene','Show-AmbientQuote','Show-Quota','Click-Character','Apply-Scene')){
  $definition=$ast.Find({param($node)$node-is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name-eq $name},$true)
  . ([ScriptBlock]::Create($definition.Extent.Text))
}
$script:window=[Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText((Join-Path $app 'widget.xaml'),[Text.Encoding]::UTF8))
$script:ui=@{}
foreach($name in @('Girl','QuoteText','SceneText','Bubble','Tail','TailNear','QuotaText','Refresh','LiveDot')){$script:ui[$name]=$script:window.FindName($name)}
$script:status=$null;$script:collapsed=$true;$script:sceneTimer=$null;$script:closeTimer=$null;$script:refreshes=0
function Get-WidgetBubbleQuote {return '挥挥手，给认真工作的你。'}
function Fit-QuoteText {$script:ui.QuoteText.Tag=$script:ui.QuoteText.Text}
function Animate-Value {}
function Set-AnimatedValue {}
function Set-WidgetSceneLayout {}
function Update-BubbleTooltip {}
function Save-Settings {}
function Request-Refresh {$script:refreshes++}
function Restart-SceneTtl([int]$renderDelay){$script:testReadableAt=1000+$renderDelay;$script:sceneDeadline=$script:testReadableAt+5000}
function Switch-Scene($mode){$script:bubbleMode=$mode}
Initialize-WidgetExpressions $app
Show-AmbientQuote
Assert-Equal $script:bubbleMode quote 'Automatic dialogue opens a quote directly'
Assert-Equal $script:sceneOrigin ambient 'Automatic scenes retain their origin'
Assert-Equal $script:expressionCurrent wave 'Automatic dialogue shows its explicitly paired gesture'
Assert-Equal $script:ui.QuotaText.Visibility ([Windows.Visibility]::Collapsed) 'Automatic dialogue never flashes the quota page'
Assert-Equal ($script:sceneDeadline-$script:testReadableAt) 5000 'Opening animation is excluded from five-second reading time'
Assert-Equal $script:refreshes 0 'Automatic dialogue does not request a quota refresh'
Click-Character
Assert-Equal $script:bubbleMode quota 'A character click still switches from automatic dialogue to quota'
Assert-Equal $script:sceneOrigin manual 'A user click takes ownership of the scene'
$script:window.Close()
Write-Output 'PASS: randomized idle dialogue, interaction reset, visibility and low-quota pause, direct paired opening, reading lifetime and manual takeover'
