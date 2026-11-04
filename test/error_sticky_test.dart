import 'package:flutter_test/flutter_test.dart';

import 'package:aiwli_music/player/models.dart';

/// 错误粘滞语义的回归测试。
///
/// 背景（真机复现）：截图里音频已在播放（00:09/03:41、暂停键激活），
/// 但底部同时挂红字 "Failed to recognize file format."。
/// 根因是 copyWith 无法用 null 表达「清空错误」——null 被当成「不改」，
/// 于是只要报过一次错，红字就永久粘在状态里。
void main() {
  group('PlayerUiState.copyWith 错误语义', () {
    test('不传 error 时保留原错误（null = 不改）', () {
      const s = PlayerUiState(error: 'boom', playing: true);
      final next = s.copyWith(position: const Duration(seconds: 3));
      expect(next.error, 'boom');
    });

    test('clearError=true 能真正清空错误', () {
      const s = PlayerUiState(error: 'boom', playing: true);
      final next = s.copyWith(clearError: true);
      expect(next.error, isNull, reason: '播放恢复后必须能清掉旧错误');
      expect(next.playing, isTrue);
    });

    test('clearError 优先于同时传入的 error', () {
      const s = PlayerUiState(error: 'old');
      final next = s.copyWith(error: 'new', clearError: true);
      expect(next.error, isNull);
    });

    test('传 error 时覆盖为新的错误', () {
      const s = PlayerUiState(error: 'old');
      final next = s.copyWith(error: 'new');
      expect(next.error, 'new');
    });

    test('清空后再设置新错误仍可用', () {
      final s = const PlayerUiState(error: 'old').copyWith(clearError: true);
      expect(s.error, isNull);
      final again = s.copyWith(error: 'later');
      expect(again.error, 'later');
    });
  });

  group('EngineSnapshot 默认值', () {
    test('新建快照默认无错误', () {
      const snap = EngineSnapshot();
      expect(snap.error, isNull);
      expect(snap.speed, 1.0);
    });
  });
}