import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/chat_message.dart';
import 'cloud_provider.dart';

/// Any OpenAI-compatible chat API. Covers Groq (console.groq.com, generous
/// free tier) and OpenRouter free models (openrouter.ai/keys) with one class.
class OpenAiCompatibleProvider implements CloudProvider {
  OpenAiCompatibleProvider({
    required this.apiKey,
    required String baseUrl,
    required this.model,
    String? name,
  })  : baseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl,
        name = name ?? 'OpenAI-compatible';

  @override
  final String name;

  final String apiKey;
  final String baseUrl;
  final String model;

  factory OpenAiCompatibleProvider.groq({
    required String apiKey,
    String model = 'llama-3.1-8b-instant',
  }) =>
      OpenAiCompatibleProvider(
        apiKey: apiKey,
        baseUrl: 'https://api.groq.com/openai/v1',
        model: model,
        name: 'Groq',
      );

  factory OpenAiCompatibleProvider.openRouter({
    required String apiKey,
    String model = 'meta-llama/llama-3.1-8b-instruct:free',
  }) =>
      OpenAiCompatibleProvider(
        apiKey: apiKey,
        baseUrl: 'https://openrouter.ai/api/v1',
        model: model,
        name: 'OpenRouter',
      );

  @override
  Future<String> complete({
    required String system,
    required List<ChatMessage> history,
    required String userText,
  }) async {
    final messages = <Map<String, String>>[
      {'role': 'system', 'content': system},
      for (final m in history)
        {
          'role': m.role == MessageRole.user ? 'user' : 'assistant',
          'content': m.text,
        },
      {'role': 'user', 'content': userText},
    ];

    final res = await http.post(
      Uri.parse('$baseUrl/chat/completions'),
      headers: <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode(<String, dynamic>{
        'model': model,
        'messages': messages,
        'temperature': 0.4,
        'max_tokens': 1024,
      }),
    );

    if (res.statusCode != 200) {
      throw FridayApiException('$name API error ${res.statusCode}');
    }

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final choices = body['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      throw FridayApiException('$name returned no choices');
    }
    final message =
        (choices.first as Map<String, dynamic>)['message'] as Map<String, dynamic>?;
    return message?['content'] as String? ?? '';
  }
}
