import 'package:flutter/foundation.dart';

/// dispose 后静默忽略通知的安全基类。
///
/// 背景：服务在构造时启动异步初始化（JSON 恢复），完成可能晚于 provider
/// 容器销毁；且 Riverpod 销毁流程在 dispose 之后仍会 removeListener，
/// 触发 ChangeNotifier 的 debug 断言。
///
/// 处理：刻意不调用 super.dispose()（实例为容器级单例，生命周期与
/// 容器一致，无实际泄漏），并静默忽略 dispose 后的通知。
abstract class SafeNotifier extends ChangeNotifier {
  bool _safeDisposed = false;

  @override
  // ignore: must_call_super —— 刻意不调用：保持监听器结构，避免销毁后断言（见类注释）
  void dispose() {
    _safeDisposed = true;
  }

  @override
  void notifyListeners() {
    if (!_safeDisposed) super.notifyListeners();
  }

  @override
  void removeListener(VoidCallback listener) {
    if (!_safeDisposed) super.removeListener(listener);
  }

  @override
  void addListener(VoidCallback listener) {
    if (!_safeDisposed) super.addListener(listener);
  }
}
