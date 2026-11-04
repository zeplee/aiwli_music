import 'package:flutter/material.dart';

import '../discover/discover_page.dart';
import '../library/library_page.dart';
import '../mine/mine_page.dart';
import '../search/search_page.dart';

/// 响应式断点（规格 §12）：
///   < 600dp  单列 + 底部导航（手机）
///   600–900  仍用底部导航（平板竖屏）
///   > 900dp  侧栏 Rail + 内容（桌面/平板横屏）
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  late final List<Widget> _pages = [
    DiscoverPage(onOpenSearch: _openSearch),
    const LibraryPage(),
    const MinePage(),
  ];

  static const _railDestinations = [
    NavigationRailDestination(
      icon: Icon(Icons.explore_outlined),
      selectedIcon: Icon(Icons.explore),
      label: Text('发现'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.library_music_outlined),
      selectedIcon: Icon(Icons.library_music),
      label: Text('音乐库'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.person_outline),
      selectedIcon: Icon(Icons.person),
      label: Text('我的'),
    ),
  ];

  void _openSearch() {
    Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const SearchPage()));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > 900;
        if (!wide) {
          // 手机/窄屏：保持原底部导航
          return Scaffold(
            body: IndexedStack(index: _index, children: _pages),
            bottomNavigationBar: NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: const [
                NavigationDestination(icon: Icon(Icons.explore), label: '发现'),
                NavigationDestination(
                    icon: Icon(Icons.library_music), label: '音乐库'),
                NavigationDestination(icon: Icon(Icons.person), label: '我的'),
              ],
            ),
          );
        }
        // 宽屏：左侧 Rail + 右侧内容，垂直空间全部让给内容
        return Scaffold(
          body: Row(
            children: [
              NavigationRail(
                selectedIndex: _index,
                onDestinationSelected: (i) => setState(() => _index = i),
                labelType: NavigationRailLabelType.all,
                leading: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: IconButton(
                    tooltip: '搜索',
                    onPressed: _openSearch,
                    icon: const Icon(Icons.search),
                  ),
                ),
                destinations: _railDestinations,
              ),
              const VerticalDivider(width: 1),
              Expanded(child: _pages[_index]),
            ],
          ),
        );
      },
    );
  }
}
