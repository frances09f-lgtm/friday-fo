import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// In-app self-update (same approach as Replier and Sona): checks the latest
/// GitHub release, shows the new version with its release notes, downloads
/// the APK in-app with a progress bar and hands it to the Android package
/// installer. Version, cache dir, the "install unknown apps" permission and
/// the installer intent come from the native "app/update" MethodChannel
/// (MainActivity.kt), so this file adds no pub dependencies.

// ---- per-app configuration (the only lines that change between apps) ----
const kAppName = 'Friday';
// GitHub mode: slug of the public repo whose latest release carries the APK.
const kUpdateRepo = 'frances09f-lgtm/friday-fo';
// Release asset the updater prefers; any other .apk is the fallback.
const kApkAssetName = 'Friday.apk';
// Feed mode (for apps whose source repo is private): public JSON file with
// {"<kFeedKey>": {"version": "...", "notes": "...", "apk": "..."}}.
const kUpdateFeedUrl = ''; // empty = GitHub releases mode
const kFeedKey = '';
// -------------------------------------------------------------------------

/// Launch-time checks run at most this often.
const kAutoCheckInterval = Duration(hours: 6);
const _kLastCheckKey = 'app_update_last_check_ms';

class UpdateInfo {
  final String version;
  final String notes;
  final String apkUrl;

  /// api.github.com asset URL (needs Accept: application/octet-stream);
  /// tried when [apkUrl] cannot be downloaded.
  final String? apiAssetUrl;

  /// Asset size from the release, used to verify the download.
  final int? sizeBytes;
  const UpdateInfo({
    required this.version,
    required this.notes,
    required this.apkUrl,
    this.apiAssetUrl,
    this.sizeBytes,
  });
}

enum UpdateCheckStatus { available, upToDate, failed }

/// What a check found: a newer release, already up to date, or why the
/// check could not be made.
class UpdateCheckResult {
  final UpdateCheckStatus status;
  final String current;
  final String? latest;
  final UpdateInfo? info;
  final String? error;
  const UpdateCheckResult._(
      this.status, this.current, this.latest, this.info, this.error);
  factory UpdateCheckResult.available(String current, UpdateInfo info) =>
      UpdateCheckResult._(
          UpdateCheckStatus.available, current, info.version, info, null);
  factory UpdateCheckResult.upToDate(String current, String latest) =>
      UpdateCheckResult._(
          UpdateCheckStatus.upToDate, current, latest, null, null);
  factory UpdateCheckResult.failed(String current, String error) =>
      UpdateCheckResult._(UpdateCheckStatus.failed, current, null, null, error);
  bool get hasUpdate => status == UpdateCheckStatus.available;
}

class UpdateException implements Exception {
  final String message;
  const UpdateException(this.message);
  @override
  String toString() => message;
}

/// Numeric semver-ish compare: >0 when a > b. Ignores a leading v, any
/// +build suffix and any -suffix on a segment; missing segments count as 0.
/// Friday's short release tags ("v80") mean versionName 1.0.80, so a bare
/// single number N compares as 1.0.N instead of looking newer than every
/// 1.0.x build forever.
int compareVersions(String a, String b) {
  List<int> parts(String v) {
    final core = v.trim().replaceFirst(RegExp(r'^[vV]'), '').split('+').first;
    final segs = core
        .split('.')
        .map((s) => int.tryParse(RegExp(r'^\d+').stringMatch(s) ?? '') ?? 0)
        .toList();
    return segs.length == 1 ? [1, 0, segs.first] : segs;
  }

  final pa = parts(a), pb = parts(b);
  for (var i = 0; i < pa.length || i < pb.length; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x - y;
  }
  return 0;
}

/// Plain-words reason for a failed network call, naming the host.
String describeNetworkError(Object e, {String? host}) {
  // Redirects (github.com -> release-assets.githubusercontent.com) mean the
  // host that failed can differ from the one asked; prefer the one named.
  final named = RegExp(r"Failed host lookup: '?([A-Za-z0-9.-]+)")
      .firstMatch(e.toString())
      ?.group(1);
  final h = named ?? host;
  final where = h == null ? '' : ' $h';
  if (e is UpdateException) return e.message;
  if (e is PlatformException) return e.message ?? e.code;
  if (e is TimeoutException) return 'no answer from$where (timed out)';
  if (e is SocketException) {
    final m = e.message.isNotEmpty ? e.message : e.osError?.message ?? '';
    if (m.contains('Failed host lookup') || m.contains('No address')) {
      return "can't find$where (DNS lookup failed; this network may be blocking it)";
    }
    return "can't connect to$where (${m.isEmpty ? 'connection failed' : m})";
  }
  if (e is HandshakeException || e is TlsException) {
    return 'secure connection to$where failed (this network may be blocking or intercepting it)';
  }
  if (e is http.ClientException) {
    final m = e.message;
    if (m.contains('Failed host lookup')) {
      return "can't find$where (DNS lookup failed; this network may be blocking it)";
    }
    return m.isEmpty ? 'connection to$where failed' : m;
  }
  if (e is FileSystemException) return "couldn't save the file (${e.message})";
  return e.toString();
}

class UpdateChecker {
  UpdateChecker({
    http.Client? client,
    Future<String> Function()? currentVersion,
    Future<void> Function(String apkPath)? installer,
    Future<bool> Function()? canInstall,
    Future<void> Function()? openInstallSettings,
    Future<Directory> Function()? cacheDir,
    DateTime Function()? clock,
    Future<File> Function(
      UpdateInfo info, {
      void Function(int received, int? total)? onProgress,
      Stream<void>? cancelToken,
    })?
    downloader,
  }) : _client = client ?? http.Client(),
       _currentVersion = currentVersion ?? _nativeVersion,
       _installer = installer ?? _nativeInstall,
       _canInstall = canInstall ?? _nativeCanInstall,
       _openInstallSettings = openInstallSettings ?? _nativeOpenSettings,
       _cacheDir = cacheDir ?? _nativeCacheDir,
       _downloader = downloader,
       _clock = clock ?? DateTime.now;

  static const _channel = MethodChannel('app/update');
  final http.Client _client;
  final Future<String> Function() _currentVersion;
  final Future<void> Function(String) _installer;
  final Future<bool> Function() _canInstall;
  final Future<void> Function() _openInstallSettings;
  final Future<Directory> Function() _cacheDir;
  final Future<File> Function(
    UpdateInfo info, {
    void Function(int received, int? total)? onProgress,
    Stream<void>? cancelToken,
  })?
  _downloader;
  final DateTime Function() _clock;

  static Future<String> _nativeVersion() async {
    try {
      return await _channel.invokeMethod<String>('appVersion') ?? '0.0.0';
    } catch (_) {
      return '0.0.0';
    }
  }

  static Future<Directory> _nativeCacheDir() async {
    final p = await _channel.invokeMethod<String>('cacheDir');
    if (p == null || p.isEmpty) {
      throw const UpdateException('no cache folder from Android');
    }
    return Directory(p);
  }

  static Future<bool> _nativeCanInstall() async {
    try {
      return await _channel.invokeMethod<bool>('canInstall') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _nativeOpenSettings() async {
    try {
      await _channel.invokeMethod<void>('openInstallSettings');
    } catch (_) {}
  }

  static Future<void> _nativeInstall(String path) async {
    await _channel.invokeMethod<void>('installApk', {'path': path});
  }

  Future<String> currentVersion() => _currentVersion();

  /// Full check with a reason when it fails (shown by the manual check).
  Future<UpdateCheckResult> check() async {
    final current = await _currentVersion();
    final UpdateInfo? info;
    try {
      info = kUpdateFeedUrl.isNotEmpty
          ? await _fetchFromFeed()
          : await _fetchFromGithub();
    } catch (e) {
      return UpdateCheckResult.failed(
          current, describeNetworkError(e, host: 'api.github.com'));
    }
    if (info == null) {
      return UpdateCheckResult.failed(
          current, 'the latest release has no APK attached');
    }
    return compareVersions(info.version, current) > 0
        ? UpdateCheckResult.available(current, info)
        : UpdateCheckResult.upToDate(current, info.version);
  }

  /// Latest release info, or null when there is nothing newer or the check
  /// fails (offline, rate limit).
  Future<UpdateInfo?> fetchLatest() async {
    try {
      return (await check()).info;
    } catch (_) {
      return null;
    }
  }

  Future<UpdateInfo?> _fetchFromGithub() async {
    final res = await _client
        .get(
          Uri.parse(
            'https://api.github.com/repos/$kUpdateRepo/releases/latest',
          ),
          headers: const {
            'Accept': 'application/vnd.github+json',
            'User-Agent': '$kAppName-app',
          },
        )
        .timeout(const Duration(seconds: 12));
    if (res.statusCode == 403 || res.statusCode == 429) {
      throw UpdateException(
          'GitHub is rate-limiting update checks (HTTP ${res.statusCode}); try again in a while');
    }
    if (res.statusCode != 200) {
      throw UpdateException('GitHub answered HTTP ${res.statusCode}');
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final tag = (j['tag_name'] as String? ?? '').trim();
    if (tag.isEmpty) throw const UpdateException('the latest release has no tag');
    Map? asset;
    for (final a in (j['assets'] as List? ?? const [])) {
      if (a is! Map) continue;
      final name = a['name'] as String? ?? '';
      if (name == kApkAssetName) {
        asset = a;
        break;
      }
      if (asset == null && name.toLowerCase().endsWith('.apk')) asset = a;
    }
    final apk = asset?['browser_download_url'] as String?;
    if (asset == null || apk == null) return null;
    return UpdateInfo(
      version: tag.replaceFirst(RegExp(r'^[vV]'), ''),
      notes: (j['body'] as String? ?? '').trim(),
      apkUrl: apk,
      apiAssetUrl: asset['url'] as String?,
      sizeBytes: (asset['size'] as num?)?.toInt(),
    );
  }

  Future<UpdateInfo?> _fetchFromFeed() async {
    final res = await _client
        .get(
          Uri.parse(kUpdateFeedUrl),
          headers: {'User-Agent': '$kAppName-app'},
        )
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) {
      throw UpdateException('update feed answered HTTP ${res.statusCode}');
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final e = j[kFeedKey];
    if (e is! Map) return null;
    final v = (e['version'] as String? ?? '').trim();
    final apk = (e['apk'] as String? ?? '').trim();
    if (v.isEmpty || apk.isEmpty) return null;
    return UpdateInfo(
      version: v,
      notes: (e['notes'] as String? ?? '').trim(),
      apkUrl: apk,
    );
  }

  /// Auto check on app start: at most once per [kAutoCheckInterval].
  Future<UpdateInfo?> autoCheck() async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt(_kLastCheckKey) ?? 0;
    if (_clock().millisecondsSinceEpoch - last <
        kAutoCheckInterval.inMilliseconds) {
      return null;
    }
    final result = await check();
    // Stamp even failures so an offline stretch does not poll every launch.
    await prefs.setInt(_kLastCheckKey, _clock().millisecondsSinceEpoch);
    return result.info;
  }

  /// Download the APK into the cache dir with byte progress. Tries the
  /// release's download link, then the GitHub API asset link; on failure
  /// throws an [UpdateException] naming why each one failed.
  Future<File> download(
    UpdateInfo info, {
    void Function(int received, int? total)? onProgress,
    Stream<void>? cancelToken,
  }) async {
    final dl = _downloader;
    if (dl != null) {
      return dl(info, onProgress: onProgress, cancelToken: cancelToken);
    }
    final dir = Directory(
      '${(await _cacheDir()).path}${Platform.pathSeparator}updates',
    );
    await dir.create(recursive: true);
    final file = File(
      '${dir.path}${Platform.pathSeparator}$kAppName-${info.version}.apk',
    );
    var cancelled = false;
    final sub = cancelToken?.listen((_) => cancelled = true);
    final attempts = <(String, Map<String, String>)>[
      (info.apkUrl, const {}),
      if (info.apiAssetUrl != null && info.apiAssetUrl!.isNotEmpty)
        (info.apiAssetUrl!, const {'Accept': 'application/octet-stream'}),
    ];
    final failures = <String>[];
    try {
      for (final (url, headers) in attempts) {
        if (cancelled) throw const UpdateException('download cancelled');
        final host = Uri.tryParse(url)?.host ?? url;
        try {
          await _downloadOnce(url, headers, file, info.sizeBytes, onProgress,
              () => cancelled);
          return file;
        } catch (e) {
          if (cancelled) throw const UpdateException('download cancelled');
          failures.add('$host: ${describeNetworkError(e, host: host)}');
          try {
            if (await file.exists()) await file.delete();
          } catch (_) {}
        }
      }
    } finally {
      await sub?.cancel();
    }
    throw UpdateException(
        "Couldn't download the update.\n${failures.join('\n')}");
  }

  Future<void> _downloadOnce(
    String url,
    Map<String, String> headers,
    File file,
    int? expected,
    void Function(int received, int? total)? onProgress,
    bool Function() cancelled,
  ) async {
    final req = http.Request('GET', Uri.parse(url));
    req.headers['User-Agent'] = '$kAppName-app';
    req.headers.addAll(headers);
    final res = await _client.send(req).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      await res.stream.drain<void>().catchError((_) {});
      throw UpdateException('HTTP ${res.statusCode}');
    }
    final total = res.contentLength ?? expected;
    final sink = file.openWrite();
    var received = 0;
    try {
      await for (final chunk
          in res.stream.timeout(const Duration(seconds: 60))) {
        if (cancelled()) throw const UpdateException('download cancelled');
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
    if (received == 0) throw const UpdateException('empty download');
    if (expected != null && expected > 0 && received != expected) {
      throw UpdateException(
          'download incomplete ($received of $expected bytes)');
    }
  }

  Future<void> install(File apk) => _installer(apk.path);
  Future<bool> canInstall() => _canInstall();
  Future<void> openInstallSettings() => _openInstallSettings();
}

bool get _inTests => Platform.environment['FLUTTER_TEST'] == 'true';

/// Root navigator key for apps that set MaterialApp.navigatorKey: lets the
/// update dialog survive splash->home navigation.
final appNavigatorKey = GlobalKey<NavigatorState>();

/// Launch-time check for apps using [appNavigatorKey]. Fire-and-forget.
Future<void> checkForUpdateOnLaunch({UpdateChecker? checker}) async {
  if (checker == null && _inTests) return;
  final c = checker ?? UpdateChecker();
  final info = await c.autoCheck();
  final ctx = appNavigatorKey.currentContext;
  if (info != null && ctx != null && ctx.mounted) {
    await showUpdateDialog(ctx, info, checker: c);
  }
}

/// Launch-time check, called once after the first frame (throttled to once
/// every [kAutoCheckInterval]); shows the update dialog when newer.
Future<void> maybePromptUpdate(
  BuildContext context, {
  UpdateChecker? checker,
}) async {
  if (checker == null && _inTests) return;
  final c = checker ?? UpdateChecker();
  final UpdateInfo? info;
  try {
    info = await c.autoCheck();
  } catch (_) {
    return;
  }
  if (info != null && context.mounted) {
    await showUpdateDialog(context, info, checker: c);
  }
}

/// Manual "Check for updates": always fetches and always says what it found
/// (newer version -> dialog; up to date; or why the check failed).
Future<UpdateCheckResult?> checkUpdateManually(
  BuildContext context, {
  UpdateChecker? checker,
}) async {
  if (checker == null && _inTests) return null;
  final c = checker ?? UpdateChecker();
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.hideCurrentSnackBar();
  messenger?.showSnackBar(const SnackBar(
      content: Text('Checking for updates...'),
      duration: Duration(seconds: 2)));
  final result = await c.check();
  messenger?.hideCurrentSnackBar();
  if (!context.mounted) return result;
  switch (result.status) {
    case UpdateCheckStatus.available:
      // Not awaited: the caller (Settings card) shows the result right away.
      unawaited(showUpdateDialog(context, result.info!,
          checker: c, current: result.current));
    case UpdateCheckStatus.upToDate:
      messenger?.showSnackBar(SnackBar(
          content: Text(
              "You're up to date: $kAppName ${result.current} is the latest version.")));
    case UpdateCheckStatus.failed:
      messenger?.showSnackBar(SnackBar(
          duration: const Duration(seconds: 6),
          content: Text("Couldn't check for updates: ${result.error}")));
  }
  return result;
}

enum _Phase { available, downloading, needsPermission, installing, error }

Future<void> showUpdateDialog(
  BuildContext context,
  UpdateInfo info, {
  UpdateChecker? checker,
  String? current,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => UpdateDialog(
        info: info, checker: checker ?? UpdateChecker(), current: current),
  );
}

/// "Software Update" dialog: version, release notes, download progress,
/// the one-time install permission, then Android's installer.
class UpdateDialog extends StatefulWidget {
  final UpdateInfo info;
  final UpdateChecker checker;
  final String? current;
  const UpdateDialog(
      {super.key, required this.info, required this.checker, this.current});
  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog>
    with WidgetsBindingObserver {
  _Phase phase = _Phase.available;
  int received = 0;
  int? total;
  String? error;
  bool openedSettings = false;
  final _cancel = StreamController<void>.broadcast();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancel.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from Android's "install unknown apps" screen: carry on by itself.
    if (state == AppLifecycleState.resumed &&
        phase == _Phase.needsPermission &&
        openedSettings) {
      _continueAfterPermission();
    }
  }

  Future<void> _continueAfterPermission() async {
    if (await widget.checker.canInstall()) {
      if (mounted && phase == _Phase.needsPermission) await _download();
    } else if (mounted) {
      setState(() {});
    }
  }

  Future<void> _start() async {
    // The one Android requirement we cannot skip: "install unknown apps"
    // for this app. Ask once, explain inside the dialog, then continue.
    if (!await widget.checker.canInstall()) {
      if (mounted) setState(() => phase = _Phase.needsPermission);
      return;
    }
    await _download();
  }

  Future<void> _download() async {
    setState(() {
      phase = _Phase.downloading;
      received = 0;
      total = widget.info.sizeBytes;
      error = null;
    });
    try {
      final apk = await widget.checker.download(
        widget.info,
        onProgress: (r, t) {
          if (mounted) {
            setState(() {
              received = r;
              total = t;
            });
          }
        },
        cancelToken: _cancel.stream,
      );
      if (!mounted) return;
      setState(() => phase = _Phase.installing);
      // Android always shows its own package-installer confirm screen; that
      // tap is the system's, not ours.
      await widget.checker.install(apk);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        phase = _Phase.error;
        error = describeNetworkError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dim = scheme.onSurfaceVariant;
    final v = widget.info.version;
    final progress = total != null && total! > 0
        ? (received / total!).clamp(0.0, 1.0)
        : null;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Software Update', textAlign: TextAlign.center),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Text(
              switch (phase) {
                _Phase.available => '$kAppName $v is available',
                _Phase.downloading => 'Downloading $kAppName $v...',
                _Phase.needsPermission => 'One permission needed',
                _Phase.installing => 'Opening installer...',
                _Phase.error => 'Update failed',
              },
              key: const ValueKey('update-phase'),
              style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 15,
                  fontWeight: FontWeight.w600),
            ),
          ),
          if (widget.current != null && phase == _Phase.available)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Center(
                child: Text(
                  'Installed: ${widget.current}  ->  New: $v',
                  style: TextStyle(color: dim, fontSize: 12),
                ),
              ),
            ),
          if (phase == _Phase.downloading) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 4),
            Text(
              total != null
                  ? '${(received / 1e6).toStringAsFixed(1)} / ${(total! / 1e6).toStringAsFixed(1)} MB'
                  : '${(received / 1e6).toStringAsFixed(1)} MB',
              style: TextStyle(color: dim, fontSize: 11),
            ),
          ],
          if (phase == _Phase.needsPermission)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Android asks once: allow $kAppName to install updates. '
                'Tap Open settings, turn on "Allow from this source", then '
                'come back; the update continues by itself (or tap Continue).',
                style: TextStyle(fontSize: 13, color: scheme.onSurface),
              ),
            ),
          if (phase == _Phase.error)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SelectableText(
                error ?? 'Something went wrong.',
                key: const ValueKey('update-error'),
                style: TextStyle(color: scheme.error, fontSize: 12),
              ),
            ),
          if (widget.info.notes.isNotEmpty &&
              phase != _Phase.needsPermission &&
              phase != _Phase.error) ...[
            const SizedBox(height: 12),
            Text(
              "What's new",
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface),
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: SingleChildScrollView(
                child: Text(
                  widget.info.notes,
                  style: TextStyle(fontSize: 12, color: dim),
                ),
              ),
            ),
          ],
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        if (phase == _Phase.available) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Later'),
          ),
          FilledButton(onPressed: _start, child: const Text('Update')),
        ],
        if (phase == _Phase.downloading)
          TextButton(
            onPressed: () {
              _cancel.add(null);
              Navigator.of(context).pop();
            },
            child: const Text('Cancel'),
          ),
        if (phase == _Phase.needsPermission) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          if (openedSettings)
            OutlinedButton(
              onPressed: _continueAfterPermission,
              child: const Text('Continue'),
            ),
          FilledButton(
            onPressed: () async {
              setState(() => openedSettings = true);
              await widget.checker.openInstallSettings();
            },
            child: const Text('Open settings'),
          ),
        ],
        if (phase == _Phase.error) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          FilledButton(onPressed: _download, child: const Text('Retry')),
        ],
      ],
    );
  }
}

/// Settings card: installed version, a "Check for updates" button and what
/// the last check found.
class UpdateSettingsCard extends StatefulWidget {
  const UpdateSettingsCard({super.key, this.checker});
  final UpdateChecker? checker;
  @override
  State<UpdateSettingsCard> createState() => _UpdateSettingsCardState();
}

class _UpdateSettingsCardState extends State<UpdateSettingsCard> {
  String? current;
  bool checking = false;
  UpdateCheckResult? last;

  UpdateChecker? get _checker =>
      widget.checker ?? (_inTests ? null : UpdateChecker());

  @override
  void initState() {
    super.initState();
    final c = _checker;
    if (c != null) {
      c.currentVersion().then((v) {
        if (mounted) setState(() => current = v);
      }).catchError((_) {});
    }
  }

  Future<void> _check() async {
    final c = _checker;
    if (c == null || checking) return;
    setState(() => checking = true);
    try {
      final r = await checkUpdateManually(context, checker: c);
      if (mounted) {
        setState(() {
          last = r;
          if (r != null) current = r.current;
        });
      }
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final r = last;
    final installed = 'Installed: $kAppName ${current ?? ''}'.trim();
    final status = checking
        ? 'Checking...'
        : r == null
            ? 'Also checks by itself when Friday opens'
            : switch (r.status) {
                UpdateCheckStatus.available =>
                  '${r.latest} is available - tap to install',
                UpdateCheckStatus.upToDate => "You're on the latest version.",
                UpdateCheckStatus.failed => "Couldn't check: ${r.error}",
              };
    return ListTile(
      key: const ValueKey('check-for-updates'),
      onTap: checking ? null : _check,
      leading: Icon(Icons.system_update_alt, color: s.primary),
      title: Text(r?.hasUpdate == true
          ? 'Install $kAppName ${r!.latest}'
          : 'Check for updates'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(installed, key: const ValueKey('installed-version')),
          Text(status,
              key: const ValueKey('update-status'),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: r?.status == UpdateCheckStatus.failed
                      ? s.error
                      : r?.hasUpdate == true
                          ? s.primary
                          : null)),
        ],
      ),
      trailing: checking
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.chevron_right),
    );
  }
}
