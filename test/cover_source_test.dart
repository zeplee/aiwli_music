import 'package:flutter_test/flutter_test.dart';
import 'package:aiwli_music/core/ui/cover_source.dart';

void main() {
  group('CoverSource.normalize', () {
    test('协议相对 URL 补 https', () {
      expect(CoverSource.normalize('//p1.music.126.net/a.jpg'),
          'https://p1.music.126.net/a.jpg');
    });

    test('酷我 CDN 保留 http', () {
      expect(CoverSource.normalize('//kwcdn.kuwo.cn/a.jpg'),
          'http://kwcdn.kuwo.cn/a.jpg');
    });

    test('普通 http 升级 https', () {
      expect(CoverSource.normalize('http://p1.music.126.net/a.jpg'),
          'https://p1.music.126.net/a.jpg');
    });

    test('咪咕相对路径补域名', () {
      expect(CoverSource.normalize('/data/oss/a.jpg'),
          'https://d.musicapp.migu.cn/data/oss/a.jpg');
    });

    test('网易尺寸参数：有则替换，无则追加', () {
      expect(
        CoverSource.normalize(
            'https://p1.music.126.net/a.jpg?param=300y300',
            size: 480),
        'https://p1.music.126.net/a.jpg?param=480y480');
      expect(CoverSource.normalize('https://p1.music.126.net/a.jpg', size: 480),
          'https://p1.music.126.net/a.jpg?param=480y480');
    });

    test('酷我 / 酷狗 / QQ 尺寸模板', () {
      expect(
        CoverSource.normalize('https://img2.kuwo.cn/star/albumcover/300/1.jpg',
            size: 480),
        'https://img2.kuwo.cn/star/albumcover/480/1.jpg');
      expect(
        CoverSource.normalize('https://imge.kugou.com/stdmusic/150/a.jpg',
            size: 480),
        'https://imge.kugou.com/stdmusic/480/a.jpg');
      expect(
        CoverSource.normalize(
            'https://y.gtimg.cn/music/photo_new/T002R300x300M000a.jpg',
            size: 500),
        'https://y.gtimg.cn/music/photo_new/T002R500x500M000a.jpg');
    });

    test('空值与空白', () {
      expect(CoverSource.normalize(null), isNull);
      expect(CoverSource.normalize('   '), isEmpty);
    });
  });

  group('CoverSource.headers', () {
    test('网易必须带 Referer 与 UA', () {
      final h = CoverSource.headers('https://p2.music.126.net/a.jpg');
      expect(h!['Referer'], 'https://music.163.com/');
      expect(h['User-Agent'], contains('Mozilla/5.0'));
    });

    test('酷我 / 酷狗各自 Referer', () {
      expect(CoverSource.headers('https://img2.kuwo.cn/a.jpg')!['Referer'],
          'https://www.kuwo.cn/');
      expect(CoverSource.headers('https://imge.kugou.com/a.jpg')!['Referer'],
          'https://www.kugou.com/');
    });

    test('其他域名只带 UA', () {
      final h = CoverSource.headers('https://example.com/a.jpg')!;
      expect(h.length, 1);
      expect(h['User-Agent'], contains('Mozilla/5.0'));
    });

    test('空 URL 无头', () {
      expect(CoverSource.headers(null), isNull);
      expect(CoverSource.headers(''), isNull);
    });
  });

  group('CoverSource.isUsable', () {
    test('合法 http/https', () {
      expect(CoverSource.isUsable('//p1.music.126.net/a.jpg'), isTrue);
      expect(CoverSource.isUsable('https://example.com/a.jpg'), isTrue);
    });

    test('非法/空', () {
      expect(CoverSource.isUsable(null), isFalse);
      expect(CoverSource.isUsable('   '), isFalse);
      expect(CoverSource.isUsable('data:image/png;base64,xxx'), isFalse);
    });
  });
}
