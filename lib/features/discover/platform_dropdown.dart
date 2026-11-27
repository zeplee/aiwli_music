import 'package:flutter/material.dart';

/// 平台下拉菜单：一个入口收起全部平台，展开后带彩色图标 + 当前项打勾。
///
/// 榜单区与精选歌单区共用；选中即收起，沿用工程现有的
/// 「点一下即生效、不额外确认」交互。
class PlatformDropdown extends StatelessWidget {
  const PlatformDropdown({
    super.key,
    required this.selected,
    required this.platforms,
    required this.onSelected,
    this.hint = '选择平台',
  });

  final String selected;
  final List<String> platforms;
  final ValueChanged<String> onSelected;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: PopupMenuButton<String>(
        tooltip: hint,
        color: scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        offset: const Offset(0, 44),
        onSelected: onSelected,
        itemBuilder: (context) => [
          for (final id in platforms)
            PopupMenuItem<String>(
              value: id,
              child: Row(children: [
                _PlatformBadge(id: id),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    PlatformLabels.of(id),
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                if (id == selected)
                  Icon(Icons.check, size: 17, color: scheme.primary),
              ]),
            ),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: scheme.primary.withValues(alpha: 0.30),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PlatformBadge(id: selected),
              const SizedBox(width: 8),
              Text(
                PlatformLabels.of(selected),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 2),
              Icon(Icons.arrow_drop_down, size: 18, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

/// 平台图标色块：用彩色圆角方块 + 单字母缩写，不依赖图片资源。
class _PlatformBadge extends StatelessWidget {
  const _PlatformBadge({required this.id});
  final String id;

  @override
  Widget build(BuildContext context) {
    final badge = PlatformLabels.badge(id);
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: badge.color,
        borderRadius: BorderRadius.circular(7),
      ),
      alignment: Alignment.center,
      child: Text(
        badge.glyph,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// 平台名称与图标定义（与 BuiltinBoards.labels 保持一致）。
class PlatformLabels {
  const PlatformLabels._();

  static const order = ['wy', 'tx', 'kw', 'kg', 'mg'];

  static String of(String id) => switch (id) {
        'wy' => '网易云音乐',
        'tx' => 'QQ音乐',
        'kw' => '酷我音乐',
        'kg' => '酷狗音乐',
        'mg' => '咪咕音乐',
        'qs' => '汽水音乐',
        _ => id,
      };

  static ({Color color, String glyph}) badge(String id) {
    return switch (id) {
      'wy' => (color: const Color(0xFFE60026), glyph: '网'),
      'tx' => (color: const Color(0xFF31C27C), glyph: 'Q'),
      'kw' => (color: const Color(0xFFFF6B35), glyph: '酷'),
      'kg' => (color: const Color(0xFF2B8CFF), glyph: '狗'),
      'mg' => (color: const Color(0xFFFF3B62), glyph: '咪'),
      'qs' => (color: const Color(0xFF1DB954), glyph: '汽'),
      _ => (color: const Color(0xFF757575), glyph: '?'),
    };
  }
}
