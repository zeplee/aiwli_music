import 'package:flutter_test/flutter_test.dart';

import 'package:aiwli_music/core/services/app_settings.dart';
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

/// 音乐库排序偏好必须跨会话记忆（对齐参考工程的排序持久化行为）。
void main() {
  group('AppSettings 排序偏好', () {
    test('默认 歌曲名 / 升序', () async {
      final s = AppSettings(_MemStore());
      await s.load();
      expect(s.songSort, 'title');
      expect(s.songSortAscending, isTrue);
    });

    test('设置后持久化并可恢复', () async {
      final store = _MemStore();
      final a = AppSettings(store);
      await a.load();
      await a.setSongSort('artist', false);

      final b = AppSettings(store);
      await b.load();
      expect(b.songSort, 'artist');
      expect(b.songSortAscending, isFalse);
    });

    test('不覆盖已有其它设置（flush 字段完整）', () async {
      final store = _MemStore();
      final s = AppSettings(store);
      await s.load();
      await s.setQuality(s.quality);
      await s.setLyricPrefs(translation: false);
      await s.setSongSort('duration', true);

      final b = AppSettings(store);
      await b.load();
      expect(b.lyricTranslation, isFalse, reason: '排序落盘不应丢失其它偏好');
      expect(b.songSort, 'duration');
    });
  });
}