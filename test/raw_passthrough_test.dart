import 'package:flutter_test/flutter_test.dart';

import 'package:aiwli_music/sources/lx/lx_source.dart';

/// 验证真实链路：parseScriptSongs 保留原始对象，取链时能回传私有字段。
///
/// MusicFree 插件取链依赖 play_path_64 / qualitys / musicId 等私有键，
/// 若通用模型把这些丢掉，插件会返回「未返回播放地址」。
void main() {
  test('parseScriptSongs 保留 raw（插件私有字段）', () {
    // 模拟 MusicFree 插件 search() 返回的一条原始对象
    final sourceResult = [
      {
        'id': 'abc123',
        'title': '晴天',
        'artist': '周杰伦',
        'play_path_aacv224': 'https://example.com/a.m4a',
        'play_path_64': 'https://example.com/b.mp3',
        'qualitys': [
          {'type': '128k', 'size': '3 MB'},
          {'type': '320k', 'size': '9 MB'},
        ],
        'album': {'name': '叶惠美', 'id': 'alb1'},
      }
    ];

    final parsed = parseScriptSongs(sourceResult, sourceId: 'mf-test');
    expect(parsed, hasLength(1));

    final s = parsed.first;
    expect(s.musicId, 'abc123');
    expect(s.title, '晴天');
    expect(s.artist, '周杰伦');

    // 关键断言：原始对象被完整保留
    expect(s.raw, isNotNull, reason: '必须保留原始对象供插件取链');
    expect(s.raw!['play_path_aacv224'], 'https://example.com/a.m4a');
    expect(s.raw!['play_path_64'], 'https://example.com/b.mp3');
    expect(s.raw!['qualitys'], isA<List>());
    expect((s.raw!['qualitys'] as List), hasLength(2));
  });

  test('raw 逐级透传到 PlayerItem', () {
    final parsed = parseScriptSongs([
      {'id': 'x1', 'title': 'T', 'artist': 'A', 'play_path_64': 'u'}
    ], sourceId: 's');
    final s = parsed.first;
    // 模拟搜索页构造 PlayerItem
    expect(s.raw, isNotNull);
    expect(s.raw!['play_path_64'], 'u');
  });
}