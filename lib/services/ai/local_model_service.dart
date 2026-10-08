import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart' as crypto;

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_mediapipe/flutter_gemma_mediapipe.dart';

import '../../models/chat_message.dart';
import 'cloud_provider.dart';

/// The on-device backup brain. Runs a small Gemma model locally with
/// flutter_gemma (Google AI Edge / MediaPipe), so Friday still answers and
/// still understands phone actions when every API key fails or is offline.
///
/// The model file is NOT bundled: it is downloaded once from the URL the user
/// sets in Settings (see README for free weights), then kept on the device.
class LocalModelService extends ChangeNotifier {
  static Future<void>? _engineInit;
  static Future<void> initEngine() => _engineInit ??=
      FlutterGemma.initialize(inferenceEngines: [MediaPipeEngine()]);
  static const modelRevision = '6c237a59eedeb06a821b21f0a59b03d346ac8bc3';
  static const modelFile =
      'Qwen2.5-0.5B-Instruct_multi-prefill-seq_q8_ekv1280.task';
  static const modelBytes = 546660344;
  static const modelSha =
      'e608953f169aeb1bd7b9155fec2559825e08453fc209b84eda3a781ed0452fd2';
  static const modelUrl =
      'https://huggingface.co/litert-community/Qwen2.5-0.5B-Instruct/resolve/$modelRevision/$modelFile';
  bool setupBusy = false;
  int downloaded = 0;
  String setupStatus = 'No guided model installed';
  bool _cancel = false;
  HttpClient? _download;
  ModelType _type = ModelType.gemmaIt;
  void cancelSetup() {
    _cancel = true;
    _download?.close(force: true);
  }

  Future<void> checkSetup() async {
    final p = await SharedPreferences.getInstance();
    if (p.getString('friday_local_kind') == 'qwen05') {
      _type = ModelType.qwen;
      setupStatus = 'Qwen 0.5B installed · tap Load and test';
    }
    notifyListeners();
  }

  Future<bool> loadAndTest() async {
    if (setupBusy) return false;
    setupBusy = true;
    setupStatus = 'Loading and testing local inference...';
    notifyListeners();
    try {
      await initEngine();
      await _tail;
      await checkSetup();
      final result = await _generate(
              system: 'Reply briefly.', userText: 'Reply with only READY.')
          .timeout(const Duration(seconds: 90));
      if (result.trim().isEmpty) throw StateError('Empty response');
      setupStatus =
          'Local inference responded. Agent task accuracy still needs testing.';
      return true;
    } catch (_) {
      setupStatus =
          'Model could not run on this phone. Check storage/RAM or retry. Agent is not ready.';
      return false;
    } finally {
      setupBusy = false;
      notifyListeners();
    }
  }

  Future<bool> downloadGuided() async {
    if (setupBusy) return false;
    setupBusy = true;
    _cancel = false;
    setupStatus = 'Checking free space...';
    notifyListeners();
    try {
      await initEngine();
      await _tail;
      final stats = await const MethodChannel('friday/device')
          .invokeMapMethod<String, dynamic>('modelStorage');
      if (stats == null || (stats['freeBytes'] as num?) == null)
        throw StateError('Storage check unavailable');
      if ((stats['freeBytes'] as num).toInt() < modelBytes * 2 + 268435456)
        throw StateError('Need at least 1.4 GB free storage');
      if ((stats['totalRam'] as num?) != null &&
          (stats['totalRam'] as num).toInt() < 3 * 1024 * 1024 * 1024)
        throw StateError('At least 3 GB total RAM required for this trial');
      final dir = await getApplicationSupportDirectory();
      final part = File('${dir.path}/friday-qwen05.task.part');
      var offset = await part.exists() ? await part.length() : 0;
      if (offset > modelBytes) {
        await part.delete();
        offset = 0;
      }
      downloaded = offset;
      if (offset < modelBytes) {
        setupStatus = 'Downloading Qwen 0.5B (547 MB). Keep Friday open.';
        notifyListeners();
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 30);
        _download = client;
        final req = await client.getUrl(Uri.parse(modelUrl));
        if (offset > 0) req.headers.set('Range', 'bytes=$offset-');
        final response = await req.close().timeout(const Duration(seconds: 45));
        if (response.statusCode == 200) {
          offset = 0;
          downloaded = 0;
        } else if (response.statusCode == 206) {
          if (!(response.headers.value('content-range') ?? '')
              .startsWith('bytes $offset-'))
            throw StateError('Invalid resume response');
        } else
          throw StateError('Download HTTP ${response.statusCode}');
        final sink =
            part.openWrite(mode: offset > 0 ? FileMode.append : FileMode.write);
        try {
          await for (final bytes
              in response.timeout(const Duration(seconds: 45))) {
            if (_cancel) throw StateError('Cancelled');
            downloaded += bytes.length;
            if (downloaded > modelBytes) throw StateError('Oversized model');
            sink.add(bytes);
            notifyListeners();
          }
        } finally {
          await sink.close();
          client.close();
          _download = null;
        }
      }
      if (_cancel) throw StateError('Cancelled');
      if (await part.length() != modelBytes)
        throw StateError('Incomplete download. Retry to resume');
      setupStatus = 'Verifying SHA-256...';
      notifyListeners();
      final hash = await crypto.sha256.bind(part.openRead()).first;
      final hex =
          hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      if (hex != modelSha) {
        await part.delete();
        throw StateError('Integrity mismatch; download removed');
      }
      if (_cancel) throw StateError('Cancelled');
      setupStatus = 'Installing verified local model...';
      notifyListeners();
      await _model?.close();
      _model = null;
      await FlutterGemma.installModel(
              modelType: ModelType.qwen, fileType: ModelFileType.task)
          .fromFile(part.path)
          .install();
      final p = await SharedPreferences.getInstance();
      await p.setString('friday_local_kind', 'qwen05');
      _type = ModelType.qwen;
      // fromFile registers this path without copying; retain the verified file.
      setupStatus = 'Model installed. Loading and testing...';
      notifyListeners();
      final output = await _generate(
              system: 'Reply briefly.', userText: 'Reply with only READY.')
          .timeout(const Duration(seconds: 90));
      if (output.trim().isEmpty)
        throw StateError('Model generated no response');
      setupStatus = 'Local inference responded. Ready for an Agent Mode trial.';
      return true;
    } catch (e) {
      setupStatus = _cancel
          ? 'Download cancelled. Retry resumes a partial download.'
          : 'Setup failed: $e. No readiness claimed.';
      return false;
    } finally {
      setupBusy = false;
      _download?.close(force: true);
      _download = null;
      notifyListeners();
    }
  }

  InferenceModel? _model;
  bool _loading = false;
  Future<void> _tail = Future.value();

  bool get isReady => _model != null;

  /// Downloads and installs the model file. Safe to call again; returns false
  /// when the download fails so Friday can move on to the offline engine.
  Future<bool> installFromUrl(String url) async {
    if (url.trim().isEmpty) return false;
    try {
      await initEngine();
      await _model?.close();
      _model = null;
      await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
          .fromNetwork(url.trim())
          .install();
      await (await SharedPreferences.getInstance())
          .setString('friday_local_kind', 'gemma');
      _type = ModelType.gemmaIt;
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
      await initEngine();
      await checkSetup();
      _model = await FlutterGemmaPlugin.instance.createModel(
        modelType: _type,
        preferredBackend: PreferredBackend.cpu,
        maxTokens: 1280,
      );
      return true;
    } catch (_) {
      _model = null;
      return false;
    } finally {
      _loading = false;
    }
  }

  Future<String> generate(
      {required String system,
      required String userText,
      List<ChatMessage> history = const []}) {
    if (setupBusy)
      return Future.error(
          FridayApiException('Local model setup is in progress'));
    final done = Completer<String>();
    _tail = _tail.then((_) async {
      try {
        done.complete(await _generate(
            system: system, userText: userText, history: history));
      } catch (e, st) {
        done.completeError(e, st);
      }
    });
    return done.future;
  }

  Future<String> _generate({
    required String system,
    required String userText,
    List<ChatMessage> history = const [],
  }) async {
    if (!await ensureReady()) {
      throw FridayApiException('No local model available');
    }
    final chat = await _model!.createChat(
        temperature: .1, topK: 1, modelType: _type, maxOutputTokens: 192);
    try {
      for (final m in history) {
        await chat.addQueryChunk(
          Message.text(text: m.text, isUser: m.role == MessageRole.user),
        );
      }
      await chat.addQueryChunk(Message.text(
          text: system.isEmpty ? userText : '$system\n$userText',
          isUser: true));

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
    } finally {
      await chat.session.close();
    }
  }

  Future<void> closeModel() async {
    try {
      await _model?.close();
    } catch (_) {}
    _model = null;
  }
}
