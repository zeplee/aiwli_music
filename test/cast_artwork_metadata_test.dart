import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:aiwli_music/player/models.dart';
import 'package:aiwli_music/player/player_core.dart';
import 'package:aiwli_music/player/audio_engine.dart';
import 'package:aiwli_music/player/media_session_cast.dart';

class _Cast implements MediaSessionCast {
  final metas = <TrackMetadata>[];
  @override
  Future<void> init() async {}
  @override
  bool get isReady => true;
  @override
  void updateNowPlaying(TrackMetadata meta) => metas.add(meta);
  @override
  void updatePlayback({
    required bool playing,
    required Duration position,
    Duration? duration,
  }) {}
  @override
  void updateQueue(List<TrackMetadata> queue, {int? currentIndex}) {}
  @override
  Stream<CastCommand> get commands => const Stream.empty();
}

void main() {
  test('PlayerItem.metadata 必须带上 album 与本地封面字节', () {
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    final item = PlayerItem(
      title: '本地曲',
      artist: '歌手',
      album: '专辑',
      sourceId: 'local',
      musicId: '/a.mp3',
      resolvedUrl: 'file:///a.mp3',
      artBytes: bytes,
    );

    final m = item.metadata;
    expect(m.album, '专辑', reason: '通知栏副标题需要专辑');
    expect(m.artBytes, same(bytes), reason: '本地封面必须传给 cast 落盘');
    expect(m.artUri, isNull);
  });

  test('去重 key 区分「同曲无封面」与「同曲带本地封面」', () async {
    final cast = _Cast();
    final core = PlayerCore(engine: StubEngine(), cast: cast);
    await Future<void>.delayed(Duration.zero);

    await core.setQueue([
      PlayerItem(
        title: '本地曲',
        artist: '歌手',
        sourceId: 'local',
        musicId: '/a.mp3',
        resolvedUrl: 'file:///a.mp3',
      ),
    ]);
    await Future<void>.delayed(Duration.zero);
    final first = cast.metas.length;
    expect(first, greaterThan(0));

    // 同一首歌后来拿到了封面字节：必须重推，否则通知栏一直是黑的。
    await core.setQueue([
      PlayerItem(
        title: '本地曲',
        artist: '歌手',
        sourceId: 'local',
        musicId: '/a.mp3',
        resolvedUrl: 'file:///a.mp3',
        artBytes: Uint8List.fromList([9, 8, 7]),
      ),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(cast.metas.length, greaterThan(first));

    await core.dispose();
  });
}
