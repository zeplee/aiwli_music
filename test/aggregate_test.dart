import 'package:flutter_test/flutter_test.dart';
import 'package:aiwli_music/sources/builtin/builtin_search.dart';

void main() {
  test('聚合搜索：并发 + 分组', () async {
    var emissions = 0;
    final groups = await BuiltinSearch.searchAll(
      '周杰伦',
      limit: 5,
      onGroup: (g) {
        emissions++;
        // ignore: avoid_print
        print('emit#$emissions ${g.map((x) => '${x.label}:${x.state.name}/${x.count}').join(' | ')}');
      },
    );
    // ignore: avoid_print
    print('最终: ${groups.map((g) => '${g.label}=${g.count}(${g.state.name})').join(', ')}');
    for (final g in groups) {
      if (g.songs.isNotEmpty) {
        // ignore: avoid_print
        print('  ${g.label} 首条: ${g.songs.first.title} - ${g.songs.first.artist}');
      }
    }
    final dup = BuiltinSearch.duplicates(groups);
    // ignore: avoid_print
    print('跨源重复: ${dup.length} 组');
    expect(groups.where((g) => g.hasResults).length, greaterThanOrEqualTo(2));
  }, timeout: const Timeout(Duration(seconds: 90)));
}
