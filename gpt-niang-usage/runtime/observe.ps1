param([ValidateRange(5,86400)][int]$DurationSeconds=3600)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'diagnostics.ps1')
$null=. (Join-Path $PSScriptRoot 'supervisor.ps1') -CheckOnly
$appDir=Split-Path $PSScriptRoot -Parent
$info=Get-WidgetSupervisorInfo $appDir
$log=New-WidgetDiagnosticLog $info.DataDir 'observer'
# A fixed installation key prevents multiple observers accumulating in memory.
$mutex=[Threading.Mutex]::new($false,('Local\GPTNiangObserver-'+[IO.Path]::GetFileNameWithoutExtension($log.path)+'-'+$info.Sid))
$owned=$false
try{$owned=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$owned=$true}
if(!$owned){Close-WidgetDiagnosticLog $log;$mutex.Dispose();exit 0}
$tracked=@{};$stopFile=Join-Path $info.DataDir 'diagnostics-stop.flag'
$initialStop=if(Test-Path -LiteralPath $stopFile){[IO.File]::ReadAllText($stopFile)}else{$null}
$clock=[Diagnostics.Stopwatch]::StartNew();$reason='duration-complete';$observedEvents=@{};$lastSelfSample=0L
function Add-ObservedWidgetProcess([int]$ProcessId,[long]$Started,[string]$Role){
  $key='{0}:{1}'-f $ProcessId,$Started
  if($tracked.ContainsKey($key)){return}
  $process=$null
  try{
    $process=Get-Process -Id $ProcessId -ErrorAction Stop
    if($process.StartTime.ToUniversalTime().Ticks-ne $Started){$process.Dispose();return}
    $null=$process.Handle # Retain a read handle so exit code survives teardown.
    $tracked[$key]=@{process=$process;role=$Role}
    Write-WidgetDiagnostic $log ($Role+'-seen') @{childPid=$ProcessId;processStartedAt=$process.StartTime.ToUniversalTime().ToString('o')} -Force
  }catch{if($process){$process.Dispose()};Write-WidgetDiagnosticError $log 'process-open-error' $_ $Role}
}
function Write-RecentWidgetSystemEvents {
  foreach($channel in @('Application','System')){
    $ids=if($channel-eq 'Application'){@(1000,1001,1002,1026)}else{@(2004,4101)}
    try{
      $events=@(Get-WinEvent -FilterHashtable @{LogName=$channel;Id=$ids;StartTime=[DateTime]::Now.AddMinutes(-2)} -MaxEvents 24 -ErrorAction Stop)
      foreach($item in $events){
        $key=$channel+':'+$item.RecordId
        if($observedEvents.ContainsKey($key)){continue}
        if($observedEvents.Count-ge 256){$observedEvents.Clear()}
        $observedEvents[$key]=$true
        Write-WidgetDiagnostic $log 'system-event' @{state=$channel;eventId=$item.Id;recordId=$item.RecordId;provider=$item.ProviderName;observedUtc=$item.TimeCreated.ToUniversalTime().ToString('o')} -Force
      }
    }catch{if($_.FullyQualifiedErrorId-notlike 'NoMatchingEventsFound*'){Write-WidgetDiagnosticError $log 'event-read-error' $_ $channel}}
  }
}
try{
  Write-WidgetDiagnostic $log 'start' @{remainingMinutes=[Math]::Round($DurationSeconds/60.0,2);reason='read-only-observation'} -Force
  while($clock.Elapsed.TotalSeconds-lt $DurationSeconds){
    if((Test-Path -LiteralPath $stopFile) -and [IO.File]::ReadAllText($stopFile)-ne $initialStop){$reason='stop-request';break}
    foreach($hostWindow in @([GptWidgetSupervisorNative]::Hosts())){Add-ObservedWidgetProcess $hostWindow.pid $hostWindow.started 'host'}
    if(Get-WidgetSupervisorRunningGui $info.DataDir $info.AppDir){
      try{$runtime=Get-Content -LiteralPath (Join-Path $info.DataDir 'runtime.json') -Raw -Encoding UTF8|ConvertFrom-Json;Add-ObservedWidgetProcess ([int]$runtime.pid) ([DateTime]$runtime.processStartedAt).ToUniversalTime().Ticks 'gui'}catch{Write-WidgetDiagnosticError $log 'runtime-read-error' $_ 'gui-discovery'}
    }
    foreach($key in @($tracked.Keys)){
      $entry=$tracked[$key];$sample=Get-WidgetDiagnosticProcessState $entry.process
      Write-WidgetDiagnostic $log ($entry.role+'-'+$sample.state) $sample -Force
      if($sample.state-eq 'exited'){
        $entry.process.Dispose();$tracked.Remove($key)
        Write-RecentWidgetSystemEvents
      }
    }
    if($clock.ElapsedMilliseconds-$lastSelfSample-ge 10000){
      $lastSelfSample=$clock.ElapsedMilliseconds;$self=[Diagnostics.Process]::GetCurrentProcess()
      try{Write-WidgetDiagnostic $log 'sample' (Get-WidgetDiagnosticProcessState $self) -Force}finally{$self.Dispose()}
    }
    Write-WidgetSupervisorJson (Join-Path $info.DataDir 'diagnostics-status.json') @{pid=$PID;at=[DateTime]::UtcNow.ToString('o');session=$log.session;endsAt=[DateTime]::UtcNow.AddSeconds([Math]::Max(0,$DurationSeconds-$clock.Elapsed.TotalSeconds)).ToString('o')}
    Start-Sleep -Seconds 5
  }
}catch{Write-WidgetDiagnosticError $log 'fatal' $_ 'observer';throw}
finally{
  Write-WidgetDiagnostic $log 'exit' @{reason=$reason} -Force
  foreach($entry in $tracked.Values){$entry.process.Dispose()}
  Close-WidgetDiagnosticLog $log
  try{$mutex.ReleaseMutex()}catch{};$mutex.Dispose()
}
