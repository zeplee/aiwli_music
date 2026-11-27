import 'dart:async';

import 'safe_notifier.dart';

/// 定时关闭：倒计时 或 播完当前首。
/// 倒计时到期回调 [onExpire]（由装配层接到 pause）。
class SleepTimerService extends SafeNotifier {
  SleepTimerService({required this.onExpire, this.onEndOfTrackChanged});
  final void Function() onExpire;
  final void Function(bool active)? onEndOfTrackChanged;

  Timer? _ticker;
  DateTime? _endsAt;
  bool _endOfTrack = false;

  /// 倒计时结束时间；null = 倒计时不活跃。
  DateTime? get endsAt => _endsAt;
  bool get endOfTrackActive => _endOfTrack;
  bool get active => _endsAt != null || _endOfTrack;

  Duration get remaining {
    final e = _endsAt;
    if (e == null) return Duration.zero;
    final d = e.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  void startCountdown(Duration duration) {
    _cancelInternal();
    _endOfTrack = false;
    onEndOfTrackChanged?.call(false);
    _endsAt = DateTime.now().add(duration);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (remaining <= Duration.zero) {
        cancel();
        onExpire();
      } else {
        notifyListeners();
      }
    });
    notifyListeners();
  }

  /// 播完当前首后暂停（由 PlayerCore 的 endOfTrackPause 标志实现）。
  void startEndOfTrack() {
    _cancelInternal();
    _endOfTrack = true;
    onEndOfTrackChanged?.call(true);
    notifyListeners();
  }

  void cancel() {
    _cancelInternal();
    notifyListeners();
  }

  /// SafeNotifier.dispose() 刻意不调用 super，也不会自动清理子类资源。
  /// 不覆写的话，热重启 / provider 容器销毁后 periodic Timer 仍每秒触发，
  /// 到期还会调用已失效 PlayerCore 的 pause ——
  /// 用户感知为「我没设定时，播着播着自己停了」。
  @override
  void dispose() {
    _ticker?.cancel();
    _ticker = null;
    _endsAt = null;
    _endOfTrack = false;
    super.dispose();
  }

  void _cancelInternal() {
    _ticker?.cancel();
    _ticker = null;
    _endsAt = null;
    if (_endOfTrack) {
      _endOfTrack = false;
      onEndOfTrackChanged?.call(false);
    }
  }
}
