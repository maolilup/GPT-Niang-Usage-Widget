param([string]$TestRoot=$PSScriptRoot)
$ErrorActionPreference='Stop'
$source=[IO.File]::ReadAllText((Join-Path (Split-Path $TestRoot -Parent) 'widget.ps1'),[Text.Encoding]::UTF8)
$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$null,[ref]$null)
$tick=$ast.Find({param($node)$node-is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name-eq 'Tick-Widget'},$true).Extent.Text
# Isolate the real diagnostics prefix, before scene/native-window work begins.
$prefix=$tick.Substring(0,$tick.IndexOf('  Tick-Scene $now'))+"`n}finally{`$script:updating=`$false}}"
. ([ScriptBlock]::Create($prefix))
$script:expressionCache=@{};$script:expressionCacheBytes=0L;$script:expressionDecodeCount=0L
$script:dataDir='unused';$script:updating=$false;$script:lastResourceProbe=0L;$script:writes=0
function Write-WidgetJson($File,$Value){$script:writes++;throw [IO.IOException]::new('Sharing violation while another process reads diagnostics.')}
try{Tick-Widget}catch{throw 'A locked diagnostic file aborts the UI tick and can starve the heartbeat.'}
if($script:updating -or $script:lastResourceProbe-le 0){throw 'Diagnostic failure did not release the tick or advance its sampling clock.'}
Tick-Widget
if($script:writes-ne 1){throw 'A failed diagnostic write is retried on every UI tick.'}
$script:lastResourceProbe=0L;$script:snapshot=$null
function Write-WidgetJson($File,$Value){$script:snapshot=$Value}
Tick-Widget
if(!$script:snapshot -or $script:snapshot.pid-ne $PID -or $script:snapshot.privateBytes-le 0){throw 'Healthy resource sampling stopped working.'}
$writer=$ast.Find({param($node)$node-is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name-eq 'Write-WidgetJson'},$true)
. ([ScriptBlock]::Create($writer.Extent.Text))
$script:dataDir=Join-Path (Split-Path (Split-Path $TestRoot -Parent) -Parent) ('test-temp\resource-probe-'+[guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($script:dataDir)
$file=Join-Path $script:dataDir 'resource-status.json';[IO.File]::WriteAllText($file,'{}')
$reader=[IO.File]::Open($file,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
try{$script:lastResourceProbe=0L;Tick-Widget}finally{$reader.Dispose()}
$script:lastResourceProbe=0L;Tick-Widget
if((Get-Content $file -Raw|ConvertFrom-Json).pid-ne $PID){throw 'Sampling did not recover after a real file-sharing conflict.'}
'PASS: locked diagnostics do not abort UI/heartbeat work, failed probes stay throttled and healthy probes record current-process memory'
