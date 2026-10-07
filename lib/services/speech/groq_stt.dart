import 'dart:convert';

import 'package:http/http.dart' as http;

/// Groq's hosted Whisper endpoint (OpenAI-compatible /audio/transcriptions).
/// Used on platforms where the on-device speech_to_text plugin has no engine
/// (Windows desktop). whisper-large-v3-turbo keeps English, Hindi and Marathi
/// support at a fraction of large-v3's transcription time.
class GroqStt {
  GroqStt({required this.apiKey});

  final String apiKey;

  static const _url =
      'https://api.groq.com/openai/v1/audio/transcriptions';

  Future<String> transcribe(String wavPath) async {
    final req = http.MultipartRequest('POST', Uri.parse(_url))
      ..headers['Authorization'] = 'Bearer $apiKey'
      ..fields['model'] = 'whisper-large-v3-turbo'
      ..fields['response_format'] = 'json'
      ..files.add(await http.MultipartFile.fromPath('file', wavPath));
    final res = await req.send().timeout(const Duration(seconds: 45));
    final body = await res.stream.bytesToString();
    if (res.statusCode != 200) {
      throw StateError('Groq speech-to-text failed (${res.statusCode})');
    }
    return parseTranscript(body);
  }

  static String parseTranscript(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) return '';
    return (decoded['text'] as String? ?? '').trim();
  }
}
