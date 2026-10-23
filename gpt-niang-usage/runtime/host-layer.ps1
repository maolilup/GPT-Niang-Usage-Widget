if(!('GptWidgetZOrderNative' -as [type])){
Add-Type -TypeDefinition @'
using System;using System.Runtime.InteropServices;
public static class GptWidgetZOrderNative {
 [DllImport("user32.dll")]public static extern IntPtr GetWindow(IntPtr h,uint command);
 [DllImport("user32.dll")]public static extern bool IsWindow(IntPtr h);
 [DllImport("user32.dll")]public static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")]public static extern bool IsIconic(IntPtr h);
 [DllImport("user32.dll")]public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")]static extern uint GetWindowThreadProcessId(IntPtr h,out uint processId);
 [DllImport("user32.dll",EntryPoint="GetWindowLongPtrW")]public static extern IntPtr GetWindowLongPtr(IntPtr h,int index);
 [DllImport("user32.dll",EntryPoint="SetWindowLongPtrW")]public static extern IntPtr SetWindowLongPtr(IntPtr h,int index,IntPtr value);
 [DllImport("user32.dll")]public static extern bool SetWindowPos(IntPtr h,IntPtr after,int x,int y,int width,int height,uint flags);
 [DllImport("dwmapi.dll")]static extern int DwmGetWindowAttribute(IntPtr h,int attribute,out uint value,int size);
 public static bool Topmost(IntPtr h){return (GetWindowLongPtr(h,-20).ToInt64()&8)!=0;}
 public static bool VisibleSurface(IntPtr h){uint cloaked;return IsWindowVisible(h)&&(DwmGetWindowAttribute(h,14,out cloaked,4)!=0||cloaked==0);}
 public static bool ForegroundBelongsToWidget(IntPtr widget,IntPtr foreground){
  if(foreground==IntPtr.Zero)return false;
  uint widgetProcess,foregroundProcess;GetWindowThreadProcessId(widget,out widgetProcess);GetWindowThreadProcessId(foreground,out foregroundProcess);
  return widgetProcess!=0&&widgetProcess==foregroundProcess;
 }
 public static IntPtr PreviousVisible(IntPtr h){
  IntPtr prior=GetWindow(h,3);for(int n=0;n<10000&&prior!=IntPtr.Zero;n++){
   if(VisibleSurface(prior))return prior;prior=GetWindow(prior,3);
  }return IntPtr.Zero;
 }
}
'@
}
function Set-WidgetAboveHost([IntPtr]$Widget,[IntPtr]$HostWindowHandle){
  if(![GptWidgetZOrderNative]::IsWindow($Widget) -or ![GptWidgetZOrderNative]::IsWindow($HostWindowHandle)){
    return [pscustomobject]@{ok=$false;changed=$false;reason='invalid-window'}
  }
  if(![GptWidgetZOrderNative]::VisibleSurface($HostWindowHandle) -or [GptWidgetZOrderNative]::IsIconic($HostWindowHandle)){
    return [pscustomobject]@{ok=$false;changed=$false;reason='host-not-visible'}
  }
  $changed=$false
  # Keep separate native ownership/input queues. A hung overlay must not couple
  # the host's activation, teardown or message processing to its own UI thread.
  if([GptWidgetZOrderNative]::GetWindowLongPtr($Widget,-8)-ne [IntPtr]::Zero){
    [GptWidgetZOrderNative]::SetWindowLongPtr($Widget,-8,[IntPtr]::Zero)|Out-Null
    if([GptWidgetZOrderNative]::GetWindowLongPtr($Widget,-8)-ne [IntPtr]::Zero){
      return [pscustomobject]@{ok=$false;changed=$false;reason='owner-detachment-failed'}
    }
    $changed=$true
  }
  $hostBand=[GptWidgetZOrderNative]::Topmost($HostWindowHandle)
  $foreground=[GptWidgetZOrderNative]::GetForegroundWindow()
  $foregroundBoost=$foreground-eq $HostWindowHandle -or [GptWidgetZOrderNative]::ForegroundBelongsToWidget($Widget,$foreground)
  $desiredTopmost=$hostBand -or $foregroundBoost
  $widgetBand=[GptWidgetZOrderNative]::Topmost($Widget)
  # Windows can deny a background process's attempt to raise an unowned normal
  # window above the foreground host. Scope the topmost band to host/widget
  # interaction, and leave it as soon as another application takes foreground.
  if($widgetBand-ne $desiredTopmost){
    $band=if($desiredTopmost){[IntPtr](-1)}else{[IntPtr](-2)}
    if(![GptWidgetZOrderNative]::SetWindowPos($Widget,$band,0,0,0,0,0x4413)){
      return [pscustomobject]@{ok=$false;changed=$false;reason='band-change-failed'}
    }
    $changed=$true
  }
  if($foregroundBoost -and !$hostBand){
    return [pscustomobject]@{ok=[GptWidgetZOrderNative]::Topmost($Widget);changed=$changed;hostTopmost=$hostBand;foregroundBoost=$true}
  }
  # WPF may create invisible owner windows. Visible adjacency, rather than raw
  # HWND adjacency, avoids reordering forever against an invisible owner.
  $previous=[GptWidgetZOrderNative]::PreviousVisible($HostWindowHandle)
  if($previous-eq $Widget){return [pscustomobject]@{ok=$true;changed=$changed;adjacent=$true;hostTopmost=$hostBand}}
  $after=$previous
  if($after-eq [IntPtr]::Zero -or (!$hostBand -and [GptWidgetZOrderNative]::Topmost($after))){$after=[IntPtr]::Zero}
  if(![GptWidgetZOrderNative]::SetWindowPos($Widget,$after,0,0,0,0,0x4413)){
    return [pscustomobject]@{ok=$false;changed=$changed;reason='placement-failed'}
  }
  $adjacent=[GptWidgetZOrderNative]::PreviousVisible($HostWindowHandle)-eq $Widget
  [pscustomobject]@{ok=$adjacent;changed=$true;adjacent=$adjacent;hostTopmost=$hostBand}
}
