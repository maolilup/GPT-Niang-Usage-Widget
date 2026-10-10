# Selection uses explicit timestamps. Images and hit masks are decoded once per sprite.
$script:expressionRegistry=@(
  @{name='neutral';label='默认';file='assets\gpt-dragon-niang-bust.png'},
  @{name='happy';label='开心';file='assets\expressions\happy.png'},
  @{name='shy';label='害羞';file='assets\expressions\shy.png'},
  @{name='thinking';label='思考';file='assets\expressions\thinking.png'},
  @{name='surprised';label='惊讶';file='assets\expressions\surprised.png'},
  @{name='sleepy';label='困倦';file='assets\expressions\sleepy.png'},
  @{name='worried';label='担忧';file='assets\expressions\worried.png'},
  @{name='wave';label='挥手';file='assets\expressions\wave.png'},
  @{name='cheer';label='双拳欢呼';file='assets\expressions\cheer.png'},
  @{name='pout';label='抱臂鼓脸';file='assets\expressions\pout.png'},
  @{name='comfort';label='合掌安慰';file='assets\expressions\comfort.png'}
)
function Get-WidgetExpressionRegistry {return $script:expressionRegistry}
function Resolve-WidgetExpressionMode($Mode){
  if($Mode-eq 'auto' -or $Mode-in @($script:expressionRegistry|ForEach-Object{$_.name})){return [string]$Mode}
  return 'auto'
}
function New-WidgetExpressionState([long]$Now){
  return @{mode='auto';lastActiveAt=$Now;pressed=$false;reaction='';reactionUntil=0L;refreshAt=0L;clickIndex=0;quoteIndex=0}
}
function Register-WidgetExpressionEvent($State,[ValidateSet('interact','press','release','click','quote','refresh')][string]$Kind,[long]$Now){
  $State.lastActiveAt=$Now
  switch($Kind){
    'press' {$State.pressed=$true}
    'release' {$State.pressed=$false}
    'refresh' {$State.refreshAt=$Now}
    'click' {$State.reaction=@('happy','cheer','wave')[$State.clickIndex%3];$State.clickIndex++;$State.reactionUntil=$Now+3000}
    'quote' {$State.reaction=@('shy','comfort')[$State.quoteIndex%2];$State.quoteIndex++;$State.reactionUntil=$Now+3000}
  }
}
function ConvertTo-WidgetExpressionNumber($Value){
  if($null-eq $Value -or $Value-is [bool] -or $Value-is [Array] -or $Value-is [Collections.IDictionary]){return $null}
  $number=0.0
  if(![double]::TryParse([string]$Value,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$number) -or [double]::IsNaN($number) -or [double]::IsInfinity($number)){return $null}
  return $number
}
function Get-WidgetQuotaExpression($Status,[long]$Now){
  if(!$Status -or $Status.ok-isnot [bool] -or !$Status.ok -or $Status.queryOk-isnot [bool] -or !$Status.queryOk -or $Status.error){return 'neutral'}
  $observed=ConvertTo-WidgetExpressionNumber $Status.observedAt
  if($null-eq $observed -or $observed-le 0 -or $Now-$observed-lt 0 -or $Now-$observed-gt 180000){return 'neutral'}
  $low=$false
  foreach($window in @($Status.windows)){
    if(!$window){continue}
    $remaining=ConvertTo-WidgetExpressionNumber $window.remaining
    if($null-eq $remaining -or $remaining-lt 0 -or $remaining-gt 100){continue}
    if($null-ne $window.resetsAt){
      $reset=ConvertTo-WidgetExpressionNumber $window.resetsAt
      if($null-eq $reset -or $reset-le $Now/1000.0){continue}
    }
    if($remaining-eq 0){return 'pout'}
    if($remaining-lt 20){$low=$true}
  }
  if($low){return 'worried'}
  return 'neutral'
}
function Get-WidgetExpressionName($State,$Status,[long]$Now){
  if($State.mode-ne 'auto'){return Resolve-WidgetExpressionMode $State.mode}
  # A cached observation predating this request must never finish its thinking pose.
  if($State.refreshAt-gt 0){
    $observed=ConvertTo-WidgetExpressionNumber $Status.observedAt
    if(($null-ne $observed -and $observed-ge $State.refreshAt) -or $Now-ge $State.refreshAt+8000){$State.refreshAt=0L}
  }
  if($State.pressed){return 'surprised'}
  if($State.reaction -and $Now-lt $State.reactionUntil){return $State.reaction}
  if($State.refreshAt-gt 0){return 'thinking'}
  $quota=Get-WidgetQuotaExpression $Status $Now
  if($quota-ne 'neutral'){return $quota}
  if($Now-$State.lastActiveAt-ge 120000){return 'sleepy'}
  return 'neutral'
}
function Get-WidgetExpressionAsset([string]$Name){
  if($script:expressionCache.ContainsKey($Name)){return $script:expressionCache[$Name]}
  $row=$script:expressionRegistry|Where-Object{$_.name-eq $Name}|Select-Object -First 1
  try{
    if(!$row){throw 'Unknown expression.'}
    $stream=[IO.File]::OpenRead((Join-Path $script:expressionAppDir $row.file))
    try{
      $image=[Windows.Media.Imaging.BitmapImage]::new()
      $image.BeginInit();$image.CacheOption=[Windows.Media.Imaging.BitmapCacheOption]::OnLoad
      $image.StreamSource=$stream;$image.EndInit();$image.Freeze()
    }finally{$stream.Dispose()}
    $alpha=[Windows.Media.Imaging.FormatConvertedBitmap]::new($image,[Windows.Media.PixelFormats]::Bgra32,$null,0)
    $stride=$image.PixelWidth*4;$pixels=New-Object byte[] ($stride*$image.PixelHeight)
    $alpha.CopyPixels($pixels,$stride,0);$alpha.Freeze()
    $asset=@{name=$Name;bitmap=$image;alphaBitmap=$alpha;stride=$stride;pixels=$pixels}
  }catch{
    if($Name-eq 'neutral'){throw}
    $asset=Get-WidgetExpressionAsset 'neutral'
  }
  # Failed optional images also stay cached, avoiding repeated disk access each tick.
  $script:expressionCache[$Name]=$asset
  return $asset
}
function Update-WidgetExpression([long]$Now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()){
  if(!$script:expressionState){return}
  $name=Get-WidgetExpressionName $script:expressionState $script:status $Now
  $asset=Get-WidgetExpressionAsset $name
  $script:expressionCurrent=$asset.name
  $script:bitmap=$asset.bitmap;$script:alphaBitmap=$asset.alphaBitmap
  $script:alphaStride=$asset.stride;$script:alphaPixels=$asset.pixels
  if($script:ui.Girl.Source-ne $script:bitmap){$script:ui.Girl.Source=$script:bitmap}
  if($script:widgetColors){
    foreach($surface in @($script:widgetColors.halo,$script:widgetColors.tint)){
      if($surface -and $surface.OpacityMask-is [Windows.Media.ImageBrush]){$surface.OpacityMask.ImageSource=$script:bitmap}
    }
  }
}
function Initialize-WidgetExpressions([string]$AppDir,[long]$Now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()){
  $script:expressionAppDir=$AppDir;$script:expressionCache=@{}
  $script:expressionState=New-WidgetExpressionState $Now;$script:expressionMode='auto'
  Update-WidgetExpression $Now
}
function Set-WidgetExpressionMode($Mode,[long]$Now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()){
  $script:expressionMode=Resolve-WidgetExpressionMode $Mode
  $script:expressionState.mode=$script:expressionMode
  Register-WidgetExpressionEvent $script:expressionState 'interact' $Now
  Update-WidgetExpression $Now
}
function Invoke-WidgetExpressionEvent([string]$Kind,[long]$Now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()){
  if(!$script:expressionState){return}
  Register-WidgetExpressionEvent $script:expressionState $Kind $Now
  Update-WidgetExpression $Now
}
