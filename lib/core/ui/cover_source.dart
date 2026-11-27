/// 封面图片的 URL 规范化与请求头（纯 Dart，零依赖）。
///
/// 背景：播放页此前所有 `Image.network` 都是裸请求，而网易 CDN
/// (`p*.music.126.net`) 有防盗链，裸请求会被拒；酷我 / 咪咕 / 酷狗 /
/// QQ 还有协议相对 URL、相对路径、尺寸模板等差异。栖弦为此专门写了
/// `CoverImageSource`（带 `cached_network_image` 依赖），本工程按
/// 「零新增 pub 依赖」的约束用纯 Dart 实现同样的语义，供
/// `Image.network` / `NetworkImage` 统一调用。
///
/// 注意：这里只处理**图片** URL，与「零内置取链」无关，不涉及播放地址。
class CoverSource {
  CoverSource._();

  static const _desktopUa = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/120.0.0.0 Safari/537.36';

  /// 归一化封面 URL：
  ///  - `/data/oss/...` → 咪咕 CDN 绝对地址
  ///  - `//host/path` → 补协议（酷我 `kwcdn` 例外保留 http）
  ///  - `http://` → `https://`（同上例外）
  ///  - 网易 `music.126.net` 统一尺寸参数
  ///  - 酷我 / 酷狗 / QQ 的尺寸模板替换
  static String? normalize(String? raw, {int? size}) {
    if (raw == null) return null;
    var url = raw.trim();
    if (url.isEmpty) return url;

    if (url.startsWith('/data/oss/')) {
      url = 'https://d.musicapp.migu.cn$url';
    }

    final candidate = url.startsWith('//') ? 'http:$url' : url;
    final host = Uri.tryParse(candidate)?.host.toLowerCase() ?? '';
    // 酷我 CDN 的 http 版本可用，强行升级 https 反而可能失败。
    final keepHttp =
        host == 'kwcdn.kuwo.cn' || host.endsWith('.kwcdn.kuwo.cn');

    if (url.startsWith('//')) {
      url = '${keepHttp ? 'http' : 'https'}:$url';
    } else if (url.startsWith('http://') && !keepHttp) {
      url = url.replaceFirst('http://', 'https://');
    }

    if (size != null && url.contains('music.126.net')) {
      final dimension = RegExp(r'([?&])param=\d+y\d+');
      if (dimension.hasMatch(url)) {
        url = url.replaceFirstMapped(
          dimension,
          (m) => '${m[1]}param=${size}y$size',
        );
      } else {
        url += '${url.contains('?') ? '&' : '?'}param=${size}y$size';
      }
    }
    if (size != null && (host == 'kuwo.cn' || host.endsWith('.kuwo.cn'))) {
      url = url.replaceFirstMapped(
        RegExp(r'/star/(albumcover|starheads)/\d+/'),
        (m) => '/star/${m[1]}/$size/',
      );
    }
    if (size != null && (host == 'kugou.com' || host.endsWith('.kugou.com'))) {
      url = url
          .replaceAll('{size}', '$size')
          .replaceFirstMapped(
            RegExp(r'/(stdmusic|softhead)/\d+/'),
            (m) => '/${m[1]}/$size/',
          );
    }
    if (size != null && host == 'y.gtimg.cn') {
      final qq = size <= 300 ? 300 : (size <= 500 ? 500 : 800);
      url = url.replaceFirstMapped(
        RegExp(r'/T002R\d+x\d+M000'),
        (_) => '/T002R${qq}x${qq}M000',
      );
    }
    return url;
  }

  /// 请求头：网易 CDN 必须有 Referer + UA，否则防盗链返回 403。
  /// 其他域名也带 UA，避免部分 CDN 拒绝默认 Flutter UA。
  static Map<String, String>? headers(String? url) {
    if (url == null || url.isEmpty) return null;
    if (url.contains('music.126.net')) {
      return const {
        'User-Agent': _desktopUa,
        'Referer': 'https://music.163.com/',
      };
    }
    if (url.contains('kuwo.cn') || url.contains('kwcdn')) {
      return const {
        'User-Agent': _desktopUa,
        'Referer': 'https://www.kuwo.cn/',
      };
    }
    if (url.contains('kugou.com')) {
      return const {
        'User-Agent': _desktopUa,
        'Referer': 'https://www.kugou.com/',
      };
    }
    return const {'User-Agent': _desktopUa};
  }

  /// 是否是可交给 Image.network 的合法地址。
  static bool isUsable(String? raw, {int? size}) {
    final n = normalize(raw, size: size);
    if (n == null || n.isEmpty) return false;
    final uri = Uri.tryParse(n);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }
}
