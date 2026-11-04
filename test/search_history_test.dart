import 'package:flutter_test/flutter_test.dart';

import 'package:aiwli_music/core/services/search_history_service.dart';
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

void main() {
  group('SearchHistoryService', () {
    test('去重（忽略大小写）且最新在前', () async {
      final svc = SearchHistoryService(_MemStore());
      await svc.add('周杰伦');
      await svc.add('陈奕迅');
      expect(svc.items, ['陈奕迅', '周杰伦']);
      await svc.add('周杰伦');
      expect(svc.items, ['周杰伦', '陈奕迅']);
    });

    test('大小写视为同一词', () async {
      final svc = SearchHistoryService(_MemStore());
      await svc.add('Taylor');
      await svc.add('taylor');
      expect(svc.items.length, 1);
      expect(svc.items.single, 'taylor');
    });

    test('trim 后为空不入库', () async {
      final svc = SearchHistoryService(_MemStore());
      await svc.add('   ');
      expect(svc.items, isEmpty);
    });

    test('上限丢弃最旧', () async {
      final svc = SearchHistoryService(_MemStore());
      for (var i = 0; i < SearchHistoryService.maxItems + 3; i++) {
        await svc.add('k$i');
      }
      expect(svc.items.length, SearchHistoryService.maxItems);
      expect(svc.items.first, 'k${SearchHistoryService.maxItems + 2}');
    });

    test('remove / clear / 持久化', () async {
      final store = _MemStore();
      final svc = SearchHistoryService(store);
      await svc.add('a');
      await svc.add('b');
      await svc.remove('b');
      expect(svc.items, ['a']);
      final b = SearchHistoryService(store);
      await b.ensureLoaded();
      expect(b.items, ['a']);
      await b.clear();
      expect(b.items, isEmpty);
    });
  });
}
