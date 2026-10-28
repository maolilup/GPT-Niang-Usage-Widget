# Fixed-size, best-effort JSONL. No UI callbacks, background queue or transcript.
if(!('GptWidgetDiagnosticClock' -as [type])){
  try{Add-Type -TypeDefinition @'
using System;using System.Runtime.InteropServices;
public static class GptWidgetDiagnosticClock {
 [DllImport("kernel32.dll")]static extern bool QueryUnbiasedInterruptTime(out ulong time);
 public static long ActiveMilliseconds {get{ulong time;return QueryUnbiasedInterruptTime(out time)?(long)(time/10000):-1;}}
}
'@}catch{}
}
function New-WidgetDiagnosticStage([string]$Stage,[long]$Now=-1){
  try{if($Now-lt 0){$Now=[GptWidgetDiagnosticClock]::ActiveMilliseconds};if($Now-lt 0){return $null};return @{stage=$Stage;started=$Now;since=$Now;activeMs=0L}}catch{return $null}
}
function Set-WidgetDiagnosticStage($Log,$State,[string]$Stage,[long]$Now=-1){
  if(!$State){return}
  try{
    $providedClock=$Now-ge 0
    if($Now-lt 0){$Now=[GptWidgetDiagnosticClock]::ActiveMilliseconds}
    if($Now-lt [long]$State.since){return}
    $duration=$Now-[long]$State.since
    $previous=$State.stage;$State.activeMs=$Now-[long]$State.started;$State.stage=$Stage;$State.since=$Now
    if($duration-ge 1000){
      Write-WidgetDiagnostic $Log 'slow-stage' @{stage=$previous;elapsedMs=$duration;tickActiveMs=$State.activeMs} -Force
      # Do not attribute diagnostic file I/O to the operation that starts next.
      if(!$providedClock){$afterLog=[GptWidgetDiagnosticClock]::ActiveMilliseconds;if($afterLog-ge $Now){$State.since=$afterLog}}
    }
  }catch{}
}
function New-WidgetDiagnosticLog([string]$DataDir,[ValidateSet('widget','supervisor','observer')][string]$Component,[int]$MaxBytes=1048576){
  $directory=Join-Path $DataDir 'logs'
  $hash=[Security.Cryptography.SHA256]::Create()
  try{$key=[BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes(([IO.Path]::GetFullPath($directory).ToLowerInvariant()+$Component)))).Replace('-','')}finally{$hash.Dispose()}
  $mutex=$null;try{$mutex=[Threading.Mutex]::new($false,('Local\GPTNiangLog-'+$key))}catch{}
  return @{path=(Join-Path $directory ($Component+'.jsonl'));directory=$directory;component=$Component;session=[Guid]::NewGuid().ToString('N');clock=[Diagnostics.Stopwatch]::StartNew();maxBytes=[Math]::Max(4096,$MaxBytes);mutex=$mutex;retryAt=0L;last=@{};suppressed=0L}
}
function Write-WidgetDiagnostic($Log,[string]$Event,[System.Collections.IDictionary]$Data=@{},[switch]$Force){
  if(!$Log -or !$Log.mutex -or $Event-notmatch '^[a-z][a-z0-9-]{0,63}$'){return}
  $now=$Log.clock.ElapsedMilliseconds
  if($now-lt $Log.retryAt){return}
  if(!$Force -and $Log.last.ContainsKey($Event) -and $now-[long]$Log.last[$Event]-lt 1000){$Log.suppressed++;return}
  $owned=$false;$stream=$null
  try{
    try{$owned=$Log.mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$owned=$true}
    if(!$owned){$Log.suppressed++;return}
    # Only diagnostic primitives from explicitly permitted fields are accepted.
    $allowed='privateBytes workingSetBytes managedBytes handles cpuMs threads uptimeMs stage state reason action hostPid host widget visible hostVisible foreground owner topmost displayScale scale spriteBytes spriteCount spriteDecodes followEvents positionChanges tickMs tickActiveMs heartbeatAgeMs faultSamples childPid parentPid exitCode signal ok queryOk errorCode errorType hresult stack elapsedMs method requestId pending queryId eventId recordId provider observedUtc osError changed count nextLaunchMs processStartedAt policy version sourceVersion enabled paused mainWindows busy hostEvents frameWidth frameHeight remainingMinutes'.Split(' ')
    $safe=@{}
    foreach($key in $allowed){
      if(!$Data.Contains($key)){continue};$value=$Data[$key]
      if($null-eq $value -or $value-is [bool] -or $value-is [ValueType]){$safe[$key]=$value}
      elseif($value-is [string]){$limit=if($key-eq 'stack'){1536}else{256};$safe[$key]=$value.Substring(0,[Math]::Min($limit,$value.Length))}
    }
    $row=@{schema=1;utc=[DateTime]::UtcNow.ToString('o');pid=$PID;component=$Log.component;session=$Log.session;elapsedMs=$now;event=$Event;suppressed=$Log.suppressed;data=$safe}
    $bytes=[Text.Encoding]::UTF8.GetBytes(($row|ConvertTo-Json -Depth 4 -Compress)+"`n")
    if($bytes.Length-gt $Log.maxBytes){return}
    $null=[IO.Directory]::CreateDirectory($Log.directory)
    if([IO.File]::Exists($Log.path) -and ([IO.FileInfo]$Log.path).Length+$bytes.Length-gt $Log.maxBytes){
      $old=$Log.path.Replace('.jsonl','.2.jsonl');$previous=$Log.path.Replace('.jsonl','.1.jsonl')
      if([IO.File]::Exists($old)){[IO.File]::Delete($old)}
      if([IO.File]::Exists($previous)){[IO.File]::Move($previous,$old)}
      [IO.File]::Move($Log.path,$previous)
    }
    $stream=[IO.FileStream]::new($Log.path,[IO.FileMode]::Append,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite)
    $stream.Write($bytes,0,$bytes.Length);$stream.Flush();$Log.suppressed=0
    if($Log.last.Count-lt 64 -or $Log.last.ContainsKey($Event)){$Log.last[$Event]=$now}
  }catch{$Log.retryAt=$now+5000;$Log.suppressed++}
  finally{if($stream){try{$stream.Dispose()}catch{}};if($owned){try{$Log.mutex.ReleaseMutex()}catch{}}}
}
function Write-WidgetDiagnosticError($Log,[string]$Event,$Record,[string]$Stage){
  # Stack frames carry locations; exception messages may contain account/RPC data.
  try{
    $exception=if($Record-is [Exception]){$Record}else{$Record.Exception}
    $frames=if($Record-is [Exception]){''}else{[string]$Record.ScriptStackTrace}
    $cause=$exception
    for($depth=0;$depth-lt 8 -and $cause.InnerException;$depth++){$cause=$cause.InnerException}
    Write-WidgetDiagnostic $Log $Event @{stage=$Stage;errorType=$cause.GetType().FullName;hresult=$cause.HResult;stack=($frames+"`n"+[string]$exception.StackTrace)}
  }catch{}
}
function Close-WidgetDiagnosticLog($Log){if($Log -and $Log.mutex){try{$Log.mutex.Dispose()}catch{};$Log.mutex=$null}}
function Get-WidgetDiagnosticProcessState([Diagnostics.Process]$Process){
  try{
    $Process.Refresh()
    if($Process.HasExited){return @{state='exited';childPid=$Process.Id;exitCode=$Process.ExitCode}}
    return @{state='running';childPid=$Process.Id;processStartedAt=$Process.StartTime.ToUniversalTime().ToString('o');privateBytes=$Process.PrivateMemorySize64;workingSetBytes=$Process.WorkingSet64;handles=$Process.HandleCount;threads=$Process.Threads.Count;cpuMs=[long]$Process.TotalProcessorTime.TotalMilliseconds}
  }catch{return @{state='unavailable';errorType=$_.Exception.GetType().FullName;hresult=$_.Exception.HResult}}
}
