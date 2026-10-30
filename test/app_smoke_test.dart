import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aiwli_music/app.dart';
import 'package:aiwli_music/player/audio_engine.dart';
import 'package:aiwli_music/player/providers.dart';

void main() {
  testWidgets('app boots to home', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [engineProvider.overrideWithValue(StubEngine())],
      child: const AiwliApp(),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    // 三 Tab 壳（发现/音乐库/我的）+ 发现页顶栏
    expect(find.text('发现'), findsWidgets);
    expect(find.text('音乐库'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
  });
}
