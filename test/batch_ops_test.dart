import 'package:flutter_test/flutter_test.dart';

import 'package:aiwli_music/core/services/playlists.dart';
import 'package:aiwli_music/core/storage/settings_store.dart';

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

PlaylistEntry e(String id) =>
    PlaylistEntry(sourceId: 'kw', musicId: id, title: 'T$id', artist: 'A');

/// 歌单内批量操作：多选删除、多选移动到其他歌单。
void main() {
  group('批量删除', () {
    test('按索引一次删多条', () async {
      final svc = PlaylistService(_MemStore());
      await svc.load();
      final p = svc.create('测试');
      svc.addEntries(p.id, [e('1'), e('2'), e('3'), e('4')]);

      svc.removeEntries(p.id, {0, 2});
      expect(svc.byId(p.id)!.entries.map((x) => x.musicId), ['2', '4']);
    });

    test('空集合不改动', () async {
      final svc = PlaylistService(_MemStore());
      await svc.load();
      final p = svc.create('测试');
      svc.addEntries(p.id, [e('1')]);
      svc.removeEntries(p.id, {});
      expect(svc.byId(p.id)!.entries.length, 1);
    });

    test('越界索引安全', () async {
      final svc = PlaylistService(_MemStore());
      await svc.load();
      final p = svc.create('测试');
      svc.addEntries(p.id, [e('1'), e('2')]);
      svc.removeEntries(p.id, {5, 9});
      expect(svc.byId(p.id)!.entries.length, 2);
    });
  });

  group('批量移动', () {
    test('移动到另一歌单，源歌单不再保留', () async {
      final svc = PlaylistService(_MemStore());
      await svc.load();
      final a = svc.create('源');
      final b = svc.create('目标');
      svc.addEntries(a.id, [e('1'), e('2'), e('3')]);

      final moved = svc.moveEntries(a.id, b.id, {0, 1});
      expect(moved, 2);
      expect(svc.byId(a.id)!.entries.map((x) => x.musicId), ['3']);
      expect(svc.byId(b.id)!.entries.map((x) => x.musicId), ['1', '2']);
    });

    test('目标已有同曲则跳过，不产生重复', () async {
      final svc = PlaylistService(_MemStore());
      await svc.load();
      final a = svc.create('源');
      final b = svc.create('目标');
      svc.addEntries(a.id, [e('1'), e('2')]);
      svc.addEntries(b.id, [e('2')]);

      final moved = svc.moveEntries(a.id, b.id, {0, 1});
      expect(moved, 1, reason: '只有 1 首是新的');
      expect(svc.byId(b.id)!.entries.map((x) => x.musicId), ['2', '1']);
      expect(svc.byId(a.id)!.entries, isEmpty, reason: '源侧两条都应移走');
    });

    test('移动到自己是空操作', () async {
      final svc = PlaylistService(_MemStore());
      await svc.load();
      final a = svc.create('源');
      svc.addEntries(a.id, [e('1')]);
      expect(svc.moveEntries(a.id, a.id, {0}), 0);
      expect(svc.byId(a.id)!.entries.length, 1);
    });

    test('跨文件夹移动', () async {
      final svc = PlaylistService(_MemStore());
      await svc.load();
      svc.ensureFolder('李泽鹏');
      svc.ensureFolder('梁登宵');
      final a = svc.create('李的列表');
      final b = svc.create('梁的列表');
      svc.setFolder(a.id, '李泽鹏');
      svc.setFolder(b.id, '梁登宵');
      svc.addEntries(a.id, [e('1'), e('2')]);

      svc.moveEntries(a.id, b.id, {0, 1});
      expect(svc.byId(b.id)!.entries.length, 2);
      expect(svc.byId(b.id)!.folder, '梁登宵');
      expect(svc.byId(a.id)!.entries, isEmpty);
    });

    test('目标不存在时不动数据', () async {
      final svc = PlaylistService(_MemStore());
      await svc.load();
      final a = svc.create('源');
      svc.addEntries(a.id, [e('1')]);
      expect(svc.moveEntries(a.id, 'not-exist', {0}), 0);
      expect(svc.byId(a.id)!.entries.length, 1);
    });
  });
}