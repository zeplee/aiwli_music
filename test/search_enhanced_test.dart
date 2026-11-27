import 'package:flutter_test/flutter_test.dart';
import 'package:aiwli_music/features/search/widgets/search_suggestions.dart';

void main() {
  group('searchSuggestions', () {
    test('空输入不产生建议', () {
      expect(
        searchSuggestions(input: '   ', history: ['周杰伦']),
        isEmpty,
      );
    });

    test('历史优先、去重、大小写不敏感，且不含完全相同的词', () {
      final out = searchSuggestions(
        input: 'jay',
        history: ['Jay Chou', 'jay chou', 'Jay Live'],
        resultTitles: ['Jay 晴天'],
        resultArtists: ['JAY'],
      );
      expect(out, ['Jay Chou', 'Jay Live', 'Jay 晴天']);
    });

    test('结果歌名/歌手也进入建议，按历史→歌名→歌手排序', () {
      final out = searchSuggestions(
        input: '周',
        history: ['周杰伦演唱会'],
        resultTitles: ['周杰伦的夜曲'],
        resultArtists: ['周华健'],
      );
      expect(out, ['周杰伦演唱会', '周杰伦的夜曲', '周华健']);
    });

    test('limit 生效', () {
      final out = searchSuggestions(
        input: 'a',
        history: ['a1', 'a2', 'a3', 'a4', 'a5'],
        limit: 2,
      );
      expect(out, ['a1', 'a2']);
    });
  });

  group('SearchSelection', () {
    test('默认未激活、无选中', () {
      final s = SearchSelection();
      expect(s.active, isFalse);
      expect(s.isEmpty, isTrue);
    });

    test('enter/toggle/count/exit', () {
      final s = SearchSelection()..enter();
      s.toggle(1);
      s.toggle(3);
      expect(s.count, 2);
      s.toggle(1);
      expect(s.count, 1);
      expect(s.selected, {3});
      s.exit();
      expect(s.active, isFalse);
      expect(s.isEmpty, isTrue);
    });

    test('selectAll 与 invert', () {
      final s = SearchSelection()..enter();
      s.selectAll(5);
      expect(s.count, 5);
      s.invert(5);
      expect(s.isEmpty, isTrue);
      s.invert(5);
      expect(s.count, 5);
    });
  });
}
