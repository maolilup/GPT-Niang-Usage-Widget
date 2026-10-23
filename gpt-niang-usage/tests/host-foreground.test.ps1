param([string]$TestRoot=$PSScriptRoot)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -ReferencedAssemblies System.Windows.Forms -TypeDefinition @'
using System;using System.Windows.Forms;using System.Runtime.InteropServices;
public sealed class ForegroundOverlayForm:Form {
 protected override bool ShowWithoutActivation {get{return true;}}
}
public static class ForegroundProbeNative {
 [DllImport("user32.dll")]public static extern IntPtr GetForegroundWindow();
}
'@
. (Join-Path (Split-Path $TestRoot -Parent) 'runtime\host-layer.ps1')
# Use the real foreground HWND without activating or changing it. Both probe
# windows have zero opacity on this test's separate input queue. Switching the
# host binding exercises focus states while leaving the user's focus alone.
$foreground=[ForegroundProbeNative]::GetForegroundWindow()
if($foreground-eq [IntPtr]::Zero -or ![GptWidgetZOrderNative]::VisibleSurface($foreground) -or [GptWidgetZOrderNative]::IsIconic($foreground)){
  throw 'This integration test requires a visible foreground window in an interactive Windows session.'
}
$backgroundHost=[ForegroundOverlayForm]::new();$overlay=[ForegroundOverlayForm]::new()
foreach($form in @($backgroundHost,$overlay)){$form.ShowInTaskbar=$false;$form.Opacity=0}
function Assert-Above([IntPtr]$Upper,[IntPtr]$Lower){
  $cursor=[GptWidgetZOrderNative]::GetWindow($Lower,3)
  for($i=0;$i-lt 10000 -and $cursor-ne [IntPtr]::Zero;$i++){
    if($cursor-eq $Upper){return};$cursor=[GptWidgetZOrderNative]::GetWindow($cursor,3)
  }
  throw 'Overlay is occluded by the foreground host.'
}
try{
  $backgroundHost.Show();$overlay.Show()
  [GptWidgetZOrderNative]::SetWindowPos($backgroundHost.Handle,[IntPtr]1,0,0,0,0,0x4413)|Out-Null
  for($cycle=0;$cycle-lt 3;$cycle++){
    $null=Set-WidgetAboveHost $overlay.Handle $foreground
    Assert-Above $overlay.Handle $foreground
    if(![GptWidgetZOrderNative]::Topmost($overlay.Handle)){throw 'Foreground host needs a scoped topmost overlay when background raising is denied.'}
    if([ForegroundProbeNative]::GetForegroundWindow()-ne $foreground){throw 'Overlay stole focus from its host.'}
    $steady=Set-WidgetAboveHost $overlay.Handle $foreground
    if($steady.changed){throw 'Stable foreground state repeatedly reorders the overlay.'}
    $null=Set-WidgetAboveHost $overlay.Handle $backgroundHost.Handle
    if([GptWidgetZOrderNative]::Topmost($overlay.Handle)){throw 'Overlay stayed globally topmost over another application.'}
    Assert-Above $foreground $overlay.Handle
    if([GptWidgetZOrderNative]::GetWindowLongPtr($overlay.Handle,-8)-ne [IntPtr]::Zero){throw 'Overlay acquired a cross-process owner.'}
  }
  $backgroundHost.Hide()
  if((Set-WidgetAboveHost $overlay.Handle $backgroundHost.Handle).reason-ne 'host-not-visible'){throw 'Hidden host was treated as visible.'}
  'PASS: three foreground/background host-binding cycles, scoped topmost, no focus theft, other-app occlusion and independent ownership'
}finally{$overlay.Dispose();$backgroundHost.Dispose()}
