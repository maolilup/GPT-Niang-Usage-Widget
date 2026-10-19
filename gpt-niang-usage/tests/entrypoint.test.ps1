param([string]$PreviewDirectory)
$ErrorActionPreference='Stop'
$source=Split-Path $PSScriptRoot -Parent
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('gpt-niang-entrypoint-'+[Guid]::NewGuid().ToString('N'))
$testApp=Join-Path $testRoot 'app'
$testData=Join-Path $testRoot 'state'
$files=@('widget.ps1','widget.xaml','runtime\start-widget.ps1','runtime\quotes.ps1','runtime\ui-settings.ps1','runtime\color-theme.ps1','runtime\quote-layout.ps1','runtime\expressions.ps1','runtime\headpat.ps1','runtime\low-quota.ps1','runtime\dialogue-config.ps1','runtime\audio.ps1','runtime\host-layer.ps1','runtime\host-follow.ps1','runtime\supervisor-task.ps1','assets\quotes.json','assets\headpat-quotes.json','assets\low-quota-quotes.json','assets\quote-layouts.json','assets\gpt-dragon-niang-bust.png')
$directories=@($testRoot,$testApp,$testData,(Join-Path $testApp 'runtime'),(Join-Path $testApp 'assets'))
try{
  foreach($directory in $directories){$null=New-Item -ItemType Directory -Path $directory}
  foreach($file in $files){Copy-Item -LiteralPath (Join-Path $source $file) -Destination (Join-Path $testApp $file)}
  $config=@{appDir=$testApp;dataDir=$testData;codexPath='unused-in-preview'}
  [IO.File]::WriteAllText((Join-Path $testApp 'installation.json'),($config|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText((Join-Path $testData 'settings.json'),(@{scale=0.8;expressionMode='neutral';hideMenu=$true}|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
  $snapshot=@{ok=$true;queryOk=$true;observedAt=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();windows=@(@{minutes=300;used=25;remaining=75;resetsAt=$null},@{minutes=10080;used=10;remaining=90;resetsAt=$null})}
  [IO.File]::WriteAllText((Join-Path $testData 'status.json'),($snapshot|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
  $powerShell=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $checked=& $powerShell -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $testApp 'runtime\start-widget.ps1') -WidgetPath (Join-Path $testApp 'widget.ps1') -CheckOnly
  if($LASTEXITCODE-ne 0){throw 'The startup preference check failed.'}
  $restored=($checked -join "`n")|ConvertFrom-Json
  if(!$restored.ok -or [Math]::Abs([double]$restored.scale-0.8)-gt 0.001 -or $restored.expressionMode-ne 'neutral'){throw 'The entry point did not restore saved size and manual expression preferences.'}
  if($restored.autoDialogue-ne $true){throw 'Automatic dialogue should default to enabled when no preference exists.'}
  $settings=@{scale=0.8;expressionMode='neutral';hideMenu=$true;autoDialogue=$false}
  [IO.File]::WriteAllText((Join-Path $testData 'settings.json'),($settings|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
  $checked=& $powerShell -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $testApp 'runtime\start-widget.ps1') -WidgetPath (Join-Path $testApp 'widget.ps1') -CheckOnly
  if($LASTEXITCODE-ne 0 -or (($checked-join "`n")|ConvertFrom-Json).autoDialogue-ne $false){throw 'The startup entry point must preserve disabled automatic dialogue.'}
  & $powerShell -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $testApp 'runtime\start-widget.ps1') -WidgetPath (Join-Path $testApp 'widget.ps1') -Preview
  if($LASTEXITCODE-ne 0){throw 'The full WPF entry point failed.'}
  $preview=Join-Path $testApp 'preview.png'
  if(!(Test-Path -LiteralPath $preview) -or [IO.File]::ReadAllBytes($preview).Length-lt 1000){throw 'The WPF preview is missing or empty.'}
  if($PreviewDirectory){
    $null=New-Item -ItemType Directory -Path $PreviewDirectory -Force
    Copy-Item -LiteralPath $preview -Destination (Join-Path $PreviewDirectory 'quota-aligned.png')
  }
  Write-Output 'PASS: full WPF widget, UTF-8 entry point and restored size/manual expression preferences on Windows PowerShell 5.1'
}finally{
  $resolved=[IO.Path]::GetFullPath($testRoot)
  $prefix=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
  if(!$resolved.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved)-notlike 'gpt-niang-entrypoint-*'){throw 'Unsafe entrypoint test cleanup path.'}
  foreach($file in ($files+@('installation.json','preview.png'))){$target=Join-Path $testApp $file;if(Test-Path -LiteralPath $target){Remove-Item -LiteralPath $target}}
  foreach($name in @('status.json','settings.json')){$stateFile=Join-Path $testData $name;if(Test-Path -LiteralPath $stateFile){Remove-Item -LiteralPath $stateFile}}
  [Array]::Reverse($directories)
  foreach($directory in $directories){if(Test-Path -LiteralPath $directory){Remove-Item -LiteralPath $directory}}
}
