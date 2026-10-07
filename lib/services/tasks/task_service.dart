import 'dart:io';
import 'package:flutter/services.dart';
import 'gold_task.dart';

class TaskService {
  static const _channel = MethodChannel('friday/device');
  Future<Map<String, dynamic>> state() async {
    if (!Platform.isAndroid) return {'mode': 'unsupported', 'tasks': []};
    final result = await _channel.invokeMapMethod<String, dynamic>('taskState');
    return result ?? {'mode': 'unavailable', 'tasks': []};
  }

  Future<String> create(GoldTaskRequest request) async {
    if (!Platform.isAndroid)
      return 'Background Oro checks run on the Android phone, where Oro is installed.';
    try {
      return await _channel.invokeMethod<String>(
              'taskCreate', request.toJson()) ??
          'Could not start the task.';
    } catch (_) {
      return 'Could not start the task. Open Friday and check notification permissions.';
    }
  }

  Future<String> cancelAll() async {
    if (!Platform.isAndroid)
      return 'Cancel your gold tasks in Friday on the phone.';
    return await _channel.invokeMethod<String>('taskCancelAll') ??
        'Could not cancel the tasks.';
  }

  Future<String> setMode(bool saver) async {
    return await _channel.invokeMethod<String>('taskMode', {'saver': saver}) ??
        'Could not change background mode.';
  }
}
