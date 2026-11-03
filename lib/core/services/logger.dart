import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'app_paths.dart';

enum LogLevel { debug, info, warn, error }

/// 日志：同时输出到控制台（debug）和**文件**（所有模式）。
///
/// 为什么必须落文件：`developer.log` 在 release 包里不会进 logcat / Console，
/// 线上/真机问题拿到手只有"慢"，没有现场。落盘后可以直接 `adb pull` 取证。
class AppLog {
  AppLog._();

  static IOSink? _sink;
  static String? _filePath;
  static bool _initStarted = false;
  static final _pending = <String>[];

  /// 单文件上限，超过就轮转一次（保留 .1）。
  static const int _maxBytes = 2 * 1024 * 1024;

  /// 初始化：定位文件并打开追加写入。需在 App 启动时调用一次。
  static Future<void> init() async {
    if (_initStarted) return;
    _initStarted = true;
    try {
      final dir = await AppPaths.supportDir();
      final path = '$dir/app.log';
      _filePath = path;
      // 简单轮转
      final f = File(path);
      if (f.existsSync() && f.lengthSync() > _maxBytes) {
        final old = File('$path.1');
        if (old.existsSync()) old.deleteSync();
        f.renameSync(old.path);
      }
      _sink = File(path).openWrite(mode: FileMode.append);
      for (final line in _pending) {
        _sink!.writeln(line);
      }
      _pending.clear();
      i('AppLog', '日志文件已就绪: $path');
    } catch (e) {
      debugPrint('AppLog init 失败: $e');
    }
  }

  /// 当前日志文件路径（供「导出日志」用）。
  static String? get filePath => _filePath;

  static void d(String tag, String msg) => _log(LogLevel.debug, tag, msg);
  static void i(String tag, String msg) => _log(LogLevel.info, tag, msg);
  static void w(String tag, String msg) => _log(LogLevel.warn, tag, msg);
  static void e(String tag, String msg, [Object? err]) =>
      _log(LogLevel.error, tag, err == null ? msg : '$msg ($err)');

  static void _log(LogLevel level, String tag, String msg) {
    final ts = DateTime.now().toIso8601String().substring(11, 23);
    final line = '$ts ${level.name.toUpperCase().padRight(5)} [$tag] $msg';
    // debug 下仍进控制台，方便开发
    if (kDebugMode) {
      debugPrint(line);
    }
    final sink = _sink;
    if (sink == null) {
      // 启动早期（init 未完成）先缓存，init 后补写
      if (_pending.length < 500) _pending.add(line);
      return;
    }
    try {
      sink.writeln(line);
    } catch (_) {}
  }

  /// 计时器：`AppLog.timer('tag','desc')` → 结束后打印耗时。
  static Stopwatch timer(String tag, String what) {
    i(tag, '▶ $what');
    return Stopwatch()..start();
  }

  static void done(String tag, String what, Stopwatch sw) {
    sw.stop();
    i(tag, '✔ $what 用时 ${sw.elapsedMilliseconds}ms');
  }

  static Future<void> flush() async {
    try {
      await _sink?.flush();
    } catch (_) {}
  }
}