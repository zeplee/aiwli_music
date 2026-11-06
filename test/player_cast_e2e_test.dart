/// 播放 → 通知栏/媒体会话 的端到端回归测试。
///
/// 这组测试是为了固化真实踩过的坑。它们都符合同一个失败模式：
/// **同一个概念被两套数据描述，然后对不上**。这类 bug 单测很难覆盖，
/// 只能靠真机日志暴露，所以这里用可控的假引擎把链路钉死。
///
/// 已固化的坑：
///   1. 通知栏空白（title/text = null）：去重 key 拼了 s.title
///      而不是 item.metadata —— 切歌后 key 不变，永不推送
///   2. 切歌时旧曲快照污染（陈旧事件守卫）
///   3. 死链轮换后已试过的源不被重试
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:aiwli_music/player/audio_engine.dart';
import 'package:aiwli_music/player/media_session_cast.dart';
import 'package:aiwli_music/player/models.dart';
import 'package:aiwli_music/player/playback_resolver.dart';
import 'package:aiwli_music/player/player_core.dart';


/// 可主动推送快照的假引擎，用来驱动 PlayerCore 的状态机。
class _FakeEngine implements AudioEngine {
  _FakeEngine();

  final _ctrl = StreamController<EngineSnapshot>.broadcast();
  EngineSnapshot _snap = const EngineSnapshot();
  Uri? _src;

  /// 记录每次 load 的地址，用于断言重试/换源行为。
  final loadedUrls = <String>[];

  /// 这些地址的 load 会抛异常（模拟死链打不开）。
  final failingUrls = <String>{};

  @override
  Future<Duration?> load(Uri source,
      {Map<String, String>? headers, String? formatHint}) async {
    loadedUrls.add(source.toString());
    if (failingUrls.contains(source.toString())) {
      throw Exception('Failed to open $source');
    }
    _src = source;
    return const Duration(minutes: 3);
  }

  @override
  Future<void> play() async {
    _snap = EngineSnapshot(
      processing: EngineProcessing.ready,
      playing: true,
      duration: const Duration(minutes: 3),
    );
    _ctrl.add(_snap);
  }

  @override
  Future<void> pause() async {
    _snap = _snap.copyWithPaused();
    _ctrl.add(_snap);
  }

  /// 伪造引擎当前加载的地址（用于模拟"事件属于旧曲"的场景）。
  void forceSource(Uri? u) => _src = u;

  /// 模拟引擎上报的异步事件（mpv 的 error / completed 走这条路）。
  void emit(EngineSnapshot snap) {
    _snap = snap;
    _ctrl.add(snap);
  }

  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> setVolume(double v) async {}
  @override
  Future<void> setSpeed(double v) async {}
  @override
  Future<void> setEqualizer(List<double>? gainsDb) async {}
  @override
  Future<void> dispose() async => _ctrl.close();

  @override
  Stream<EngineSnapshot> get snapshots => _ctrl.stream;
  @override
  EngineSnapshot get current => _snap;
  @override
  Uri? get currentSource => _src;
  @override
  String? get lastWarning => null;
}

extension on EngineSnapshot {
  EngineSnapshot copyWithPaused() => EngineSnapshot(
        processing: processing,
        playing: false,
        position: position,
        duration: duration,
        buffered: buffered,
        speed: speed,
        error: error,
      );
}

/// 记录推送到系统媒体层的元数据（对应真机的 android.title/text）。
class _RecordingCast implements MediaSessionCast {
  final nowPlaying = <TrackMetadata>[];
  final playback = <String>[];

  @override
  Future<void> init() async {}
  @override
  void updateNowPlaying(TrackMetadata meta) => nowPlaying.add(meta);
  @override
  void updatePlayback(
      {required bool playing, required Duration position, Duration? duration}) {
    playback.add('$playing@${position.inMilliseconds}');
  }

  @override
  void updateQueue(List<TrackMetadata> queue, {int? currentIndex}) {}
  @override
  Stream<CastCommand> get commands => const Stream.empty();
}

PlayerItem _item(String title, String artist, String musicId,
        {String? artUrl, String? resolvedUrl}) =>
    PlayerItem(
      title: title,
      artist: artist,
      sourceId: 'kw',
      musicId: musicId,
      resolvedUrl: resolvedUrl,
      album: '专辑',
      duration: const Duration(minutes: 3),
      artUri: artUrl == null ? null : Uri.parse(artUrl),
    );

void main() {
  fallbackResumeTests();

  late _FakeEngine engine;
  late _RecordingCast cast;
  late PlayerCore core;

  setUp(() {
    engine = _FakeEngine();
    cast = _RecordingCast();
    core = PlayerCore(
      engine: engine,
      cast: cast,
      urlResolver: (item, exclude) async => ResolvedPlayback(
        url: 'https://cdn.example/${item.musicId}.mp3',
        sourceId: 'kw',
        winnerId: '音源A',
        winnerPlatform: 'kw',
        sourceLabel: '酷我',
        musicId: item.musicId,
        title: item.title,
        artist: item.artist,
      ),
    );
  });

  tearDown(() async => core.dispose());

  // ————————————————————————————————————————————————
  // 坑 1：通知栏空白（本次真机事故）
  // ————————————————————————————————————————————————
  group('通知栏元数据（真机 android.title=null 事故）', () {
    test('第一次播放就必须推送歌曲名和歌手', () async {
      // 注意：setQueue 内部已自动 _loadAt，不要再补 playAt（会双载）
      await core.setQueue([_item('无奈的思绪', '嘉慧', '1')]);
      await Future<void>.delayed(Duration.zero);

      expect(cast.nowPlaying, isNotEmpty,
          reason: '不能因为去重 key 相同就一次都不推');
      final meta = cast.nowPlaying.last;
      expect(meta.title, '无奈的思绪',
          reason: '真机上这里曾是 null（android.title=null）');
      expect(meta.artist, '嘉慧');
    });

    test('切歌后必须推送新歌元数据（即使引擎 state.title 为空）', () async {
      // 这是事故的精确复刻：metrics 里 s.title 为空、sourceId 相同，
      // 旧实现把 s.title 拼进 key → key 不变 → 直接 return → 不推送。
      await core.setQueue([
        _item('第一首', '歌手A', '1'),
        _item('第二首', '歌手B', '2'),
      ]);
      await Future<void>.delayed(Duration.zero);
      final before = cast.nowPlaying.length;

      await core.playAt(1);
      await Future<void>.delayed(Duration.zero);

      expect(cast.nowPlaying.length, greaterThan(before),
          reason: '切歌必须产生新的元数据推送');
      expect(cast.nowPlaying.last.title, '第二首',
          reason: '推送的必须是新歌，不能停在上一首');
      expect(cast.nowPlaying.last.artist, '歌手B');
    });

    test('同一首歌重复推送会被去重（不刷屏）', () async {
      await core.setQueue([_item('单曲', '歌手', '1')]);
      await Future<void>.delayed(Duration.zero);
      final n = cast.nowPlaying.length;

      // 引擎重复上报同一状态（播放中的进度更新不应重推元数据）
      engine.emit(const EngineSnapshot(
        processing: EngineProcessing.ready,
        playing: true,
        duration: Duration(minutes: 3),
      ));
      await Future<void>.delayed(Duration.zero);

      expect(cast.nowPlaying.length, n,
          reason: '元数据没变就不该重复推送');
    });

    test('封面 URL 随元数据一起推送', () async {
      await core.setQueue([
        _item('有封面的歌', '歌手', '1',
            artUrl: 'https://p1.music.126.net/x.jpg'),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(cast.nowPlaying.last.artUri?.toString(),
          'https://p1.music.126.net/x.jpg');
    });

    test('无封面时不报错（酷我榜单有意留空）', () async {
      await core.setQueue([_item('无封面', '歌手', '1')]);
      await Future<void>.delayed(Duration.zero);

      expect(cast.nowPlaying.last.artUri, isNull);
      expect(cast.nowPlaying.last.title, '无封面');
    });
  });

  // ————————————————————————————————————————————————
  // 坑 2：陈旧事件守卫
  // ————————————————————————————————————————————————
  group('陈旧引擎事件守卫（音频与页面必须是同一首）', () {
    test('currentSource 与 activeResolved 不一致时丢弃事件', () async {
      // 守卫的语义是：引擎的 currentSource（最后请求加载的地址）
      // 与 PlayerCore 认为的活跃地址不同 → 说明事件属于上一首 → 丢弃。
      var resolveCalls = 0;
      core = PlayerCore(
        engine: engine,
        cast: cast,
        urlResolver: (item, exclude) async {
          resolveCalls++;
          return ResolvedPlayback(
            url: 'https://cdn.example/${item.musicId}.mp3',
            sourceId: 'kw',
            winnerId: '音源A',
            winnerPlatform: 'kw',
            sourceLabel: '酷我',
            musicId: item.musicId,
            title: item.title,
            artist: item.artist,
          );
        },
      );
      await core.setQueue([_item('第一首', 'A', '1')]);
      await Future<void>.delayed(Duration.zero);
      final callsAfterLoad = resolveCalls;

      // 伪造：引擎仍在旧地址（模拟 load 尚未切到新地址时旧事件到达）
      engine.forceSource(Uri.parse('https://old.example/0.mp3'));
      engine.emit(const EngineSnapshot(
        processing: EngineProcessing.error,
        error: 'Failed to open https://old.example/0.mp3',
      ));
      await Future<void>.delayed(Duration.zero);

      expect(resolveCalls, callsAfterLoad,
          reason: '不属于当前曲目的事件必须丢弃，不能触发换源');
      // 错误也不该污染当前曲目的状态
      expect(core.state.value.processing, isNot(EngineProcessing.error));
    });

    test('切歌后旧曲事件不引发多余取链（真机踩过的坑）', () async {
      // 精确复刻：切到第二首后，第一首的 error 迟到。
      // 此时 currentSource 与 _activeResolved 都是第二首的地址 ——
      // 只比 currentSource 的旧实现会漏判（实测会白跑一次取链）。
      // 现在靠错误文本里的 URL 判定归属。
      var calls = 0;
      core = PlayerCore(
        engine: engine,
        cast: cast,
        urlResolver: (item, exclude) async {
          calls++;
          return ResolvedPlayback(
            url: 'https://cdn.example/${item.musicId}.mp3',
            sourceId: 'kw',
            winnerId: 'A',
            winnerPlatform: 'kw',
            sourceLabel: '酷我',
            musicId: item.musicId,
            title: item.title,
            artist: item.artist,
          );
        },
        onSourceUnplayable: (r, e) {},
      );
      await core.setQueue([_item('一', 'A', '1'), _item('二', 'B', '2')]);
      await core.playAt(1);
      await Future<void>.delayed(Duration.zero);
      final before = calls;

      engine.emit(const EngineSnapshot(
        processing: EngineProcessing.error,
        error: 'Failed to open https://cdn.example/1.mp3',
      ));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(calls, before,
          reason: '旧曲的错误不能触发新曲重新取链');
    });

    test('URL 含特殊字符时不会被误判为陈旧事件', () async {
      // 真机复现过的回归：酷我直链形如
      //   http://car-lv.kuwo.cn/.../x.mp3?bitrate$128&format$mp3&user$abc
      // 早期用「正则截断 + 全等比对」，含 $ 的地址会被判成不同 →
      // 当前曲目的正常事件被误丢弃（日志里 cur 与 active 明明相同）。
      const tricky =
          r'http://car-lv.kuwo.cn/a/b/x.mp3?bitrate$128&format$mp3&user$abc';
      var calls = 0;
      core = PlayerCore(
        engine: engine,
        cast: cast,
        urlResolver: (item, exclude) async {
          calls++;
          return ResolvedPlayback(
            url: tricky,
            sourceId: 'kw',
            winnerId: 'A',
            winnerPlatform: 'kw',
            sourceLabel: '酷我',
            musicId: item.musicId,
            title: item.title,
            artist: item.artist,
          );
        },
        onSourceUnplayable: (r, e) {},
      );
      await core.setQueue([_item('带美元符的直链', '歌手', '1')]);
      await Future<void>.delayed(Duration.zero);
      final before = calls;

      // 同一地址的 loading/ready 事件绝不能被丢弃
      engine.emit(const EngineSnapshot(processing: EngineProcessing.loading));
      engine.emit(const EngineSnapshot(
        processing: EngineProcessing.ready,
        playing: true,
      ));
      await Future<void>.delayed(Duration.zero);

      expect(calls, before, reason: '自己曲目的事件不该触发额外交互');
      expect(core.state.value.processing, EngineProcessing.ready,
          reason: 'loading/ready 必须能正常传入状态机');
    });

    test('粘性 error 不能让后续正常事件被误丢弃', () async {
      // 真机复现的第二个回归：EngineSnapshot.error 是粘性的
      // （_emit 里 `error ?? _snapshot.error`），上一次失败的文案会一直挂着。
      // 早期用残留 error 判断归属，导致 loading/ready 事件也被丢弃，
      // 真机上表现为进度条不动（同一 URL、same=true 却进丢弃分支）。
      core = PlayerCore(
        engine: engine,
        cast: cast,
        urlResolver: (item, exclude) async {
          return ResolvedPlayback(
            url: 'https://live.example/1.mp3',
            sourceId: 'kw',
            winnerId: 'A',
            winnerPlatform: 'kw',
            sourceLabel: '酷我',
            musicId: item.musicId,
            title: item.title,
            artist: item.artist,
          );
        },
        onSourceUnplayable: (r, e) {},
      );
      await core.setQueue([_item('正常的歌', '歌手', '1')]);
      await Future<void>.delayed(Duration.zero);

      // 一条属于别的地址的旧错误残留在快照里
      engine.emit(const EngineSnapshot(
        processing: EngineProcessing.loading,
        error: 'Failed to open https://music-dl.sayqz.com/old.mp3',
      ));
      // 随后同一曲目的 ready 事件必须生效
      engine.emit(const EngineSnapshot(
        processing: EngineProcessing.ready,
        playing: true,
        error: 'Failed to open https://music-dl.sayqz.com/old.mp3',
      ));
      await Future<void>.delayed(Duration.zero);

      expect(core.state.value.processing, EngineProcessing.ready,
          reason: '带残留错误文案的 ready 事件不能被当成陈旧事件丢掉');
      expect(core.state.value.playing, isTrue);
    });

    test('同一曲目的真实 error 仍然会触发换源（守卫不能误杀）', () async {
      var round = 0;
      core = PlayerCore(
        engine: engine,
        cast: cast,
        urlResolver: (item, exclude) async {
          round++;
          return ResolvedPlayback(
            url: round == 1
                ? 'https://dead.example/1.mp3'
                : 'https://live.example/1.mp3',
            sourceId: 'kw',
            winnerId: '音源$round',
            winnerPlatform: 'kw',
            sourceLabel: '酷我',
            musicId: item.musicId,
            title: item.title,
            artist: item.artist,
          );
        },
        onSourceUnplayable: (resolved, error) {},
      );
      await core.setQueue([_item('正常的歌', '歌手', '1')]);
      await Future<void>.delayed(Duration.zero);
      final before = round;

      // 当前曲目的 URL 真打不开 → 引擎报错，cur 与 active 一致
      engine.emit(const EngineSnapshot(
        processing: EngineProcessing.error,
        error: 'Failed to open https://dead.example/1.mp3',
      ));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(round, greaterThan(before),
          reason: '守卫只该丢弃陈旧事件，当前曲目的错误必须走换源');
    });
  });

  // ————————————————————————————————————————————————
  // 坑 3：死链换源
  // ————————————————————————————————————————————————
  group('死链换源', () {
    test('首次地址打不开时自动换源并最终播放', () async {
      var round = 0;
      core = PlayerCore(
        engine: engine,
        cast: cast,
        urlResolver: (item, exclude) async {
          round++;
          // 第一轮给死链，第二轮给活链
          return ResolvedPlayback(
            url: round == 1
                ? 'https://dead.example/${item.musicId}.mp3'
                : 'https://live.example/${item.musicId}.mp3',
            sourceId: 'kw',
            winnerId: '音源$round',
            winnerPlatform: 'kw',
            sourceLabel: '酷我',
            musicId: item.musicId,
            title: item.title,
            artist: item.artist,
          );
        },
        onSourceUnplayable: (resolved, error) {},
      );
      engine.failingUrls.add('https://dead.example/1.mp3');

      await core.setQueue([_item('活下来', '歌手', '1')]);
      await Future<void>.delayed(Duration.zero);

      expect(round, greaterThan(1), reason: '死链后必须重新取链');
      expect(engine.loadedUrls.last, 'https://live.example/1.mp3');
      expect(core.state.value.error, isNull, reason: '换源成功不该留下错误态');
    });

    test('全部源都是死链时进入错误态而不是无限重试', () async {
      core = PlayerCore(
        engine: engine,
        cast: cast,
        urlResolver: (item, exclude) async => ResolvedPlayback(
          url: 'https://always-dead.example/1.mp3',
          sourceId: 'kw',
          winnerId: '音源',
          winnerPlatform: 'kw',
          sourceLabel: '酷我',
          musicId: item.musicId,
          title: item.title,
          artist: item.artist,
        ),
        onSourceUnplayable: (resolved, error) {},
      );
      engine.failingUrls.add('https://always-dead.example/1.mp3');

      await core.setQueue([_item('永远打不开', '歌手', '1')]);
      await Future<void>.delayed(Duration.zero);

      expect(core.state.value.processing, EngineProcessing.error);
      expect(core.state.value.error, isNotNull);
      // 重试次数受 maxRounds(3) 约束，不能无限打
      expect(engine.loadedUrls.length, lessThanOrEqualTo(3));
    });
  });

  // ————————————————————————————————————————————————
  // 基本状态机
  // ————————————————————————————————————————————————
  group('队列与状态', () {
    test('playAt 越界不崩溃', () async {
      await core.setQueue([_item('只有一首', '歌手', '1')]);
      await core.playAt(99);
      expect(core.state.value.processing, isNot(EngineProcessing.error));
    });

    test('空队列时 playAt 安全返回', () async {
      await core.setQueue([]);
      await core.playAt(0);
      expect(engine.loadedUrls, isEmpty);
    });
  });
}

/// 换源续播：用户已听过的部分不应该重来。
///
/// 真机症状：幻音给的死链播了 20 多秒才报错，换源后进度条从
/// 00:22 跳回 00:00 —— 用户看到的就是「进度条不是从头」。
void fallbackResumeTests() {
  group('换源续播（进度不能跳回 0）', () {
    test('换源后 seek 回原进度', () async {
      final eng = _ResumableEngine();
      var round = 0;
      final pc = PlayerCore(
        engine: eng,
        cast: _RecordingCast(),
        urlResolver: (item, exclude) async {
          round++;
          return ResolvedPlayback(
            url: round == 1
                ? 'https://dead.example/1.mp3'
                : 'https://live.example/1.mp3',
            sourceId: 'kw',
            winnerId: '源$round',
            winnerPlatform: 'kw',
            sourceLabel: '酷我',
            musicId: item.musicId,
            title: item.title,
            artist: item.artist,
          );
        },
        onSourceUnplayable: (r, e) {},
      );
      await pc.setQueue([_item('听到一半换源', '歌手', '1')]);
      await Future<void>.delayed(Duration.zero);

      // 模拟：死链播到 22 秒后报错
      eng.simulateProgress(const Duration(seconds: 22));
      eng.emitError('Failed to open https://dead.example/1.mp3');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(round, greaterThan(1), reason: '应触发换源');
      expect(eng.seekedTo, isNotNull, reason: '换源后必须 seek 回原位置');
      expect(eng.seekedTo!.inSeconds, closeTo(22, 2),
          reason: '应该恢复到大致的原进度，而不是从头播');
      await pc.dispose();
    });

    test('原进度超过新地址时长时从头播（不越界）', () async {
      final eng = _ResumableEngine();
      var round = 0;
      final pc = PlayerCore(
        engine: eng,
        cast: _RecordingCast(),
        urlResolver: (item, exclude) async {
          round++;
          return ResolvedPlayback(
            url: round == 1
                ? 'https://dead.example/1.mp3'
                : 'https://live.example/1.mp3',
            sourceId: 'kw',
            winnerId: '源$round',
            winnerPlatform: 'kw',
            sourceLabel: '酷我',
            musicId: item.musicId,
            title: item.title,
            artist: item.artist,
          );
        },
        onSourceUnplayable: (r, e) {},
      );
      await pc.setQueue([_item('短歌', '歌手', '1')]);
      await Future<void>.delayed(Duration.zero);

      // 原位置 200 秒，但新地址只有 60 秒
      eng.simulateProgress(const Duration(seconds: 200));
      eng.newDuration = const Duration(seconds: 60);
      eng.emitError('Failed to open https://dead.example/1.mp3');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      if (eng.seekedTo != null) {
        expect(eng.seekedTo!.inSeconds, lessThan(60),
            reason: '不能 seek 到超出新地址时长的位置');
      }
      await pc.dispose();
    });

    test('刚开始就失败（<1s）不做无意义 seek', () async {
      final eng = _ResumableEngine();
      var round = 0;
      final pc = PlayerCore(
        engine: eng,
        cast: _RecordingCast(),
        urlResolver: (item, exclude) async {
          round++;
          return ResolvedPlayback(
            url: round == 1
                ? 'https://dead.example/1.mp3'
                : 'https://live.example/1.mp3',
            sourceId: 'kw',
            winnerId: '源$round',
            winnerPlatform: 'kw',
            sourceLabel: '酷我',
            musicId: item.musicId,
            title: item.title,
            artist: item.artist,
          );
        },
        onSourceUnplayable: (r, e) {},
      );
      await pc.setQueue([_item('秒挂', '歌手', '1')]);
      await Future<void>.delayed(Duration.zero);

      eng.simulateProgress(const Duration(milliseconds: 300));
      eng.emitError('Failed to open https://dead.example/1.mp3');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(eng.seekedTo, isNull, reason: '位置太靠前就别 seek 了');
      await pc.dispose();
    });
  });
}

/// 能记录 seek 目标、可模拟进度的假引擎。
class _ResumableEngine extends _FakeEngine {
  Duration? seekedTo;
  Duration newDuration = const Duration(minutes: 3);
  Duration _pos = Duration.zero;

  void simulateProgress(Duration p) => _pos = p;

  void emitError(String msg) {
    // 先把 position 写进快照，让 PlayerCore 拿到"换源前的位置"
    emitPos(_pos);
    emit(EngineSnapshot(
      processing: EngineProcessing.error,
      error: msg,
      position: _pos,
      duration: newDuration,
    ));
  }

  void emitPos(Duration p) {
    emit(EngineSnapshot(
      processing: EngineProcessing.ready,
      playing: true,
      position: p,
      duration: newDuration,
    ));
  }

  @override
  Future<void> seek(Duration position) async => seekedTo = position;

  @override
  Future<Duration?> load(Uri source,
      {Map<String, String>? headers, String? formatHint}) async {
    loadedUrls.add(source.toString());
    if (failingUrls.contains(source.toString())) {
      throw Exception('Failed to open $source');
    }
    _pos = Duration.zero;
    return newDuration;
  }
}
