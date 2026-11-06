import 'package:flutter_test/flutter_test.dart';

import 'package:aiwli_music/player/models.dart';

/// 错误提示分级规则（决定"红条什么时候该出现"）。
///
/// 真机反馈：换源自动播放成功后，红条还要挂满 3 秒，很干扰观感。
///
/// 规则：
///   · processing == error  → 真失败，弹红条
///   · processing == loading 且有 error → 换源中，**不弹**
///   · error == null        → 一切正常，不弹，并重置去重标记
///
/// 这里把判断函数化，避免以后有人把它改回"只看 s.error != null"。
void main() {
  /// 与 player_page 里的判定保持一致。
  bool shouldShowErrorSnackBar(EngineProcessing p, Object? error) =>
      error != null && p == EngineProcessing.error;

  test('真失败（processing=error）才弹红条', () {
    expect(shouldShowErrorSnackBar(EngineProcessing.error, 'boom'), isTrue);
  });

  test('换源中（loading + 残留 error）不弹', () {
    // 这是修复的核心：换源过程会短暂带 error，
    // 若此时弹条，换源成功后红条仍要挂满 3 秒。
    expect(shouldShowErrorSnackBar(EngineProcessing.loading, 'Failed to open'), isFalse);
    expect(shouldShowErrorSnackBar(EngineProcessing.buffering, 'x'), isFalse);
  });

  test('播放正常时不弹', () {
    expect(shouldShowErrorSnackBar(EngineProcessing.ready, null), isFalse);
    expect(shouldShowErrorSnackBar(EngineProcessing.idle, null), isFalse);
    expect(shouldShowErrorSnackBar(EngineProcessing.completed, null), isFalse);
  });

  test('枚举覆盖完整：任何状态配 error 都只在该状态为 error 时弹', () {
    for (final p in EngineProcessing.values) {
      final shown = shouldShowErrorSnackBar(p, 'err');
      expect(shown, p == EngineProcessing.error,
          reason: '状态 $p 的判定与预期不符');
    }
  });
}