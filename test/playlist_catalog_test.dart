import 'package:flutter_test/flutter_test.dart';
import 'package:aiwli_music/features/discover/platform_dropdown.dart';
import 'package:aiwli_music/features/discover/playlist_catalog.dart';
import 'package:aiwli_music/features/discover/featured_playlists.dart';

void main() {
  group('平台覆盖', () {
    test('精选歌单支持 5 家平台（不再只有网易/酷我）', () {
      expect(FeaturedPlaylists.supportedSources,
          ['wy', 'kw', 'tx', 'kg', 'mg']);
      expect(PlaylistCatalog.supportedSources,
          FeaturedPlaylists.supportedSources);
    });

    test('分类表：每家至少 1 个，3 家有多分类', () {
      for (final s in PlaylistCatalog.supportedSources) {
        final cats = PlaylistCatalog.categories[s];
        expect(cats, isNotNull, reason: '$s 应有分类');
        expect(cats!.isNotEmpty, isTrue);
        expect(cats.first.id, isNotEmpty);
      }
      expect(PlaylistCatalog.categories['kg']!.length, 5);
      expect(PlaylistCatalog.categories['tx']!.length, 3);
      expect(PlaylistCatalog.categories['kw']!.length, 2);
      expect(PlaylistCatalog.categories['wy']!.length, 1);
      expect(PlaylistCatalog.categories['mg']!.length, 1);
    });
  });

  group('PlatformDropdown 映射', () {
    test('5 家平台都有中文名与彩色图标', () {
      for (final s in PlaylistCatalog.supportedSources) {
        expect(PlatformLabels.of(s), isNot(s), reason: '$s 应有中文名');
        final badge = PlatformLabels.badge(s);
        expect(badge.glyph, isNotEmpty);
      }
      expect(PlatformLabels.of('wy'), '网易云音乐');
      expect(PlatformLabels.of('kg'), '酷狗音乐');
      expect(PlatformLabels.order, ['wy', 'tx', 'kw', 'kg', 'mg']);
    });
  });
}
