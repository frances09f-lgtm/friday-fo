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
import 'model_download.dart';

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
  static const installedFilename = 'friday-qwen05.task';
  static const modelBytes = 546660344;
  static const modelSha =
      'e608953f169aeb1bd7b9155fec2559825e08453fc209b84eda3a781ed0452fd2';
  static const modelUrl =
      'https://huggingface.co/litert-community/Qwen2.5-0.5B-Instruct/resolve/$modelRevision/$modelFile';
  String setupStage = 'Not started';
  String? lastLoadError;
  String diagnostics = '';
  void _stage(String stage, String status) {
    setupStage = stage;
    setupStatus = status;
    debugPrint('Friday local model stage: $stage');
    notifyListeners();
  }

  Future<void> _failure(Object error) async {
    final rawReason = error
        .toString()
        .replaceAll(RegExp(r'https?://\S+'), '[source]')
        .replaceAll(RegExp(r'gsk_[A-Za-z0-9]+'), '[redacted]');
    final reason = error is TimeoutException
        ? 'No response for two minutes or inference test timeout. Retry; saved download bytes are kept. $rawReason'
        : error is SocketException
            ? 'Network connection failed. Retry on a stable connection; saved bytes are kept. $rawReason'
            : error is FileSystemException
                ? 'Could not read/write model file. Check free storage and retry. $rawReason'
                : rawReason;
    diagnostics =
        '${DateTime.now().toIso8601String()} | $setupStage | ${reason.length > 700 ? reason.substring(0, 700) : reason}';
    debugPrint('Friday local model failure: $diagnostics');
    try {
      await (await SharedPreferences.getInstance())
          .setString('friday_model_diagnostic', diagnostics);
    } catch (_) {}
    setupStatus = '$setupStage failed: $reason. Agent is not ready.';
  }

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
    if (p.getString('friday_local_kind') == 'qwen05') _type = ModelType.qwen;
    if (!setupBusy) {
      diagnostics = p.getString('friday_model_diagnostic') ?? '';
      try {
        final dir = await getApplicationSupportDirectory();
        final complete = File('${dir.path}/$installedFilename');
        final part = await complete.exists()
            ? complete
            : File('${dir.path}/friday-qwen05.task.part');
        downloaded = await part.exists() ? await part.length() : 0;
        if (p.getString('friday_local_kind') == 'qwen05')
          setupStatus = 'Qwen 0.5B registered · tap Load and test';
        else if (downloaded > 0)
          setupStatus =
              'Saved ${(downloaded / 1000000).toStringAsFixed(1)} MB. Download resumes from this file.';
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<bool> loadAndTest() async {
    if (setupBusy) return false;
    setupBusy = true;
    _stage('Engine initialization', 'Preparing local engine...');
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
    } catch (e) {
      await _failure(e);
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
    _stage('Engine initialization', 'Preparing local engine...');
    try {
      await initEngine();
      await _tail;
      _stage('Storage check', 'Checking free space and RAM...');
      final stats = await const MethodChannel('friday/device')
          .invokeMapMethod<String, dynamic>('modelStorage');
      if (stats == null || (stats['freeBytes'] as num?) == null)
        throw StateError('Storage check unavailable');
      final dir = await getApplicationSupportDirectory();
      final complete = File('${dir.path}/$installedFilename');
      var part = await complete.exists()
          ? complete
          : File('${dir.path}/friday-qwen05.task.part');
      final saved = await part.exists() ? await part.length() : 0;
      final requiredFree =
          modelBytes - (saved <= modelBytes ? saved : 0) + 268435456;
      if ((stats['freeBytes'] as num).toInt() < requiredFree)
        throw StateError(
            'Not enough free storage. Need ${(requiredFree / 1000000).ceil()} MB free for remaining download and setup.');
      if ((stats['totalRam'] as num?) != null &&
          (stats['totalRam'] as num).toInt() < 3 * 1024 * 1024 * 1024)
        throw StateError('At least 3 GB total RAM required for this trial');
      _stage('Download', 'Downloading Qwen 0.5B (547 MB). Keep Friday open.');
      await ModelDownload.fetch(
          url: Uri.parse(modelUrl),
          part: part,
          expectedBytes: modelBytes,
          cancelled: () => _cancel,
          progress: (bytes) {
            downloaded = bytes;
            notifyListeners();
          },
          clientChanged: (client) => _download = client);
      if (_cancel) throw StateError('Cancelled');
      if (await part.length() != modelBytes)
        throw StateError('Incomplete download. Retry to resume');
      _stage('Integrity check', 'Verifying SHA-256...');
      final hash = await crypto.sha256.bind(part.openRead()).first;
      final hex =
          hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      if (hex != modelSha) {
        await part.delete();
        throw StateError('Integrity mismatch; download removed');
      }
      if (_cancel) throw StateError('Cancelled');
      if (part.path != complete.path) part = await part.rename(complete.path);
      _stage('Registration', 'Registering verified local model...');
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
      _stage('Load', 'Model registered. Loading native inference...');
      final output = await _generate(
              system: 'Reply briefly.', userText: 'Reply with only READY.')
          .timeout(const Duration(seconds: 90));
      if (output.trim().isEmpty)
        throw StateError('Model generated no response');
      setupStatus = 'Local inference responded. Ready for an Agent Mode trial.';
      return true;
    } catch (e) {
      await _failure(e);
      if (_cancel)
        setupStatus = 'Download cancelled. Retry resumes a partial download.';
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
      _stage('Load', 'Loading native inference...');
      await initEngine();
      await checkSetup();
      if (_type == ModelType.qwen) {
        final dir = await getApplicationSupportDirectory();
        final target = File('${dir.path}/$installedFilename');
        final legacy = File('${dir.path}/friday-qwen05.task.part');
        if (!await target.exists() &&
            await legacy.exists() &&
            await legacy.length() == modelBytes) {
          _stage('Integrity check', 'Checking existing completed download...');
          if ((await crypto.sha256.bind(legacy.openRead()).first).toString() !=
              modelSha)
            throw StateError(
                'Existing file checksum mismatch. Use Download to retry.');
          await legacy.rename(target.path);
        }
        if (!await target.exists())
          throw StateError(
              'Complete model file not found. Use Download to resume.');
        if (await target.length() != modelBytes)
          throw StateError('Model file size is wrong. Use Download to retry.');
        _stage('Registration', 'Registering local .task file...');
        await FlutterGemma.installModel(
                modelType: ModelType.qwen, fileType: ModelFileType.task)
            .fromFile(target.path)
            .install();
      }
      _stage('Load', 'Loading native inference...');
      _model = await FlutterGemmaPlugin.instance.createModel(
        modelType: _type,
        preferredBackend: PreferredBackend.cpu,
        maxTokens: 1280,
      );
      lastLoadError = null;
      return true;
    } catch (e) {
      lastLoadError = e.toString();
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
      throw FridayApiException(lastLoadError ??
          'Local model is already loading. Retry when that operation finishes.');
    }
    if (setupBusy)
      _stage('Inference test', 'Native model loaded. Testing inference...');
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
