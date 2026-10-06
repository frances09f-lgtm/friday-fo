import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/chat_message.dart';
import 'cloud_provider.dart';

/// Google Gemini, the default free-tier brain (free keys at aistudio.google.com).
class GeminiProvider implements CloudProvider {
  GeminiProvider({required this.apiKey, this.model = 'gemini-2.0-flash'});

  static const _endpoint =
      'https://generativelanguage.googleapis.com/v1beta/models';

  @override
  final String name = 'Google Gemini';

  final String apiKey;
  final String model;

  @override
  Future<String> complete({
    required String system,
    required List<ChatMessage> history,
    required String userText,
  }) async {
    final contents = <Map<String, dynamic>>[
      for (final m in history)
        {
          'role': m.role == MessageRole.user ? 'user' : 'model',
          'parts': [
            {'text': m.text},
          ],
        },
      {
        'role': 'user',
        'parts': [
          {'text': userText},
        ],
      },
    ];

    final res = await http.post(
      Uri.parse('$_endpoint/$model:generateContent'),
      headers: <String, String>{
        'Content-Type': 'application/json',
        'x-goog-api-key': apiKey,
      },
      body: jsonEncode(<String, dynamic>{
        'system_instruction': {
          'parts': [
            {'text': system},
          ],
        },
        'contents': contents,
        'generationConfig': {'temperature': 0.4, 'maxOutputTokens': 1024},
      }),
    );

    if (res.statusCode != 200) {
      throw FridayApiException('Gemini API error ${res.statusCode}');
    }

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final candidates = body['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      throw FridayApiException('Gemini returned no candidates');
    }
    final content = (candidates.first as Map<String, dynamic>)['content']
        as Map<String, dynamic>?;
    final parts = content?['parts'] as List?;
    if (parts == null || parts.isEmpty) {
      throw FridayApiException('Gemini returned an empty answer');
    }
    return (parts.first as Map<String, dynamic>)['text'] as String? ?? '';
  }
}
