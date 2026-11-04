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

/// 歌词字号与本地扫描目录（对齐栖弦 lyric_settings_sheet / directory_picker）。
void main() {
  group('歌词字号', () {
    test('默认中号（19）', () async {
      final s = AppSettings(_MemStore());
      await s.load();
      expect(s.lyricSizeLevel, 2);
      expect(s.lyricFontSize, 19);
    });

    test('四档字号映射', () async {
      final s = AppSettings(_MemStore());
      await s.load();
      await s.setLyricPrefs(sizeLevel: 1);
      expect(s.lyricFontSize, 15);
      await s.setLyricPrefs(sizeLevel: 3);
      expect(s.lyricFontSize, 23);
      await s.setLyricPrefs(sizeLevel: 4);
      expect(s.lyricFontSize, 28);
    });

    test('越界档位被夹紧', () async {
      final s = AppSettings(_MemStore());
      await s.load();
      await s.setLyricPrefs(sizeLevel: 99);
      expect(s.lyricSizeLevel, 4);
      await s.setLyricPrefs(sizeLevel: 0);
      expect(s.lyricSizeLevel, 1);
    });

    test('持久化后可恢复', () async {
      final store = _MemStore();
      final a = AppSettings(store);
      await a.load();
      await a.setLyricPrefs(sizeLevel: 4);

      final b = AppSettings(store);
      await b.load();
      expect(b.lyricSizeLevel, 4);
    });

    test('改字号不影响翻译/罗马音开关', () async {
      final s = AppSettings(_MemStore());
      await s.load();
      await s.setLyricPrefs(translation: false, roman: false);
      await s.setLyricPrefs(sizeLevel: 3);
      expect(s.lyricTranslation, isFalse);
      expect(s.lyricRoman, isFalse);
    });
  });

  group('歌词对齐', () {
    test('默认居中', () async {
      final s = AppSettings(_MemStore());
      await s.load();
      expect(s.lyricAlignStart, isFalse);
    });

    test('切左对齐并持久化', () async {
      final store = _MemStore();
      final a = AppSettings(store);
      await a.load();
      await a.setLyricPrefs(alignStart: true);

      final b = AppSettings(store);
      await b.load();
      expect(b.lyricAlignStart, isTrue);
    });

    test('改对齐不影响字号与开关', () async {
      final s = AppSettings(_MemStore());
      await s.load();
      await s.setLyricPrefs(sizeLevel: 4, translation: false);
      await s.setLyricPrefs(alignStart: true);
      expect(s.lyricSizeLevel, 4);
      expect(s.lyricTranslation, isFalse);
      expect(s.lyricAlignStart, isTrue);
    });
  });

  group('本地扫描目录', () {
    test('默认空 = 扫描全部', () async {
      final s = AppSettings(_MemStore());
      await s.load();
      expect(s.localMusicDirs, isEmpty);
    });

    test('设置后可持久化', () async {
      final store = _MemStore();
      final a = AppSettings(store);
      await a.load();
      await a.setLocalMusicDirs(['/storage/emulated/0/Music']);

      final b = AppSettings(store);
      await b.load();
      expect(b.localMusicDirs, ['/storage/emulated/0/Music']);
    });

    test('传空列表恢复扫描全部', () async {
      final s = AppSettings(_MemStore());
      await s.load();
      await s.setLocalMusicDirs(['/a', '/b']);
      await s.setLocalMusicDirs(const []);
      expect(s.localMusicDirs, isEmpty);
    });
  });
}