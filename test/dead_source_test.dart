import 'package:flutter_test/flutter_test.dart';

import 'package:aiwli_music/player/playback_resolver.dart';
import 'dart:io';

import 'package:aiwli_music/core/models/quality.dart';
import 'package:aiwli_music/core/services/app_paths.dart';
import 'package:aiwli_music/sources/registry.dart';
import 'package:aiwli_music/core/storage/settings_store.dart';

/// 坏源记忆（dead-source memory）的回归测试。
///
/// 真机事故：幻音脚本返回的酷我直链（music-dl.sayqz.com，域名已注销）
/// 打不开后，日志出现「标记坏源 kw（30min 内跳过）」。
///
/// 但 kw 是**平台**，不是脚本。坏源应该记成 (脚本, 平台) 二元组：
///   · 只按脚本判死 → 幻音的酷我挂了，会连带把该脚本的网易/QQ 也判死
///   · 只按平台判死 → 幻音的酷我挂了，会连带把其他脚本的酷我也判死
///
/// 历史 bug：`_deadUntil` 是 `Map<String, DateTime>`，写入方（缓存命中 /
/// 换源路径）传平台 id、读取方 `_isDead(lx.id)` 传脚本 id —— 键混用，
/// 导致那些记录永远命中不到，成了死数据。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SettingsStore store;
  late SourceRegistry reg;
  late PlaybackResolver resolver;

  late Directory tmp;

  setUp(() {
    // SourceRegistry 构造时会读真实文件系统，用临时目录隔离。
    // 唯一目录名：并发测试时避免与其他用例（data_safety_test 等）
    // 撞到同一个 AppPaths 缓存值。
    tmp = Directory.systemTemp.createTempSync('aiwli_dead_${DateTime.now().microsecondsSinceEpoch}_');
    AppPaths.overrideSupportDirForTesting(tmp.path);
    store = SettingsStore();
    reg = SourceRegistry(store);
    resolver = PlaybackResolver(reg);
  });

  tearDown(() {
    AppPaths.overrideSupportDirForTesting(null);
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('拉黑后同一(脚本,平台)判死', () {
    resolver.reportUnplayable('幻音音源', platformId: 'kw', error: 'open failed');
    expect(resolver.debugIsDead('幻音音源', platformId: 'kw'), isTrue);
  });

  test('拉黑某脚本的 kw 不连带判死它自己的其他平台', () {
    resolver.reportUnplayable('幻音音源', platformId: 'kw', error: 'open failed');
    expect(resolver.debugIsDead('幻音音源', platformId: 'kw'), isTrue);
    // 同一脚本的网易/QQ 不受影响 —— 否则一个平台的死链会废掉整个脚本
    expect(resolver.debugIsDead('幻音音源', platformId: 'wy'), isFalse);
    expect(resolver.debugIsDead('幻音音源', platformId: 'tx'), isFalse);
  });

  test('拉黑某脚本的 kw 不连带判死其他脚本的 kw', () {
    resolver.reportUnplayable('幻音音源', platformId: 'kw', error: 'open failed');
    // 另一个脚本仍能取酷我 —— 这是最关键的：不能因为一个脚本挂了
    // 就把「酷我」这个平台整体判死 30 分钟
    expect(resolver.debugIsDead('杰翔聚合音源', platformId: 'kw'), isFalse);
  });

  test('未拉黑的源不判死', () {
    expect(resolver.debugIsDead('任意音源', platformId: 'kw'), isFalse);
  });

  test('缓存/换源路径只有平台 id 时，退化记录仍能命中', () {
    // 这条路径拿不到脚本 id，只能传平台 id（platformId 为 null）
    resolver.reportUnplayable('kw', error: 'open failed');
    // 退化键（脚本=平台, 平台=空）应能被同一平台查到
    expect(resolver.debugIsDead('kw', platformId: 'kw'), isTrue);
  });

  test('无可用源时抛业务异常（不是崩溃/空结果）', () async {
    resolver.reportUnplayable('幻音音源', platformId: 'kw', error: 'x');
    // 没有任何脚本注册 → 应抛「所有音源都无法取到」的业务异常，
    // 让上层给出可读提示，而不是返回 null 让播放器静默卡住。
    await expectLater(
      resolver.resolve(
        title: 't',
        artist: 'a',
        sourceId: 'kw',
        musicId: '1',
        quality: Quality.standard,
      ),
      throwsA(isA<Exception>()),
    );
  });
}