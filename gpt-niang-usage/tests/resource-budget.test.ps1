param([string]$TestRoot=$PSScriptRoot,[switch]$ProfileOnly,[int]$Rounds=3,[switch]$NaturalGc)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$appDir=Split-Path $TestRoot -Parent
. ([ScriptBlock]::Create([IO.File]::ReadAllText((Join-Path $appDir 'runtime\expressions.ps1'),[Text.Encoding]::UTF8)))
$script:ui=@{Girl=[Windows.Controls.Image]::new()}
$script:widgetColors=$null
Initialize-WidgetExpressions $appDir 1800000000000L
$samples=@();$warmDecodes=$null
for($round=1;$round-le $Rounds;$round++){
  foreach($row in Get-WidgetExpressionRegistry){
    Set-WidgetExpressionMode $row.name 1800000000000L
    if(!$ProfileOnly -and [Math]::Max($script:bitmap.PixelWidth,$script:bitmap.PixelHeight)-gt 512){throw 'Decoded sprite exceeds the 512px resource budget.'}
    if(!$ProfileOnly -and $script:expressionCache.Count-gt 32){throw 'Decoded sprite cache exceeds its entry limit.'}
  }
  if(!$NaturalGc){[GC]::Collect();[GC]::WaitForPendingFinalizers();[GC]::Collect()}
  $p=[Diagnostics.Process]::GetCurrentProcess()
  try{
    $cacheBytes=0L
    foreach($asset in $script:expressionCache.Values){$cacheBytes+=if($asset.bytes){$asset.bytes}else{$asset.pixels.Length+[long]$asset.bitmap.PixelWidth*$asset.bitmap.PixelHeight*8}}
    $sample=[pscustomobject]@{round=$round;privateMiB=[Math]::Round($p.PrivateMemorySize64/1MB,2);workingMiB=[Math]::Round($p.WorkingSet64/1MB,2);managedMiB=[Math]::Round([GC]::GetTotalMemory($false)/1MB,2);cacheMiB=[Math]::Round($cacheBytes/1MB,2);decodes=$script:expressionDecodeCount}
    $samples+=$sample;if($Rounds-le 25 -or $round-eq 1 -or $round%25-eq 0 -or $round-eq $Rounds){$sample|ConvertTo-Json -Compress}
    if(!$ProfileOnly -and $cacheBytes-gt 48MB){throw 'Decoded sprites and hit masks exceed the 48 MiB cache budget.'}
    if(!$ProfileOnly -and $round-ge 2 -and $script:expressionDecodeCount-ne $warmDecodes){throw 'A warmed expression library keeps decoding images.'}
    $warmDecodes=$script:expressionDecodeCount
    if($round-ge 2 -and $p.PrivateMemorySize64-gt 512MB){throw 'Sprite stress test exceeded its 512 MiB safety limit.'}
  }finally{$p.Dispose()}
}
if(!$ProfileOnly -and $samples.Count-ge 3 -and $samples[-1].privateMiB-$samples[-2].privateMiB-gt 32){throw 'Warm sprite cycling continues to grow private memory.'}
'PASS: bounded decoding, byte-budgeted cache and warmed-library reuse'
