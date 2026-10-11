param([string]$TestRoot=$PSScriptRoot)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$app=Split-Path $TestRoot -Parent
. ([ScriptBlock]::Create([IO.File]::ReadAllText((Join-Path $app 'runtime\expressions.ps1'),[Text.Encoding]::UTF8)))
$module=Join-Path $app 'runtime\low-quota.ps1'
if(!(Test-Path -LiteralPath $module)){throw 'Low-quota contextual dialogue feature is missing'}
. ([ScriptBlock]::Create([IO.File]::ReadAllText($module,[Text.Encoding]::UTF8)))
function Assert-Equal($actual,$expected,[string]$message){if($actual-ne $expected){throw "$message : expected '$expected', got '$actual'"}}
$now=1800000000000L
function Snapshot($remaining,[long]$at=$now){@{ok=$true;queryOk=$true;observedAt=$at;windows=@(@{remaining=$remaining;resetsAt=[Math]::Floor($at/1000)+3600})}}
foreach($pair in @(@(50,'normal'),@(20,'normal'),@(19.9,'low'),@(5,'critical'),@(0.1,'critical'),@(0,'empty'))){
  Assert-Equal (Get-WidgetQuotaLevel (Snapshot $pair[0]) $now) $pair[1] 'Low-quota severity boundaries'
}
Assert-Equal (Get-WidgetQuotaLevel (Snapshot 10 ($now-180001)) $now) unknown 'Stale data never triggers a warning'
Assert-Equal (Get-WidgetQuotaLevel (Snapshot 10 ($now+1)) $now) unknown 'Future observations never trigger'
$bad=Snapshot 0;$bad.queryOk=$false
Assert-Equal (Get-WidgetQuotaLevel $bad $now) unknown 'Failed queries never trigger'
$expired=Snapshot 0;$expired.windows[0].resetsAt=[Math]::Floor($now/1000)
Assert-Equal (Get-WidgetQuotaLevel $expired $now) unknown 'Expired windows never trigger'
$multi=Snapshot 80;$multi.windows+=@{remaining=2;resetsAt=$null}
Assert-Equal (Get-WidgetQuotaLevel $multi $now) critical 'The lowest valid window determines severity'
$s=New-WidgetLowQuotaState
Assert-Equal (Update-WidgetLowQuotaDialogue $s (Snapshot 80) $now $true) $false 'Normal quota is silent'
Assert-Equal (Update-WidgetLowQuotaDialogue $s (Snapshot 15 ($now+1)) ($now+1) $false) $false 'Manual reading or a hidden host defers a new warning'
Assert-Equal $s.pending $true 'A new low-quota warning remains pending'
Assert-Equal (Update-WidgetLowQuotaDialogue $s (Snapshot 15 ($now+2)) ($now+2) $true) $true 'The pending warning opens once ready'
Assert-Equal $s.count 1 'Opening is counted once'
foreach($offset in @(3,1000,100000,180001)){
  Assert-Equal (Update-WidgetLowQuotaDialogue $s (Snapshot 15 ($now+$offset)) ($now+$offset) $true) $false 'Status polling cannot spam reminders'
}
Assert-Equal (Update-WidgetLowQuotaDialogue $s (Snapshot 15 ($now+180002)) ($now+180002) $true) $true 'Persistent low quota can remind after three minutes'
Assert-Equal (Update-WidgetLowQuotaDialogue $s (Snapshot 4 ($now+180003)) ($now+180003) $true) $true 'A newly critical quota has its own warning'
Assert-Equal (Update-WidgetLowQuotaDialogue $s (Snapshot 0 ($now+180004)) ($now+180004) $true) $true 'Newly depleted quota has its own reply pool'
$s=New-WidgetLowQuotaState
Update-WidgetLowQuotaDialogue $s (Snapshot 10) $now $true|Out-Null
Update-WidgetLowQuotaDialogue $s $null ($now+1000) $true|Out-Null
Assert-Equal (Update-WidgetLowQuotaDialogue $s (Snapshot 10 ($now+2000)) ($now+2000) $true) $false 'A temporary missing snapshot does not count as recovery'
Assert-Equal (Update-WidgetLowQuotaDialogue $s (Snapshot 80 ($now+2001)) ($now+2001) $true) $false 'Confirmed recovery re-arms without talking'
Assert-Equal (Update-WidgetLowQuotaDialogue $s (Snapshot 10 ($now+2002)) ($now+2002) $true) $true 'A new low episode triggers again'
Initialize-WidgetQuoteExpressions $app
Initialize-WidgetLowQuotaQuotes $app
Assert-Equal $script:lowQuotaQuotes.Count 9 'Nine contextual replies are bundled'
$s=New-WidgetLowQuotaState
foreach($level in @('low','critical','empty')){
  $last=''
  foreach($i in 1..15){
    $row=Get-WidgetLowQuotaQuote $s $level
    Assert-Equal $row.level $level 'Only severity-appropriate replies are picked'
    Assert-Equal (Get-WidgetQuoteExpression $row.text) worried 'Low-quota dialogue uses a matching worried pose'
    if($row.text-eq $last){throw 'Low-quota replies cannot immediately repeat'}
    if($row.text-match '小龙|GPT\s*娘'){throw 'Replies must not use character names'}
    $last=$row.text
  }
}
# Exercise the production timer gates, including manual/headpat ownership and disabled auto dialogue.
$source=[IO.File]::ReadAllText((Join-Path $app 'widget.ps1'),[Text.Encoding]::UTF8)
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors|Out-String)}
$definition=$ast.Find({param($node)$node-is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name-eq 'Tick-LowQuotaDialogue'},$true)
if(!$definition){throw 'Missing low-quota production timer'}
. ([ScriptBlock]::Create($definition.Extent.Text))
$script:window=[pscustomobject]@{IsVisible=$true}
$script:context=[pscustomobject]@{IsOpen=$false}
$script:expressionState=New-WidgetExpressionState ($now-10000)
$script:headpatState=@{strokes=0};$script:autoDialogueEnabled=$true;$script:drag=$null
$script:quoteEditor=$null;$script:colorTriggerEditor=$null
$script:collapsed=$true;$script:sceneOrigin='manual';$script:status=Snapshot 15;$script:lowQuotaState=New-WidgetLowQuotaState
$script:opens=0;$script:closes=0
function Show-LowQuotaQuote {$script:opens++;$script:collapsed=$false;$script:sceneOrigin='low-quota'}
function Hide-Quota {$script:closes++;$script:collapsed=$true;$script:sceneOrigin='manual'}
Tick-LowQuotaDialogue $now $true $true
Assert-Equal $script:opens 1 'A fresh low snapshot triggers the timer'
Tick-LowQuotaDialogue ($now+1) $true $true
Assert-Equal $script:opens 1 'An open warning cannot be replaced'
$script:status=Snapshot 80 ($now+2)
Tick-LowQuotaDialogue ($now+2) $true $true
Assert-Equal $script:closes 1 'Recovery closes an automatic warning'
foreach($origin in @('manual','headpat')){
  $script:collapsed=$false;$script:sceneOrigin=$origin;$script:lowQuotaState=New-WidgetLowQuotaState;$script:status=Snapshot 10
  $before=$script:opens
  Tick-LowQuotaDialogue $now $true $true
  Assert-Equal $script:opens $before 'A low warning never overwrites a user-owned scene'
  Assert-Equal $script:closes 1 'User-owned scenes are not closed by quota recovery or warning logic'
}
foreach($reason in @('hidden','inactive','disabled','menu','drag','press','editor','refresh','recent','stroking')){
  $script:collapsed=$true;$script:sceneOrigin='manual';$script:lowQuotaState=New-WidgetLowQuotaState;$script:status=Snapshot 10
  $script:autoDialogueEnabled=$true;$script:context.IsOpen=$false;$script:drag=$null;$script:quoteEditor=$null
  $script:expressionState=New-WidgetExpressionState ($now-10000);$script:headpatState.strokes=0
  $visible=$true;$active=$true
  switch($reason){
    hidden {$visible=$false}
    inactive {$active=$false}
    disabled {$script:autoDialogueEnabled=$false}
    menu {$script:context.IsOpen=$true}
    drag {$script:drag=@{moved=$true}}
    press {$script:expressionState.pressed=$true}
    editor {$script:quoteEditor=[pscustomobject]@{IsVisible=$true}}
    refresh {$script:expressionState.refreshAt=$now}
    recent {$script:expressionState.lastActiveAt=$now}
    stroking {$script:headpatState.strokes=1;$script:headpatState.lastAt=$now}
  }
  $before=$script:opens
  Tick-LowQuotaDialogue $now $visible $active
  Assert-Equal $script:opens $before ('A blocked low warning is deferred: '+$reason)
  Assert-Equal $script:lowQuotaState.pending $true 'The pending episode survives temporary UI blockers'
}
$before=$script:opens
Tick-LowQuotaDialogue ($now+1500) $true $true
Assert-Equal $script:opens ($before+1) 'An unfinished stroke cannot pause quota reminders indefinitely'
# Verify the real opener uses contextual text and a matching expression, without a quota refresh.
foreach($name in @('Show-LowQuotaQuote','Show-WidgetScene','Apply-Scene')){
  $definition=$ast.Find({param($node)$node-is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name-eq $name},$true)
  . ([ScriptBlock]::Create($definition.Extent.Text))
}
$script:window=[Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText((Join-Path $app 'widget.xaml'),[Text.Encoding]::UTF8))
$script:ui=@{}
foreach($name in @('Girl','QuoteText','SceneText','Bubble','Tail','TailNear','QuotaText','Refresh','LiveDot')){$script:ui[$name]=$script:window.FindName($name)}
$script:status=$null;$script:widgetColors=$null;$script:sceneTimer=$null;$script:closeTimer=$null;$script:refreshes=0
function Fit-QuoteText {$script:ui.QuoteText.Tag=$script:ui.QuoteText.Text}
function Animate-Value {}
function Set-AnimatedValue {}
function Set-WidgetSceneLayout {}
function Update-BubbleTooltip {}
function Save-Settings {}
function Request-Refresh {$script:refreshes++}
function Restart-SceneTtl([int]$renderDelay){$script:sceneDeadline=1000+$renderDelay+5000}
function Get-WidgetBubbleQuote {throw 'Low-quota warnings must never use the everyday pool'}
Initialize-WidgetExpressions $app
try{
  foreach($level in @('low','critical','empty')){
    $script:collapsed=$true;$script:lowQuotaState=New-WidgetLowQuotaState;$script:lowQuotaState.level=$level
    Show-LowQuotaQuote
    Assert-Equal $script:sceneOrigin low-quota 'Contextual scenes retain their origin'
    Assert-Equal $script:bubbleMode quote 'Warnings show dialogue directly'
    Assert-Equal $script:expressionCurrent worried 'Low-quota dialogue displays its paired worried pose'
    Assert-Equal $script:refreshes 0 'Warnings do not request extra quota refreshes'
    $row=$script:lowQuotaQuotes|Where-Object{$_.text-eq $script:ui.QuoteText.Tag}
    Assert-Equal $row.level $level 'The opener chooses text appropriate to the remaining quota'
  }
}finally{$script:window.Close()}
Write-Output 'PASS: low-quota severity, stale/error/reset exclusions, deferred triggering, cooldown, recovery, contextual replies and production timer/scene gates'
