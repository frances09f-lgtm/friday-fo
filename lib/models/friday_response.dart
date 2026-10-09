enum FridayActionType {
  none,
  openApp,
  playMusic,
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

  static FridayActionType _typeFrom(String? raw) {
    switch (raw) {
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

  factory FridayAction.fromJson(Map<String, dynamic> json) => FridayAction(
        type: _typeFrom(json['type'] as String?),
        app: json['app'] as String? ?? '',
        query: json['query'] as String? ?? '',
        afterMinutes: (json['after_minutes'] as num?)?.toInt() ?? 0,
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        target: json['target'] as String? ?? '',
      );

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
