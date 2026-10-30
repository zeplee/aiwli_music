import 'package:drift/drift.dart';

/// drift schema 骨架（设计文档 §7）。
/// M0 仅定义表；Database 类与迁移测试待 M1 与 build_runner codegen 一起落地。

/// 下载任务表（§6）。
class DownloadTasks extends Table {
  TextColumn get id => text()();
  TextColumn get sourceId => text()();
  TextColumn get musicId => text()();
  TextColumn get title => text()();
  TextColumn get artist => text()();
  TextColumn get url => text()();
  TextColumn get quality => text()();
  // pending / running / paused / done / failed
  TextColumn get status => text()();
  IntColumn get receivedBytes => integer().withDefault(const Constant(0))();
  IntColumn get totalBytes => integer().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 播放历史（本地歌单/最近播放共用）。
class PlayHistory extends Table {
  TextColumn get sourceId => text()();
  TextColumn get musicId => text()();
  TextColumn get title => text()();
  TextColumn get artist => text()();
  DateTimeColumn get playedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {sourceId, musicId, playedAt};
}
