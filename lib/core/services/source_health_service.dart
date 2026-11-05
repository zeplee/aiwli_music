import 'dart:async';

import '../storage/settings_store.dart';
import 'logger.dart';
import 'safe_notifier.dart';

/// 源健康状态（对齐栖弦的 健康/降级/失效 三态）。
enum SourceHealth { healthy, degraded, dead }

/// 单个源的健康记录。
class SourceHealthRecord {
  const SourceHealthRecord({
    this.consecutiveFailures = 0,
    this.totalFailures = 0,
    this.totalSuccess = 0,
    this.lastError,
    this.lastFailAt,
    this.lastOkAt,
  });

  /// 连续失败次数（成功一次即清零）。
  final int consecutiveFailures;
  final int totalFailures;
  final int totalSuccess;

  /// 最近一次失败原因（原始文本，UI 负责翻译成人类语言）。
  final String? lastError;
  final DateTime? lastFailAt;
  final DateTime? lastOkAt;

  SourceHealth get health {
    if (consecutiveFailures >= 5) return SourceHealth.dead;
    if (consecutiveFailures >= 2) return SourceHealth.degraded;
    return SourceHealth.healthy;
  }

  String get healthLabel => switch (health) {
        SourceHealth.dead => '已失效',
        SourceHealth.degraded => '可能不稳定',
        SourceHealth.healthy => '健康',
      };

  /// 把底层错误翻成用户能懂的说明。
  String get friendlyError {
    final e = (lastError ?? '').toLowerCase();
    if (e.isEmpty) return '无失败记录';
    if (e.contains('nxdomain') || e.contains('host not found')) {
      return '域名已失效（服务下线）';
    }
    if (e.contains('failed to open') || e.contains('cannot open')) {
      return '拿到的地址打不开（多为中转服务失效）';
    }
    if (e.contains('timeout') || e.contains('超时')) {
      return '请求超时（网络或服务无响应）';
    }
    if (e.contains('403') || e.contains('forbidden')) {
      return '被拒绝访问（可能需要会员/授权）';
    }
    if (e.contains('404') || e.contains('not found')) {
      return '接口返回不存在（接口已变更）';
    }
    if (e.contains('cancelled')) return '被取消（并发/超时）';
    if (e.contains('vip') || e.contains('正版')) {
      return '该曲目需要会员，源无权限';
    }
    return '取链失败';
  }

  SourceHealthRecord copyWith({
    int? consecutiveFailures,
    int? totalFailures,
    int? totalSuccess,
    String? lastError,
    DateTime? lastFailAt,
    DateTime? lastOkAt,
  }) =>
      SourceHealthRecord(
        consecutiveFailures: consecutiveFailures ?? this.consecutiveFailures,
        totalFailures: totalFailures ?? this.totalFailures,
        totalSuccess: totalSuccess ?? this.totalSuccess,
        lastError: lastError ?? this.lastError,
        lastFailAt: lastFailAt ?? this.lastFailAt,
        lastOkAt: lastOkAt ?? this.lastOkAt,
      );

  Map<String, Object?> toJson() => {
        'cf': consecutiveFailures,
        'tf': totalFailures,
        'ts': totalSuccess,
        if (lastError != null) 'err': lastError,
        if (lastFailAt != null) 'failAt': lastFailAt!.toIso8601String(),
        if (lastOkAt != null) 'okAt': lastOkAt!.toIso8601String(),
      };

  factory SourceHealthRecord.fromJson(Map<Object?, Object?> m) =>
      SourceHealthRecord(
        consecutiveFailures: (m['cf'] as num?)?.toInt() ?? 0,
        totalFailures: (m['tf'] as num?)?.toInt() ?? 0,
        totalSuccess: (m['ts'] as num?)?.toInt() ?? 0,
        lastError: m['err'] as String?,
        lastFailAt: DateTime.tryParse(m['failAt'] as String? ?? ''),
        lastOkAt: DateTime.tryParse(m['okAt'] as String? ?? ''),
      );
}

/// 源健康度：**被动学习**，不主动探测。
///
/// 为什么不主动探测（设计取舍，已实测验证）：
///   · 18 个源逐个探测要数秒，进页面就卡
///   · 脚本取链需要真实歌曲 id，探测只能用假 id → 多数源返回
///     "歌不存在"，测出的是**假失败**
///   · 部分源对高频请求限流，探测反而加速失效
///
/// 所以只记录真实播放/预取中产生的成功与失败，持久化后供 UI 展示。
/// 这比探测更准（用的是真实曲目）且零额外开销。
class SourceHealthService extends SafeNotifier {
  SourceHealthService(this._store);
  final SettingsStore _store;
  static const _file = 'source_health.json';

  final Map<String, SourceHealthRecord> _records = {};
  Timer? _flushTimer;

  SourceHealthRecord recordFor(String sourceId) =>
      _records[sourceId] ?? const SourceHealthRecord();

  Map<String, SourceHealthRecord> get all => Map.unmodifiable(_records);

  Future<void> load() async {
    final data = await _store.load(_file);
    final m = (data['sources'] as Map?) ?? const {};
    _records
      ..clear()
      ..addEntries([
        for (final e in m.entries)
          MapEntry(
            '${e.key}',
            SourceHealthRecord.fromJson(
                (e.value as Map?)?.cast<Object?, Object?>() ?? const {}),
          ),
      ]);
    notifyListeners();
  }

  /// 记录一次成功（连续失败清零）。
  void reportSuccess(String sourceId) {
    if (sourceId.isEmpty) return;
    final old = recordFor(sourceId);
    _records[sourceId] = old.copyWith(
      consecutiveFailures: 0,
      totalSuccess: old.totalSuccess + 1,
      lastOkAt: DateTime.now(),
    );
    _scheduleFlush();
  }

  /// 记录一次失败。[error] 保留原始文本，由 UI 翻译成人类语言。
  void reportFailure(String sourceId, Object? error) {
    if (sourceId.isEmpty) return;
    final old = recordFor(sourceId);
    final msg = '${error ?? ''}';
    _records[sourceId] = old.copyWith(
      consecutiveFailures: old.consecutiveFailures + 1,
      totalFailures: old.totalFailures + 1,
      lastError: msg.length > 300 ? msg.substring(0, 300) : msg,
      lastFailAt: DateTime.now(),
    );
    AppLog.w('Health',
        '$sourceId 失败 ${_records[sourceId]!.consecutiveFailures} 次: ${msg.length > 80 ? msg.substring(0, 80) : msg}');
    _scheduleFlush();
  }

  /// 手动标记正常（用户在源管理页点了"重新测试"且成功）。
  void clearFailures(String sourceId) {
    final old = recordFor(sourceId);
    _records[sourceId] = old.copyWith(consecutiveFailures: 0);
    _scheduleFlush();
  }

  /// 写盘节流：失败可能连续发生，合并成一次 IO。
  void _scheduleFlush() {
    notifyListeners();
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(milliseconds: 800), _flush);
  }

  Future<void> _flush() async {
    await _store.flush(_file, {
      'sources': {
        for (final e in _records.entries) e.key: e.value.toJson(),
      },
    });
  }

  @override
  void dispose() {
    _flushTimer?.cancel();
    super.dispose();
  }
}