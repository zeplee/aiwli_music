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

PlaylistEntry e(String id, {String source = 'kw'}) =>
    PlaylistEntry(sourceId: source, musicId: id, title: 'T$id', artist: 'A');

/// 多用户共用：每人一个文件夹，文件夹内各有一份「我的收藏」，
/// 且歌单内不允许出现真重复（同 sourceId+musicId）。
void main() {
  group('歌单内去重', () {
    test('重复添加同一首只保留一条', () async {
      final svc = PlaylistService(_MemStore());
      await svc.load();
      final p = svc.create('测试');
      svc.addEntries(p.id, [e('1'), e('2')]);
      svc.addEntries(p.id, [e('2'), e('3')]);
      expect(svc.byId(p.id)!.entries.map((x) => x.musicId), ['1', '2', '3']);
    });

    test('跨源同 id 不算重复', () async {
      final svc = PlaylistService(_MemStore());
      await svc.load();
      final p = svc.create('测试');
      svc.addEntries(p.id, [e('1', source: 'kw'), e('1', source: 'wy')]);
      expect(svc.byId(p.id)!.entries.length, 2);
    });

    test('空 musicId 不入库', () async {
      final svc = PlaylistService(_MemStore());
      await svc.load();
      final p = svc.create('测试');
      svc.addEntries(p.id, [e('')]);
      expect(svc.byId(p.id)!.entries, isEmpty);
    });
  });

  group('每人一份收藏', () {
    test('不同文件夹各自独立收藏', () async {
      final svc = PlaylistService(_MemStore());
      await svc.load();
      svc.ensureFolder('李泽鹏');
      svc.ensureFolder('梁登宵');

      expect(svc.toggleFavorite(e('1'), folder: '李泽鹏'), isTrue);
      expect(svc.isFavorite('kw', '1', folder: '李泽鹏'), isTrue);
      expect(svc.isFavorite('kw', '1', folder: '梁登宵'), isFalse,
          reason: '李泽鹏的收藏不应污染梁登宵');
    });

    test('文件夹没有收藏时自动创建一份', () async {
      final svc = PlaylistService(_MemStore());
      await svc.load();
      svc.ensureFolder('梁登宵');
      expect(svc.favoritesIn('梁登宵'), isNull);

      svc.toggleFavorite(e('9'), folder: '梁登宵');
      final fav = svc.favoritesIn('梁登宵');
      expect(fav, isNotNull);
      expect(fav!.name, '我的收藏');
      expect(fav.folder, '梁登宵');
    });

    test('同一个人在收藏里再点一次会取消', () async {
      final svc = PlaylistService(_MemStore());
      await svc.load();
      expect(svc.toggleFavorite(e('1'), folder: '李泽鹏'), isTrue);
      expect(svc.toggleFavorite(e('1'), folder: '李泽鹏'), isFalse);
      expect(svc.isFavorite('kw', '1', folder: '李泽鹏'), isFalse);
    });

    test('isFavorite 不指定文件夹时检查所有收藏', () async {
      final svc = PlaylistService(_MemStore());
      await svc.load();
      svc.toggleFavorite(e('7'), folder: '梁登宵');
      expect(svc.isFavorite('kw', '7'), isTrue);
    });
  });

  group('人名歌单升级为文件夹', () {
    test('markAsSystem 改名 + 标记 + 归文件夹', () async {
      final svc = PlaylistService(_MemStore());
      await svc.load();
      final p = svc.create('李泽鹏');
      svc.addEntries(p.id, [e('1')]);

      svc.markAsSystem(p.id, folder: '李泽鹏');
      final up = svc.byId(p.id)!;
      expect(up.name, '我的收藏');
      expect(up.system, isTrue);
      expect(up.folder, '李泽鹏');
      expect(up.entries.length, 1, reason: '曲目不能丢');
    });

    test('升级后仍可删除（收藏也能删）', () async {
      final svc = PlaylistService(_MemStore());
      await svc.load();
      final p = svc.create('李泽鹏');
      svc.markAsSystem(p.id, folder: '李泽鹏');
      svc.delete(p.id);
      expect(svc.byId(p.id), isNull, reason: '收藏歌单应可删除');
    });

    test('两个文件夹可以各有同名的「我的收藏」', () async {
      final svc = PlaylistService(_MemStore());
      await svc.load();
      final a = svc.create('李泽鹏');
      final b = svc.create('梁登宵');
      svc.markAsSystem(a.id, folder: '李泽鹏');
      svc.markAsSystem(b.id, folder: '梁登宵');

      // 注意：load() 会自动建一个全局收藏（sys_favorites），
      // 所以「叫我的收藏的歌单」是 3 份（全局 + 两人各一份）。
      // 关键断言是「按文件夹查得到各自那份」。
      expect(svc.favoritesIn('李泽鹏')!.id, a.id);
      expect(svc.favoritesIn('梁登宵')!.id, b.id);
      expect(svc.favoritesIn('李泽鹏')!.id,
          isNot(svc.favoritesIn('梁登宵')!.id),
          reason: '两人的收藏必须是不同歌单');
    });
  });
}