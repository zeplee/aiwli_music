import 'package:flutter/material.dart';

import '../discover/discover_page.dart';
import '../library/library_page.dart';
import '../mine/mine_page.dart';
import '../search/search_page.dart';

/// 移动端三 Tab 壳（对齐主流音乐 App 惯例）：发现 / 音乐库 / 我的。
/// 搜索从发现页顶部进入；下载与音源配置收进「我的」。
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

  void _openSearch() {
    Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const SearchPage()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.explore), label: '发现'),
          NavigationDestination(icon: Icon(Icons.library_music), label: '音乐库'),
          NavigationDestination(icon: Icon(Icons.person), label: '我的'),
        ],
      ),
    );
  }
}
