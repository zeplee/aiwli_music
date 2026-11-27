import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sources/builtin/catalog_sdk.dart' show CatalogHit;
import 'playlist_catalog.dart';

/// 精选歌单的取数封装。
///
/// 单独抽出来的原因和 [DailyRecommend] 一样：widget 的 initState 里直接
/// 发网络请求会让 flutter_test 冒烟测试出现"挂起定时器"失败
/// （测试环境屏蔽网络但 dio 仍会创建 timer）。
/// 提供一个可替换的入口，测试注入空列表即可，生产走真实接口。
class FeaturedPlaylists {
  const FeaturedPlaylists._();

  /// 测试可注入的取数实现。
  static Future<List<CatalogHit>> Function(String source)? overrideFetcher;

  /// 五家平台都有无需签名的公开「精选歌单浏览」接口
  /// （见 PlaylistCatalog），不再用关键词搜索冒充分类浏览。
  static const supportedSources = PlaylistCatalog.supportedSources;

  static Future<List<CatalogHit>> fetch({
    required String source,
    String categoryId = '',
  }) {
    final o = overrideFetcher;
    if (o != null) return o(source);
    final s = supportedSources.contains(source) ? source : 'wy';
    return PlaylistCatalog.featured(
      source: s,
      categoryId: categoryId,
      limit: 12,
    );
  }
}

/// 精选歌单 provider 化，便于测试整体替换。
final featuredPlaylistsProvider =
    FutureProvider.family<List<CatalogHit>, String>((ref, source) {
  return FeaturedPlaylists.fetch(source: source);
});