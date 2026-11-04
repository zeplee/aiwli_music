import 'package:flutter_test/flutter_test.dart';

import 'package:aiwli_music/player/media_kit_engine.dart';

/// mpv 会往 error 流塞大量「非致命」消息。
/// 最典型的是 "Failed to recognize file format." —— 无扩展名的 HLS/直链
/// 常见此提示，但音频照样出声。若把它当致命错误，就会出现
/// 「正在播放 + 底部红字」并存的荒谬状态。
void main() {
  group('错误分级', () {
    test('识别不出容器格式 → 非致命（mpv 仍能出声）', () {
      expect(
          MediaKitEngine.isFatalError('Failed to recognize file format.'),
          isFalse);
      expect(MediaKitEngine.isFatalError('failed to recognize file format'),
          isFalse);
      expect(MediaKitEngine.isFatalError('Could not recognize file format'),
          isFalse);
    });

    test('真正打不开 → 致命', () {
      expect(MediaKitEngine.isFatalError('Failed to open https://x/y.mp3'),
          isTrue);
      expect(MediaKitEngine.isFatalError('HTTP error 403'), isTrue);
      expect(MediaKitEngine.isFatalError('404 Not Found'), isTrue);
      expect(MediaKitEngine.isFatalError('No audio or video data'),
          isTrue);
      expect(MediaKitEngine.isFatalError('Failed to initialize decoder'),
          isTrue);
    });

    test('大小写不敏感', () {
      expect(MediaKitEngine.isFatalError('FAILED TO OPEN x'), isTrue);
      expect(
          MediaKitEngine.isFatalError('FAILED TO RECOGNIZE FILE FORMAT'),
          isFalse);
    });

    test('空字符串不误判为致命', () {
      expect(MediaKitEngine.isFatalError(''), isFalse);
    });

    test('未知消息默认不打扰用户', () {
      // 保守策略：不认识的错误不当致命，避免噪音弹窗
      expect(MediaKitEngine.isFatalError('something weird happened'),
          isFalse);
    });
  });
}