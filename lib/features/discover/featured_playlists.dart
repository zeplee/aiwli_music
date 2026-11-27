import 'package:aiwli_music/sources/builtin/catalog_sdk.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  /// CatalogSdk 实测只有网易和酷我提供可用的歌单分类接口，
  /// 另外三家（tx/kg/mg）的 playlist 搜索恒为空，所以不列出来误导用户。
  static const supportedSources = <String>['wy', 'kw'];

  static Future<List<CatalogHit>> fetch({required String source}) {
    final o = overrideFetcher;
    if (o != null) return o(source);
    return CatalogSdk.search(
      kind: SearchKind.playlist,
      keyword: '热门',
      source: supportedSources.contains(source) ? source : 'wy',
      limit: 12,
    );
  }
}

/// 精选歌单 provider 化，便于测试整体替换。
final featuredPlaylistsProvider =
    FutureProvider.family<List<CatalogHit>, String>((ref, source) {
  return FeaturedPlaylists.fetch(source: source);
});