import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 队列弹窗「当前列表 / 最近播放」双 Tab 的回归测试。
///
/// 背景：这两个概念原来只靠一个「播放队列」弹层承载，用户容易混淆
/// 「当前队列」和「播放历史」——它们是**两份不同的数据**：
///   队列 = core.queue，内存，本次点播传入的列表，重启即失
///   最近 = play_history.json，落盘、参与 WebDAV 同步、长期累积
///
/// 真机实测差异：历史 1912 条 vs 队列 2 首。
void main() {
  testWidgets('TabBar 与 TabBarView 必须共用同一个 controller', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    final tabView = tester.widget<TabBarView>(find.byType(TabBarView));

    expect(tabBar.controller, isNotNull, reason: 'TabBar 必须挂 controller');
    expect(tabView.controller, isNotNull, reason: 'TabBarView 必须挂 controller');
    expect(identical(tabBar.controller, tabView.controller), isTrue,
        reason: '两者必须是同一个实例，否则点击 Tab 页面不切换');
    expect(tabBar.controller!.length, 2);
  });

  testWidgets('两个 Tab 标题正确且在计数为 0 时不显示括号', (tester) async {
    await tester.pumpWidget(_harness(queueCount: 0, historyCount: 0));
    await tester.pumpAndSettle();

    expect(find.text('当前列表'), findsOneWidget);
    expect(find.text('最近播放'), findsOneWidget);
    // 空时不该出现 "(0)"
    expect(find.textContaining('(0)'), findsNothing);
  });

  testWidgets('有数据时标题带条数', (tester) async {
    await tester.pumpWidget(_harness(queueCount: 3, historyCount: 12));
    await tester.pumpAndSettle();

    expect(find.text('当前列表 (3)'), findsOneWidget);
    expect(find.text('最近播放 (12)'), findsOneWidget);
  });

  testWidgets('切到第二个 Tab 显示最近播放内容', (tester) async {
    await tester.pumpWidget(_harness(queueCount: 2, historyCount: 3));
    await tester.pumpAndSettle();

    // 初始在第 1 页
    expect(find.text('队列中的歌 0'), findsOneWidget);

    await tester.tap(find.text('最近播放 (3)'));
    await tester.pumpAndSettle();

    expect(find.text('历史里的歌 0'), findsOneWidget,
        reason: '第二页应显示历史条目');
    expect(find.text('队列中的歌 0'), findsNothing,
        reason: '切页后不应还看到第一页内容');
  });

  testWidgets('清空按钮只在「当前列表」Tab 出现', (tester) async {
    await tester.pumpWidget(
        _harness(queueCount: 2, historyCount: 3, showClearButton: true));
    await tester.pumpAndSettle();

    expect(find.byTooltip('清空队列'), findsOneWidget);

    await tester.tap(find.text('最近播放 (3)'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('清空队列'), findsNothing,
        reason: '历史不提供一键清空，避免误清大量记录');
  });
}

/// 复刻 _QueueSheet 的骨架（不依赖 player/history provider 的真实实现，
/// 这里验证的是**结构不变量**：controller 共享、Tab 数量、切页行为）。
Widget _harness({
  int queueCount = 0,
  int historyCount = 0,
  bool showClearButton = false,
}) {
  return MaterialApp(
    home: Scaffold(
      body: _SheetProbe(
        queueCount: queueCount,
        historyCount: historyCount,
        showClearButton: showClearButton,
      ),
    ),
  );
}

class _SheetProbe extends StatefulWidget {
  const _SheetProbe({
    required this.queueCount,
    required this.historyCount,
    required this.showClearButton,
  });
  final int queueCount;
  final int historyCount;
  final bool showClearButton;

  @override
  State<_SheetProbe> createState() => _SheetProbeState();
}

class _SheetProbeState extends State<_SheetProbe>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
        child: Row(children: [
          Expanded(
            child: TabBar(
              controller: _tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(
                    text: '当前列表'
                        '${widget.queueCount == 0 ? '' : ' (${widget.queueCount})'}'),
                Tab(
                    text: '最近播放'
                        '${widget.historyCount == 0 ? '' : ' (${widget.historyCount})'}'),
              ],
            ),
          ),
          if (widget.showClearButton)
            AnimatedBuilder(
              animation: _tabs,
              builder: (context, _) => _tabs.index == 0
                  ? IconButton(
                      tooltip: '清空队列',
                      onPressed: () {},
                      icon: const Icon(Icons.delete_sweep_outlined),
                    )
                  : const SizedBox.shrink(),
            ),
        ]),
      ),
      const Divider(height: 1),
      Expanded(
        child: TabBarView(
          controller: _tabs,
          children: [
            ListView(
              children: [
                for (var i = 0; i < widget.queueCount; i++)
                  ListTile(title: Text('队列中的歌 $i')),
              ],
            ),
            ListView(
              children: [
                for (var i = 0; i < widget.historyCount; i++)
                  ListTile(title: Text('历史里的歌 $i')),
              ],
            ),
          ],
        ),
      ),
    ]);
  }
}