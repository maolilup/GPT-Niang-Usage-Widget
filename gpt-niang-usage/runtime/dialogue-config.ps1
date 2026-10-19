# One user-owned configuration supplies complete, validated dialogue snapshots.
function ConvertTo-WidgetDialogueConfiguration($Value){
  if(!$Value -or $Value-is [Array] -or $Value.version-ne 1){throw 'dialogue.json: version must be 1.'}
  $result=[ordered]@{version=1}
  $names=@((Get-WidgetExpressionRegistry).name)
  foreach($group in @('daily','headpat','lowQuota')){
    $entries=$Value.$group
    if($entries-isnot [Array]){throw ('dialogue.json: '+$group+' must be an array.')}
    $rows=New-Object 'System.Collections.Generic.List[object]';$seen=@{}
    foreach($entry in $entries){
      if($entry.text-isnot [string]){throw ('dialogue.json: '+$group+' entries need text.')}
      $text=$entry.text.Trim()
      if(!$text -or $text.Length-gt 200 -or $text-match '[\x00-\x08\x0B\x0C\x0E-\x1F]'){throw ('dialogue.json: '+$group+' text must contain 1 to 200 characters.')}
      if($entry.expression-isnot [string] -or $entry.expression-notin $names){throw ('dialogue.json: unknown expression for '+$text)}
      $weight=1.0
      if($null-ne $entry.weight){$weight=ConvertTo-WidgetExpressionNumber $entry.weight;if($null-eq $weight -or $weight-le 0 -or $weight-gt 1000){throw ('dialogue.json: invalid weight for '+$text)}}
      $key=$text
      $row=[ordered]@{text=$text;expression=[string]$entry.expression;weight=[double]$weight}
      if($group-eq 'lowQuota'){
        if($entry.level-notin @('low','critical','empty')){throw ('dialogue.json: invalid low-quota level for '+$text)}
        $row.level=[string]$entry.level;$key=$row.level+'|'+$text
      }
      if($seen.ContainsKey($key)){throw ('dialogue.json: duplicate '+$group+' entry: '+$text)}
      $seen[$key]=$true;$rows.Add([pscustomobject]$row)
    }
    if($group-eq 'daily' -and !$rows.Count){throw 'dialogue.json: daily must contain at least one entry.'}
    $result[$group]=@($rows.ToArray())
  }
  return [pscustomobject]$result
}
function Get-WidgetBundledDialogueConfiguration([string]$AppDir){
  $raw=[ordered]@{version=1}
  foreach($pair in @(@('daily','quotes.json'),@('headpat','headpat-quotes.json'),@('lowQuota','low-quota-quotes.json'))){
    $raw[$pair[0]]=@()
    try{$pool=[IO.File]::ReadAllText((Join-Path $AppDir ('assets\'+$pair[1])),[Text.Encoding]::UTF8)|ConvertFrom-Json;$raw[$pair[0]]=@($pool.quotes)}catch{}
  }
  if(!$raw.daily.Count){$raw.daily=@(@{text='Ciallo~';expression='wave';weight=1})}
  return ConvertTo-WidgetDialogueConfiguration $raw
}
function Get-WidgetDialogueFileSignature([string]$Path){
  if(![IO.File]::Exists($Path)){return 'missing'}
  $file=[IO.FileInfo]::new($Path)
  return ([string]$file.LastWriteTimeUtc.Ticks)+'/'+[string]$file.Length
}
function Write-WidgetDialogueFile($State,$Configuration,[switch]$NoOverwrite){
  $null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($State.path))
  if($NoOverwrite -and [IO.File]::Exists($State.path)){return}
  $temp=$State.path+'.'+$PID+'.'+[Guid]::NewGuid().ToString('N')+'.tmp'
  try{
    [IO.File]::WriteAllText($temp,($Configuration|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
    if($NoOverwrite){[IO.File]::Move($temp,$State.path)}
    elseif([IO.File]::Exists($State.path)){[IO.File]::Replace($temp,$State.path,($State.path+'.bak'),$true)}
    else{[IO.File]::Move($temp,$State.path)}
  }finally{if([IO.File]::Exists($temp)){[IO.File]::Delete($temp)}}
}
function Initialize-WidgetDialogueConfiguration([string]$AppDir,[string]$DataDir,[switch]$Create){
  $defaults=Get-WidgetBundledDialogueConfiguration $AppDir
  $state=@{appDir=$AppDir;dataDir=[IO.Path]::GetFullPath($DataDir);path=(Join-Path $DataDir 'dialogue.json');defaults=$defaults;current=$defaults;signature='';pending='';pendingSince=0L;error='';reloads=0;loadedAt=0L;custom=$false;random=[Random]::new();lastByGroup=@{}}
  if($Create -and ![IO.File]::Exists($state.path)){
    $seed=$defaults
    $legacy=Join-Path $DataDir 'quotes.json'
    if([IO.File]::Exists($legacy)){
      try{
        $raw=[IO.File]::ReadAllText($legacy,[Text.Encoding]::UTF8)|ConvertFrom-Json
        $rows=@(ConvertTo-WidgetQuoteRows $raw)
        if($rows.Count){
          $daily=@(foreach($row in $rows){
            $matching=@($raw.quotes|Where-Object{$_.text-is [string] -and $_.text.Trim()-ceq $row.text})
            $expression=if($matching.Count -and $matching[0].expression-in @((Get-WidgetExpressionRegistry).name)){[string]$matching[0].expression}else{Get-WidgetQuoteExpression $row.text}
            @{text=$row.text;weight=$row.weight;expression=$expression}
          })
          $seed=ConvertTo-WidgetDialogueConfiguration @{version=1;daily=$daily;headpat=$defaults.headpat;lowQuota=$defaults.lowQuota}
        }
      }catch{} # An invalid legacy file leaves the bundled seed intact.
    }
    try{Write-WidgetDialogueFile $state $seed -NoOverwrite}catch{if(![IO.File]::Exists($state.path)){$state.error=$_.Exception.Message}}
  }
  Update-WidgetDialogueConfiguration $state ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -Force|Out-Null
  return $state
}
function Update-WidgetDialogueConfiguration($State,[long]$Now,[switch]$Force){
  try{$signature=Get-WidgetDialogueFileSignature $State.path}catch{$State.error=$_.Exception.Message;return $false}
  # Editors may briefly remove/replace their file. Keep the previous snapshot.
  if($signature-eq 'missing'){return $false}
  if(!$Force -and $signature-eq $State.signature){return $false}
  if(!$Force -and $signature-ne $State.pending){$State.pending=$signature;$State.pendingSince=$Now;return $false}
  if(!$Force -and $Now-$State.pendingSince-lt 300){return $false}
  $stream=$null;$reader=$null
  try{
    $stream=[IO.File]::Open($State.path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite-bor [IO.FileShare]::Delete))
    $reader=[IO.StreamReader]::new($stream,[Text.Encoding]::UTF8)
    $text=$reader.ReadToEnd();$reader.Dispose();$reader=$null;$stream=$null
    if((Get-WidgetDialogueFileSignature $State.path)-ne $signature){$State.pending='';return $false}
  }catch{$State.error=$_.Exception.Message;return $false}
  finally{if($reader){$reader.Dispose()}elseif($stream){$stream.Dispose()}}
  $State.signature=$signature
  try{$configuration=ConvertTo-WidgetDialogueConfiguration ($text|ConvertFrom-Json -ErrorAction Stop)}
  catch{$State.error=$_.Exception.Message;return $false}
  $State.current=$configuration;$State.custom=$true;$State.error='';$State.reloads++;$State.loadedAt=$Now
  # Current scenes already retain their pose in expressionState. Future selections bind anew.
  Initialize-WidgetQuoteExpressions $State.appDir
  return $true
}
function Save-WidgetDialogueConfiguration($State,$Value){
  $configuration=ConvertTo-WidgetDialogueConfiguration $Value
  Write-WidgetDialogueFile $State $configuration
  Update-WidgetDialogueConfiguration $State ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -Force|Out-Null
  if($State.error){throw $State.error}
  return $State.current
}
function Reset-WidgetDialogueConfiguration($State){return Save-WidgetDialogueConfiguration $State $State.defaults}
function Get-WidgetDialogueQuote($State,[ValidateSet('daily','headpat','lowQuota')][string]$Group,[string]$Level='',$PreviousState=$null){
  $rows=@($State.current.$Group)
  if($Group-eq 'lowQuota'){$rows=@($rows|Where-Object{$_.level-eq $Level})}
  if(!$rows.Count){return $null}
  $key=$Group+'/'+$Level
  $last=if($PreviousState){$PreviousState.lastQuote}else{$State.lastByGroup[$key]}
  $candidates=@($rows|Where-Object{$_.text-cne $last});if(!$candidates.Count){$candidates=$rows}
  $total=0.0;foreach($row in $candidates){$total+=$row.weight}
  $draw=$State.random.NextDouble()*$total;$choice=$candidates[-1]
  foreach($row in $candidates){$draw-=$row.weight;if($draw-lt 0){$choice=$row;break}}
  $State.lastByGroup[$key]=$choice.text;if($PreviousState){$PreviousState.lastQuote=$choice.text}
  if(!$script:quoteExpressionMap){$script:quoteExpressionMap=@{}}
  $script:quoteExpressionMap[$choice.text]=$choice.expression
  return $choice
}
