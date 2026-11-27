import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:aiwli_music/core/models/quality.dart';
import 'package:aiwli_music/core/services/app_paths.dart';
import 'package:aiwli_music/core/storage/settings_store.dart';
import 'package:aiwli_music/player/playback_resolver.dart';
import 'package:aiwli_music/player/url_resolve_cache.dart';
import 'package:aiwli_music/sources/registry.dart';

/// A4 取链缓存回归：缓存命中必须保留真实胜出脚本 id，且 key 必须带 quality。
///
/// 真机事故：缓存命中把 winnerId 退化成曲目平台名（kw），播放器打不开
/// 直链后按 (kw, kw) 拉黑，而取链筛选查的是 (脚本id, kw) —— 键不匹配，
/// 加上缓存命中绕过筛选，10 分钟 TTL 内反复踩同一条死链。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync(
        'aiwli_cache_${DateTime.now().microsecondsSinceEpoch}_');
    AppPaths.overrideSupportDirForTesting(tmp.path);
  });

  tearDown(() {
    AppPaths.overrideSupportDirForTesting(null);
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  // —— 纯 Dart 缓存真类：4 个必测语义 ——
  group('UrlResolveCache', () {
    test('命中返回真实 winnerId / platform / sourceLabel', () {
      final cache = UrlResolveCache();
      cache.put(
        sourceId: 'kw',
        musicId: 'song-1',
        quality: Quality.lossless,
        url: 'https://cdn/x.flac',
        winnerId: '幻音音源',
        winnerPlatform: 'kw',
        sourceLabel: '幻音音源',
      );

      final hit = cache.get('kw', 'song-1', Quality.lossless);
      expect(hit, isNotNull);
      expect(hit!.url, 'https://cdn/x.flac');
      expect(hit.winnerId, '幻音音源', reason: '不能退化成 kw');
      expect(hit.winnerPlatform, 'kw');
      expect(hit.sourceLabel, '幻音音源');
    });

    test('过期失效并从缓存清理', () {
      var now = DateTime(2026, 1, 1, 12);
      final cache = UrlResolveCache(now: () => now);
      cache.put(
        sourceId: 'kw',
        musicId: 'song-1',
        quality: Quality.standard,
        url: 'https://cdn/x.mp3',
        winnerId: '幻音音源',
        winnerPlatform: 'kw',
        sourceLabel: '酷我',
      );
      expect(cache.get('kw', 'song-1', Quality.standard), isNotNull);

      now = now.add(const Duration(minutes: 10)); // 正好到期
      expect(cache.get('kw', 'song-1', Quality.standard), isNull);
      expect(cache.length, 0, reason: '过期条目应被删除');
    });

    test('不同 quality 不串（含 code 相同的 high/superQuality）', () {
      final cache = UrlResolveCache();
      cache.put(
        sourceId: 'kw',
        musicId: 'song-1',
        quality: Quality.standard,
        url: 'https://cdn/128k.mp3',
        winnerId: '源A',
        winnerPlatform: 'kw',
        sourceLabel: '酷我',
      );
      cache.put(
        sourceId: 'kw',
        musicId: 'song-1',
        quality: Quality.high,
        url: 'https://cdn/320k.mp3',
        winnerId: '源B',
        winnerPlatform: 'kw',
        sourceLabel: '酷我',
      );

      expect(cache.get('kw', 'song-1', Quality.standard)!.url,
          'https://cdn/128k.mp3');
      expect(cache.get('kw', 'song-1', Quality.high)!.url,
          'https://cdn/320k.mp3');
      expect(cache.get('kw', 'song-1', Quality.lossless), isNull);
      expect(cache.get('kw', 'song-1', Quality.superQuality), isNull,
          reason: 'high 与 superQuality 的 code 都是 320k，仍须分开');
      expect(UrlResolveCache.key('kw', 'song-1', Quality.high),
          isNot(UrlResolveCache.key('kw', 'song-1', Quality.superQuality)));
    });

    test('invalidateCache 清掉该曲全部 quality 变体', () {
      final cache = UrlResolveCache();
      for (final q in Quality.values) {
        cache.put(
          sourceId: 'kw',
          musicId: 'song-1',
          quality: q,
          url: 'https://cdn/${q.name}.mp3',
          winnerId: '源A',
          winnerPlatform: 'kw',
          sourceLabel: '酷我',
        );
      }
      cache.put(
        sourceId: 'kw',
        musicId: 'song-2',
        quality: Quality.standard,
        url: 'https://cdn/other.mp3',
        winnerId: '源A',
        winnerPlatform: 'kw',
        sourceLabel: '酷我',
      );
      expect(cache.length, Quality.values.length + 1);

      cache.invalidate('kw', 'song-1');
      for (final q in Quality.values) {
        expect(cache.get('kw', 'song-1', q), isNull, reason: '${q.name} 应被清掉');
      }
      expect(cache.get('kw', 'song-2', Quality.standard), isNotNull,
          reason: '别的曲目不受影响');
    });

    test('invalidateAll 按真实胜出源 id 清理（key 第一段是平台名）', () {
      final cache = UrlResolveCache();
      cache.put(
        sourceId: 'kw',
        musicId: 'song-1',
        quality: Quality.standard,
        url: 'https://cdn/a.mp3',
        winnerId: '幻音音源',
        winnerPlatform: 'kw',
        sourceLabel: '酷我',
      );
      cache.put(
        sourceId: 'wy',
        musicId: 'song-2',
        quality: Quality.lossless,
        url: 'https://cdn/b.flac',
        winnerId: '杰翔聚合音源',
        winnerPlatform: 'wy',
        sourceLabel: '网易云',
      );

      cache.invalidateAll('幻音音源'); // app_providers 传的就是 winnerId
      expect(cache.get('kw', 'song-1', Quality.standard), isNull);
      expect(cache.get('wy', 'song-2', Quality.lossless), isNotNull);
    });
  });

  // —— 真 PlaybackResolver 委托验证：缓存命中走真实实现 ——
  group('PlaybackResolver 缓存命中', () {
    test('注入缓存后 resolve 命中并保留真实 winnerId（不触发取链）', () async {
      final cache = UrlResolveCache();
      cache.put(
        sourceId: 'kw',
        musicId: 'song-1',
        quality: Quality.lossless,
        url: 'https://cdn/dead.flac',
        winnerId: '幻音音源',
        winnerPlatform: 'kw',
        sourceLabel: '幻音音源',
      );
      // 没有任何脚本注册：若没命中缓存，这里会走取链并抛异常。
      final r = PlaybackResolver(SourceRegistry(SettingsStore()), cache: cache);

      final got = await r.resolve(
        title: '晴天',
        artist: '周杰伦',
        sourceId: 'kw',
        musicId: 'song-1',
        quality: Quality.lossless,
      );

      expect(got.url, 'https://cdn/dead.flac');
      expect(got.winnerId, '幻音音源');
      expect(got.winnerPlatform, 'kw');
      expect(got.sourceLabel, '幻音音源');

      // 播放器按 (winnerId, platform) 拉黑后，取链筛选应能查到该键。
      r.reportUnplayable(got.winnerId,
          platformId: got.winnerPlatform, error: 'open failed');
      expect(r.debugIsDead('幻音音源', platformId: 'kw'), isTrue);
    });

    test('切音质后不命中旧档位 URL', () async {
      final cache = UrlResolveCache();
      cache.put(
        sourceId: 'kw',
        musicId: 'song-1',
        quality: Quality.standard,
        url: 'https://cdn/128k.mp3',
        winnerId: '源A',
        winnerPlatform: 'kw',
        sourceLabel: '酷我',
      );
      final r = PlaybackResolver(SourceRegistry(SettingsStore()), cache: cache);

      expect(
          (await r.resolve(
            title: '晴天',
            artist: '周杰伦',
            sourceId: 'kw',
            musicId: 'song-1',
            quality: Quality.standard,
          ))
              .url,
          'https://cdn/128k.mp3');
      await expectLater(
        r.resolve(
          title: '晴天',
          artist: '周杰伦',
          sourceId: 'kw',
          musicId: 'song-1',
          quality: Quality.lossless,
        ),
        throwsA(isA<PlaybackResolveException>()),
        reason: '无损档位应重新取链，无脚本时必须抛业务异常',
      );
    });

    test('invalidateCache 清掉该曲全部 quality 变体', () async {
      final cache = UrlResolveCache();
      for (final q in Quality.values) {
        cache.put(
          sourceId: 'kw',
          musicId: 'song-1',
          quality: q,
          url: 'https://cdn/${q.name}.mp3',
          winnerId: '源A',
          winnerPlatform: 'kw',
          sourceLabel: '酷我',
        );
      }
      final r = PlaybackResolver(SourceRegistry(SettingsStore()), cache: cache);
      r.invalidateCache('kw', 'song-1');
      for (final q in Quality.values) {
        expect(cache.get('kw', 'song-1', q), isNull, reason: '${q.name} 应被清掉');
        await expectLater(
          r.resolve(
            title: '晴天',
            artist: '周杰伦',
            sourceId: 'kw',
            musicId: 'song-1',
            quality: q,
          ),
          throwsA(isA<PlaybackResolveException>()),
          reason: '${q.name} 应重新取链',
        );
      }
      expect(cache.length, 0);
    });
  });
}
