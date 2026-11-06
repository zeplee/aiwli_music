import 'package:flutter_test/flutter_test.dart';

import 'package:aiwli_music/core/services/play_history_service.dart';
import 'package:aiwli_music/core/storage/settings_store.dart';

/// 历史服务是纯逻辑（不依赖平台），用内存式假 store 直接验证去重/上限/顺序。
/// SettingsStore 是 const 类且方法不 final，这里用子类覆盖读写即可。
class _MemStore extends SettingsStore {
  _MemStore();
  final Map<String, Map<String, Object?>> data = {};

  @override
  Future<Map<String, Object?>> load(String fileName) async =>
      Map.of(data[fileName] ?? const {});

  // 生产代码改用 loadOrNull 区分「不存在」与「损坏」，
  // 测试替身必须一并覆盖，否则会走真实文件系统（需要 Flutter binding）。
  @override
  Future<Map<String, Object?>?> loadOrNull(String fileName) async =>
      Map.of(data[fileName] ?? const {});

  @override
  Future<void> flush(String fileName, Map<String, Object?> payload) async {
    data[fileName] = Map.of(payload);
  }
}

void main() {
  group('PlayHistoryService', () {
    test('同一首歌重播只保留一条并提到最前', () async {
      final store = _MemStore();
      final svc = PlayHistoryService(store);
      await svc.record(
          sourceId: 'kw', musicId: '1', title: 'A', artist: 'x');
      await svc.record(
          sourceId: 'kw', musicId: '2', title: 'B', artist: 'y');
      expect(svc.items.map((e) => e.musicId), ['2', '1']);

      // 重播 1 → 应回到最前，且不产生重复条目
      await svc.record(
          sourceId: 'kw', musicId: '1', title: 'A', artist: 'x');
      expect(svc.items.length, 2);
      expect(svc.items.map((e) => e.musicId), ['1', '2']);
    });

    test('跨源同名不同 id 不误判重复', () async {
      final store = _MemStore();
      final svc = PlayHistoryService(store);
      await svc.record(
          sourceId: 'kw', musicId: '1', title: 'A', artist: 'x');
      await svc.record(
          sourceId: 'wy', musicId: '1', title: 'A', artist: 'x');
      expect(svc.items.length, 2, reason: '源前缀不同视为不同曲目');
    });

    test('不设条数上限：超过以往 200 条也全部保留', () async {
      // 曾经的 200 条上限没有理由，且会让 WebDAV 恢复静默截断，
      // 已在合并「试听列表」(1882 首) 时移除。这里锁死"不截断"。
      final store = _MemStore();
      final svc = PlayHistoryService(store);
      for (var i = 0; i < 300; i++) {
        await svc.record(
            sourceId: 'kw', musicId: '$i', title: 'T$i', artist: 'a');
      }
      expect(svc.items.length, 300, reason: '不能有任何截断');
      // 最新的是最后写入的那条
      expect(svc.items.first.musicId, '299');
    });

    test('持久化后可重新加载', () async {
      final store = _MemStore();
      final a = PlayHistoryService(store);
      await a.record(
          sourceId: 'kw', musicId: '42', title: '歌', artist: '手');
      final b = PlayHistoryService(store);
      await b.ensureLoaded();
      expect(b.items.single.musicId, '42');
      expect(b.items.single.title, '歌');
      expect(b.items.single.picUrl, isNull);
    });

    test('空 musicId 不入历史', () async {
      final store = _MemStore();
      final svc = PlayHistoryService(store);
      await svc.record(
          sourceId: 'kw', musicId: '', title: 'X', artist: 'y');
      expect(svc.items, isEmpty);
    });

    test('remove / clear', () async {
      final store = _MemStore();
      final svc = PlayHistoryService(store);
      await svc.record(
          sourceId: 'kw', musicId: '1', title: 'A', artist: 'x');
      await svc.record(
          sourceId: 'kw', musicId: '2', title: 'B', artist: 'y');
      await svc.remove('kw', '1');
      expect(svc.items.map((e) => e.musicId), ['2']);
      await svc.clear();
      expect(svc.items, isEmpty);
    });
  });
}
