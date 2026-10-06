import 'package:flutter_gemma/flutter_gemma.dart';

import '../../models/chat_message.dart';
import 'cloud_provider.dart';

/// The on-device backup brain. Runs a small Gemma model locally with
/// flutter_gemma (Google AI Edge / MediaPipe), so Friday still answers and
/// still understands phone actions when every API key fails or is offline.
///
/// The model file is NOT bundled: it is downloaded once from the URL the user
/// sets in Settings (see README for free weights), then kept on the device.
class LocalModelService {
  InferenceModel? _model;
  bool _loading = false;

  bool get isReady => _model != null;

  /// Downloads and installs the model file. Safe to call again; returns false
  /// when the download fails so Friday can move on to the offline engine.
  Future<bool> installFromUrl(String url) async {
    if (url.trim().isEmpty) return false;
    try {
      await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
          .fromNetwork(url.trim())
          .install();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> ensureReady() async {
    if (_model != null) return true;
    if (_loading) return false;
    _loading = true;
    try {
      _model = await FlutterGemmaPlugin.instance.createModel(
        modelType: ModelType.gemmaIt,
        maxTokens: 512,
      );
      return true;
    } catch (_) {
      _model = null;
      return false;
    } finally {
      _loading = false;
    }
  }

  Future<String> generate({
    required String system,
    required String userText,
    List<ChatMessage> history = const [],
  }) async {
    if (!await ensureReady()) {
      throw FridayApiException('No local model available');
    }
    final chat = await _model!.createChat();
    for (final m in history) {
      await chat.addQueryChunk(
        Message.text(text: m.text, isUser: m.role == MessageRole.user),
      );
    }
    await chat.addQueryChunk(Message.text(text: userText, isUser: true));

    final buffer = StringBuffer();
    await for (final response in chat.generateChatResponseAsync()) {
      switch (response) {
        case TextResponse(:final token):
          buffer.write(token);
        case ThinkingResponse():
          break; // Skip the model's internal reasoning.
        default:
          break;
      }
    }
    return buffer.toString();
  }

  Future<void> dispose() async {
    try {
      await _model?.close();
    } catch (_) {}
    _model = null;
  }
}
