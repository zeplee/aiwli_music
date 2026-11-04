import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 从封面图提取主色，用作播放页动态主题。
///
/// 不引入 palette_generator：把图缩到 24x24 解码像素，
/// 按「饱和度 × 亮度」加权挑最有代表性的颜色，成本几毫秒。
class CoverPalette {
  const CoverPalette._();

  static Future<Color?> extract(String? url) async {
    if (url == null || url.isEmpty) return null;
    ui.Image? image;
    try {
      image = await _loadImage(url).timeout(const Duration(seconds: 6));
      return await _dominantColor(image);
    } catch (_) {
      return null;
    } finally {
      image?.dispose();
    }
  }

  static Future<ui.Image> _loadImage(String url) {
    final completer = Completer<ui.Image>();
    final stream = NetworkImage(url).resolve(const ImageConfiguration());
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        if (!completer.isCompleted) completer.complete(info.image);
        stream.removeListener(listener);
      },
      onError: (e, _) {
        if (!completer.isCompleted) completer.completeError(e);
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
    return completer.future;
  }

  static Future<Color?> _dominantColor(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return null;
    final bytes = data.buffer.asUint8List();
    final w = image.width;
    final h = image.height;
    if (w == 0 || h == 0) return null;

    var bestScore = -1.0;
    var best = const Color(0xFF6750A4);

    final stepX = (w / 24).ceil().clamp(1, w);
    final stepY = (h / 24).ceil().clamp(1, h);

    for (var y = 0; y < h; y += stepY) {
      for (var x = 0; x < w; x += stepX) {
        final i = (y * w + x) * 4;
        if (i + 3 >= bytes.length) continue;
        if (bytes[i + 3] < 128) continue; // 跳过透明像素

        final r = bytes[i] / 255.0;
        final g = bytes[i + 1] / 255.0;
        final b = bytes[i + 2] / 255.0;

        final maxV = r > g ? (r > b ? r : b) : (g > b ? g : b);
        final minV = r < g ? (r < b ? r : b) : (g < b ? g : b);
        final lightness = (maxV + minV) / 2;
        final denom = 1 - (2 * lightness - 1).abs();
        final sat = maxV == minV || denom == 0 ? 0.0 : (maxV - minV) / denom;

        // 太暗/过亮的颜色当主题不好看，按偏离中亮度降权
        final lightBonus = 1 - (lightness - 0.5).abs() * 2;
        final score = sat * 0.7 + lightBonus * 0.3;
        if (score > bestScore) {
          bestScore = score;
          best = Color.fromARGB(
            255,
            (r * 255).round(),
            (g * 255).round(),
            (b * 255).round(),
          );
        }
      }
    }
    return best;
  }
}