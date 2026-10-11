# Low-quota replies have an independent pool and only use fresh, valid observations.
function Get-WidgetQuotaLevel($Status,[long]$Now){
  $remaining=Get-WidgetQuotaRemaining $Status $Now
  if($null-eq $remaining){return 'unknown'}
  if($remaining-eq 0){return 'empty'}
  if($remaining-le 5){return 'critical'}
  if($remaining-lt 20){return 'low'}
  return 'normal'
}
function New-WidgetLowQuotaState {
  return @{level='unknown';pending=$false;nextAt=0L;lastQuote='';count=0;lastShownAt=0L}
}
function Update-WidgetLowQuotaDialogue($State,$Status,[long]$Now,[bool]$Ready){
  $level=Get-WidgetQuotaLevel $Status $Now
  if($level-eq 'unknown'){return $false}
  if($level-eq 'normal'){$State.level=$level;$State.pending=$false;$State.nextAt=0L;return $false}
  $rank=@{unknown=-1;normal=0;low=1;critical=2;empty=3}
  if($rank[$level]-gt $rank[$State.level]){$State.pending=$true}
  $State.level=$level
  if(!$Ready -or (!$State.pending -and $Now-lt $State.nextAt)){return $false}
  $State.pending=$false;$State.nextAt=$Now+180000;$State.lastShownAt=$Now;$State.count++
  return $true
}
function Initialize-WidgetLowQuotaQuotes([string]$AppDir){
  $script:lowQuotaQuotes=@()
  try{
    $pool=[IO.File]::ReadAllText((Join-Path $AppDir 'assets\low-quota-quotes.json'),[Text.Encoding]::UTF8)|ConvertFrom-Json
    $script:lowQuotaQuotes=@($pool.quotes|Where-Object{$_.text-is [string] -and $_.text.Trim() -and $_.level-in @('low','critical','empty') -and $_.expression-in @((Get-WidgetExpressionRegistry).name)})
  }catch{}
  $script:lowQuotaRandom=New-Object Random
}
function Get-WidgetLowQuotaQuote($State,[string]$Level){
  $rows=@($script:lowQuotaQuotes|Where-Object{$_.level-eq $Level})
  $candidates=@($rows|Where-Object{$_.text-ne $State.lastQuote})
  if(!$candidates.Count){$candidates=$rows}
  if(!$candidates.Count){return $null}
  $row=$candidates[$script:lowQuotaRandom.Next($candidates.Count)]
  $State.lastQuote=$row.text;return $row
}
