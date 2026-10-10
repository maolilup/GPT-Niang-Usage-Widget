param([string]$TestRoot=$PSScriptRoot)
$ErrorActionPreference='Stop'
$appDir=Split-Path $TestRoot -Parent
$source=[IO.File]::ReadAllText((Join-Path $appDir 'widget.ps1'),[Text.Encoding]::UTF8)
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors|Out-String)}
$definition=$ast.Find({param($node)$node-is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name-eq 'Get-WidgetAdaptiveLayout'},$true)
if(!$definition){throw 'Adaptive window sizing is missing'}
. ([ScriptBlock]::Create($definition.Extent.Text))
function Assert-Equal($actual,$expected,[string]$message){if($actual-ne $expected){throw "$message : expected '$expected', got '$actual'"}}
function Assert-Close($actual,$expected,[string]$message){if([Math]::Abs($actual-$expected)-gt 0.000001){throw "$message : expected '$expected', got '$actual'"}}
$requested=0.8
$large=Get-WidgetAdaptiveLayout 2100 1350 1.5 $requested 378 378
$medium=Get-WidgetAdaptiveLayout 1500 1050 1.5 $requested 378 378
$narrow=Get-WidgetAdaptiveLayout 1200 1500 1.5 $requested 378 378
$short=Get-WidgetAdaptiveLayout 2100 900 1.5 $requested 378 378
Assert-Close $large.scale $requested 'Large host restores the user size'
Assert-Close ($medium.scale*378) 250 'Moderate host width limits the whole widget to one quarter'
Assert-Close ($narrow.scale*378) 200 'Narrow host shrinks earlier than fitting the whole host'
Assert-Close ($short.scale*378) 240 'Short host limits the widget to forty percent of its height'
Assert-Close (Get-WidgetAdaptiveLayout 1500 1050 1.5 0.6 378 378).scale 0.6 'Adaptive fitting never enlarges a smaller user preference'
Assert-Close (Get-WidgetAdaptiveLayout 1500 1050 1.5 2.5 378 378).scale $medium.scale 'Oversized user preferences also respect the host budget'
Assert-Equal (Get-WidgetAdaptiveLayout 719 900 1 0.8 378 378).visible $false 'Too narrow hides'
Assert-Equal (Get-WidgetAdaptiveLayout 1200 519 1 0.8 378 378).visible $false 'Too short hides'
Assert-Equal (Get-WidgetAdaptiveLayout 720 520 1 0.8 378 378).visible $true 'Hide boundary is inclusive for an already visible widget'
Assert-Equal (Get-WidgetAdaptiveLayout 740 540 1 0.8 378 378 $true).visible $false 'Hidden widget remains hidden in the hysteresis band'
Assert-Equal (Get-WidgetAdaptiveLayout 760 560 1 0.8 378 378 $true).visible $true 'Enough room restores visibility automatically'
Assert-Equal (Get-WidgetAdaptiveLayout 760 559 1 0.8 378 378 $true).visible $false 'Restoration requires both dimensions'
foreach($dpi in @(1,1.25,1.5,2)){
  Assert-Close (Get-WidgetAdaptiveLayout (1000*$dpi) (700*$dpi) $dpi $requested 378 378).scale $medium.scale 'Same logical host size fits identically across DPI settings'
  Assert-Equal (Get-WidgetAdaptiveLayout (700*$dpi) (650*$dpi) $dpi $requested 378 378).visible $false 'Small-window hiding is DPI independent'
}
foreach($layout in @(@{width=378;height=378},@{width=480;height=300})){
  for($iteration=0;$iteration-lt 100;$iteration++){
    $small=Get-WidgetAdaptiveLayout 1500 1050 1.5 $requested $layout.width $layout.height
    $restored=Get-WidgetAdaptiveLayout 3000 1800 1.5 $requested $layout.width $layout.height
    Assert-Close $restored.scale $requested 'Repeated shrinking and growing never accumulates scale drift'
    if($small.scale*$layout.width-gt 250.001 -or $small.scale*$layout.height-gt 280.001){throw 'Adaptive widget exceeds its host budget'}
  }
}
foreach($size in @(@(0,900),@(-1,900),@(1000,0),@([double]::NaN,900))){
  $result=Get-WidgetAdaptiveLayout $size[0] $size[1] 1 $requested 378 378
  Assert-Equal $result.visible $false 'Invalid native frames stay hidden'
  Assert-Close $result.scale 0 'Invalid frame does not produce a native size'
}
Assert-Close $requested 0.8 'Fitting does not overwrite the user preference'
Write-Output 'PASS: proportional fitting, small-window hide/restore hysteresis, four DPIs, user size cap and 200 shrink/grow cycles without drift'
