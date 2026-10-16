enum FridayActionType {
  none,
  openApp,
  playMusic,
  nextMusic,
  previousMusic,
  stopMusic,
  searchApp,
  readMessages,
  setReminder,
  torchOn,
  torchOff,
  volumeUp,
  volumeDown,
  wifiSettings,
  bluetoothSettings,
  callContact,
  sendText,
  sendWhatsApp,
  setVolume,
  setBrightness,
  brightnessUp,
  brightnessDown,
  oroStatus,
  lookoutStatus,
  closeAllApps,
}

enum FridaySource { cloud, local, offline }

class FridayAction {
  const FridayAction({
    this.type = FridayActionType.none,
    this.app = '',
    this.query = '',
    this.afterMinutes = 0,
    this.title = '',
    this.body = '',
    this.target = '',
  });

  final FridayActionType type;
  final String app;
  final String query;
  final int afterMinutes;
  final String title;
  final String body;
  final String target;

  /// Small models drift on the action name: "OpenApp", "Open App",
  /// "TORCH-ON". Normalize to lower_snake before matching (forgiving
  /// handling adapted from OpenJarvis, Apache-2.0).
  static String _normalizeType(String raw) {
    final camel = raw
        .trim()
        .replaceAllMapped(
          RegExp(r'(?<=[a-z0-9])(?=[A-Z])'),
          (m) => '_',
        )
        .toLowerCase();
    return camel.replaceAll(RegExp(r'[\s\-]+'), '_');
  }

  static FridayActionType _typeFrom(String? raw) {
    switch (raw == null ? null : _normalizeType(raw)) {
      case 'next_music':
        return FridayActionType.nextMusic;
      case 'previous_music':
        return FridayActionType.previousMusic;
      case 'stop_music':
        return FridayActionType.stopMusic;
      case 'play_music':
        return FridayActionType.playMusic;
      case 'open_app':
        return FridayActionType.openApp;
      case 'read_messages':
        return FridayActionType.readMessages;
      case 'set_reminder':
        return FridayActionType.setReminder;
      case 'torch_on':
        return FridayActionType.torchOn;
      case 'torch_off':
        return FridayActionType.torchOff;
      case 'volume_up':
        return FridayActionType.volumeUp;
      case 'volume_down':
        return FridayActionType.volumeDown;
      case 'wifi':
        return FridayActionType.wifiSettings;
      case 'bluetooth':
        return FridayActionType.bluetoothSettings;
      case 'call_contact':
        return FridayActionType.callContact;
      case 'send_text':
        return FridayActionType.sendText;
      case 'send_whatsapp':
        return FridayActionType.sendWhatsApp;
      case 'set_volume':
        return FridayActionType.setVolume;
      case 'set_brightness':
        return FridayActionType.setBrightness;
      case 'brightness_up':
        return FridayActionType.brightnessUp;
      case 'brightness_down':
        return FridayActionType.brightnessDown;
      case 'oro_status':
        return FridayActionType.oroStatus;
      case 'close_all_apps':
        return FridayActionType.closeAllApps;
      default:
        return FridayActionType.none;
    }
  }

  /// Field lookup forgiving case, spaces, underscores, hyphens and camelCase
  /// ("App", " after_minutes ", "afterMinutes" all match).
  static Map<String, dynamic> _forgivingKeys(Map<String, dynamic> json) {
    final out = <String, dynamic>{};
    json.forEach((key, value) {
      out.putIfAbsent(
        key.trim().toLowerCase().replaceAll(RegExp(r'[-_\s]'), ''),
        () => value,
      );
    });
    return out;
  }

  factory FridayAction.fromJson(Map<String, dynamic> json) {
    final j = _forgivingKeys(json);
    // after_minutes can arrive as a number or a numeric string.
    final rawMinutes = j['afterminutes'];
    final minutes = rawMinutes is num
        ? rawMinutes.toInt()
        : int.tryParse('${rawMinutes ?? ''}') ?? 0;
    final rawTarget = j['target'];
    return FridayAction(
      type: _typeFrom(j['type'] as String?),
      app: j['app'] as String? ?? '',
      query: j['query'] as String? ?? '',
      afterMinutes: minutes,
      title: j['title'] as String? ?? '',
      body: j['body'] as String? ?? '',
      target: rawTarget is String ? rawTarget : '${rawTarget ?? ''}',
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': type.name,
        'app': app,
        'query': query,
        'after_minutes': afterMinutes,
        'title': title,
        'body': body,
        'target': target,
      };
}

class FridayResponse {
  const FridayResponse({
    required this.reply,
    this.action = const FridayAction(),
    this.extraActions = const <FridayAction>[],
    this.source = FridaySource.offline,
  });

  final String reply;
  final FridayAction action;

  /// More actions from the same message, after [action], for multi-part
  /// commands ("set brightness 50 and volume 20"). Empty for one request.
  final List<FridayAction> extraActions;
  final FridaySource source;

  /// Every action to run, in the order the user asked for them.
  List<FridayAction> get allActions => <FridayAction>[action, ...extraActions];
}
