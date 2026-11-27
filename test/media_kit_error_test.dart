import 'package:flutter_test/flutter_test.dart';

import 'package:aiwli_music/player/media_kit_engine.dart';

void main() {
  group('MediaKitEngine.isFatalError 边界', () {
    test('打开失败同时含格式提示 → 致命，触发换源', () {
      expect(
        MediaKitEngine.isFatalError(
            'Failed to open https://x/y.mp3: unknown format'),
        isTrue,
      );
    });

    test('纯格式识别失败 → 非致命，mpv 仍可能出声', () {
      expect(
        MediaKitEngine.isFatalError('failed to recognize file format'),
        isFalse,
      );
    });

    test('403 → 致命', () {
      expect(MediaKitEngine.isFatalError('HTTP error 403 Forbidden'), isTrue);
    });

    test('无关文本 → 非致命', () {
      expect(MediaKitEngine.isFatalError('something unrelated happened'),
          isFalse);
    });
  });
}
