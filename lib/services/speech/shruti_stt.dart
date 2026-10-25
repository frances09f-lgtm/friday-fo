import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../ai/model_download.dart';

/// Optional on-device speech-to-text: the needle engine running the Shruti
/// model (udgamlabs/Shruti on HuggingFace, Apache-2.0). The model downloads
/// once into app storage from Settings > Voice; recognition then runs fully
/// offline on the phone. Android only - everywhere else the existing engines
/// (speech_to_text on mobile, Groq Whisper on Windows) stay in charge.
class ShrutiStt extends ChangeNotifier {
  static const _channel = MethodChannel('friday/shruti');

  // Pinned to Shruti revision ebf52e614065ce20e56affdab641f749a04511a5.
  static const modelUrl =
      'https://huggingface.co/udgamlabs/Shruti/resolve/ebf52e614065ce20e56affdab641f749a04511a5/shruti.cact';
  static const expectedBytes = 29546527;
  static const expectedSha256 =
      'b189e954aaed4a9fd41acbad3ac05e486381e96325b22a4c695b9ea5153d7065';
  static const _modelName = 'shruti.cact';

  bool downloading = false;
  int downloadedBytes = 0;
  String? lastDownloadError;

  Future<File> _modelFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}$_modelName');
  }

  Future<String> modelPath() async => (await _modelFile()).path;

  Future<bool> isModelReady() async {
    try {
      final f = await _modelFile();
      return await f.exists() && await f.length() == expectedBytes;
    } catch (_) {
      return false;
    }
  }

  /// Downloads the model with resume support (the same downloader the
  /// on-device LLM setup uses). A failed or interrupted run picks up where
  /// it stopped on the next call. Notifies listeners with progress.
  Future<bool> ensureModel() async {
    if (downloading) return false;
    if (await isModelReady()) return true;
    downloading = true;
    lastDownloadError = null;
    downloadedBytes = 0;
    notifyListeners();
    try {
      final f = await _modelFile();
      await f.parent.create(recursive: true);
      await ModelDownload.fetch(
        url: Uri.parse(modelUrl),
        part: f,
        expectedBytes: expectedBytes,
        cancelled: () => false,
        progress: (n) {
          downloadedBytes = n;
          notifyListeners();
        },
        clientChanged: (_) {},
      );
      final digest = await sha256.bind(f.openRead()).first;
      if (digest.toString() != expectedSha256) {
        await f.delete();
        lastDownloadError =
            'Downloaded model failed its integrity check. Retry the download.';
        return false;
      }
      return true;
    } catch (_) {
      lastDownloadError = 'Download failed. Check the connection and retry.';
      return false;
    } finally {
      downloading = false;
      notifyListeners();
    }
  }

  Future<void> deleteModel() async {
    try {
      final f = await _modelFile();
      if (await f.exists()) await f.delete();
    } catch (_) {}
    downloadedBytes = 0;
    notifyListeners();
  }

  /// Transcribes a 16 kHz mono 16-bit WAV file and returns the text. Throws
  /// with an honest, fixable message when the model or engine is missing.
  Future<String> transcribe(String wavPath) async {
    final model = await _modelFile();
    if (!await model.exists()) {
      throw StateError(
          'The Shruti model is not downloaded yet. Open Settings > Voice to download it.');
    }
    final reply = await _channel.invokeMethod<String>('transcribe', {
      'modelPath': model.path,
      'wavPath': wavPath,
    });
    if (reply == null || reply.isEmpty) {
      throw StateError('No reply from the on-device speech engine.');
    }
    final decoded = jsonDecode(reply);
    if (decoded is Map && decoded['error'] is String) {
      throw StateError(decoded['error'] as String);
    }
    if (decoded is Map && decoded['text'] is String) {
      return (decoded['text'] as String).trim();
    }
    throw StateError('Unexpected reply from the on-device speech engine.');
  }
}
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../ai/model_download.dart';

/// Optional on-device speech-to-text: the needle engine running the Shruti
/// model (udgamlabs/Shruti on HuggingFace, Apache-2.0). The model downloads
/// once into app storage from Settings > Voice; recognition then runs fully
/// offline on the phone. Android only - everywhere else the existing engines
/// (speech_to_text on mobile, Groq Whisper on Windows) stay in charge.
class ShrutiStt extends ChangeNotifier {
  static const _channel = MethodChannel('friday/shruti');

  // Pinned to Shruti revision ebf52e614065ce20e56affdab641f749a04511a5.
  static const modelUrl =
      'https://huggingface.co/udgamlabs/Shruti/resolve/ebf52e614065ce20e56affdab641f749a04511a5/shruti.cact';
  static const expectedBytes = 29546527;
  static const expectedSha256 =
      'b189e954aaed4a9fd41acbad3ac05e486381e96325b22a4c695b9ea5153d7065';
  static const _modelName = 'shruti.cact';

  bool downloading = false;
  int downloadedBytes = 0;
  String? lastDownloadError;

  Future<File> _modelFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}$_modelName');
  }

  Future<String> modelPath() async => (await _modelFile()).path;

  Future<bool> isModelReady() async {
    try {
      final f = await _modelFile();
      return await f.exists() && await f.length() == expectedBytes;
    } catch (_) {
      return false;
    }
  }

  /// Downloads the model with resume support (the same downloader the
  /// on-device LLM setup uses). A failed or interrupted run picks up where
  /// it stopped on the next call. Notifies listeners with progress.
  Future<bool> ensureModel() async {
    if (downloading) return false;
    if (await isModelReady()) return true;
    downloading = true;
    lastDownloadError = null;
    downloadedBytes = 0;
    notifyListeners();
    try {
      final f = await _modelFile();
      await f.parent.create(recursive: true);
      await ModelDownload.fetch(
        url: Uri.parse(modelUrl),
        part: f,
        expectedBytes: expectedBytes,
        cancelled: () => false,
        progress: (n) {
          downloadedBytes = n;
          notifyListeners();
        },
        clientChanged: (_) {},
      );
      final digest = await sha256.bind(f.openRead()).first;
      if (digest.toString() != expectedSha256) {
