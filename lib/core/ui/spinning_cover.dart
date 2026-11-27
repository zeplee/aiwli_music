import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'cover_source.dart';

/// 黑胶唱片式旋转封面（纯 Flutter，零依赖）。
///
/// 参考栖弦 v1.1.3 的 SpinningCoverArt：24 秒匀速转一圈，播放时
/// `repeat()`，暂停时 `stop(canceled: false)` 保留当前角度，
/// 默认圆形，可切方形（方形时冻结角度）。
/// 这里不引入 cached_network_image，直接复用工程现有的 Image 组件。
class SpinningCover extends StatefulWidget {
  const SpinningCover({
    super.key,
    required this.size,
    required this.playing,
    required this.round,
    this.uri,
    this.bytes,
    this.enableAnimation = true,
  });

  final double size;
  final bool playing;
  final bool round;

  /// 网络封面（可以为空，此时使用 bytes 或占位唱片）。
  final Uri? uri;

  /// 本地封面字节，优先于 uri。
  final Uint8List? bytes;

  /// 系统减少动画 / 测试环境可关掉动画。
  final bool enableAnimation;

  @override
  State<SpinningCover> createState() => _SpinningCoverState();
}

class _SpinningCoverState extends State<SpinningCover>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    );
    _sync();
  }

  @override
  void didUpdateWidget(covariant SpinningCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playing != widget.playing ||
        oldWidget.round != widget.round ||
        oldWidget.enableAnimation != widget.enableAnimation) {
      _sync();
    }
  }

  void _sync() {
    final shouldSpin =
        widget.playing && widget.round && widget.enableAnimation;
    if (shouldSpin) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      // canceled:false 保留当前角度：暂停时不突然跳回 0 度。
      _controller.stop(canceled: false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final key = widget.bytes != null
        ? 'bytes:${widget.bytes!.length}'
        : widget.uri?.toString() ?? 'none';

    // 方形模式冻结角度，切回圆形时从当前角度继续（controller 没被销毁）。
    final turns = widget.round ? _controller : const AlwaysStoppedAnimation(0.0);

    return RepaintBoundary(
      child: RotationTransition(
        turns: turns,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: widget.round ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: widget.round ? null : BorderRadius.circular(18),
            color: scheme.surfaceContainerHighest,
            boxShadow: [
              BoxShadow(
                color: scheme.shadow.withValues(alpha: 0.22),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: _artwork(scheme, key),
        ),
      ),
    );
  }

  Widget _artwork(ColorScheme scheme, String key) {
    final bytes = widget.bytes;
    if (bytes != null && bytes.isNotEmpty) {
      return Image.memory(
        bytes,
        key: ValueKey(key),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _VinylPlaceholder(size: widget.size),
      );
    }
    final uri = widget.uri;
    final url = CoverSource.normalize(uri?.toString());
    if (url != null && CoverSource.isUsable(url)) {
      return Image.network(
        url,
        key: ValueKey(key),
        headers: CoverSource.headers(url),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _VinylPlaceholder(size: widget.size),
      );
    }
    return _VinylPlaceholder(size: widget.size);
  }
}

/// 没有封面时的占位唱片：中央圆孔 + 同心纹路，
/// 比一个孤零零的 Icons.graphic_eq 更像真实播放器。
class _VinylPlaceholder extends StatelessWidget {
  const _VinylPlaceholder({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CustomPaint(
      size: Size(size, size),
      painter: _VinylPainter(
        base: Color.lerp(scheme.primary, scheme.tertiary, 0.35) ?? scheme.primary,
        ink: scheme.onPrimary.withValues(alpha: 0.14),
        hole: scheme.surface,
      ),
    );
  }
}

class _VinylPainter extends CustomPainter {
  const _VinylPainter({
    required this.base,
    required this.ink,
    required this.hole,
  });

  final Color base;
  final Color ink;
  final Color hole;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = math.min(size.width, size.height) / 2;

    canvas.drawCircle(c, r, Paint()..color = base);
    // 外圈几道纹路，用半透明描边即可，不需要图片资源。
    for (var i = 1; i <= 6; i++) {
      canvas.drawCircle(
        c,
        r * (1 - i * 0.10),
        Paint()
          ..color = ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1, size.width * 0.006),
      );
    }
    // 中心标签 + 圆孔
    canvas.drawCircle(
        c, r * 0.34, Paint()..color = base.withValues(alpha: 0.72));
    canvas.drawCircle(c, r * 0.055, Paint()..color = hole);
  }

  @override
  bool shouldRepaint(covariant _VinylPainter oldDelegate) =>
      oldDelegate.base != base || oldDelegate.ink != ink || oldDelegate.hole != hole;
}
