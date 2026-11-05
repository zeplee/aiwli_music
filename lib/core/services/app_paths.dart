import 'package:path_provider/path_provider.dart';

/// 平台无关的应用目录定位（内部走 path_provider，无平台分支）。
class AppPaths {
  AppPaths._();

  static String? _support;

  /// 测试用：预置目录，避免依赖 path_provider 的平台通道。
  /// 也可用于"用户自定义数据目录"等场景。
  static void overrideSupportDirForTesting(String? path) => _support = path;

  static Future<String> supportDir() async {
    final cached = _support;
    if (cached != null) return cached;
    final dir = await getApplicationSupportDirectory();
    _support = dir.path;
    return dir.path;
  }
}
