import 'package:flutter_test/flutter_test.dart';

import 'package:aiwli_music/player/playback_resolver.dart';
import 'package:aiwli_music/sources/registry.dart';
import 'package:aiwli_music/core/models/quality.dart';
import 'package:aiwli_music/core/storage/settings_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('内置平台标签映射', () {
    expect(PlaybackResolver.builtinLabels['kw'], '酷我');
    expect(PlaybackResolver.builtinLabels['tx'], 'QQ音乐');
    expect(PlaybackResolver.builtinLabels['wy'], '网易云');
    expect(PlaybackResolver.builtinLabels['kg'], '酷狗');
    expect(PlaybackResolver.builtinLabels['mg'], '咪咕');
  });

  test('无可用源时抛 PlaybackResolveException 且带已试源', () async {
    final store = SettingsStore();
    final reg = SourceRegistry(store);
    final r = PlaybackResolver(reg);
    try {
      await r.resolve(
        title: '晴天',
        artist: '周杰伦',
        sourceId: 'kw', // 内置平台，但没有任何脚本 → 无法取链
        musicId: '123',
        quality: Quality.standard,
      );
      fail('应当抛异常');
    } on PlaybackResolveException catch (e) {
      expect(e.tried, contains('酷我'));
      expect(e.toString(), contains('已试'));
    }
  });
}
