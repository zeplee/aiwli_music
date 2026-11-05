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

/// 收藏歌单的删除行为（用户反馈："外层我的收藏歌单没法删除"）。
///
/// 三条必须成立：
///   1. 收藏歌单**可以删**
///   2. 删掉后**不会**在下次启动自动重建（否则"删了又冒出来"）
///   3. 再次点收藏时仍能**新建**一份空收藏
void main() {
  group('收藏歌单可删除', () {
    test('delete 真的删掉收藏歌单', () async {
      final svc = PlaylistService(_MemStore());
      await svc.load();
      expect(svc.favorites, isNotNull);

      svc.delete(PlaylistService.favoritesId);
      expect(svc.favorites, isNull, reason: '收藏歌单必须能被删除');
    });

    test('删除后标记 favoritesDeleted', () async {
      final svc = PlaylistService(_MemStore());
      await svc.load();
      expect(svc.favoritesDeleted, isFalse);

      svc.delete(PlaylistService.favoritesId);
      expect(svc.favoritesDeleted, isTrue);
    });

    test('删除后重新 load 不会复活（关键）', () async {
      final store = _MemStore();
      final a = PlaylistService(store);
      await a.load();
      a.delete(PlaylistService.favoritesId);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final b = PlaylistService(store);
      await b.load();
      expect(b.favorites, isNull,
          reason: '用户主动删掉的收藏不能在下次启动冒出来');
    });

    test('再次收藏会新建空收藏（并清除删除标记）', () async {
      final svc = PlaylistService(_MemStore());
      await svc.load();
      svc.delete(PlaylistService.favoritesId);
      expect(svc.favorites, isNull);

      svc.toggleFavorite(e('1'));
      expect(svc.favorites, isNotNull, reason: '点收藏应自动建一份');
      expect(svc.favorites!.entries.length, 1);
      expect(svc.favoritesDeleted, isFalse, reason: '重建后标记应清除');
    });

    test('restoreFavorites 可手动恢复', () async {
      final svc = PlaylistService(_MemStore());
      await svc.load();
      svc.delete(PlaylistService.favoritesId);

      final restored = svc.restoreFavorites();
      expect(restored.name, '我的收藏');
      expect(svc.favorites, isNotNull);
    });

    test('删普通歌单不影响删除标记', () async {
      final svc = PlaylistService(_MemStore());
      await svc.load();
      final p = svc.create('普通歌单');
      svc.delete(p.id);
      expect(svc.favoritesDeleted, isFalse);
      expect(svc.favorites, isNotNull);
    });

    test('删除文件夹里的收藏也算删除收藏', () async {
      final store = _MemStore();
      final svc = PlaylistService(store);
      await svc.load();
      // 造一个文件夹收藏
      final f = svc.ensureFavoritesIn('李泽鹏');
      svc.delete(f.id);
      expect(svc.favoritesIn('李泽鹏'), isNull);
      // 顶层收藏还在，所以不该置位 deleted 标记
      expect(svc.favorites, isNotNull);
    });
  });
}