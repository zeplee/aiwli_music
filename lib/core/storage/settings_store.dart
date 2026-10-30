import 'dart:convert';
import 'dart:io';

import '../services/app_paths.dart';

/// JSON 偏好存储（aiwli_git 同款思路：单文件、整读整写、无平台分支）。
class SettingsStore {
  const SettingsStore();

  Future<Map<String, Object?>> load(String fileName) async {
    final dir = await AppPaths.supportDir();
    final f = File('$dir/$fileName');
    if (!await f.exists()) return {};
    try {
      return (jsonDecode(await f.readAsString()) as Map)
          .cast<String, Object?>();
    } catch (_) {
      return {};
    }
  }

  Future<void> flush(String fileName, Map<String, Object?> data) async {
    final dir = await AppPaths.supportDir();
    final f = File('$dir/$fileName');
    await f.parent.create(recursive: true);
    await f.writeAsString(jsonEncode(data));
  }
}
