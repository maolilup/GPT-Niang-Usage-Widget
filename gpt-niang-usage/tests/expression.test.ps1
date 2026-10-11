param([string]$TestRoot=$PSScriptRoot)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$appDir=Split-Path $TestRoot -Parent
$module=Join-Path $appDir 'runtime\expressions.ps1'
if(!(Test-Path -LiteralPath $module)){throw 'Expression feature missing: runtime/expressions.ps1 must provide deterministic selection and sprite swapping.'}
. ([ScriptBlock]::Create([IO.File]::ReadAllText($module,[Text.Encoding]::UTF8)))
function Assert-Equal($actual,$expected,[string]$message){if($actual-ne $expected){throw "$message : expected '$expected', got '$actual'"}}
function Assert-Same($actual,$expected,[string]$message){if(![Object]::ReferenceEquals($actual,$expected)){throw $message}}
function New-Snapshot($remaining,[long]$at=$now){@{ok=$true;queryOk=$true;observedAt=$at;windows=@(@{remaining=$remaining;resetsAt=[Math]::Floor($now/1000)+3600})}}
$now=1800000000000L
$script:ui=@{Girl=[Windows.Controls.Image]::new()}
Initialize-WidgetExpressions $appDir $now
Assert-Equal $script:expressionMode auto 'Default selection is automatic'
Assert-Equal $script:expressionCurrent neutral 'Default sprite is original'
Assert-Equal @(Get-WidgetExpressionRegistry).Count 11 'Registry includes neutral and ten expressions'
Assert-Equal (Resolve-WidgetExpressionMode 'bad') auto 'Unknown persisted modes recover to automatic'
Assert-Equal (Resolve-WidgetExpressionMode 'cheer') cheer 'Gesture modes are registered even if optional art is absent'
$state=New-WidgetExpressionState $now
Assert-Equal (Get-WidgetExpressionName $state $null ($now+11999)) neutral 'Normal pose gets a calm initial hold'
Assert-Equal (Get-WidgetExpressionName $state $null ($now+12000)) happy 'Normal idle includes a smiling pose'
Assert-Equal (Get-WidgetExpressionName $state $null ($now+18000)) neutral 'Normal idle returns to the original pose'
Assert-Equal (Get-WidgetExpressionName $state $null ($now+28000)) shy 'Normal idle varies facial expressions'
Assert-Equal (Get-WidgetExpressionName $state $null ($now+44000)) comfort 'Normal idle includes a hand gesture'
Assert-Equal (Get-WidgetExpressionName $state $null ($now+64000)) wave 'Normal idle occasionally waves'
Assert-Equal (Get-WidgetExpressionName $state $null ($now+120000)) sleepy 'Idle deadline is deterministic'
Assert-Equal (Get-WidgetExpressionName $state $null ($now+138000)) neutral 'Resting idle also changes pose'
Assert-Equal (Get-WidgetExpressionName $state $null ($now+148000)) comfort 'Resting idle does not freeze indefinitely'
# Dialogue semantics replace the old independent click/quote pose rotations.
$builtIn=[IO.File]::ReadAllText((Join-Path $appDir 'assets\quotes.json'),[Text.Encoding]::UTF8)|ConvertFrom-Json
foreach($row in $builtIn.quotes){
  if(!$row.expression -or $row.expression-notin @((Get-WidgetExpressionRegistry).name)){throw 'Every built-in quote needs a registered expression'}
  Assert-Equal (Get-WidgetQuoteExpression $row.text) $row.expression 'Built-in pairing survives quote normalization'
}
Assert-Equal (Get-WidgetQuoteExpression 'Ciallo～ 今天也请多关照。') wave 'Greeting waves'
Assert-Equal (Get-WidgetQuoteExpression '小小的成功，也值得开心一下。') cheer 'Success celebrates'
Assert-Equal (Get-WidgetQuoteExpression '休息一下，灵感也要充电。') sleepy 'Resting dialogue looks sleepy'
Assert-Equal (Get-WidgetQuoteExpression '  我在看额度。你在看我。各忙各的。  ') shy 'Canonical text is trimmed before pairing'
Assert-Equal (Get-WidgetQuoteExpression '辛苦啦，休息一下吧') sleepy 'Custom resting text gets a matching mood'
Assert-Equal (Get-WidgetQuoteExpression '不怕，我们慢慢来') comfort 'Custom reassurance uses the comforting gesture'
Assert-Equal (Get-WidgetQuoteExpression '自定义的一句话') happy 'Unclassified custom text has a calm friendly fallback'
Assert-Equal (Get-WidgetQuoteExpression '') happy 'Missing text has a safe fallback'
Assert-Equal (Get-WidgetQuoteExpression '你说得对。……这次是真的。') neutral 'Deadpan agreement is neutral rather than bashful'
Assert-Equal (Get-WidgetQuoteExpression '我是啥龙？') thinking 'An identity question is curious rather than startled'
Assert-Equal (Get-WidgetQuoteExpression '突然夸我，我还没准备好呢。') shy 'An embarrassed response uses the blushing pose'
Assert-Equal (Get-WidgetQuoteExpression '握拳！为今天的进步庆祝一下。') cheer 'Fist-raised celebration uses the cheering gesture'
Assert-Equal (Get-WidgetQuoteExpression '抱起手了。这次得听我说完。') pout 'Folded arms use the grumpy gesture'
Assert-Equal (Get-WidgetQuoteExpression '合起手给你打气，这次也陪你慢慢来。') comfort 'Clasped hands use the reassuring gesture'
Register-WidgetExpressionEvent $state 'click' ($now+120000) -CurrentExpression sleepy
Assert-Equal (Get-WidgetExpressionName $state $null ($now+120001)) sleepy 'Quota click preserves the current ambient pose'
Register-WidgetExpressionEvent $state 'quote' ($now+120100) -Quote 'Ciallo～ 今天也请多关照。'
Assert-Equal (Get-WidgetExpressionName $state $null ($now+120100)) wave 'Dialogue replaces the preserved pose with its matching gesture'
for($offset=120200;$offset-le 121000;$offset+=100){
  Register-WidgetExpressionEvent $state 'press' ($now+$offset) -CurrentExpression wave
  Assert-Equal (Get-WidgetExpressionName $state $null ($now+$offset+50)) wave 'Brief presses do not flash another sprite'
  Register-WidgetExpressionEvent $state 'release' ($now+$offset+60) -CurrentExpression wave
  Register-WidgetExpressionEvent $state 'click' ($now+$offset+60) -CurrentExpression wave
  Assert-Equal (Get-WidgetExpressionName $state $null ($now+$offset+60)) wave 'Repeated quota clicks preserve the dialogue pose'
}
Register-WidgetExpressionEvent $state 'quote' ($now+121100) -Quote '小小的成功，也值得开心一下。'
Assert-Equal (Get-WidgetExpressionName $state $null ($now+121100)) cheer 'A new dialogue changes the matching gesture even inside the previous hold'
Register-WidgetExpressionEvent $state 'click' ($now+121200) -CurrentExpression cheer
Register-WidgetExpressionEvent $state 'quota' ($now+121200)
Assert-Equal (Get-WidgetExpressionName $state $null ($now+121200)) cheer 'Returning to quota retains the last dialogue pose'
Assert-Equal (Get-WidgetExpressionName $state $null ($now+126599)) cheer 'Dialogue pose lasts through the bubble fade and full reading time'
Assert-Equal (Get-WidgetExpressionName $state $null ($now+126600)) neutral 'After the dialogue hold, daily variation resumes'

# The actual event adapter must capture the displayed sprite before resetting the idle clock.
Initialize-WidgetExpressions $appDir $now
Update-WidgetExpression ($now+12000)
Assert-Equal $script:expressionCurrent happy 'Fixture is in an ambient smile'
Invoke-WidgetExpressionEvent 'press' ($now+12001)
Invoke-WidgetExpressionEvent 'release' ($now+12030)
Invoke-WidgetExpressionEvent 'click' ($now+12030)
Assert-Equal $script:expressionCurrent happy 'Real quota click does not reset an ambient smile to neutral'
Invoke-WidgetExpressionEvent 'quote' ($now+12100) -Quote '我在看额度。你在看我。各忙各的。'
Assert-Equal $script:expressionCurrent shy 'Real dialogue event applies the paired sprite'
Invoke-WidgetExpressionEvent 'click' ($now+12200)
Invoke-WidgetExpressionEvent 'quota' ($now+12200)
Assert-Equal $script:expressionCurrent shy 'Real quota return does not change the paired sprite'

# Quota reminders and dialogue poses belong to separate display states.
$state=New-WidgetExpressionState $now
$low=New-Snapshot 10
Register-WidgetExpressionEvent $state 'click' $now -CurrentExpression happy
Assert-Equal (Get-WidgetExpressionName $state $low ($now+1)) worried 'Low quota immediately overrides a preserved ambient smile'
Register-WidgetExpressionEvent $state 'refresh' ($now+2)
Assert-Equal (Get-WidgetExpressionName $state $low ($now+3)) worried 'Refreshing does not interrupt an existing low-quota reminder'
Register-WidgetExpressionEvent $state 'quote' ($now+4) -Quote '小小的成功，也值得开心一下。'
Assert-Equal (Get-WidgetExpressionName $state $low ($now+5)) cheer 'Visible dialogue owns its paired expression even at low quota'
Register-WidgetExpressionEvent $state 'interact' ($now+5000) -CurrentExpression cheer
Assert-Equal (Get-WidgetExpressionName $state $low ($now+12000)) cheer 'Extending a dialogue cannot let its paired expression time out'
Register-WidgetExpressionEvent $state 'press' ($now+12001) -CurrentExpression cheer
Assert-Equal (Get-WidgetExpressionName $state $low ($now+12500)) cheer 'A held press cannot replace a visible dialogue pose'
Register-WidgetExpressionEvent $state 'release' ($now+12501) -CurrentExpression cheer
Register-WidgetExpressionEvent $state 'quota' ($now+12502)
Assert-Equal (Get-WidgetExpressionName $state $low ($now+12502)) worried 'Returning to quota immediately restores its independent reminder'
Register-WidgetExpressionEvent $state 'quote' ($now+12503) -Quote 'Ciallo～ 今天也请多关照。'
Register-WidgetExpressionEvent $state 'close' ($now+12504)
Assert-Equal (Get-WidgetExpressionName $state $low ($now+12504)) worried 'Closing dialogue restores the low-quota expression without another click'
Assert-Equal (Get-WidgetExpressionName $state (New-Snapshot 50) ($now+12505)) neutral 'Recovered quota resumes normal idle without leaking the dialogue pose'

$state=New-WidgetExpressionState $now
Register-WidgetExpressionEvent $state 'refresh' $now
$old=New-Snapshot 90 ($now-1)
Assert-Equal (Get-WidgetExpressionName $state $old ($now+1)) thinking 'Old cached status cannot complete a new refresh'
Register-WidgetExpressionEvent $state 'quote' ($now+2) -Quote '小小的成功，也值得开心一下。'
Assert-Equal (Get-WidgetExpressionName $state $old ($now+2)) cheer 'Dialogue reaction takes precedence over refresh'
Register-WidgetExpressionEvent $state 'press' ($now+3)
Assert-Equal (Get-WidgetExpressionName $state $old ($now+452)) cheer 'Brief presses retain their reaction'
Assert-Equal (Get-WidgetExpressionName $state $old ($now+453)) cheer 'Visible dialogue also takes precedence over a held press'
Register-WidgetExpressionEvent $state 'quota' ($now+454)
Assert-Equal (Get-WidgetExpressionName $state $old ($now+454)) surprised 'Outside dialogue a held press takes precedence after 450 milliseconds'
$state.mode='shy'
Assert-Equal (Get-WidgetExpressionName $state (New-Snapshot 0) ($now+130000)) shy 'Manual choice wins over press, refresh, low quota and idle'
Register-WidgetExpressionEvent $state 'release' ($now+130000)
Assert-Equal $state.pressed $false 'Release clears pressed state'
Assert-Equal (Get-WidgetExpressionName $state $null ($now+300000)) shy 'Manual mode stays selected indefinitely'
$state.mode='auto'
Assert-Equal (Get-WidgetExpressionName $state $null ($now+300000)) sleepy 'Returning to automatic resumes state deadlines'

$state=New-WidgetExpressionState $now
Register-WidgetExpressionEvent $state 'refresh' $now
Assert-Equal (Get-WidgetExpressionName $state $old ($now+7999)) thinking 'Refresh survives just before eight-second deadline'
Assert-Equal (Get-WidgetExpressionName $state $old ($now+8000)) neutral 'Refresh expires at eight seconds and resumes normal state'
$state=New-WidgetExpressionState $now
Register-WidgetExpressionEvent $state 'refresh' $now
Assert-Equal (Get-WidgetExpressionName $state (New-Snapshot 0) ($now+1)) worried 'Observation at the request timestamp completes refresh with a low-quota reminder'
Assert-Equal (Get-WidgetExpressionName $state $null ($now+2)) neutral 'Completed refresh cannot return to thinking after status loss'

$state=New-WidgetExpressionState $now
Assert-Equal (Get-WidgetExpressionName $state (New-Snapshot 19.9) $now) worried 'Fresh below twenty percent is worried'
Assert-Equal (Get-WidgetExpressionName $state (New-Snapshot 20) $now) neutral 'Twenty percent is normal'
Assert-Equal (Get-WidgetExpressionName $state (New-Snapshot 0) $now) worried 'Depleted quota uses the same independent worried reminder'
Assert-Equal (Get-WidgetExpressionName $state (New-Snapshot 10) ($now+17999)) worried 'Low quota keeps its main mood for a calm hold'
Assert-Equal (Get-WidgetExpressionName $state (New-Snapshot 10) ($now+18000)) worried 'Low quota stays worried instead of rotating into an unrelated gesture'
Assert-Equal (Get-WidgetExpressionName $state (New-Snapshot 0) ($now+18000)) worried 'Depleted quota also stays worried'
Assert-Equal (Get-WidgetExpressionName $state (New-Snapshot 0) ($now+24000)) worried 'Idle phases do not replace the quota reminder'
$mixed=New-Snapshot 10;$mixed.windows+=@{remaining=0;resetsAt=$null}
Assert-Equal (Get-WidgetExpressionName $state $mixed $now) worried 'Any low window triggers the quota reminder'
foreach($value in @($null,'',-1,101,'bad',[double]::NaN,[double]::PositiveInfinity,$true,@(0,1))){
  Assert-Equal (Get-WidgetExpressionName $state (New-Snapshot $value) $now) neutral 'Malformed remaining never becomes zero'
}
foreach($snapshot in @(
  @{ok=$true;queryOk=$true;observedAt=$now;windows=@(@{used=100})},
  @{ok=$true;queryOk=$false;observedAt=$now;windows=@(@{remaining=0})},
  @{ok=$false;queryOk=$true;observedAt=$now;windows=@(@{remaining=0})},
  @{ok=$true;queryOk=$true;error='failed';observedAt=$now;windows=@(@{remaining=0})},
  (New-Snapshot 0 ($now-180001)),(New-Snapshot 0 ($now+1)),(New-Snapshot 0 0),
  @{ok=$true;queryOk=$true;observedAt='bad';windows=@(@{remaining=0})},
  @{ok=$true;queryOk=$true;observedAt=$now;windows=@(@{remaining=0;resetsAt=[Math]::Floor($now/1000)})},
  @{ok=$true;queryOk=$true;observedAt=$now;windows=@(@{remaining=0;resetsAt='bad'})},
  @{ok=$true;queryOk=$true;observedAt=$now;windows=@()}
)){
  Assert-Equal (Get-WidgetExpressionName $state $snapshot $now) neutral 'No data, stale, failed or expired quota uses normal fallback'
}
Assert-Equal (Get-WidgetExpressionName $state (New-Snapshot 10 ($now-180000)) $now) worried 'Freshness boundary includes 180 seconds'
Register-WidgetExpressionEvent $state 'click' $now
Assert-Equal (Get-WidgetExpressionName $state (New-Snapshot 0) ($now+3000)) worried 'Transient activity does not replace the quota reminder'

# Real PNGs exercise WPF decoding, alpha caches and shared colour masks.
Initialize-WidgetExpressions $appDir $now
$neutral=$script:bitmap
$mask=[Windows.Media.ImageBrush]::new($neutral)
$halo=[Windows.Shapes.Rectangle]::new();$tint=[Windows.Shapes.Rectangle]::new()
$halo.OpacityMask=$mask;$tint.OpacityMask=$mask
$flow=[Windows.Media.LinearGradientBrush]::new();$halo.Fill=$flow;$tint.Fill=$flow
$script:widgetColors=@{halo=$halo;tint=$tint}
Set-WidgetExpressionMode happy $now
Assert-Equal $script:expressionCurrent happy 'Manual choice displays real happy sprite'
Assert-Equal $script:bitmap.IsFrozen $true 'Decoded image is frozen'
Assert-Equal $script:bitmap.PixelWidth 1254 'Expression uses its own decoded dimensions'
Assert-Same $script:bitmap $script:ui.Girl.Source 'Visible image and alpha bitmap source are synchronized'
Assert-Same $script:bitmap $mask.ImageSource 'Colour opacity mask follows current sprite'
Assert-Same $halo.Fill $flow 'Expression does not replace animated colour brush'
Assert-Equal $script:alphaStride ($script:bitmap.PixelWidth*4) 'Stride follows the selected bitmap'
Assert-Equal $script:alphaPixels.Length ($script:alphaStride*$script:bitmap.PixelHeight) 'Alpha buffer matches selected bitmap'
$happy=$script:bitmap;$happyAlpha=$script:alphaPixels
Set-WidgetExpressionMode neutral $now
Assert-Same $script:bitmap $neutral 'Neutral bitmap is cached'
Set-WidgetExpressionMode happy $now
Assert-Same $script:bitmap $happy 'Decoded expression is reused'
Assert-Same $script:alphaPixels $happyAlpha 'Alpha buffer is reused'
Register-WidgetExpressionEvent $script:expressionState 'press' $now
Update-WidgetExpression ($now+130000)
Assert-Equal $script:expressionCurrent happy 'Manual visual survives automatic events and idle ticks'

# Tiny fixtures verify variant dimensions and transparent click-through, independent of generated art.
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('gpt-niang-expression-'+[Guid]::NewGuid().ToString('N'))
try{
  $null=New-Item -ItemType Directory -Path (Join-Path $fixture 'assets\expressions') -Force
  Copy-Item -LiteralPath (Join-Path $appDir 'assets\gpt-dragon-niang-bust.png') -Destination (Join-Path $fixture 'assets\gpt-dragon-niang-bust.png')
  $pixels=[byte[]](0,0,0,0, 20,30,40,255, 20,30,40,255, 0,0,0,0, 0,0,0,0, 20,30,40,255)
  $tiny=[Windows.Media.Imaging.BitmapSource]::Create(2,3,96,96,[Windows.Media.PixelFormats]::Bgra32,$null,$pixels,8)
  $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($tiny))
  $stream=[IO.File]::Create((Join-Path $fixture 'assets\expressions\happy.png'));try{$encoder.Save($stream)}finally{$stream.Dispose()}
  [IO.File]::WriteAllText((Join-Path $fixture 'assets\expressions\shy.png'),'not a png')
  $script:widgetColors=$null
  $script:ui.Root=[Windows.Controls.Canvas]::new();$script:ui.Girl=[Windows.Controls.Image]::new()
  $script:ui.Girl.Width=20;$script:ui.Girl.Height=30;$script:ui.Girl.Stretch=[Windows.Media.Stretch]::UniformToFill
  $script:ui.Root.Children.Add($script:ui.Girl)|Out-Null
  Initialize-WidgetExpressions $fixture $now
  Set-WidgetExpressionMode happy $now
  $root=$script:ui.Root;$root.Measure([Windows.Size]::new(30,40));$root.Arrange([Windows.Rect]::new(0,0,30,40));$root.UpdateLayout()
  $tokens=$null;$errors=$null
  $widget=[IO.File]::ReadAllText((Join-Path $appDir 'widget.ps1'),[Text.Encoding]::UTF8)
  $ast=[Management.Automation.Language.Parser]::ParseInput($widget,[ref]$tokens,[ref]$errors)
  if($errors.Count){throw ($errors|Out-String)}
  foreach($name in @('Test-GirlAlpha','Write-WidgetJson','Save-Settings')){
    $function=$ast.Find({param($node)$node-is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name-eq $name},$true)
    . ([ScriptBlock]::Create($function.Extent.Text))
  }
  Assert-Equal $script:bitmap.PixelWidth 2 'Variant width is not assumed to equal original'
  Assert-Equal $script:bitmap.PixelHeight 3 'Variant height is not assumed to equal original'
  Assert-Equal (Test-GirlAlpha ([Windows.Point]::new(5,5))) $false 'Transparent variant region clicks through'
  Assert-Equal (Test-GirlAlpha ([Windows.Point]::new(15,5))) $true 'Opaque variant region accepts click'
  Assert-Equal (Test-GirlAlpha ([Windows.Point]::new(-1,5))) $false 'Outside variant is not clickable'
  Set-WidgetExpressionMode wave $now
  Assert-Equal $script:expressionCurrent neutral 'Missing optional image falls back to original'
  Assert-Equal $script:expressionMode wave 'Missing image preserves manual preference'
  Set-WidgetExpressionMode shy $now
  Assert-Equal $script:expressionCurrent neutral 'Corrupt optional image falls back to original'
  $settingsFile=Join-Path $fixture 'settings.json'
  Save-Settings
  $saved=Get-Content -LiteralPath $settingsFile -Raw -Encoding UTF8|ConvertFrom-Json
  Assert-Equal $saved.expressionMode shy 'Settings persist the registered manual choice'
  Initialize-WidgetExpressions $fixture $now
  Set-WidgetExpressionMode (Resolve-WidgetExpressionMode $saved.expressionMode) $now
  Assert-Equal $script:expressionMode shy 'Saved mode restores after a fresh initialization'
  # Exercise the real WPF submenu and its handlers, including restored checkmarks.
  . ([ScriptBlock]::Create([IO.File]::ReadAllText((Join-Path $appDir 'runtime\ui-settings.ps1'),[Text.Encoding]::UTF8)))
  . ([ScriptBlock]::Create([IO.File]::ReadAllText((Join-Path $appDir 'runtime\color-theme.ps1'),[Text.Encoding]::UTF8)))
  $script:window=[Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText((Join-Path $appDir 'widget.xaml'),[Text.Encoding]::UTF8))
  $script:scale=1.0;$script:soundOn=$true;$script:soundVolume=0.9;$script:hideMenu=$false;$script:bubbleTapAdvance=$false
  $script:collapsed=$true;$script:bubbleMode='quota'
  Initialize-WidgetSettingsMenu
  Assert-Equal $script:settingsMenuUi.ExpressionItems.Count 12 'Submenu offers auto, original, all expressions and gestures'
  Assert-Equal $script:settingsMenuUi.ExpressionItems.shy.IsChecked $true 'Restored manual preference has a checkmark'
  $item=$script:settingsMenuUi.ExpressionItems.happy
  $item.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.MenuItem]::ClickEvent,$item))
  Assert-Equal $script:expressionMode happy 'Real submenu handler selects its tagged sprite'
  Assert-Equal $script:settingsMenuUi.ExpressionItems.happy.IsChecked $true 'New choice synchronizes its checkmark'
  Assert-Equal $script:settingsMenuUi.ExpressionItems.shy.IsChecked $false 'Previous choice loses its checkmark'
  Assert-Equal (Get-Content -LiteralPath $settingsFile -Raw -Encoding UTF8|ConvertFrom-Json).expressionMode happy 'Menu choice is persisted'
  $automatic=$script:settingsMenuUi.ExpressionItems.auto
  $automatic.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.MenuItem]::ClickEvent,$automatic))
  Assert-Equal $script:expressionMode auto 'Auto menu item resumes automatic selection'
  Assert-Equal $script:settingsMenuUi.ExpressionItems.auto.IsChecked $true 'Auto checkmark is synchronized'
  $script:window.Close()
  Write-Output 'PASS: expression priorities, deterministic deadlines, safe quota validation, manual persistence, WPF cache, alpha hit regions, palette masks and optional image recovery'
}finally{
  $resolved=[IO.Path]::GetFullPath($fixture);$prefix=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
  if(!$resolved.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved)-notlike 'gpt-niang-expression-*'){throw 'Unsafe expression fixture cleanup path.'}
  if(Test-Path -LiteralPath $fixture){Remove-Item -LiteralPath $fixture -Recurse -Force}
}
