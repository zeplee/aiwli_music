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
    // 限尺寸解码：取色只需要小图，别为了一张 3000px 封面解码几十 MB。
    final provider = ResizeImage(NetworkImage(url), width: 64, height: 64);
    final stream = provider.resolve(const ImageConfiguration());
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
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final w = image.width;
    final h = image.height;
    if (w == 0 || h == 0) return null;

    // 5x5 网格取样：比随机采样稳定，不同封面不会因采样点抖动而跳色。
    // alpha 加权：半透明像素（部分 PNG 封面）不应和实心像素同权。
    var r = 0, g = 0, b = 0;
    for (var row = 0; row < 5; row++) {
      final y = ((row + 0.5) * h / 5).floor().clamp(0, h - 1);
      for (var col = 0; col < 5; col++) {
        final x = ((col + 0.5) * w / 5).floor().clamp(0, w - 1);
        final i = (y * w + x) * 4;
        if (i + 3 >= bytes.length) continue;
        final a = bytes[i + 3];
        r += bytes[i] * a ~/ 255;
        g += bytes[i + 1] * a ~/ 255;
        b += bytes[i + 2] * a ~/ 255;
      }
    }
    // 均值色做基底
    var base = Color.fromARGB(255, r ~/ 25, g ~/ 25, b ~/ 25);

    // 均值常常偏灰（封面上蓝天下草地混在一起）。再挑一个高饱和像素做校正，
    // 让动态主题有明显色相，而不是一片灰。
    var bestSat = 0.0;
    Color? vivid;
    final stepX = (w / 16).ceil().clamp(1, w);
    final stepY = (h / 16).ceil().clamp(1, h);
    for (var y = 0; y < h; y += stepY) {
      for (var x = 0; x < w; x += stepX) {
        final i = (y * w + x) * 4;
        if (i + 3 >= bytes.length) continue;
        if (bytes[i + 3] < 160) continue; // 只看较实的像素
        final rr = bytes[i] / 255.0;
        final gg = bytes[i + 1] / 255.0;
        final bb = bytes[i + 2] / 255.0;
        final maxV = rr > gg ? (rr > bb ? rr : bb) : (gg > bb ? gg : bb);
        final minV = rr < gg ? (rr < bb ? rr : bb) : (gg < bb ? gg : bb);
        final lightness = (maxV + minV) / 2;
        if (lightness < 0.15 || lightness > 0.88) continue; // 近黑/近白跳过
        final denom = 1 - (2 * lightness - 1).abs();
        final sat = (maxV == minV || denom == 0) ? 0.0 : (maxV - minV) / denom;
        if (sat > bestSat) {
          bestSat = sat;
          vivid = Color.fromARGB(
              255, (rr * 255).round(), (gg * 255).round(), (bb * 255).round());
        }
      }
    }

    // 饱和度足够就用以有辨识度的色，否则退回均值
    if (vivid != null && bestSat > 0.28) {
      return Color.lerp(base, vivid, 0.65) ?? vivid;
    }
    return base;
  }
}
