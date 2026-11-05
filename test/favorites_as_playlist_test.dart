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

PlaylistEntry entry(String id, {String source = 'kw'}) => PlaylistEntry(
      sourceId: source,
      musicId: id,
      title: 'T$id',
      artist: 'A',
    );

/// 收藏与歌单合并后的核心语义：
/// 「我的收藏」= 一个不可删除、置顶的系统歌单，爱心按钮只是往它里加/删。
void main() {
  group('系统歌单「我的收藏」', () {
    test('load 后自动补建，且 system 标记正确', () async {
      final store = _MemStore();
      final svc = PlaylistService(store);
      await svc.load();
      final fav = svc.favorites;
      expect(fav, isNotNull);
      expect(fav!.id, PlaylistService.favoritesId);
      expect(fav.system, isTrue);
      expect(fav.name, '我的收藏');
    });

    test('已存在时不重复创建', () async {
      final store = _MemStore();
      final a = PlaylistService(store);
      await a.load();
      await a.load();
      expect(
          a.playlists.where((p) => p.id == PlaylistService.favoritesId).length,
          1);
    });

    test('可以删除（用户明确要求：收藏歌单也能删）', () async {
      final svc = PlaylistService(_MemStore());
      await svc.load();
      svc.delete(PlaylistService.favoritesId);
      expect(svc.favorites, isNull, reason: '收藏歌单应可删除');
    });

    test('不可改名', () async {
      final svc = PlaylistService(_MemStore());
      await svc.load();
      svc.rename(PlaylistService.favoritesId, '改了');
      expect(svc.favorites!.name, '我的收藏');
    });

    test('永远排在最前（sorted）', () async {
      final svc = PlaylistService(_MemStore());
      await svc.load();
      svc.create('普通歌单 A');
      svc.create('普通歌单 B');
      expect(svc.sorted.first.id, PlaylistService.favoritesId);
    });
  });

  group('toggleFavorite', () {
    test('首次加入返回 true，再次移除返回 false', () async {
      final svc = PlaylistService(_MemStore());
      await svc.load();
      expect(svc.toggleFavorite(entry('1')), isTrue);
      expect(svc.isFavorite('kw', '1'), isTrue);
      expect(svc.favorites!.entries.length, 1);

      expect(svc.toggleFavorite(entry('1')), isFalse);
      expect(svc.isFavorite('kw', '1'), isFalse);
      expect(svc.favorites!.entries, isEmpty);
    });

    test('跨源同 id 视为不同曲目', () async {
      final svc = PlaylistService(_MemStore());
      await svc.load();
      svc.toggleFavorite(entry('1', source: 'kw'));
      svc.toggleFavorite(entry('1', source: 'wy'));
      expect(svc.favorites!.entries.length, 2);
    });

    test('持久化后可恢复', () async {
      final store = _MemStore();
      final a = PlaylistService(store);
      await a.load();
      a.toggleFavorite(entry('9'));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final b = PlaylistService(store);
      await b.load();
      expect(b.isFavorite('kw', '9'), isTrue);
    });
  });

  group('mergeIntoFavorites（旧 favorites.json 迁移）', () {
    test('按 key 去重', () async {
      final svc = PlaylistService(_MemStore());
      await svc.load();
      svc.addEntries(PlaylistService.favoritesId, [entry('1')]);

      final added = await svc.mergeIntoFavorites([entry('1'), entry('2')]);
      expect(added, 1, reason: '1 已存在，只应新增 2');
      expect(svc.favorites!.entries.length, 2);
    });

    test('空列表返回 0', () async {
      final svc = PlaylistService(_MemStore());
      await svc.load();
      expect(await svc.mergeIntoFavorites([]), 0);
    });

    test('重复迁移幂等', () async {
      final svc = PlaylistService(_MemStore());
      await svc.load();
      await svc.mergeIntoFavorites([entry('1'), entry('2')]);
      final again = await svc.mergeIntoFavorites([entry('1'), entry('2')]);
      expect(again, 0);
      expect(svc.favorites!.entries.length, 2);
    });
  });

  group('picUrl 持久化', () {
    test('歌单条目保留封面 URL', () async {
      final store = _MemStore();
      final a = PlaylistService(store);
      await a.load();
      a.addEntries(PlaylistService.favoritesId, [
        const PlaylistEntry(
          sourceId: 'kw',
          musicId: '77',
          title: 'X',
          artist: 'Y',
          picUrl: 'https://img.example/a.jpg',
        ),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final b = PlaylistService(store);
      await b.load();
      expect(b.favorites!.entries.single.picUrl, 'https://img.example/a.jpg');
    });
  });
}