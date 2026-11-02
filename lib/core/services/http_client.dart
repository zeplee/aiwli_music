import 'package:dio/dio.dart';

/// 唯一创建 dio 的地方（设计文档 §2 强制规则）。
class Http {
  Http._();

  static const String defaultUa =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0 Safari/537.36';

  static Dio create({
    String? userAgent,
    Map<String, String> baseHeaders = const {},
    Duration timeout = const Duration(seconds: 15),
  }) {
    return Dio(BaseOptions(
      connectTimeout: timeout,
      receiveTimeout: timeout,
      sendTimeout: timeout,
      headers: {
        'User-Agent': userAgent ?? defaultUa,
        ...baseHeaders,
      },
      // 音源可能返回任意 content-type，统一拿文本再自行解析
      responseType: ResponseType.plain,
    ));
  }
}
