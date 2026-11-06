import 'package:flutter_test/flutter_test.dart';
import 'package:aiwli_music/sources/runtime/runtime_host.dart';

/// MusicFree 插件 → 标准平台的映射。
///
/// 问题：MF 插件的 id 是 `mf-酷我-念心音源`，宿主只把它当平台标识，
/// 导致内置榜单（sourceId=kw）借不到它取链。
/// 但 `getMediaSource(musicItem, quality)` 不吃平台参数，
/// 插件本身就是单一平台实现——所以补一个标准平台 key 是安全的。
void main() {
  test('按 ID 关键词识别（真机实际的 14 个插件）', () {
    final cases = {
      'mf-酷我-念心音源': 'kw',
      'mf-网易-念心音源': 'wy',
      'mf-溯音网易': 'wy',
      'mf-qq-念心音源': 'tx',
      'mf-弥音qq-128k': 'tx',
      'mf-酷狗-念心音源': 'kg',
    };
    for (final e in cases.entries) {
      expect(guessMusicFreePlatform(e.key, ''), e.value,
          reason: '${e.key} 应识别为 ${e.value}');
    }
  });

  test('无平台的插件返回 null（不能乱映射）', () {
    for (final id in [
      'mf-开心汽水',
      'mf-猫耳fm',
      'mf-5sing',
      'mf-好听轻音乐',
      'mf-碳酸氢钠',
      'mf-哔哩哔哩-cookie',
      'mf-bilibili',
      'mf-gd音乐台',
    ]) {
      expect(guessMusicFreePlatform(id, ''), isNull,
          reason: '$id 不是五平台之一，不该被映射');
    }
  });

  test('域名优先于名称：源码含 kuwo.cn 即判为 kw', () {
    // 名称不含"酷我"，但源码请求 kuw o 域名
    expect(guessMusicFreePlatform('mf-某聚合源', 'https://www.kuwo.cn/api'), 'kw');
    expect(guessMusicFreePlatform('mf-某聚合源', 'https://music.163.com/api'), 'wy');
    expect(guessMusicFreePlatform('mf-某聚合源', 'https://u.y.qq.com/cgi'), 'tx');
    expect(guessMusicFreePlatform('mf-某聚合源', 'https://m.kugou.com/x'), 'kg');
    expect(guessMusicFreePlatform('mf-某聚合源', 'https://app.c.nf.migu.cn/x'), 'mg');
  });

  test('QQ 与网易不互相误判', () {
    final qq = guessMusicFreePlatform('mf-qq-念心音源', '');
    final wy = guessMusicFreePlatform('mf-网易-念心音源', '');
    expect(qq, 'tx');
    expect(wy, 'wy');
    expect(qq, isNot(wy));
  });
}
