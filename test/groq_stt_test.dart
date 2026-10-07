import 'package:flutter_test/flutter_test.dart';
import 'package:friday/services/speech/groq_stt.dart';
import 'package:friday/services/speech/speech_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('parses a whisper transcript', () {
    expect(GroqStt.parseTranscript('{"text":"  send a message to dad  "}'),
        'send a message to dad');
  });

  test('empty or odd payloads degrade to empty text', () {
    expect(GroqStt.parseTranscript('{"text":""}'), '');
    expect(GroqStt.parseTranscript('{}'), '');
  });

  test('SpeechService constructs without a key provider', () {
    expect(SpeechService(), isNotNull);
    expect(SpeechService(groqKeyProvider: () async => 'k'), isNotNull);
  });
}
