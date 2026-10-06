import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Voice in (speech_to_text, uses Google's Android engine so Marathi and
/// Hindi work alongside English) and voice out (flutter_tts).
///
/// A later swap to Cactus Whistle for the input side only touches this class.
class SpeechService {
  final stt.SpeechToText _stt = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();

  bool _sttReady = false;

  Future<bool> initSpeech() async {
    if (_sttReady) return true;
    try {
      _sttReady = await _stt.initialize();
    } catch (_) {
      _sttReady = false;
    }
    return _sttReady;
  }

  bool get isListening => _stt.isListening;

  void startListening({
    required void Function(String text) onResult,
    required void Function() onDone,
    String localeId = 'en_IN',
  }) {
    if (!_sttReady) return;
    _stt.listen(
      onResult: (r) {
        onResult(r.recognizedWords);
        if (r.finalResult) onDone();
      },
      localeId: localeId,
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
      ),
    );
  }

  Future<void> stopListening() => _stt.stop();

  Future<void> speak(String text, {String locale = 'en-IN'}) async {
    try {
      await _tts.setLanguage(locale);
      await _tts.setSpeechRate(0.5);
      await _tts.speak(text);
    } catch (_) {
      // Speaking is a nicety; never block the answer on it.
    }
  }

  Future<void> stopSpeaking() => _tts.stop();
}
