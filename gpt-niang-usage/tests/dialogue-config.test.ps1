param([string]$TestRoot=$PSScriptRoot)
$ErrorActionPreference='Stop'
$app=Split-Path $TestRoot -Parent
$module=Join-Path $app 'runtime\dialogue-config.ps1'
if(!(Test-Path -LiteralPath $module)){throw 'Missing live dialogue configuration: text and expression must reload together.'}
. (Join-Path $app 'runtime\quotes.ps1')
. ([ScriptBlock]::Create([IO.File]::ReadAllText((Join-Path $app 'runtime\expressions.ps1'),[Text.Encoding]::UTF8)))
. ([ScriptBlock]::Create([IO.File]::ReadAllText((Join-Path $app 'runtime\headpat.ps1'),[Text.Encoding]::UTF8)))
. ([ScriptBlock]::Create([IO.File]::ReadAllText((Join-Path $app 'runtime\low-quota.ps1'),[Text.Encoding]::UTF8)))
. ([ScriptBlock]::Create([IO.File]::ReadAllText($module,[Text.Encoding]::UTF8)))
function Assert($value,[string]$message){if(!$value){throw $message}}
function Assert-Throws([scriptblock]$Action,[string]$message){try{& $Action|Out-Null}catch{return};throw $message}
$root=Join-Path ([IO.Path]::GetTempPath()) ('gpt-niang-dialogue-'+[Guid]::NewGuid().ToString('N'))
$now=1800000000000L
function Write-Config($value){
  [IO.File]::WriteAllText($script:widgetDialogueState.path,($value|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
  $script:writeTime++
  [IO.File]::SetLastWriteTimeUtc($script:widgetDialogueState.path,[DateTime]::new(2026,10,12).AddSeconds($script:writeTime))
}
function Example {
  @{version=1;daily=@(@{text='配置里的问候。';expression='wink';weight=1});headpat=@(@{text='配置里的问候。';expression='shy';weight=1});lowQuota=@(@{text='低额度的话。';expression='worried';level='low';weight=1},@{text='快用完的话。';expression='pout';level='critical';weight=1},@{text='用完以后的话。';expression='sleepy';level='empty';weight=1})}
}
try{
  $null=New-Item -ItemType Directory -Path $root
  Initialize-WidgetQuoteExpressions $app
  $script:writeTime=0
  $script:widgetDialogueState=Initialize-WidgetDialogueConfiguration $app $root -Create
  Assert ([IO.File]::Exists($script:widgetDialogueState.path)) 'A first run creates editable dialogue.json'
  Assert ($script:widgetDialogueState.current.daily.Count-eq 254) 'First-run daily pool is complete'
  Assert ($script:widgetDialogueState.current.headpat.Count-eq 12) 'Headpat replies are configurable'
  Assert ($script:widgetDialogueState.current.lowQuota.Count-eq 9) 'Low-quota replies are configurable'
  $config=Example;Write-Config $config
  Assert (!(Update-WidgetDialogueConfiguration $script:widgetDialogueState $now)) 'Changes wait for a stable save'
  Assert (Update-WidgetDialogueConfiguration $script:widgetDialogueState ($now+400)) 'Stable changes reload without a restart'
  Assert ((Get-WidgetQuote $root)-eq '配置里的问候。') 'Normal dialogue reads the custom config'
  Assert ((Get-WidgetQuoteExpression '配置里的问候。')-eq 'wink') 'Normal dialogue uses the configured expression'
  $held=New-WidgetExpressionState $now
  Register-WidgetExpressionEvent $held quote $now -Quote '配置里的问候。'
  $h=Get-WidgetHeadpatQuote (New-WidgetHeadpatState)
  Assert ($h.expression-eq 'shy') 'Identical text can have a different contextual expression'
  Assert ((Get-WidgetQuoteExpression $h.text)-eq 'shy') 'A headpat binds its own paired expression'
  $l=Get-WidgetLowQuotaQuote (New-WidgetLowQuotaState) critical
  Assert ($l.text-eq '快用完的话。' -and (Get-WidgetQuoteExpression $l.text)-eq 'pout') 'Low-quota selection honors severity and explicit expression'
  $config.daily[0].expression='smug';Write-Config $config
  Update-WidgetDialogueConfiguration $script:widgetDialogueState ($now+1000)|Out-Null
  Update-WidgetDialogueConfiguration $script:widgetDialogueState ($now+1400)|Out-Null
  Get-WidgetQuote $root|Out-Null
  Assert ((Get-WidgetQuoteExpression '配置里的问候。')-eq 'smug') 'Editing only an expression is picked up'
  Assert ($held.quoteExpression-eq 'wink') 'Reloading does not replace a currently displayed dialogue pose'
  $loads=$script:widgetDialogueState.reloads
  foreach($i in 1..20){Update-WidgetDialogueConfiguration $script:widgetDialogueState ($now+2000+$i*1000)|Out-Null}
  Assert ($script:widgetDialogueState.reloads-eq $loads) 'Unchanged files are not reparsed every tick'
  [IO.File]::WriteAllText($script:widgetDialogueState.path,'{"version":1,"daily":[',[Text.UTF8Encoding]::new($false))
  Update-WidgetDialogueConfiguration $script:widgetDialogueState ($now+30000)|Out-Null
  Assert (!(Update-WidgetDialogueConfiguration $script:widgetDialogueState ($now+30400))) 'Incomplete JSON cannot replace the valid snapshot'
  Assert ($script:widgetDialogueState.error) 'Reload errors are available to the editor and menu'
  Assert ((Get-WidgetQuote $root)-eq '配置里的问候。') 'The last valid lines remain usable during a broken save'
  $bad=Example;$bad.daily[0].expression='unknown-pose';Write-Config $bad
  Assert (!(Update-WidgetDialogueConfiguration $script:widgetDialogueState ($now+31000) -Force)) 'Unknown expressions are rejected'
  Assert ($script:widgetDialogueState.current.daily[0].expression-eq 'smug') 'Invalid expression metadata is not partially applied'
  $bad=Example;$bad.lowQuota[0].level='normal'
  Assert-Throws {ConvertTo-WidgetDialogueConfiguration $bad} 'Unknown low-quota levels must be rejected'
  $bad=Example;$bad.daily[0].weight=0
  Assert-Throws {ConvertTo-WidgetDialogueConfiguration $bad} 'Zero weights must be rejected'
  $bad=Example;$bad.daily=@()
  Assert-Throws {ConvertTo-WidgetDialogueConfiguration $bad} 'An empty daily pool must be rejected'
  $bad=Example;$bad.daily+=$bad.daily[0]
  Assert-Throws {ConvertTo-WidgetDialogueConfiguration $bad} 'Duplicate daily entries must be rejected'
  $config=Example;$config.headpat=@();$config.lowQuota=@();Write-Config $config
  Assert (Update-WidgetDialogueConfiguration $script:widgetDialogueState ($now+32000) -Force) 'Empty optional contextual pools are allowed'
  Assert (!(Get-WidgetHeadpatQuote (New-WidgetHeadpatState))) 'An empty headpat pool disables its reply'
  Assert (!$script:widgetDialogueState.error) 'A repaired save clears the error'
  $other=Example;$other.daily=@(@{text='第一句。';expression='happy';weight=1},@{text='第二句。';expression='neutral';weight=100})
  Save-WidgetDialogueConfiguration $script:widgetDialogueState $other|Out-Null
  $last='';foreach($i in 1..30){$text=Get-WidgetQuote $root;Assert ($text-ne $last) 'Configured random dialogue avoids immediate repeats';$last=$text}
  Assert ([IO.File]::Exists($script:widgetDialogueState.path+'.bak')) 'Editor saves preserve a backup'
  $saved=[IO.File]::ReadAllText($script:widgetDialogueState.path)
  Initialize-WidgetDialogueConfiguration $app $root -Create|Out-Null
  Assert ([IO.File]::ReadAllText($script:widgetDialogueState.path)-eq $saved) 'Startup preserves an existing edited configuration'
  Reset-WidgetDialogueConfiguration $script:widgetDialogueState|Out-Null
  Assert ($script:widgetDialogueState.current.daily.Count-eq 254) 'Reset restores bundled dialogue'
  # Existing text/weight quote files migrate without losing user additions or bindings.
  $legacy=Join-Path $root 'legacy';$null=New-Item -ItemType Directory -Path $legacy
  [IO.File]::WriteAllText((Join-Path $legacy 'quotes.json'),'{"quotes":[{"text":"用户原来的句子。","weight":3,"expression":"heart"}]}',[Text.UTF8Encoding]::new($false))
  $state=Initialize-WidgetDialogueConfiguration $app $legacy -Create
  Assert ($state.current.daily.Count-eq 1 -and $state.current.daily[0].text-eq '用户原来的句子。' -and $state.current.daily[0].expression-eq 'heart' -and $state.current.daily[0].weight-eq 3) 'Legacy custom text, weight and expression migrate together'
  $invalid=Join-Path $root 'invalid';$null=New-Item -ItemType Directory -Path $invalid
  [IO.File]::WriteAllText((Join-Path $invalid 'dialogue.json'),'{broken',[Text.UTF8Encoding]::new($false))
  $state=Initialize-WidgetDialogueConfiguration $app $invalid -Create
  Assert ($state.current.daily.Count-eq 254 -and $state.error) 'Malformed configuration on startup uses bundled defaults and reports the problem'
  Assert ([IO.File]::ReadAllText($state.path)-eq '{broken') 'Startup never overwrites a malformed user file'
  # Drive the production WPF editor and the reload function called by Tick-Widget.
  Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
  $source=[IO.File]::ReadAllText((Join-Path $app 'widget.ps1'),[Text.Encoding]::UTF8)
  $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
  Assert (!$errors.Count) 'Production widget parses correctly'
  $definition=$ast.Find({param($n)$n-is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name-eq 'Sync-WidgetDialogueConfiguration'},$true)
  . ([ScriptBlock]::Create($definition.Extent.Text))
  $tick=$ast.Find({param($n)$n-is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name-eq 'Tick-Widget'},$true)
  Assert ($tick.Extent.Text.Contains('Sync-WidgetDialogueConfiguration $now')) 'Production timer polls the configuration'
  $ui=[IO.File]::ReadAllText((Join-Path $app 'runtime\ui-settings.ps1'),[Text.Encoding]::UTF8)
  . ([ScriptBlock]::Create($ui.Replace('$editor.Show()','$editor.Opacity=0;$editor.ShowInTaskbar=$false;$editor.Show()')))
  $script:dataDir=$root;$script:settingsMenuUi=@{};$script:window=[Windows.Window]::new()
  $script:window.Opacity=0;$script:window.ShowInTaskbar=$false;$script:window.Width=1;$script:window.Height=1;$script:window.Show()
  try{
    Open-QuoteEditor
    $script:quoteEditor.FindName('Lines').Text='{'
    $script:quoteEditor.FindName('Save').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
    Assert ($script:widgetDialogueState.current.daily.Count-eq 254) 'Invalid editor input keeps the valid configuration'
    $edited=Example;$edited.daily[0].expression='heart'
    $script:quoteEditor.FindName('Lines').Text=$edited|ConvertTo-Json -Depth 8
    $script:quoteEditor.FindName('Save').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
    Get-WidgetQuote $root|Out-Null
    Assert ((Get-WidgetQuoteExpression '配置里的问候。')-eq 'heart') 'Real editor saves and activates the selected expression'
    $external=Example;Write-Config $external;Sync-WidgetDialogueConfiguration -Force
    $before=[IO.File]::ReadAllText($script:widgetDialogueState.path)
    $script:quoteEditor.FindName('Save').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
    Assert ([IO.File]::ReadAllText($script:widgetDialogueState.path)-eq $before) 'Stale editor content cannot overwrite external changes'
    Assert ($script:quoteEditor.FindName('Feedback').Text-match '外部修改') 'Editor explains the concurrent modification'
    $script:quoteEditor.Close();$script:quoteEditor=$null;Open-QuoteEditor
    $script:quoteEditor.FindName('Defaults').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
    Assert ($script:widgetDialogueState.current.daily.Count-eq 254) 'Real editor restores all bundled pools'
  }finally{if($script:quoteEditor){$script:quoteEditor.Close();$script:quoteEditor=$null};$script:window.Close()}
  Write-Output 'PASS: hot reload, scoped text/expression bindings, stable saves, last-valid recovery, validation, editor backup/reset and legacy migration'
}finally{
  $script:widgetDialogueState=$null
  $resolved=[IO.Path]::GetFullPath($root);$prefix=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
  if(!$resolved.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved)-notlike 'gpt-niang-dialogue-*'){throw 'Unsafe test cleanup path'}
  if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
