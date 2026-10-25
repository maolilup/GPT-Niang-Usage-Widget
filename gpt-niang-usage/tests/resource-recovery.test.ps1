param([string]$TestRoot=$PSScriptRoot)
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path $TestRoot -Parent) 'runtime\supervisor-task.ps1')
if(!(Get-Command Get-WidgetResourceRecovery -ErrorAction SilentlyContinue)){throw 'A single healthy memory-limit incident permanently disables the widget; bounded automatic recovery is missing.'}
$now=1800000000000L
function Assert-Action($Previous,[string]$Reason,[long]$At,[long]$Private,[bool]$Healthy,[string]$Expected){
  $result=Get-WidgetResourceRecovery $Previous $Reason $At $Private $Healthy
  if($result.action-ne $Expected){throw "Recovery action: expected $Expected, got $($result.action)"}
  return $result
}
$first=Assert-Action $null 'memory-limit' $now 520MB $true 'restart'
if(@($first.restarts).Count-ne 1 -or $first.restarts[0]-ne $now){throw 'First recovery was not recorded.'}
$second=Assert-Action $first 'memory-limit' ($now+60000) 520MB $true 'restart'
if(@($second.restarts).Count-ne 2){throw 'Recovery history is not persisted across GUI lifetimes.'}
$null=Assert-Action $second 'memory-limit' ($now+120000) 520MB $true 'disable'
$expired=Assert-Action $second 'memory-limit' ($now+1800000+60001) 520MB $true 'restart'
if(@($expired.restarts).Count-ne 1){throw 'Old recovery entries never expire.'}
$null=Assert-Action $null 'heartbeat-timeout' $now 100MB $false 'disable'
$null=Assert-Action $null 'memory-limit' $now 520MB $false 'disable'
$null=Assert-Action $null 'memory-limit' $now 768MB $true 'disable'
$null=Assert-Action $null 'memory-limit' $now 3GB $true 'disable'
$null=Assert-Action @{restarts=@($now+1)} 'memory-limit' $now 520MB $true 'disable'
$null=Assert-Action @{restarts=@('invalid')} 'memory-limit' $now 520MB $true 'disable'
'PASS: healthy memory recovery, two restarts per 30 minutes, expiry, severe memory/stalled heartbeat circuit breaker and invalid-history protection'
