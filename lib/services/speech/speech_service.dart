import 'dart:async';
import 'dart:io' show Directory, File, Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_to_text.dart';

import 'groq_stt.dart';

/// Voice in and voice out.
///
/// On Android/iOS, input uses the speech_to_text plugin (Google's engine, so
/// Marathi and Hindi work alongside English). On Windows there is no such
/// engine, so input records the mic with the record plugin and transcribes
/// through Groq's hosted Whisper with the same Groq key the brain uses -
/// tap the mic to start, tap again to stop and send. No partial words on
/// Windows; the text lands when you stop. Output is flutter_tts everywhere.
class SpeechService {
  SpeechService({Future<String> Function()? groqKeyProvider})
      : _groqKeyProvider = groqKeyProvider;

  final stt.SpeechToText _stt = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();

  // Lazy: constructing AudioRecorder spins up plugin machinery, which must
  // only happen on Windows where it is actually used.
  AudioRecorder? _recField;
  AudioRecorder get _rec => _recField ??= AudioRecorder();
  final Future<String> Function()? _groqKeyProvider;

  bool _sttReady = false;
  bool _recListening = false;
  Timer? _maxTimer;
  void Function(String text)? _onResult;
  void Function()? _onDone;
  String? _wavPath;

  /// Honest reason the last Windows transcription failed, if it did. Cleared
  /// on each new listen. Null on mobile.
  String? lastSttError;

  static bool get _isWindows => !kIsWeb && Platform.isWindows;

  Future<bool> initSpeech() async {
    if (_isWindows) {
      try {
        return await _rec.hasPermission();
      } catch (_) {
        return false;
      }
    }
    if (_sttReady) return true;
    try {
      _sttReady = await _stt.initialize();
    } catch (_) {
      _sttReady = false;
    }
    return _sttReady;
  }

  bool get isListening => _isWindows ? _recListening : _stt.isListening;

  void startListening({
    required void Function(String text) onResult,
    required void Function() onDone,
    String localeId = 'en_IN',
  }) {
    lastSttError = null;
    if (_isWindows) {
      _onResult = onResult;
      _onDone = onDone;
      unawaited(_startRecording());
      return;
    }
    if (!_sttReady) return;
    _stt.listen(
      onResult: (r) {
        onResult(r.recognizedWords);
        if (r.finalResult) onDone();
      },
      listenOptions: SpeechListenOptions(
        localeId: localeId,
        partialResults: true,
        cancelOnError: true,
      ),
    );
  }

  Future<void> _startRecording() async {
    try {
      if (!await _rec.hasPermission()) {
        lastSttError =
            'Microphone permission is off. Enable it in Windows Settings > Privacy > Microphone.';
        _recListening = false;
        _onDone?.call();
        return;
      }
      _wavPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}friday_mic_${DateTime.now().millisecondsSinceEpoch}.wav';
      await _rec.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: _wavPath!,
      );
      _recListening = true;
      _maxTimer = Timer(const Duration(seconds: 90), () => stopListening());
    } catch (_) {
      lastSttError = 'Could not start the microphone.';
      _recListening = false;
      _onDone?.call();
    }
  }

  Future<void> stopListening() async {
    if (!_isWindows) return _stt.stop();
    _maxTimer?.cancel();
    _maxTimer = null;
    if (!_recListening) return;
    _recListening = false;
    try {
      await _rec.stop();
    } catch (_) {}
    final path = _wavPath;
    _wavPath = null;
    if (path == null || !File(path).existsSync()) {
      lastSttError = 'No audio was captured.';
      _onDone?.call();
      return;
    }
    try {
      final key = (await _groqKeyProvider?.call()) ?? '';
      if (key.isEmpty) {
        lastSttError =
            'Voice input needs a Groq API key. Add one in Settings.';
      } else {
        final text = await GroqStt(apiKey: key).transcribe(path);
        if (text.isEmpty) {
          lastSttError = 'Nothing was heard. Try again, a little louder.';
        } else {
          _onResult?.call(text);
        }
      }
    } catch (_) {
      lastSttError = 'Speech-to-text failed. Check the connection.';
    }
    try {
      File(path).delete();
    } catch (_) {}
    _onDone?.call();
  }

  Future<void> speak(String text, {String locale = 'en-IN'}) async {
    try {
      // Windows voice lookup with an Indian-English code can stall the
      // plugin; use the system voice there, and never let TTS block the
      // reply path for more than a few seconds anywhere.
      if (!_isWindows) await _tts.setLanguage(locale);
      await _tts.setSpeechRate(0.5);
      await _tts.speak(text).timeout(const Duration(seconds: 5));
    } catch (_) {
      // Speaking is a nicety; never block the answer on it.
    }
  }

  Future<void> stopSpeaking() => _tts.stop();
}
