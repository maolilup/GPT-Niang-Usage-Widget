param([string]$TestRoot=$PSScriptRoot)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
. (Join-Path (Split-Path $TestRoot -Parent) 'runtime\host-layer.ps1')
$hostForm=[Windows.Forms.Form]::new();$overlay=[Windows.Forms.Form]::new()
$hostForm.ShowInTaskbar=$false;$overlay.ShowInTaskbar=$false
try{
  $hostForm.Show();$overlay.Show()
  $null=Set-WidgetAboveHost $overlay.Handle $hostForm.Handle
  if([GptWidgetZOrderNative]::GetWindowLongPtr($overlay.Handle,-8)-ne [IntPtr]::Zero){throw 'Overlay attaches a native owner: a stalled widget can couple to its host input queue.'}
  $hostForm.Close()
  if($overlay.IsDisposed){throw 'Closing the host destroyed the independent overlay.'}
  'PASS: independent overlay ownership and host lifetime'
}finally{$overlay.Dispose();$hostForm.Dispose()}
