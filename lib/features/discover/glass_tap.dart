import 'package:flutter/material.dart';

/// 玻璃容器内的可点击区域。
///
/// 为什么需要这个包装：`InkWell` 要求祖先里必须有 `Material`，
/// 而 `GlassScaffold`/`GlassContainer` 都不是 Material——
/// 直接放 InkWell 会在运行时抛 "No Material widget found"。
/// 这里用一层透明的 Material 提供水波纹宿主，同时不破坏玻璃外观。
class GlassTap extends StatelessWidget {
  const GlassTap({
    required this.onTap,
    required this.child,
    this.borderRadius = 12,
    this.tapKey,
    super.key,
  });

  final VoidCallback? onTap;
  final Widget child;
  final double borderRadius;

  /// 打在 InkWell 上的 key，便于测试与自动化定位可点区域。
  final Key? tapKey;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: tapKey,
        borderRadius: BorderRadius.circular(borderRadius),
        onTap: onTap,
        child: child,
      ),
    );
  }
}