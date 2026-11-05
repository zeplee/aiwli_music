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

/// 文件夹分组：按人/场景把歌单收纳起来（用户需求：
/// 「李泽鹏一个文件夹，梁登宵一个文件夹，里面各有自己的收藏和歌单」）。
void main() {
  group('文件夹分组', () {
    test('新建文件夹后可列出', () async {
      final svc = PlaylistService(_MemStore());
      await svc.load();
      svc.ensureFolder('李泽鹏');
      expect(svc.folders, contains('李泽鹏'));
    });

    test('重复新建不产生重复文件夹', () async {
      final svc = PlaylistService(_MemStore());
      await svc.load();
      svc.ensureFolder('李泽鹏');
      svc.ensureFolder('李泽鹏');
      expect(svc.folders.where((f) => f == '李泽鹏').length, 1);
    });

    test('歌单可移入/移出文件夹', () async {
      final svc = PlaylistService(_MemStore());
      await svc.load();
      final p = svc.create('我的收藏');
      svc.setFolder(p.id, '李泽鹏');
      expect(svc.byId(p.id)!.folder, '李泽鹏');

      svc.setFolder(p.id, null);
      expect(svc.byId(p.id)!.folder, isNull);
    });

    test('grouped 正确分组（null 键 = 顶层）', () async {
      final svc = PlaylistService(_MemStore());
      await svc.load();
      final a = svc.create('顶层歌单');
      final b = svc.create('小李的收藏');
      svc.setFolder(b.id, '李泽鹏');

      final g = svc.grouped;
      expect(g[null]!.any((x) => x.id == a.id), isTrue);
      expect(g['李泽鹏']!.any((x) => x.id == b.id), isTrue);
    });

    test('删除文件夹：其下歌单回到顶层，歌单不丢', () async {
      final svc = PlaylistService(_MemStore());
      await svc.load();
      final p = svc.create('小李的收藏');
      svc.setFolder(p.id, '李泽鹏');
      svc.removeFolder('李泽鹏');

      expect(svc.byId(p.id), isNotNull, reason: '歌单本身不能被删');
      expect(svc.byId(p.id)!.folder, isNull);
      expect(svc.folders, isNot(contains('李泽鹏')));
    });

    test('空文件夹占位不出现在分组展示里（已在 UI 过滤）', () async {
      final svc = PlaylistService(_MemStore());
      await svc.load();
      svc.ensureFolder('空文件夹');
      final g = svc.grouped;
      // 占位歌单存在，但 UI 用 name=='（空文件夹）' && entries.isEmpty 过滤
      final inFolder = g['空文件夹'] ?? const <Playlist>[];
      expect(inFolder.every((p) => p.name == '（空文件夹）'), isTrue);
    });

    test('folder 字段持久化', () async {
      final store = _MemStore();
      final a = PlaylistService(store);
      await a.load();
      final p = a.create('小李的收藏');
      a.setFolder(p.id, '李泽鹏');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final b = PlaylistService(store);
      await b.load();
      final reloaded = b.playlists.where((x) => x.id == p.id).firstOrNull;
      expect(reloaded!.folder, '李泽鹏');
    });
  });

  group('冗余收藏清理', () {
    test('重名「我的收藏」内容并入后删除（不保留副本）', () async {
      final svc = PlaylistService(_MemStore());
      await svc.load();
      // 造一个与系统同名、内容重复的歌单
      final dup = svc.create('我的收藏');
      final entry = const PlaylistEntry(
          sourceId: 'kw', musicId: '1', title: 'A', artist: 'x');
      svc.addEntries(dup.id, [entry]);
      svc.addEntries(PlaylistService.favoritesId, [entry]);

      // 模拟迁移逻辑：全部并入则删除
      final merged = await svc.mergeIntoFavorites(dup.entries);
      final allIn =
          dup.entries.every((e) => svc.isFavorite(e.sourceId, e.musicId));
      if (allIn) svc.delete(dup.id);

      expect(merged, 0, reason: '内容已存在，无需新增');
      expect(svc.byId(dup.id), isNull, reason: '重复歌单应被删除');
      expect(svc.favorites!.entries.length, 1);
    });
  });
}