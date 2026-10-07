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

  /// Volume keys go through the WScript.Shell COM object: 174 = down,
  /// 175 = up. One key press is a 2% step.
  static String volumeScript({required bool up, int steps = 5}) {
    final key = up ? 175 : 174;
    return "\$w = New-Object -ComObject WScript.Shell; "
        "1..$steps | % { \$w.SendKeys([char]$key); Start-Sleep -m 30 }";
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
      _runShell(volumeScript(up: up));

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
