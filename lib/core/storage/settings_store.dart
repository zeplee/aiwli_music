import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../services/app_paths.dart';

/// JSON 偏好存储（单文件、整读整写、无平台分支）。
///
/// 写入必须是**原子**的，否则会出现数据损坏：
/// 真机事故（实测文件内容）：
///   ..."folder":"梁登宵"}]}509","title":"咱们结婚吧"...
///                        ↑ 第一个 JSON 已结束，后面又粘了旧内容
/// 原因是 `File.writeAsString` 会先截断再写入，两个并发 flush
/// 交错执行时，后一个把内容插到了前一个中间，产生"两个 JSON 拼接"。
/// 结果：下次 `load` 解析失败 → 返回空 Map → **用户的歌单全被清空**。
///
/// 现在改为：① 按文件名串行化（同文件不并发）② 写临时文件 + 原子 rename。
class SettingsStore {
  const SettingsStore();

  /// 每个文件名一把"锁"：同一文件的写入串行执行。
  static final Map<String, Future<void>> _writeChains = {};

  Future<Map<String, Object?>> load(String fileName) async =>
      await loadOrNull(fileName) ?? {};

  /// 区分「文件不存在」与「文件损坏」：
  ///   · 不存在 → 返回 {}（首次运行，正常）
  ///   · 存在且可解析 → 返回内容
  ///   · 存在但损坏且抢救失败 → **返回 null**
  ///
  /// 调用方拿到 null 时应**放弃持久化**，否则会把空数据写回，
  /// 造成"解析失败 → 清空 → 永久丢数据"（真机已发生过）。
  Future<Map<String, Object?>?> loadOrNull(String fileName) async {
    final dir = await AppPaths.supportDir();
    final f = File('$dir/$fileName');
    if (!await f.exists()) return {};

    String text;
    try {
      text = await f.readAsString();
    } catch (_) {
      return null;
    }
    try {
      return (jsonDecode(text) as Map).cast<String, Object?>();
    } catch (_) {
      // 尝试抢救历史损坏文件（两个 JSON 拼接）：
      // 取最后一个完整对象（"}]}" 结尾处）
      final end = text.lastIndexOf('}]}');
      if (end > 0) {
        try {
          return (jsonDecode(text.substring(0, end + 3)) as Map)
              .cast<String, Object?>();
        } catch (_) {}
      }
      // 针对非列表型文件（如 flags），尝试取第一个完整对象
      final firstClose = text.indexOf('}');
      if (firstClose > 0) {
        try {
          return (jsonDecode(text.substring(0, firstClose + 1)) as Map)
              .cast<String, Object?>();
        } catch (_) {}
      }
      return null; // 无法抢救
    }
  }

  Future<void> flush(String fileName, Map<String, Object?> data) {
    // 串行化：排在该文件上一次写入之后
    final prev = _writeChains[fileName] ?? Future<void>.value();
    final next = prev.then((_) => _writeAtomic(fileName, data));
    _writeChains[fileName] = next.catchError((_) {});
    return next;
  }

  Future<void> _writeAtomic(
      String fileName, Map<String, Object?> data) async {
    final dir = await AppPaths.supportDir();
    final f = File('$dir/$fileName');
    await f.parent.create(recursive: true);

    final tmp = File('$dir/.$fileName.tmp');
    // ① 先写临时文件（同一目录，保证 rename 原子）
    await tmp.writeAsString(jsonEncode(data), flush: true);
    // ② 原子替换：同文件系统内 rename 是原子操作，
    //    中途崩溃也只会留下旧的完整文件或新的完整文件，绝不会拼接。
    await tmp.rename(f.path);
  }
}