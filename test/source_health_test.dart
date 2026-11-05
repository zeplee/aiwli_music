import 'package:flutter_test/flutter_test.dart';

import 'package:aiwli_music/core/services/source_health_service.dart';
import 'package:aiwli_music/core/storage/settings_store.dart';

class _MemStore extends SettingsStore {
  _MemStore();
  final Map<String, Map<String, Object?>> data = {};

  @override
  Future<Map<String, Object?>> load(String fileName) async =>
      Map.of(data[fileName] ?? const {});

  @override
  Future<void> flush(String fileName, Map<String, Object?> payload) async {
    data[fileName] = Map.of(payload);
  }
}

/// 源健康度：被动学习（不主动探测），三态判定 + 人类可读的失败原因。
void main() {
  group('健康状态判定', () {
    test('无记录 = 健康', () {
      final svc = SourceHealthService(_MemStore());
      expect(svc.recordFor('kw').health, SourceHealth.healthy);
    });

    test('连续失败 1 次仍是健康', () {
      final svc = SourceHealthService(_MemStore());
      svc.reportFailure('kw', 'timeout');
      expect(svc.recordFor('kw').health, SourceHealth.healthy);
    });

    test('连续失败 2 次 → 降级', () {
      final svc = SourceHealthService(_MemStore());
      svc.reportFailure('kw', 'e1');
      svc.reportFailure('kw', 'e2');
      expect(svc.recordFor('kw').health, SourceHealth.degraded);
      expect(svc.recordFor('kw').healthLabel, '可能不稳定');
    });

    test('连续失败 5 次 → 失效', () {
      final svc = SourceHealthService(_MemStore());
      for (var i = 0; i < 5; i++) {
        svc.reportFailure('kw', 'e$i');
      }
      expect(svc.recordFor('kw').health, SourceHealth.dead);
      expect(svc.recordFor('kw').healthLabel, '已失效');
    });

    test('成功一次即清零连续失败', () {
      final svc = SourceHealthService(_MemStore());
      for (var i = 0; i < 4; i++) {
        svc.reportFailure('kw', 'e');
      }
      expect(svc.recordFor('kw').health, SourceHealth.degraded);
      svc.reportSuccess('kw');
      expect(svc.recordFor('kw').health, SourceHealth.healthy);
      expect(svc.recordFor('kw').consecutiveFailures, 0);
      // 但总失败数保留，便于评估历史稳定度
      expect(svc.recordFor('kw').totalFailures, 4);
    });

    test('各源互不影响', () {
      final svc = SourceHealthService(_MemStore());
      for (var i = 0; i < 5; i++) {
        svc.reportFailure('kw', 'e');
      }
      expect(svc.recordFor('kw').health, SourceHealth.dead);
      expect(svc.recordFor('wy').health, SourceHealth.healthy);
    });

    test('空 sourceId 不记录', () {
      final svc = SourceHealthService(_MemStore());
      svc.reportFailure('', 'e');
      expect(svc.all, isEmpty);
    });
  });

  group('失败原因翻译', () {
    SourceHealthRecord withError(String e) {
      final svc = SourceHealthService(_MemStore());
      svc.reportFailure('x', e);
      return svc.recordFor('x');
    }

    test('NXDOMAIN → 域名已失效', () {
      expect(withError('SocketException: host not found (NXDOMAIN)')
          .friendlyError, contains('域名已失效'));
    });

    test('Failed to open → 地址打不开', () {
      expect(withError('Failed to open https://x/y.mp3').friendlyError,
          contains('打不开'));
    });

    test('403 → 需要会员/授权', () {
      expect(withError('HTTP 403 Forbidden').friendlyError,
          contains('会员'));
    });

    test('未知错误有兜底文案', () {
      expect(withError('something weird').friendlyError, '取链失败');
    });

    test('无失败记录时给出明确说明', () {
      const r = SourceHealthRecord();
      expect(r.friendlyError, '无失败记录');
    });
  });

  group('持久化', () {
    test('记录落盘后能恢复', () async {
      final store = _MemStore();
      final a = SourceHealthService(store);
      await a.load();
      for (var i = 0; i < 3; i++) {
        a.reportFailure('kw', 'boom');
      }
      // 等节流写盘
      await Future<void>.delayed(const Duration(milliseconds: 1000));

      final b = SourceHealthService(store);
      await b.load();
      expect(b.recordFor('kw').consecutiveFailures, 3);
      expect(b.recordFor('kw').health, SourceHealth.degraded);
    });

    test('clearFailures 手动清除', () {
      final svc = SourceHealthService(_MemStore());
      svc.reportFailure('kw', 'e');
      svc.reportFailure('kw', 'e');
      expect(svc.recordFor('kw').health, SourceHealth.degraded);
      svc.clearFailures('kw');
      expect(svc.recordFor('kw').health, SourceHealth.healthy);
    });
  });
}