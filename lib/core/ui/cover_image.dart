import 'package:flutter/material.dart';

/// 通用封面图：网络图优先，加载失败/无 URL 时用主色渐变兜底。
/// 不引入第三方缓存库（保持 pubspec 精简），Image.network 自带内存缓存。
class CoverImage extends StatelessWidget {
  const CoverImage({
    required this.url,
    this.size = 44,
    this.radius = 8,
    this.icon = Icons.music_note,
    super.key,
  });

  final String? url;
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
