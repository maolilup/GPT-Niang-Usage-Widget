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
function Initialize-WidgetQuoteExpressions([string]$AppDir){
  $script:quoteExpressionMap=@{}
  try{
    $quotes=[IO.File]::ReadAllText((Join-Path $AppDir 'assets\quotes.json'),[Text.Encoding]::UTF8)|ConvertFrom-Json
    foreach($row in $quotes.quotes){
      if($row.text-is [string] -and $row.expression-in @($script:expressionRegistry.name)){
        $script:quoteExpressionMap[$row.text.Trim()]=[string]$row.expression
      }
    }
  }catch{} # Missing optional metadata does not prevent the original widget from starting.
}
function Get-WidgetQuoteExpression([string]$Quote){
  $text=$Quote.Trim()
  if($script:quoteExpressionMap -and $script:quoteExpressionMap.ContainsKey($text)){return $script:quoteExpressionMap[$text]}
  # Custom quotes keep their existing text/weight format; use a gentle fallback by topic.
  if($text-match '休息|睡|困|充电|歇一会'){return 'sleepy'}
  if($text-match '没关系|不怕|别怕|慢慢来|辛苦|加油'){return 'comfort'}
  if($text-match '恭喜|成功|太棒|做到了|完成啦'){return 'cheer'}
  if($text-match '你好|早上好|晚上好|多关照|ciallo|hello'){return 'wave'}
  if($text-match '害羞|喜欢|看我|脸红'){return 'shy'}
  if($text-match '惊讶|吓|居然|竟然'){return 'surprised'}
  if($text-match '生气|血压|便宜货|哼'){return 'pout'}
  if($text-match '担心|余额不足|额度不足|崩了|小心|保存'){return 'worried'}
  if($text-match '思考|想想|问题|代码|思路|试试'){return 'thinking'}
  return 'happy'
}
function New-WidgetExpressionState([long]$Now){
  return @{mode='auto';lastActiveAt=$Now;pressed=$false;pressedAt=0L;quoteExpression='';reaction='';reactionUntil=0L;refreshAt=0L}
}
function Register-WidgetExpressionEvent($State,[ValidateSet('interact','press','release','click','quote','quota','close','refresh')][string]$Kind,[long]$Now,[string]$Quote='',[string]$CurrentExpression=''){
  $State.lastActiveAt=$Now
  switch($Kind){
    'press' {if(!$State.pressed){$State.pressedAt=$Now};$State.pressed=$true}
    'release' {$State.pressed=$false}
    'refresh' {$State.refreshAt=$Now}
    'quota' {$State.quoteExpression=''}
    'close' {$State.quoteExpression='';$State.reaction='';$State.reactionUntil=0L}
  }
  if($Kind-eq 'quote'){
    # The rendered dialogue owns its pose until the scene changes or closes.
    $State.quoteExpression=Get-WidgetQuoteExpression $Quote
    $State.reaction=$State.quoteExpression
    # Retain the previous pose briefly on a normal quota page, without masking low quota.
    $State.reactionUntil=$Now+5500
  }elseif($Kind-notin @('refresh','close') -and $CurrentExpression-in @($script:expressionRegistry.name)){
    # Resetting the idle clock must not reset the visible pose on a quota click or short press.
    $State.reaction=$CurrentExpression
    $State.reactionUntil=[Math]::Max($State.reactionUntil,$Now+3000)
  }
}
function Get-WidgetAmbientExpression([long]$IdleMilliseconds){
  if($IdleMilliseconds-ge 120000){
    $phase=($IdleMilliseconds-120000)%36000
    if($phase-lt 18000){return 'sleepy'}
    if($phase-lt 28000){return 'neutral'}
    return 'comfort'
  }
  # Calm holds between facial changes and occasional hand gestures; no tick-rate flicker.
  $phase=[Math]::Max(0,$IdleMilliseconds)%70000
  if($phase-lt 12000){return 'neutral'}
  if($phase-lt 18000){return 'happy'}
  if($phase-lt 28000){return 'neutral'}
  if($phase-lt 34000){return 'shy'}
  if($phase-lt 44000){return 'neutral'}
  if($phase-lt 52000){return 'comfort'}
  if($phase-lt 64000){return 'neutral'}
  return 'wave'
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
  if($State.quoteExpression){return $State.quoteExpression}
  $quota=Get-WidgetQuotaExpression $Status $Now
  if($quota-ne 'neutral'){return $quota}
  if($State.pressed -and $Now-$State.pressedAt-ge 450){return 'surprised'}
  if($State.reaction -and $Now-lt $State.reactionUntil){return $State.reaction}
  if($State.refreshAt-gt 0){return 'thinking'}
  return Get-WidgetAmbientExpression ($Now-$State.lastActiveAt)
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
  Initialize-WidgetQuoteExpressions $AppDir
  $script:expressionState=New-WidgetExpressionState $Now;$script:expressionMode='auto'
  Update-WidgetExpression $Now
}
function Set-WidgetExpressionMode($Mode,[long]$Now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()){
  $script:expressionMode=Resolve-WidgetExpressionMode $Mode
  $script:expressionState.mode=$script:expressionMode
  Register-WidgetExpressionEvent $script:expressionState 'interact' $Now
  Update-WidgetExpression $Now
}
function Invoke-WidgetExpressionEvent([string]$Kind,[long]$Now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds(),[string]$Quote=''){
  if(!$script:expressionState){return}
  Register-WidgetExpressionEvent $script:expressionState $Kind $Now -Quote $Quote -CurrentExpression $script:expressionCurrent
  Update-WidgetExpression $Now
}
