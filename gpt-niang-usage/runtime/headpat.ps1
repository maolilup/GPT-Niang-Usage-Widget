# Recognize intentional unpressed strokes in normalized sprite coordinates.
function New-WidgetHeadpatState {
  return @{lastAt=0L;startedAt=0L;anchorX=0.0;extremeX=0.0;direction=0;strokes=0;cooldownUntil=0L;count=0;lastQuote=''}
}
function Reset-WidgetHeadpatGesture($State){
  $State.lastAt=0L;$State.startedAt=0L;$State.direction=0;$State.strokes=0
}
function ConvertTo-WidgetSpritePoint([double]$X,[double]$Y,[double]$Width,[double]$Height,[double]$PixelWidth,[double]$PixelHeight){
  foreach($value in @($Width,$Height,$PixelWidth,$PixelHeight)){if($value-le 0 -or [double]::IsNaN($value) -or [double]::IsInfinity($value)){return $null}}
  if([double]::IsNaN($X) -or [double]::IsInfinity($X) -or [double]::IsNaN($Y) -or [double]::IsInfinity($Y)){return $null}
  $fit=[Math]::Max($Width/$PixelWidth,$Height/$PixelHeight)
  return @{x=($X-($Width-$PixelWidth*$fit)/2)/($PixelWidth*$fit);y=($Y-($Height-$PixelHeight*$fit)/2)/($PixelHeight*$fit)}
}
function Update-WidgetHeadpat($State,[double]$X,[double]$Y,[bool]$Opaque,[bool]$Blocked,[long]$Now){
  if($Blocked -or !$Opaque -or [double]::IsNaN($X) -or [double]::IsNaN($Y) -or $X-lt 0.28 -or $X-gt 0.72 -or $Y-lt 0.12 -or $Y-gt 0.40 -or $Now-lt $State.cooldownUntil){
    Reset-WidgetHeadpatGesture $State;return $false
  }
  if(!$State.lastAt -or $Now-lt $State.lastAt -or $Now-$State.lastAt-gt 700 -or $Now-$State.startedAt-gt 2500){
    Reset-WidgetHeadpatGesture $State;$State.startedAt=$Now;$State.anchorX=$X;$State.extremeX=$X
  }
  $State.lastAt=$Now
  if(!$State.direction){
    $distance=$X-$State.anchorX
    if([Math]::Abs($distance)-ge 0.12){$State.direction=[Math]::Sign($distance);$State.strokes=1;$State.extremeX=$X}
  }else{
    $distance=($X-$State.extremeX)*$State.direction
    if($distance-gt 0){$State.extremeX=$X}
    elseif($distance-le -0.12){$State.direction=-$State.direction;$State.extremeX=$X;$State.strokes++}
  }
  if($State.strokes-ge 3 -and $Now-$State.startedAt-ge 400){
    $State.count++;$State.cooldownUntil=$Now+8000;Reset-WidgetHeadpatGesture $State;return $true
  }
  return $false
}
function Initialize-WidgetHeadpatQuotes([string]$AppDir){
  $script:headpatQuotes=@()
  try{
    $pool=[IO.File]::ReadAllText((Join-Path $AppDir 'assets\headpat-quotes.json'),[Text.Encoding]::UTF8)|ConvertFrom-Json
    $script:headpatQuotes=@($pool.quotes|Where-Object{$_.text-is [string] -and $_.text.Trim() -and $_.expression-in @((Get-WidgetExpressionRegistry).name)})
  }catch{}
  $script:headpatRandom=New-Object Random
}
function Get-WidgetHeadpatQuote($State){
  $candidates=@($script:headpatQuotes|Where-Object{$_.text-ne $State.lastQuote})
  if(!$candidates.Count){$candidates=@($script:headpatQuotes)}
  if(!$candidates.Count){return $null}
  $row=$candidates[$script:headpatRandom.Next($candidates.Count)]
  $State.lastQuote=$row.text;return $row
}
