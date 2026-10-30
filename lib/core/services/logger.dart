import 'dart:developer' as developer;

enum LogLevel { debug, info, warn, error }

/// 极简日志：M0/spike 够用；后续按需加文件落盘。
class AppLog {
  AppLog._();

  static void d(String tag, String msg) => _log(LogLevel.debug, tag, msg);
  static void i(String tag, String msg) => _log(LogLevel.info, tag, msg);
  static void w(String tag, String msg) => _log(LogLevel.warn, tag, msg);
  static void e(String tag, String msg, [Object? err]) =>
      _log(LogLevel.error, tag, err == null ? msg : '$msg ($err)');

  static void _log(LogLevel level, String tag, String msg) {
    developer.log('[$tag] $msg', name: 'aiwli.${level.name}');
  }
}
