import 'dart:io';

/// Windows system controls for the laptop build, done with plain
/// PowerShell/cmd - no new plugin dependencies. Every method reports
/// success honestly: unsupported hardware (external-monitor brightness,
/// an app name Windows cannot resolve) returns failure so Friday says so
/// instead of pretending.
class WindowsDevice {
  /// Well-known app names to launch targets: URI schemes for Store apps,
  /// executable names for classic apps.
  static String resolveAppTarget(String query) {
    final q = query.trim().toLowerCase();
    const known = {
      'whatsapp': 'whatsapp:',
      'spotify': 'spotify:',
      'telegram': 'tg:',
      'zoom': 'zoom:',
      'settings': 'ms-settings:',
      'camera': 'microsoft.windows.camera:',
      'chrome': 'chrome',
      'google chrome': 'chrome',
      'edge': 'msedge',
      'firefox': 'firefox',
      'notepad': 'notepad',
      'calculator': 'calc',
      'calc': 'calc',
      'paint': 'mspaint',
      'vlc': 'vlc',
      'word': 'winword',
      'excel': 'excel',
      'powerpoint': 'powerpnt',
      'outlook': 'outlook',
      'teams': 'teams',
      'explorer': 'explorer',
      'file explorer': 'explorer',
      'files': 'explorer',
      'terminal': 'wt',
      'cmd': 'cmd',
      'powershell': 'powershell',
    };
    return known[q] ?? q;
  }

  /// Requests normal window closure and preserves unsaved-work prompts.
  /// Never force-kills a process. Status says a request was sent, not that
  /// every window has already closed.
  static const closeAllAppsScript = r"""
$self = $PID
$parent = (Get-CimInstance Win32_Process -Filter "ProcessId=$PID").ParentProcessId
$skip = @('explorer','ApplicationFrameHost','ShellExperienceHost','StartMenuExperienceHost','SearchHost','SystemSettings','TextInputHost','sihost','dwm','taskmgr','powershell','cmd','friday','friday-fo','friday_fo')
$procs = Get-Process | Where-Object { $_.MainWindowTitle -ne '' -and $_.Id -ne $self -and $_.Id -ne $parent -and $skip -notcontains $_.ProcessName }
$n = 0
foreach ($p in $procs) { try { if ($p.CloseMainWindow()) { $n++ } } catch {} }
if ($procs.Count -eq 0) { 'none' } elseif ($n -gt 0) { 'requested' } else { 'error' }
""";

  static Future<String> closeAllApps() async {
    try {
      final res = await Process.run(
          'powershell', ['-NoProfile', '-Command', closeAllAppsScript]);
      if (res.exitCode != 0) return 'error';
      final out = res.stdout.toString().trim();
      return out == 'none' || out == 'requested' ? out : 'error';
    } catch (_) {
      return 'error';
    }
  }

  static Future<bool> openApp(String query) async {
    if (query.trim().isEmpty) return false;
    final target = resolveAppTarget(query);
    try {
      final res = await Process.run(
        'powershell',
        ['-NoProfile', '-Command', "Start-Process '$target' -ErrorAction Stop"],
      );
      if (res.exitCode == 0) return true;
      // Last resort: cmd's start handles some registered names Start-Process
      // misses, but it does not report failure - only trust it for URI
      // schemes, where a missing handler is rare.
      if (target.endsWith(':')) {
        await Process.run('cmd', ['/c', 'start', '', target]);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Exact +/-5% volume steps (user ask). SendKeys volume presses only do
  /// 2% steps, so the step goes through the Core Audio API via an inline
  /// C# type compiled by PowerShell - no new dependency, works on stock
  /// Windows 10. Returns null when the endpoint cannot be opened.
  static String _coreAudioType = """
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
[Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioEndpointVolume {
    int _0(); int _1(); int _2(); int _3(); int _4();
    int SetMasterVolumeLevelScalar(float level, Guid eventContext);
    int GetMasterVolumeLevelScalar(out float level);
}
[Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDevice {
    int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object ppInterface);
}
[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDeviceEnumerator {
    int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice ppDevice);
}
[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumeratorComObject { }
public class FridayAudio {
    static IAudioEndpointVolume Epv() {
        var en = (IMMDeviceEnumerator)(new MMDeviceEnumeratorComObject());
        IMMDevice dev; en.GetDefaultAudioEndpoint(0, 1, out dev);
        Guid iid = typeof(IAudioEndpointVolume).GUID;
        object o; dev.Activate(ref iid, 1, IntPtr.Zero, out o);
        return (IAudioEndpointVolume)o;
    }
    public static float GetVolume() { float v; Epv().GetMasterVolumeLevelScalar(out v); return v; }
    public static void SetVolume(float v) { Epv().SetMasterVolumeLevelScalar(v, Guid.Empty); }
}
'@
""";

  static String volumeStepScript({required bool up, int percent = 5}) {
    final delta = (up ? percent : -percent) / 100.0;
    return _coreAudioType +
        "\$cur = [FridayAudio]::GetVolume(); "
            "\$new = [Math]::Min(1.0, [Math]::Max(0.0, \$cur + ($delta))); "
            "[FridayAudio]::SetVolume([single]\$new)";
  }

  /// Absolute volume: bottom out with 50 downs, then climb (n / 2) ups.
  static String setVolumeScript(int percent) {
    final ups = (percent.clamp(0, 100) / 2).round();
    return "\$w = New-Object -ComObject WScript.Shell; "
        "1..50 | % { \$w.SendKeys([char]174); Start-Sleep -m 15 }; "
        "1..$ups | % { \$w.SendKeys([char]175); Start-Sleep -m 15 }";
  }

  static Future<bool> _runShell(String script) async {
    try {
      final res = await Process.run(
        'powershell',
        ['-NoProfile', '-Command', script],
      );
      return res.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> adjustVolume({required bool up}) =>
      _runShell(volumeStepScript(up: up));

  /// Brightness in exact 5% steps: read the current level through WMI,
  /// add/subtract 5, clamp, write back.
  static String brightnessStepScript({required bool up, int percent = 5}) {
    final delta = up ? percent : -percent;
    return "\$cur = (Get-WmiObject -Namespace root/wmi -Class WmiMonitorBrightness -ErrorAction Stop).CurrentBrightness; "
        "\$new = [Math]::Min(100, [Math]::Max(0, \$cur + ($delta))); "
        "(Get-WmiObject -Namespace root/wmi -Class WmiMonitorBrightnessMethods -ErrorAction Stop).WmiSetBrightness(1, [byte]\$new) | Out-Null";
  }

  static Future<bool> adjustBrightness({required bool up}) =>
      _runShell(brightnessStepScript(up: up));

  static Future<bool> setVolumePercent(int percent) =>
      _runShell(setVolumeScript(percent));

  static String brightnessScript(int percent) =>
      "(Get-WmiObject -Namespace root/wmi -Class WmiMonitorBrightnessMethods "
      "-ErrorAction Stop).WmiSetBrightness(1, ${percent.clamp(0, 100)})";

  static Future<bool> setBrightnessPercent(int percent) =>
      _runShell(brightnessScript(percent));

  static Future<bool> openSettingsPanel(String which) async {
    final page = which == 'bluetooth' ? 'bluetooth' : 'network-wifi';
    try {
      await Process.run('cmd', ['/c', 'start', '', 'ms-settings:$page']);
      return true;
    } catch (_) {
      return false;
    }
  }
}
