param([string]$TestRoot=$PSScriptRoot)
$ErrorActionPreference='Stop'
$app=Split-Path $TestRoot -Parent
$module=Join-Path $app 'runtime\headpat.ps1'
if(!(Test-Path -LiteralPath $module)){throw 'Headpat feature missing: deliberate head strokes must be recognized independently of clicks and dragging.'}
. ([ScriptBlock]::Create([IO.File]::ReadAllText($module,[Text.Encoding]::UTF8)))
function Assert-Equal($actual,$expected,[string]$message){if($actual-ne $expected){throw "$message : expected '$expected', got '$actual'"}}
$now=1800000000000L
$state=New-WidgetHeadpatState
Assert-Equal (Update-WidgetHeadpat $state 0.42 0.25 $true $false $now) $false 'One hover cannot trigger a headpat'
foreach($i in 1..12){Assert-Equal (Update-WidgetHeadpat $state (0.42+($i%2)*0.01) 0.25 $true $false ($now+$i*25)) $false 'Mouse jitter is not stroking'}
Reset-WidgetHeadpatGesture $state
foreach($point in @(@(0.38,0),@(0.60,200),@(0.40,400))){Assert-Equal (Update-WidgetHeadpat $state $point[0] 0.25 $true $false ($now+$point[1])) $false 'Wait for three deliberate passes'}
Assert-Equal (Update-WidgetHeadpat $state 0.61 0.25 $true $false ($now+600)) $true 'Three alternating passes trigger one reaction'
Assert-Equal $state.count 1 'One completed gesture is counted once'
foreach($i in 1..20){Assert-Equal (Update-WidgetHeadpat $state (0.38+($i%2)*0.23) 0.25 $true $false ($now+600+$i*100)) $false 'Continued strokes cannot spam dialogue during cooldown'}
Assert-Equal $state.count 1 'Cooldown does not count more reactions'
foreach($scenario in @(@(0.8,$true,$false),@(0.25,$false,$false),@(0.25,$true,$true))){
  $s=New-WidgetHeadpatState
  foreach($i in 0..4){Assert-Equal (Update-WidgetHeadpat $s (0.38+($i%2)*0.23) $scenario[0] $scenario[1] $scenario[2] ($now+$i*200)) $false 'Body, transparent pixels and held buttons cannot trigger'}
}
$s=New-WidgetHeadpatState
foreach($i in 0..4){Assert-Equal (Update-WidgetHeadpat $s (0.38+($i%2)*0.23) 0.25 $true $false ($now+$i*900)) $false 'Separated movements cannot accumulate into a gesture'}
$s=New-WidgetHeadpatState
Update-WidgetHeadpat $s 0.38 0.25 $true $false $now|Out-Null
Update-WidgetHeadpat $s 0.61 0.25 $true $false ($now+200)|Out-Null
Update-WidgetHeadpat $s 0.90 0.25 $true $false ($now+250)|Out-Null
Assert-Equal (Update-WidgetHeadpat $s 0.38 0.25 $true $false ($now+400)) $false 'Leaving the head resets accumulated strokes'
Assert-Equal (Update-WidgetHeadpat $s 0.61 0.25 $true $false ($now+600)) $false 'Reentry requires a new complete gesture'
# The same sprite point is recognized across widget sizes and UniformToFill cropping.
foreach($size in @(104,208,416)){
  $p=ConvertTo-WidgetSpritePoint ($size*0.42) ($size*0.25) $size $size 1254 1254
  if([Math]::Abs($p.x-0.42)-gt 0.00001 -or [Math]::Abs($p.y-0.25)-gt 0.00001){throw 'Head hit region changed with scale'}
}
$p=ConvertTo-WidgetSpritePoint 42 25 100 100 200 100
Assert-Equal ([Math]::Round($p.x,2)) 0.46 'UniformToFill crop is accounted for'
Assert-Equal (ConvertTo-WidgetSpritePoint 0 0 0 0 1254 1254) $null 'Unarranged controls cannot trigger'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
. ([ScriptBlock]::Create([IO.File]::ReadAllText((Join-Path $app 'runtime\expressions.ps1'),[Text.Encoding]::UTF8)))
Initialize-WidgetQuoteExpressions $app
Initialize-WidgetHeadpatQuotes $app
Assert-Equal $script:headpatQuotes.Count 12 'Headpat has twelve dedicated replies'
foreach($row in $script:headpatQuotes){
  Assert-Equal (Get-WidgetQuoteExpression $row.text) $row.expression 'Dedicated replies have exact expression bindings'
  if($row.text-match '小龙|GPT\s*娘'){throw 'Dialogue must use first person, not the character name'}
}
$s=New-WidgetHeadpatState
$last=''
foreach($i in 1..40){
  $row=Get-WidgetHeadpatQuote $s
  if($row.text-eq $last){throw 'Headpat must avoid the previous reply'}
  $last=$row.text
}
# Exercise the production scene adapter and real WPF presentation, including overriding an open quota/dialogue.
$source=[IO.File]::ReadAllText((Join-Path $app 'widget.ps1'),[Text.Encoding]::UTF8)
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors|Out-String)}
foreach($name in @('Invoke-WidgetHeadpat','Click-Character','Apply-Scene','Switch-Scene','Show-WidgetScene','Hide-Quota')){
  $definition=$ast.Find({param($node)$node-is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name-eq $name},$true)
  if(!$definition){throw ('Missing production headpat adapter: '+$name)}
  . ([ScriptBlock]::Create($definition.Extent.Text))
}
$script:window=[Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText((Join-Path $app 'widget.xaml'),[Text.Encoding]::UTF8))
$script:ui=@{}
foreach($name in @('Girl','PressScale','QuoteText','SceneText','Bubble','Tail','TailNear','QuotaText','Refresh','LiveDot')){$script:ui[$name]=$script:window.FindName($name)}
$script:status=$null;$script:widgetColors=$null;$script:sceneRevision=0;$script:bubbleEpoch=0;$script:sceneTimer=$null;$script:collapsed=$true;$script:bubbleMode='quota'
$script:headpatState=New-WidgetHeadpatState
$script:refreshCount=0
function Animate-Value {}
function Set-AnimatedValue {}
function Animate-Headpat {}
function Set-WidgetSceneLayout {}
function Update-BubbleTooltip {}
function Fit-QuoteText {$script:ui.QuoteText.Tag=$script:ui.QuoteText.Text}
function Restart-SceneTtl {}
function Save-Settings {}
function Set-BubbleState {}
function Get-WidgetBubbleQuote {throw 'Headpat must use its own contextual pool'}
function Request-Refresh {$script:refreshCount++}
function Wait-SceneRender {
  $frame=[Windows.Threading.DispatcherFrame]::new()
  $stop=[Windows.Threading.DispatcherTimer]::new();$stop.Interval=[TimeSpan]::FromMilliseconds(180)
  $stop.Add_Tick({param($timer,$event)$timer.Stop();$frame.Continue=$false}.GetNewClosure())
  $stop.Start();[Windows.Threading.Dispatcher]::PushFrame($frame)
}
Initialize-WidgetExpressions $app $now
try{
  foreach($mode in @('closed','quota','quote')){
    if($mode-eq 'closed'){$script:collapsed=$true}else{$script:collapsed=$false;$script:bubbleMode=$mode}
    Invoke-WidgetHeadpat
    Wait-SceneRender
    Assert-Equal $script:bubbleMode quote 'Headpat opens a dedicated reply from any scene'
    Assert-Equal $script:sceneOrigin headpat 'Headpat is a distinct scene origin'
    Assert-Equal $script:expressionCurrent (Get-WidgetQuoteExpression $script:ui.QuoteText.Tag) 'Rendered headpat expression matches its actual reply'
    Assert-Equal $script:refreshCount 0 'Headpat never refreshes quota or calls a model'
    Click-Character
    Wait-SceneRender
    Assert-Equal $script:bubbleMode quota 'A normal click after headpat returns to quota'
  }
  Hide-Quota
  Assert-Equal $script:expressionState.quoteExpression '' 'Closing the headpat reply releases its expression'
  $liveNow=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $script:status=@{ok=$true;queryOk=$true;observedAt=$liveNow;windows=@(@{remaining=10;resetsAt=[Math]::Floor($liveNow/1000)+3600})}
  Invoke-WidgetHeadpat
  Wait-SceneRender
  Assert-Equal $script:expressionCurrent (Get-WidgetQuoteExpression $script:ui.QuoteText.Tag) 'Headpat replies own their expression even at low quota'
  Hide-Quota
  Assert-Equal $script:expressionCurrent worried 'After headpat closes the low-quota reminder resumes'
  $script:expressionState.mode='cheer'
  Invoke-WidgetHeadpat
  Wait-SceneRender
  Assert-Equal $script:expressionCurrent cheer 'Headpat respects a manually fixed expression'
  Hide-Quota
  $script:expressionState.mode='auto';$script:status=$null
  # Route unpressed movement through the real handler with a real decoded alpha mask.
  $assignment=$ast.Find({param($node)$node-is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text-eq '$pressMove'},$true)
  $move=[ScriptBlock]::Create($assignment.Right.Extent.Text.Trim().TrimStart('{').TrimEnd('}'))
  $script:window.Content.Measure([Windows.Size]::new(378,378));$script:window.Content.Arrange([Windows.Rect]::new(0,0,378,378));$script:window.Content.UpdateLayout()
  $script:headpatState=New-WidgetHeadpatState;$script:drag=$null;$script:context=[pscustomobject]@{IsOpen=$false}
  $script:quoteEditor=$null;$script:colorTriggerEditor=$null
  foreach($x in @(0.38,0.61,0.38,0.61)){
    $event=[pscustomobject]@{point=[Windows.Point]::new($script:ui.Girl.ActualWidth*$x,$script:ui.Girl.ActualHeight*0.25)}
    $event|Add-Member -MemberType ScriptMethod -Name GetPosition -Value {param($control)return $this.point}
    & $move $script:ui.Girl $event
    Wait-SceneRender
  }
  Assert-Equal $script:headpatState.count 1 'Production mouse handler detects one full headpat'
  Assert-Equal $script:sceneOrigin headpat 'Mouse handler presents the contextual scene'
  # The motion returns to unit scale instead of changing the stored widget size.
  $definition=$ast.Find({param($node)$node-is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name-eq 'Animate-Headpat'},$true)
  . ([ScriptBlock]::Create($definition.Extent.Text))
  Animate-Headpat
  foreach($i in 1..4){Wait-SceneRender}
  if([Math]::Abs($script:ui.PressScale.ScaleX-1)-gt 0.001 -or [Math]::Abs($script:ui.PressScale.ScaleY-1)-gt 0.001){throw 'Headpat motion must return to the original scale'}
}finally{
  if($script:sceneTimer){$script:sceneTimer.Stop()}
  if($script:closeTimer){$script:closeTimer.Stop()}
  $script:window.Close()
}
Write-Output 'PASS: deliberate head strokes, scale-independent region, jitter/drag/alpha exclusion, cooldown, contextual replies and paired WPF scene transitions'
