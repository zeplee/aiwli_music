import 'package:path_provider/path_provider.dart';

/// 平台无关的应用目录定位（内部走 path_provider，无平台分支）。
class AppPaths {
  AppPaths._();

  static String? _support;

  static Future<String> supportDir() async {
    final cached = _support;
    if (cached != null) return cached;
    final dir = await getApplicationSupportDirectory();
    _support = dir.path;
    return dir.path;
  }
}
