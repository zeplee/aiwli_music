import 'dart:typed_data';

import 'package:flutter/material.dart';

/// 通用封面图：网络图优先，加载失败/无 URL 时用主色渐变兜底。
/// 不引入第三方缓存库（保持 pubspec 精简），Image.network 自带内存缓存。
class CoverImage extends StatelessWidget {
  const CoverImage({
    this.url,
    this.bytes,
    this.size = 44,
    this.radius = 8,
    this.icon = Icons.music_note,
    super.key,
  });

  final String? url;

  /// 本地封面字节（on_audio_query.queryArtwork），优先于 [url]。
  final Uint8List? bytes;
  final double size;
  final double radius;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primary, scheme.tertiary],
        ),
      ),
      child: Icon(icon, size: size * 0.45,
          color: Colors.white.withValues(alpha: 0.9)),
    );
    // 本地字节封面优先（本地歌曲没有网络封面 URL）
    final b = bytes;
    if (b != null && b.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.memory(
          b,
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => placeholder,
        ),
      );
    }
    final u = url;
    if (u == null || u.isEmpty) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.network(
        u,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => placeholder,
        loadingBuilder: (ctx, child, progress) =>
            progress == null ? child : placeholder,
      ),
    );
  }
}
