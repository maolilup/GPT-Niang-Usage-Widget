function Get-WidgetInstallationDataDir {
  param([Parameter(Mandatory=$true)][string]$AppDir,[Parameter(Mandatory=$true)]$Configuration)
  if(![string]$Configuration.appDir -or ![string]$Configuration.dataDir){throw 'Installation paths are missing.'}
  $root=[IO.Path]::GetFullPath($AppDir).TrimEnd('\')
  $previousRoot=[IO.Path]::GetFullPath([string]$Configuration.appDir).TrimEnd('\')
  $data=[IO.Path]::GetFullPath([string]$Configuration.dataDir)
  if($previousRoot-ine $root){
    # A moved installation may retain its preferences, but a copied active one may not claim the same registration.
    if(Test-Path -LiteralPath $previousRoot){throw 'The original installation folder still exists. Disable and move it before reinstalling.'}
    $disabled=[bool]$Configuration.disabledAt -or (Test-Path -LiteralPath (Join-Path $data 'supervisor-disabled.flag'))
    if(!$disabled){throw 'Installation was moved without disabling it first.'}
  }
  return $data
}

function Test-WidgetStartupShortcutIdentity {
  param([Parameter(Mandatory=$true)]$Shortcut,[Parameter(Mandatory=$true)][string]$AppDir)
  $expectedExecute=Join-Path $env:WINDIR 'System32\wscript.exe'
  $expectedArguments='"'+(Join-Path ([IO.Path]::GetFullPath($AppDir)) 'launch.vbs')+'"'
  return [bool]($Shortcut.TargetPath -and [IO.Path]::GetFullPath([string]$Shortcut.TargetPath)-ieq $expectedExecute -and [string]$Shortcut.Arguments-ieq $expectedArguments)
}

function Stop-WidgetGui {
  param([Parameter(Mandatory=$true)][string]$AppDir,[Parameter(Mandatory=$true)][string]$DataDir)
  $null=New-Item -ItemType Directory -Path $DataDir -Force
  [IO.File]::WriteAllText((Join-Path $DataDir 'stop.flag'),'stop')
  $runtime=$null
  try{$runtime=Get-Content -LiteralPath (Join-Path $DataDir 'runtime.json') -Raw -Encoding UTF8|ConvertFrom-Json}catch{}
  $guiPid=0
  if(!$runtime -or ![int]::TryParse([string]$runtime.pid,[ref]$guiPid) -or $guiPid-le 0){return}
  $process=Get-CimInstance Win32_Process -Filter ('ProcessId='+$guiPid) -ErrorAction Stop
  $expectedGui='"'+(Join-Path $AppDir 'widget.ps1')+'"'
  if(!$process -or $process.Name-notin @('powershell.exe','pwsh.exe') -or ![string]$process.CommandLine -or $process.CommandLine.IndexOf($expectedGui,[StringComparison]::OrdinalIgnoreCase)-lt 0){return}
  $deadline=[DateTime]::UtcNow.AddSeconds(6)
  do{
    $current=Get-CimInstance Win32_Process -Filter ('ProcessId='+$guiPid) -ErrorAction Stop
    # Do not wait for an unrelated process that reused the previous GUI's PID.
    if(!$current -or $current.CreationDate-ne $process.CreationDate){return}
    Start-Sleep -Milliseconds 100
  }while([DateTime]::UtcNow-lt $deadline)
  throw 'The previous widget did not stop within 6 seconds.'
}

function Open-WidgetSupervisorStateStream([string]$File){
  # The GUI atomically replaces heartbeat files. Readers must allow deletion
  # of the old file while retaining their own stable snapshot.
  return [IO.FileStream]::new($File,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite-bor [IO.FileShare]::Delete))
}
function Read-WidgetSupervisorPresence([string]$DataDir){
  $stream=$null;$reader=$null
  try{
    $stream=Open-WidgetSupervisorStateStream (Join-Path $DataDir 'presence.json')
    if($stream.Length-gt 1MB){return $null}
    $reader=[IO.StreamReader]::new($stream,[Text.Encoding]::UTF8,$true)
    return ($reader.ReadToEnd()|ConvertFrom-Json -ErrorAction Stop)
  }catch{return $null}
  finally{if($reader){$reader.Dispose()}elseif($stream){$stream.Dispose()}}
}
function Get-WidgetHeartbeatClock {
  try {
    $before=[GptWidgetDiagnosticClock]::UptimeMilliseconds
    $activeMs=[GptWidgetDiagnosticClock]::ActiveMilliseconds
    $after=[GptWidgetDiagnosticClock]::UptimeMilliseconds
    if($activeMs-lt 0){return $null}
    # Reject a suspend sample if this thread was delayed between clock reads.
    $suspendMs=if($after-$before-le 100){[Math]::Max(0L,$after-$activeMs)}else{-1L}
    return @{activeMs=$activeMs;suspendMs=$suspendMs}
  }catch{return $null}
}

function Get-WidgetResourceFault($Process,$Presence,[long]$Now,$HeartbeatState=$null,$Clock=$null){
  $startTicks=$Process.StartTime.ToUniversalTime().Ticks
  $started=[DateTimeOffset]::new($Process.StartTime.ToUniversalTime()).ToUnixTimeMilliseconds()
  if($HeartbeatState-is [Collections.IDictionary]){
    $key='{0}:{1}'-f $Process.Id,$startTicks
    $useActive=$null-ne $Clock -and $Clock.activeMs-ge 0
    $heartbeatNow=if($useActive){[long]$Clock.activeMs}else{$Now}
    if($HeartbeatState.key-ne $key -or $HeartbeatState.useActive-ne $useActive -or $heartbeatNow-lt $HeartbeatState.now){
      $HeartbeatState.Clear()
      $HeartbeatState.key=$key
      $HeartbeatState.useActive=$useActive
      $HeartbeatState.firstSeen=$heartbeatNow
      $HeartbeatState.startupUntil=$heartbeatNow+[Math]::Max(0L,60000L-[Math]::Max(0L,$Now-$started))
    }
    $HeartbeatState.now=$heartbeatNow

    if($useActive -and $Clock.suspendMs-ge 0){
      if($null-ne $HeartbeatState.suspendMs -and $Clock.suspendMs-$HeartbeatState.suspendMs-ge 2000){
        $HeartbeatState.resumeAt=$heartbeatNow
        $HeartbeatState.resumeUntil=$heartbeatNow+120000
      }
      $HeartbeatState.suspendMs=$Clock.suspendMs
    }

    if($Presence -and $Presence.pid-eq $Process.Id){
      $activeAt=0L
      $wallAt=0L
      if($useActive -and [long]::TryParse([string]$Presence.activeAt,[ref]$activeAt) -and $activeAt-gt 0){
        if($Presence.processStartTicks-eq $startTicks -and $activeAt-le $heartbeatNow -and
            (!$HeartbeatState.native -or $activeAt-gt $HeartbeatState.last.at)){
          $HeartbeatState.last=@{at=$activeAt}
          $HeartbeatState.native=$true
        }
      }elseif(!$HeartbeatState.native -and [long]::TryParse([string]$Presence.at,[ref]$wallAt) -and
          $wallAt-gt 0 -and $wallAt-le $Now -and $wallAt-ne $HeartbeatState.lastWallAt){
        # Older writers only publish UTC. Translate a changed, valid sample once
        # so repeated reads of the same file cannot renew its observed heartbeat.
        $projected=$heartbeatNow-($Now-$wallAt)
        if(!$HeartbeatState.last -or $projected-gt $HeartbeatState.last.at){
          $HeartbeatState.last=@{at=$projected}
          $HeartbeatState.lastWallAt=$wallAt
        }
      }
    }

    $age=if($HeartbeatState.last){$heartbeatNow-[long]$HeartbeatState.last.at}else{-1L}
    $HeartbeatState.heartbeatAgeMs=$age
    if($HeartbeatState.resumeUntil -and ($heartbeatNow-ge $HeartbeatState.resumeUntil -or
        ($HeartbeatState.last -and $HeartbeatState.last.at-gt $HeartbeatState.resumeAt))){
      $HeartbeatState.resumeUntil=0L
    }
    if($Process.PrivateMemorySize64-gt 512MB){return 'memory-limit'}
    if($heartbeatNow-lt $HeartbeatState.startupUntil -or $HeartbeatState.resumeUntil){return ''}
    if(!$HeartbeatState.last -and $heartbeatNow-$HeartbeatState.firstSeen-le 30000){return ''}
    if($age-lt 0 -or $age-gt 30000){return 'heartbeat-timeout'}
    return ''
  }

  if($Process.PrivateMemorySize64-gt 512MB){return 'memory-limit'}
  if($Now-$started-lt 60000){return ''}
  if(!$Presence -or $Presence.pid-ne $Process.Id){return 'heartbeat-timeout'}
  $at=0L
  if(![long]::TryParse([string]$Presence.at,[ref]$at)){return 'heartbeat-timeout'}
  $age=$Now-$at
  if($age-lt 0 -or $age-gt 30000){return 'heartbeat-timeout'}
  return ''
}

function Get-WidgetResourceRecovery($Previous,[string]$Reason,[long]$Now,[long]$PrivateBytes,[bool]$HeartbeatHealthy){
  $recent=[Collections.Generic.List[long]]::new();$valid=$true
  foreach($entry in @($Previous.restarts)){
    if($null-eq $entry){continue}
    $at=0L
    if(![long]::TryParse([string]$entry,[ref]$at) -or $at-le 0 -or $at-gt $Now){$valid=$false;break}
    if($Now-$at-lt 1800000){$recent.Add($at)}
  }
  $action='disable'
  if($valid -and $Reason-eq 'memory-limit' -and $HeartbeatHealthy -and $PrivateBytes-lt 768MB -and $recent.Count-lt 2){
    $action='restart';$recent.Add($Now)
  }
  [pscustomobject]@{action=$action;restarts=@($recent)}
}

function Stop-WidgetResourceFault($Process,[string]$AppDir,[string]$DataDir,[string]$Reason,$Presence=$null,$HeartbeatState=$null){
  # Recheck the executable and exact widget path before ending any process.
  $target=Get-CimInstance Win32_Process -Filter ('ProcessId='+$Process.Id) -ErrorAction Stop
  if(!$target -or $target.Name-notin @('powershell.exe','pwsh.exe') -or !$target.CommandLine -or !$target.CommandLine.Contains('"'+(Join-Path $AppDir 'widget.ps1')+'"')){return $false}
  if(!$target.CreationDate -or [Math]::Abs(($target.CreationDate.ToUniversalTime()-$Process.StartTime.ToUniversalTime()).TotalMilliseconds)-gt 1){return $false}
  $faultFile=Join-Path $DataDir 'resource-fault.json';$previous=$null
  if(Test-Path -LiteralPath $faultFile){
    try{$previous=Get-Content -LiteralPath $faultFile -Raw -Encoding UTF8|ConvertFrom-Json}
    catch{$previous=@{restarts=@('invalid')}}
  }
  # Read again after the identity and recovery-history I/O. Stop immediately
  # after the last check so persisting the fault cannot race a resumed GUI.
  $latest=Read-WidgetSupervisorPresence $DataDir
  if(!$latest){$latest=$Presence}
  $Process.Refresh()
  if($Process.HasExited){return $false}
  $now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $clock=Get-WidgetHeartbeatClock
  $currentFault=Get-WidgetResourceFault $Process $latest $now $HeartbeatState $clock
  if($Reason-eq 'heartbeat-timeout' -and $currentFault-ne 'heartbeat-timeout'){return $false}
  $age=-1L
  if($HeartbeatState-is [Collections.IDictionary] -and $HeartbeatState.Contains('heartbeatAgeMs')){
    $age=$HeartbeatState.heartbeatAgeMs
  }elseif($latest -and $latest.pid-eq $Process.Id){
    $at=0L
    if([long]::TryParse([string]$latest.at,[ref]$at)){$age=$now-$at}
  }
  $healthy=$age-ge 0 -and $age-le 30000
  $privateBytes=$Process.PrivateMemorySize64
  $recovery=Get-WidgetResourceRecovery $previous $Reason $now $privateBytes ([bool]$healthy)
  $action=if($recovery.action-eq 'restart'){'restart-after-cooldown'}else{'disabled-until-manual-open'}
  Stop-Process -InputObject $Process -ErrorAction Stop
  try{
    Write-WidgetSupervisorJson $faultFile @{pid=$Process.Id;at=[DateTime]::UtcNow.ToString('o');reason=$Reason;privateBytes=$privateBytes;action=$action;restarts=$recovery.restarts}
  }catch{
    # If recovery history cannot be persisted, stop rather than risk a restart loop.
    $recovery.action='disable'
  }
  if($recovery.action-eq 'disable'){try{Disable-WidgetSupervisor -AppDir $AppDir}catch{}}
  return [pscustomobject]@{stopped=$true;action=$recovery.action}
}

function Get-WidgetSupervisorInfo {
  param([Parameter(Mandatory=$true)][string]$AppDir,$Configuration=$null)
  $root=[IO.Path]::GetFullPath($AppDir).TrimEnd('\')
  $config=$Configuration
  if(!$config){$config=Get-Content -LiteralPath (Join-Path $root 'installation.json') -Raw -Encoding UTF8 -ErrorAction Stop|ConvertFrom-Json}
  if(![string]$config.appDir -or ![string]$config.dataDir){throw 'Installation paths are missing.'}
  if([IO.Path]::GetFullPath([string]$config.appDir).TrimEnd('\')-ine $root){throw 'Supervisor installation identity mismatch.'}
  $data=[IO.Path]::GetFullPath([string]$config.dataDir)
  $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  [pscustomobject]@{AppDir=$root;DataDir=$data;Sid=$sid;TaskName=('GPT Niang Usage - '+$sid);TaskPath='\';Execute=(Join-Path $env:WINDIR 'System32\wscript.exe');Arguments=('"'+(Join-Path $root 'supervisor.vbs')+'"');WorkingDirectory=$root}
}

function Resolve-WidgetSupervisorSid([string]$Identity){
  if($Identity-match '^S-\d-') {return ([Security.Principal.SecurityIdentifier]::new($Identity)).Value}
  return ([Security.Principal.NTAccount]::new($Identity)).Translate([Security.Principal.SecurityIdentifier]).Value
}

function Assert-WidgetSupervisorTaskIdentity {
  param([Parameter(Mandatory=$true)]$Task,[Parameter(Mandatory=$true)]$Info)
  if($Task.TaskName-ine $Info.TaskName -or $Task.TaskPath-ine $Info.TaskPath){throw 'Supervisor task name mismatch.'}
  if((Resolve-WidgetSupervisorSid ([string]$Task.Principal.UserId))-ne $Info.Sid){throw 'Supervisor task owner mismatch.'}
  if([string]$Task.Principal.LogonType-notin @('Interactive','3') -or [string]$Task.Principal.RunLevel-notin @('Limited','0')){throw 'Supervisor task privilege mismatch.'}
  $actions=@($Task.Actions)
  if($actions.Count-ne 1){throw 'Supervisor task action count mismatch.'}
  $action=$actions[0]
  if([IO.Path]::GetFullPath([string]$action.Execute)-ine $Info.Execute -or [string]$action.Arguments-ine $Info.Arguments -or [IO.Path]::GetFullPath([string]$action.WorkingDirectory).TrimEnd('\')-ine $Info.WorkingDirectory){throw 'Supervisor task action path mismatch.'}
}

function Get-WidgetSupervisorTask {
  param([Parameter(Mandatory=$true)]$Info)
  $tasks=@(Get-ScheduledTask -TaskPath $Info.TaskPath -ErrorAction Stop|Where-Object{$_.TaskName-eq $Info.TaskName})
  if($tasks.Count-gt 1){throw 'Multiple supervisor tasks found.'}
  if($tasks.Count-eq 1){Assert-WidgetSupervisorTaskIdentity $tasks[0] $Info;return $tasks[0]}
  return $null
}

function Write-WidgetSupervisorJson([string]$File,$Value){
  $null=New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($File)) -Force
  $temp=$File+'.'+$PID+'.'+[Guid]::NewGuid().ToString('N')+'.tmp'
  try{
    [IO.File]::WriteAllText($temp,($Value|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
    if([IO.File]::Exists($File)){[IO.File]::Replace($temp,$File,[System.Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($temp,$File)}
  }finally{if([IO.File]::Exists($temp)){[IO.File]::Delete($temp)}}
}

function Set-WidgetSupervisorPause {
  param([Parameter(Mandatory=$true)][string]$AppDir,[long]$HostHandle=0,[int]$HostPid=0)
  $info=Get-WidgetSupervisorInfo $AppDir
  if($HostHandle-le 0){try{$presence=Get-Content -LiteralPath (Join-Path $info.DataDir 'presence.json') -Raw -Encoding UTF8|ConvertFrom-Json;$HostHandle=[long]$presence.host}catch{}}
  if($HostHandle-gt 0 -and $HostPid-le 0){
    if(!('GptWidgetSupervisorPauseNative' -as [type])){Add-Type -TypeDefinition @'
using System;using System.Runtime.InteropServices;
public static class GptWidgetSupervisorPauseNative {
 [DllImport("user32.dll")]static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
 public static int ProcessId(IntPtr h){uint pid;GetWindowThreadProcessId(h,out pid);return (int)pid;}
}
'@}
    $HostPid=[GptWidgetSupervisorPauseNative]::ProcessId([IntPtr]$HostHandle)
  }
  $started=0L
  if($HostPid-gt 0){try{$started=(Get-Process -Id $HostPid -ErrorAction Stop).StartTime.ToUniversalTime().Ticks}catch{}}
  Write-WidgetSupervisorJson (Join-Path $info.DataDir 'supervisor-pause.json') @{host=$HostHandle;hostPid=$HostPid;hostStarted=$started;at=[DateTime]::UtcNow.ToString('o')}
}

function Resume-WidgetSupervisor {
  param([Parameter(Mandatory=$true)][string]$AppDir)
  $info=Get-WidgetSupervisorInfo $AppDir
  foreach($name in @('supervisor-pause.json','supervisor-disabled.flag','supervisor-stop.flag')){
    $file=Join-Path $info.DataDir $name
    if(Test-Path -LiteralPath $file){Remove-Item -LiteralPath $file -ErrorAction Stop}
  }
}

function Disable-WidgetSupervisor {
  param([Parameter(Mandatory=$true)][string]$AppDir)
  $info=Get-WidgetSupervisorInfo $AppDir
  $null=New-Item -ItemType Directory -Path $info.DataDir -Force
  [IO.File]::WriteAllText((Join-Path $info.DataDir 'supervisor-disabled.flag'),'disabled')
}

function New-WidgetSupervisorTaskDefinition {
  param([Parameter(Mandatory=$true)]$Info)
  $action=New-ScheduledTaskAction -Execute $Info.Execute -Argument $Info.Arguments -WorkingDirectory $Info.WorkingDirectory
  $principal=New-ScheduledTaskPrincipal -UserId $Info.Sid -LogonType Interactive -RunLevel Limited
  $trigger=New-ScheduledTaskTrigger -AtLogOn -User $Info.Sid
  $settings=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -StartWhenAvailable -Hidden
  New-ScheduledTask -Action $action -Principal $principal -Trigger $trigger -Settings $settings -Description 'Keep the local GPT Niang widget attached to the current user Codex main window.'
}

function Register-WidgetSupervisorTask {
  param([Parameter(Mandatory=$true)][string]$AppDir)
  $info=Get-WidgetSupervisorInfo $AppDir
  foreach($relative in @('supervisor.vbs','runtime\supervisor.ps1','widget.ps1')){if(!(Test-Path -LiteralPath (Join-Path $info.AppDir $relative))){throw "Missing supervisor file: $relative"}}
  $existing=Get-WidgetSupervisorTask $info
  if($existing -and [string]$existing.State-eq 'Running'){Stop-WidgetSupervisorTask $AppDir}
  Resume-WidgetSupervisor $AppDir
  $definition=New-WidgetSupervisorTaskDefinition $info
  Register-ScheduledTask -TaskName $info.TaskName -TaskPath $info.TaskPath -InputObject $definition -Force -ErrorAction Stop|Out-Null
  $registered=Get-WidgetSupervisorTask $info
  if(!$registered){throw 'Supervisor task registration not confirmed.'}
  Start-ScheduledTask -TaskName $info.TaskName -TaskPath $info.TaskPath -ErrorAction Stop
  return $info
}

function Start-WidgetSupervisorTask {
  param([Parameter(Mandatory=$true)][string]$AppDir)
  $info=Get-WidgetSupervisorInfo $AppDir
  $task=Get-WidgetSupervisorTask $info
  if(!$task){throw 'Supervisor task is not installed.'}
  Resume-WidgetSupervisor $AppDir
  Start-ScheduledTask -TaskName $info.TaskName -TaskPath $info.TaskPath -ErrorAction Stop
}

function Stop-WidgetSupervisorTask {
  param([Parameter(Mandatory=$true)][string]$AppDir)
  $info=Get-WidgetSupervisorInfo $AppDir
  $task=Get-WidgetSupervisorTask $info
  # Task state alone does not prove its child PowerShell has exited.
  $expectedScript='"'+(Join-Path $info.AppDir 'runtime\supervisor.ps1')+'"'
  $processes=@(Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" -ErrorAction Stop|Where-Object{
    [string]$_.CommandLine -and $_.CommandLine.IndexOf($expectedScript,[StringComparison]::OrdinalIgnoreCase)-ge 0
  })
  $null=New-Item -ItemType Directory -Path $info.DataDir -Force
  [IO.File]::WriteAllText((Join-Path $info.DataDir 'supervisor-stop.flag'),'stop')
  if($task -and [string]$task.State-eq 'Running'){
    Stop-ScheduledTask -TaskName $info.TaskName -TaskPath $info.TaskPath -ErrorAction Stop
  }
  $deadline=[DateTime]::UtcNow.AddSeconds(6)
  do{
    $running=$false
    if($task){
      $stopped=Get-ScheduledTask -TaskName $info.TaskName -TaskPath $info.TaskPath -ErrorAction Stop
      Assert-WidgetSupervisorTaskIdentity $stopped $info
      $running=[string]$stopped.State-eq 'Running'
    }
    foreach($process in $processes){
      $current=Get-CimInstance Win32_Process -Filter ('ProcessId='+[int]$process.ProcessId) -ErrorAction Stop
      if($current -and $current.CreationDate-eq $process.CreationDate){$running=$true}
    }
    if(!$running){return}
    Start-Sleep -Milliseconds 150
  }while([DateTime]::UtcNow-lt $deadline)
  throw 'Supervisor did not stop within 6 seconds.'
}

function Unregister-WidgetSupervisorTask {
  param([Parameter(Mandatory=$true)][string]$AppDir)
  $info=Get-WidgetSupervisorInfo $AppDir
  $task=Get-WidgetSupervisorTask $info
  Disable-WidgetSupervisor $AppDir
  Stop-WidgetSupervisorTask $AppDir
  if($task){Unregister-ScheduledTask -TaskName $info.TaskName -TaskPath $info.TaskPath -Confirm:$false -ErrorAction Stop}
}
