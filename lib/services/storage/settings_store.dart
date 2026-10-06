import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ai/cloud_provider.dart';
import '../ai/gemini_provider.dart';
import '../ai/openai_compatible_provider.dart';

/// Everything Friday needs to know about itself. API keys live in secure
/// storage (Android Keystore-backed); the rest in plain preferences.
class SettingsStore extends ChangeNotifier {
  SettingsStore(this._secure, this._prefs);

  static const _keyGemini = 'friday_key_gemini';
  static const _keyGroq = 'friday_key_groq';
  static const _keyOpenRouter = 'friday_key_openrouter';

  final FlutterSecureStorage _secure;
  final SharedPreferences _prefs;

  String geminiKey = '';
  String groqKey = '';
  String openRouterKey = '';

  /// Comma-separated order cloud brains are tried in.
  String cloudOrder = 'gemini,groq,openrouter';
  String groqModel = 'llama-3.1-8b-instant';
  String openRouterModel = 'meta-llama/llama-3.1-8b-instruct:free';
  bool localFallbackEnabled = true;

  /// Mute toggle: when true Friday speaks its replies out loud.
  bool speakReplies = true;

  /// Where the Gemma weights come from (set in Settings; see README).
  String localModelUrl = '';

  bool get hasAnyCloudKey =>
      geminiKey.isNotEmpty || groqKey.isNotEmpty || openRouterKey.isNotEmpty;

  /// Groq key baked in at build time via --dart-define (CI secret). A key
  /// typed in Settings (secure storage) always wins over the built-in one.
  static const _builtInGroqKey = String.fromEnvironment('GROQ_API_KEY');

  Future<void> load() async {
    geminiKey = await _secure.read(key: _keyGemini) ?? '';
    groqKey = await _secure.read(key: _keyGroq) ?? '';
    if (groqKey.isEmpty) groqKey = _builtInGroqKey;
    openRouterKey = await _secure.read(key: _keyOpenRouter) ?? '';
    cloudOrder = _prefs.getString('friday_cloud_order') ?? cloudOrder;
    groqModel = _prefs.getString('friday_groq_model') ?? groqModel;
    openRouterModel =
        _prefs.getString('friday_openrouter_model') ?? openRouterModel;
    localFallbackEnabled = _prefs.getBool('friday_local_fallback') ?? true;
    speakReplies = _prefs.getBool('friday_speak_replies') ?? true;
    localModelUrl = _prefs.getString('friday_local_model_url') ?? '';
    notifyListeners();
  }

  Future<void> setApiKey(String slot, String value) async {
    final key = switch (slot) {
      'gemini' => _keyGemini,
      'groq' => _keyGroq,
      'openrouter' => _keyOpenRouter,
      _ => null,
    };
    if (key == null) return;
    await _secure.write(key: key, value: value.trim());
    switch (slot) {
      case 'gemini':
        geminiKey = value.trim();
      case 'groq':
        groqKey = value.trim();
      case 'openrouter':
        openRouterKey = value.trim();
    }
    notifyListeners();
  }

  Future<void> setLocalModelUrl(String value) async {
    localModelUrl = value.trim();
    await _prefs.setString('friday_local_model_url', localModelUrl);
    notifyListeners();
  }

  Future<void> setSpeakReplies(bool enabled) async {
    speakReplies = enabled;
    await _prefs.setBool('friday_speak_replies', enabled);
    notifyListeners();
  }

  Future<void> setLocalFallback(bool enabled) async {
    localFallbackEnabled = enabled;
    await _prefs.setBool('friday_local_fallback', enabled);
    notifyListeners();
  }

  /// Builds the cloud brains in the order they should be tried, skipping
  /// any slot with no key.
  List<CloudProvider> buildProviders() {
    final providers = <CloudProvider>[];
    for (final slot in cloudOrder.split(',')) {
      switch (slot.trim()) {
        case 'gemini':
          if (geminiKey.isNotEmpty) {
            providers.add(GeminiProvider(apiKey: geminiKey));
          }
        case 'groq':
          if (groqKey.isNotEmpty) {
            providers.add(
              OpenAiCompatibleProvider.groq(
                apiKey: groqKey,
                model: groqModel,
              ),
            );
          }
        case 'openrouter':
          if (openRouterKey.isNotEmpty) {
            providers.add(
              OpenAiCompatibleProvider.openRouter(
                apiKey: openRouterKey,
                model: openRouterModel,
              ),
            );
          }
      }
    }
    return providers;
  }
}
