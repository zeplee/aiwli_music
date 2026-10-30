# Aiwli Music 技术设计与实施规格（交接文档）

**版本** v2.1 · 2026-10-27 · 状态：可施工（文档完整，代码未开始）
**读者**：接手本项目的 AI 或人类工程师。本文档自包含，不需要额外对话上下文。
**替代关系**：本文档**替代** v1.0 设计文档与 `selection-evidence.md` 的施工地位。后者降级为「选型证据附录」，仅供追溯决策依据；**两者冲突时以本文档为准**。

### 阅读指引

| 你的角色 | 读这些章节 |
|---|---|
| 第一次接手 | §0 项目定义 → §17 决策记录 → §2 目录 → §13 里程碑 → §14 第一周清单 |
| 写播放域代码 | §3.1 接口 → §18.2 状态机 → §13 M1 |
| 写音源代码 | §4 音源宿主 → §19 测试规格 → §20 Spike 判据 |
| 写 UI 代码 | §21 UI/交互规格 → §3 接口 |
| 写歌词/下载 | §5 歌词域 / §6 下载域 |
| 评审或挑战设计 | §17 决策记录（先看是否已被否决） |

---

## 0. 项目定义

### 0.1 目标
用 Flutter 构建**五端**（Android / iOS / macOS / Windows / Linux）音乐播放器，功能对齐 lx-music（洛雪音乐助手），并可加载 MusicFree 插件作为音源。

### 0.2 硬约束（先读，违反会导致返工）

1. **从零新建工程**。CyShineMusic（栖弦，MIT）是第三方开源项目，仅作**参考实现**与**可移植素材来源**（MIT 允许复制），不作为代码基座，也不承担其历史技术债。
2. **播放引擎统一**。全平台使用 media_kit，不做"移动一套、桌面一套"。
3. **业务层零平台 import**。`lib/features/**`、`lib/core/**` 中不得出现平台插件 import；平台分支只允许出现在 `lib/platform/**`。
4. **许可红线**：
   - 可参考并复制代码：lx-music-desktop（Apache-2.0）、CyShineMusic（MIT）、namida（许可需逐个确认，见 §6）
   - **只能读思路、不得复制代码**：MusicFree / MusicFreeDesktop / MusicWEP（AGPL-3.0）、ZeroBit-Player（GPL-3.0）、any-listen（AGPL-3.0 + **明确禁止商用**）
   - 若本项目将来商用，AGPL 生态必须完全避开；当前设计只在"协议规范"与"架构思路"层面借鉴，未复制其代码。

### 0.3 音源生态定位（关键决策，见 §4.3）

**以 MusicFree 插件为主生态，lx 源脚本为兼容层。** 原因：MusicFree 插件是完整源（自带搜索/详情/歌词/封面），lx 脚本只有 `musicUrl`。若以 lx 为主，必须自己移植 5 个平台的官方 API 才能让用户搜得到歌。

### 0.4 非目标
- 不做视频播放（虽然 media_kit 支持）
- 不做 Web 端（flutter_js 平台声明不含 web，且浏览器内音源脚本受限）
- 首期不做 iOS 小组件

---

## 1. 技术选型与决策依据

### 1.1 最终选型

| 层 | 选型 | 版本 | 平台 | 许可 |
|---|---|---|---|---|
| 状态管理 | flutter_riverpod | ^2.6 | 全 | MIT |
| 路由 | go_router | ^14 | 全 | BSD |
| HTTP | dio | ^5.11 | 全 | MIT |
| **播放引擎** | **media_kit + media_kit_libs_audio** | ^1.2.6 / ^1.0.7 | 五端 | MIT |
| 音频焦点 | audio_session | ^0.2.4 | A/iOS/mac | MIT |
| 媒体广播（A/iOS/mac/Win/Web） | **flutter_media_session**（ADR-014） | ^3.0.9 | A/iOS/mac/Win/web | MIT |
| 媒体广播-Linux | **audio_service_mpris（直驱 platform interface，ADR-014）** | ^0.2.1 | Linux | MIT |
| **音源 JS 引擎** | **flutter_js** | **0.8.7** | 五端 | MIT |
| 加密/zlib/GBK | pointycastle + crypto + archive + fast_gbk | 各最新 | 纯 Dart | 宽松 |
| 标签读写 | audio_metadata_reader | ^1.8.1 | 纯 Dart | MIT |
| 数据库 | drift（+ sqlite3） | ^2.x | 全 | MIT |
| 安全存储 | flutter_secure_storage | ^11.2 | 全 | BSD |
| 应用目录 | path_provider（M0 实测补充，aiwli_git 同款） | ^2.1.0 | 全 | MIT |
| 桌面窗口 | window_manager | ^0.5 | 桌面 | MIT |
| 系统托盘 | tray_manager | ^0.5 | 桌面 | MIT |
| 桌面歌词窗口 | desktop_multi_window | ^0.3 | 桌面 | MIT |
| 本地 HTTP 服务（开放 API） | shelf | ^1.x | 全 | BSD |
| HTML 解析（cheerio 桥备用） | html | ^0.15 | 纯 Dart | MIT |

### 1.2 已否决的方案（**不要再提**）

| 方案 | 否决依据（实测，2026-10） |
|---|---|
| `just_audio` 作为统一引擎 | 桌面端无官方实现，必须依赖 `just_audio_media_kit`（Pato05，**14★、18 个月未发版、unverified uploader**）。该桥 README 自承：gapless 需开实验性 `--prefetch-playlist`、`shuffleOrder` 被忽略、header 支持 "(untested)"。桥底层**仍是 media_kit**——多垫一层却损失三个音乐播放器刚需功能 |
| `flutter_qjs` | 最后发版 2022-05，SDK 约束 `>=2.12 <3.0.0`，无法在现代 Flutter 使用 |
| 自研 BASS 原生插件（栖弦做法） | 需 Win/macOS/Linux 三套原生桥（2-3 周），且 BASS 商用需 un4seen 授权；media_kit（libmpv, LGPL）无此问题 |
| `flutter_audio_tagger` | pub 上所有版本仅注册 Android 平台 |
| WebView 跑音源脚本 | 桌面 webview 库生态分裂（webview_flutter 不支持桌面）、内存开销大、结构化数据交换困难 |
| 为 any-listen 单独做第三套适配器 | `any-listen-extension-lx-api-source-loader/config.ts` 声明 `resource: [{id:'kw', resource:['musicUrl']}, ...]`，与 lx 脚本能力面完全一致；`grant:['internet','isolate_context']` + `buildConfig.isIsolateMode:true` 表明它只是 **lx 脚本的隔离进程容器**，不是新协议。见 §4.5 |

### 1.3 已知弱点（接受并监控）
- `flutter_js` 单人维护（abner，542★，81 open issues，2025-09→2026-01 有四个月空窗）。缓解：封装隔离在 `lib/sources/runtime/`，必要时 fork 或换底层。
- QuickJS ≠ V8，音源脚本兼容性需实测。缓解：§3.6 双轨策略 + M2 spike 前置验证。
- **`flutter_media_session` 较年轻**（2026-04 创建、单人维护但活跃；ADR-014）→ 风险被 `MediaSessionCast` 适配层隔离；回退链：audio_service 三件套+fork（ADR-013）→ win32 自实现（ADR-012）。**seek 五端第一天全通**（Win 端 TimelineProperties + SeekTo 已源码核实）。Windows 构建链**不需要 rustup**。

---

## 2. 目录结构

```
lib/
├── main.dart                       # 入口，仅做 platform 选择 + runApp
├── app.dart                        # MaterialApp、主题、全局 Provider
├── router.dart                     # go_router 定义
├── core/
│   ├── models/                     # 纯数据类（freezed）
│   │   ├── music.dart              # MusicInfo / Album / Artist
│   │   ├── lyric.dart              # LyricLine / LyricWord / LyricDocument
│   │   └── quality.dart            # Quality enum
│   ├── services/
│   │   ├── http_client.dart        # dio 工厂（唯一创建 dio 的地方）
│   │   ├── logger.dart
│   │   └── app_paths.dart
│   ├── storage/
│   │   ├── settings_store.dart     # shared_preferences 封装
│   │   └── db.dart                 # drift database（schema 见 §7）
│   └── ui/                         # 通用组件
├── player/                         # ★ 播放域
│   ├── player_core.dart            # 纯逻辑状态机（无插件 import）
│   ├── audio_engine.dart           # 接口
│   ├── media_kit_engine.dart       # 唯一引擎实现
│   ├── audio_focus_policy.dart     # 接口 + 工厂
│   ├── interruption_coordinator.dart
│   ├── media_session_cast.dart     # 接口 + 工厂
│   ├── cast/                       # fms 适配器（A/iOS/mac/Win/Web）+ mpris 直驱器（Linux）两实现
│   └── models.dart                 # EngineSnapshot / PlayerUiState
├── sources/                        # ★ 音源域
│   ├── music_source.dart           # 统一接口
│   ├── manifest.dart               # SourceManifest / 能力声明
│   ├── aggregator.dart             # 多源搜索聚合（§4.6）
│   ├── health.dart                 # 源健康度与降级（§4.7）
│   ├── runtime/                    # 共享 JS 宿主
│   │   ├── runtime_host.dart       # 实例池 / 路由 / 串行 / 超时
│   │   ├── runtime_instance.dart
│   │   ├── bridges/                # HTTP / crypto / buffer / zlib / storage
│   │   └── polyfills/              # JS 侧 shim（buffer.js / qs.js / he.js ...）
│   ├── lx/
│   │   ├── lx_adapter.dart         # MusicSource 实现
│   │   └── lx_manifest_parser.dart # 解析 @name 等头部注释
│   ├── musicfree/
│   │   ├── musicfree_adapter.dart
│   │   └── shims/                  # axios/cheerio/crypto-js... JS 侧
│   └── registry.dart               # 已安装源的管理与持久化
├── lyrics/                         # ★ 歌词域（§5）
│   ├── parsers/                    # lrc / qrc / krc / yrc / lxlyric
│   ├── lyric_repository.dart       # 本地+内嵌+在线匹配
│   └── lyric_sync.dart             # 时间轴同步与高亮计算
├── downloads/                      # ★ 下载域（§6）
│   ├── download_manager.dart
│   └── download_task.dart
├── platform/                       # ★ 唯一允许平台分支的地方
│   ├── platform_focus.dart         # 返回 Mobile/Desktop 实现
│   ├── platform_cast.dart
│   └── desktop/                    # 窗口/托盘/应用内快捷键/歌词窗
├── features/                       # 业务 UI（纯 Dart）
│   ├── search/  playlists/  downloads/  songs/  player/
│   ├── sources/                    # 源管理界面
│   └── settings/
└── theme/
```

**强制规则**：
- `sources/` 与 `player/` 不得 import `features/`
- `core/` 不得 import 上述任何层
- 平台判断只允许出现在 `platform/` 与 `main.dart`

---

## 3. 核心接口定义（完整签名）

### 3.1 播放域

```dart
// player/models.dart
enum EngineProcessing { idle, loading, buffering, ready, completed, error }

class EngineSnapshot {
  final EngineProcessing processing;
  final bool playing;
  final Duration position;
  final Duration? duration;
  final Duration buffered;
  final double speed;
  final Object? error;
}

// player/audio_engine.dart
abstract interface class AudioEngine {
  Future<Duration?> load(
    Uri source, {
    Map<String, String>? headers,   // UA / Referer，音源 URL 必需
    String? formatHint,
  });
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setVolume(double v);
  Future<void> dispose();

  Stream<EngineSnapshot> get snapshots;
  EngineSnapshot get current;
}
```

```dart
// player/player_core.dart —— 纯逻辑，不 import 任何插件
class PlayerCore {
  PlayerCore({required AudioEngine engine, required AudioFocusPolicy focus});

  ValueListenable<PlayerUiState> get state;

  Future<void> playTrack(TrackSource source, {int? queueIndex});
  Future<void> play(); Future<void> pause();
  Future<void> seek(Duration pos);
  Future<void> next(); Future<void> previous();

  Future<void> setQueue(List<TrackSource> tracks, {int index = 0});
  Future<void> setRepeat(RepeatMode mode);
  Future<void> setShuffle(bool on);
}
```

**PlayerCore 必须实现的三个机制**（源自栖弦 `player_audio_handler.dart`，MIT 可参考）：
1. `_loadGeneration`：每次 load 自增；load 完成后若已过期则丢弃结果（防旧加载覆盖新切歌）
2. `_trackTransition`：切歌期间状态为 loading，失败则回滚到上一首并置 error
3. `_retryAfterSourceFailure`：音源取 URL 失败时保留重试回调，UI 提供重试入口

```dart
// player/audio_focus_policy.dart
abstract interface class AudioFocusPolicy {
  Future<bool> activate();      // 返回是否获得焦点
  Future<void> deactivate();
  Stream<FocusEvent> get events; // interrupted / ducked / resumed / becomingNoisy
}

enum FocusEventType { interruptionBegin, interruptionEnd, duckBegin, duckEnd, becomingNoisy }
class FocusEvent { final FocusEventType type; final bool isDuck; }
```

**双实现**：
- `MobileAudioFocus`（Android/iOS/macOS）：包 `audio_session`，实现 configure / setActive / interruptionEventStream / becomingNoisyEventStream
- `DesktopNoopFocus`（Windows/Linux）：全空操作，`events` 返回 `Stream.empty()`。桌面无音频焦点概念

`InterruptionCoordinator`（约 80 行，仅手机编译路径引用）负责：中断→记住是否在播→暂停；恢复→按记录决定是否继续；duck→音量降到 0.2 / 恢复 1.0；becomingNoisy→暂停。

```dart
// player/media_session_cast.dart
abstract interface class MediaSessionCast {
  Future<void> init();
  void updateNowPlaying(TrackMetadata meta);
  void updatePlayback({required bool playing, required Duration position, Duration? duration});
  void updateQueue(List<TrackMetadata> queue, {int? currentIndex});
  Stream<CastCommand> get commands; // play/pause/next/prev/seek/setRepeat/setShuffle
}
```

三实现：`AudioServiceCast`（移动+macOS，用 `BaseAudioHandler` 的 MediaItem/PlaybackState 广播）、`SmtcCast`（Windows）、`MprisCast`（Linux）。每个约 100 行，本质都是"订阅 PlayerCore 状态 → 广播，反向接收命令"。

### 3.2 音源域

```dart
// sources/manifest.dart
enum SourceCapability {
  searchMusic, searchAlbum, searchArtist, searchPlaylist,
  musicUrl, lyric, pic, albumInfo, artistInfo, playlistImport, topList
}

enum SourceKind { lxScript, musicFreePlugin }

class SourceManifest {
  final String id;              // 稳定标识（脚本 hash 或插件 platform+version）
  final String name;
  final String? version, author, description, homepage;
  final SourceKind kind;
  final Set<String> platforms;  // kw/kg/tx/wy/mg/local/<plugin id>
  final Set<Quality> qualities;
  final Set<SourceCapability> capabilities;  // ★ 驱动 UI 降级
  final List<UserVariable> userVariables;    // MusicFree 专属
}

// sources/music_source.dart
abstract interface class MusicSource {
  SourceManifest get manifest;

  Future<SearchResult> search(SearchQuery q);
  Future<List<AlbumInfo>> searchAlbum(String kw, int page);
  Future<List<ArtistInfo>> searchArtist(String kw, int page);
  Future<MusicUrlResult> musicUrl(MusicInfo info, Quality q);
  Future<LyricResult> lyric(MusicInfo info);
  Future<Uri?> pic(MusicInfo info);
  Future<List<MusicInfo>> importPlaylist(String url);

  Future<void> dispose();
}
```

**能力降级规则（必须遵守）**：`manifest.capabilities` 不含 `searchMusic` 时，UI 隐藏该源的搜索入口；不含 `lyric` 时走本地歌词匹配。**任何 `MusicSource` 实现都必须能安全返回"不支持"而非抛异常**——具体用 `UnsupportedError` 还是返回空结果，统一规定：**能力位缺失时调用方不得调用该方法**（由 `aggregator`/UI 依 manifest 判断），实现方对未声明能力抛 `UnsupportedSourceCapability`。

### 3.3 数据模型

```dart
class MusicInfo {
  final String id;            // 源内 ID
  final String sourceKey;     // kw/kg/tx/wy/mg/local/<plugin id>
  final String name;
  final List<String> artists;
  final String? albumName, albumId, picUrl, interval;
  final Map<String, dynamic> raw;  // 保留原始字段，供脚本回传
}

enum Quality { q128k, q320k, flac, flac24bit }  // 字符串值：'128k' '320k' 'flac' 'flac24bit'

class LyricResult {
  final String? lyric, tlyric, rlyric, lxlyric;  // lxlyric 为逐字格式
}

class TrackSource {
  final MusicInfo info;
  final Uri? resolvedUrl;       // 可能延迟解析
  final Map<String, String> headers;
  final Quality quality;
}
```

---

## 4. 音源宿主设计

### 4.1 RuntimeHost（共享基础设施）

一套机制，两个协议适配器复用：

```dart
class RuntimeHost {
  Future<RuntimeInstance> load(String script, {String? storageKey});
}

class RuntimeInstance {
  Future<Manifest> inspect();
  Future<T> invoke<T>(String method, List<dynamic> args, {Duration timeout});
  void dispose();
}
```

**五个必须实现的机制**（照抄 MusicWEP 解法，见 §6）：
1. **实例隔离**：消息通道带 `#$instanceId` 后缀，多实例不串台
2. **串行调用**：`_SerialQueue`，因 QuickJS pending-job 顺序依赖 embedder 串行
3. **单次超时**：默认 15s，超时后实例仍可用（丢弃该次结果，标记 `hasTimedOut`）
4. **脚本只执行一次**：后续 invoke 复用同一 runtime，保留 token/cookie 顶层状态
5. **诊断日志**：console 捕获 + 持久化到文件（每源一个日志文件）

**运行时选择**（flutter_js 平台差异）：

```dart
JavascriptRuntime createRuntime() {
  if (Platform.isWindows || Platform.isLinux || Platform.isAndroid) {
    final rt = QuickJsRuntime2(hostPromiseRejectionHandler: (_) {});
    rt.enableFetch();
    rt.enableHandlePromises();
    return rt;
  }
  return getJavascriptRuntime();  // iOS/macOS → JSC
}
```

### 4.2 lx 协议桥接表（官方规范，已核实于 lxmusic.toside.cn/desktop/custom-source）

| lx API | Dart 实现 |
|---|---|
| `lx.EVENT_NAMES` | 常量对象注入（`inited` / `request` / `updateAlert`） |
| `lx.on(name, handler)` | 注册到 Dart 侧 handler 表，调用时通过 bridge 触发，**必须返回 Promise** |
| `lx.send(name, data)` | bridge 消息 → Dart（`inited` / `updateAlert`） |
| `lx.request(url, opts, cb)` | → dio，支持 method/headers/body/form/formData/timeout；**返回取消函数**；回调 `(err, resp)`，`resp.body` 为响应体 |
| `lx.utils.crypto.aesEncrypt(buf, mode, key, iv)` | pointycastle AES |
| `lx.utils.crypto.md5(str)` | crypto |
| `lx.utils.crypto.randomBytes(n)` | Random.secure |
| `lx.utils.crypto.rsaEncrypt(buf, key)` | pointycastle RSA |
| `lx.utils.buffer.from(...)` | **JS 侧 polyfill + Dart 字节桥**（最大工作量，见 §4.4） |
| `lx.utils.buffer.bufToString(buf, fmt)` | 同上，支持 utf8/hex/base64 |
| `lx.utils.zlib.inflate/deflate` | archive |
| `lx.env = 'desktop'` | 注入常量（本项目统一注入 `'desktop'`，因能力等同桌面版的 Node 环境） |
| `lx.currentScriptInfo.*` | 解析头部注释后注入（name/description/version/author/homepage/rawScript） |

**生命周期**（严格对齐官方语义）：
1. 解析头部 `/** @name @description @version @author @homepage */`（UTF-8）
2. 注入 `globalThis.lx` → 执行脚本
3. 等待 `send(EVENT_NAMES.inited, { sources, openDevTools })` —— **inited 之前任何异常即初始化失败**
4. 校验 `sources[key]`：`type==='music'`；非 local 的 `actions` 必须为 `['musicUrl']`；`qualitys` 取值限于 `128k/320k/flac/flac24bit`
5. 运行期 `on(EVENT_NAMES.request, {source, action, info})` → 返回 Promise
   - `action==='musicUrl'`：`info = {type, musicInfo}`，返回音频 URL 字符串
   - `action==='lyric'`（仅 local）：`info = {musicInfo}`，返回 `{lyric, tlyric, rlyric, lxlyric}`
   - `action==='pic'`（仅 local）：返回封面 URL
6. `updateAlert`（每脚本仅一次）：`{log, updateUrl}` → 弹窗提示用户更新源

### 4.3 lx 源的能力边界（必须理解）

**lx 自定义源脚本只提供 `musicUrl`（local 源额外提供 lyric/pic）。搜索、榜单、歌单导入全部由 App 内置 API 提供，与脚本无关。**

推论：要实现"lx 全部功能"，必须自己移植 lx 的内置官方源 API（kw/kg/tx/wy/mg 的搜索/榜单/歌单/详情），这部分在 lx-music-desktop 源码中，Apache-2.0 允许参考移植，但是实打实的工作量（§8 M6 列为独立里程碑）。

**因此本项目音源策略为**：
1. **MusicFree 插件 = 主生态**（自带搜索/详情/歌词，用户装插件即全功能）
2. **lx 脚本 = 兼容层**（只能播放，搜不到的歌曲用 MusicFree 插件或内置 API 补）
3. **lx 内置官方 API = 可选补齐**（M6，决定是否让 lx 脚本用户也能搜索）

### 4.4 Buffer polyfill（最大技术风险）

lx 脚本大量使用 `lx.utils.buffer` 做 hex/base64/字节运算，QuickJS 无 Node Buffer。需要：
- Dart 侧：`Uint8List` 桥（`from(array/hex/base64/utf8)`、`bufToString(buf,'hex'|'base64'|'utf8')`）
- JS 侧：暴露 `buffer` 对象 + 少量常用方法（`byteLength`、`concat`、`slice`、`writeUInt32BE` 等按需补）

**策略**：先实现最小集（`from` / `bufToString` / `concat` / `slice`），在 spike 中按真实脚本报错逐步补。不要试图一次实现完整 Node Buffer API。

### 4.5 MusicFree 插件协议

模块导出式，能力完整。插件对象字段（已从 MusicWEP inspect 实现核实）：`platform, version, appVersion, author, description, srcUrl, supportedMethods, supportedSearchType, userVariables`。

> **待核实**：具体方法名（`search` / `getMediaSource` / `getLyric` / `getAlbumInfo` / `getArtistInfo` / `getTopLists` / `importMusicSheet` 等）以 MusicFree 官方插件文档与真实插件为准，M3 阶段用 3-5 个官方仓库插件实测确认，不要凭记忆写死。

需要的 JS 侧 shim 清单（MusicWEP 已验证可行）：`axios` `cheerio` `crypto-js` `dayjs` `big-integer` `qs` `he` `webdav` `@react-native-cookies/cookies` `musicfree/storage`。

桥接策略：
- `axios` → Dart dio 桥（保留 `get/post`、`headers`、`params`、`data`、`timeout` 语义）
- `crypto-js` → pointycastle 桥（MD5/SHA/AES/HmacMD5 等常用子集）
- `qs` / `he` / `dayjs` / `big-integer` → 纯 JS polyfill（不经过 Dart，性能更好）
- `cheerio` → Dart `html` 包桥（选择器子集）或内嵌轻量 JS 实现；先用 `html` 包桥，不够再议
- `webdav` → 可选，首期可返回"不支持"

### 4.6 多源搜索聚合（aggregator）

```dart
class SourceAggregator {
  // 对所有"已启用且声明 searchMusic"的源并发搜索
  Stream<SourceSearchChunk> search(SearchQuery q);
}
```

规则：
- **并发扇出**，每源独立超时（默认 10s），单源失败不影响其他源
- **渐进式返回**：哪个源先回就先展示（`Stream` 而非等全部）
- **分组展示**（默认按源分组），不做跨源去重合并（各源 ID 体系不同，强行合并会断播放）
- 提供"聚合视图"选项：按 `name + artists` 归一化做**弱去重**，仅用于展示，点播时仍回到具体源
- 分页：每源独立页码，UI 记住每源游标

### 4.7 源健康度与降级

```dart
enum SourceHealth { unknown, healthy, degraded, broken }
```

- 连续失败 3 次 → `degraded`（UI 标注"可能失效"，仍可尝试）
- 初始化失败 → `broken`（列表置灰，展示诊断信息与最后错误）
- 记录 `lastError / lastCheckedAt / failureCount` 到 `sources` 表
- 提供"重新检测"按钮，手动重置状态

---

## 5. 歌词域设计

### 5.1 支持格式

| 格式 | 特性 | 来源 |
|---|---|---|
| 标准 LRC | 逐行 `[mm:ss.xx]text` | 本地文件 / 内嵌 / 在线 |
| 增强 LRC | 逐行 + 翻译/罗马音（同时间戳多行） | 同上 |
| lxlyric | 逐字 `[mm:ss.mmm]<start,dur>字<start,dur>字...` | lx 源脚本返回 |
| QRC | 逐字（QQ 音乐格式，含加密变体） | 在线获取 |
| KRC | 逐字（酷狗格式，含加密变体） | 在线获取 |
| YRC | 逐字（网易格式） | 在线获取 |

### 5.2 内部统一模型

```dart
class LyricDocument {
  final List<LyricLine> lines;
  final List<LyricLine>? translation;
  final List<LyricLine>? romanization;
}
class LyricLine {
  final Duration start;
  final Duration? end;
  final String text;
  final List<LyricWord>? words;  // 逐字时非空
}
class LyricWord { final Duration start; final Duration duration; final String text; }
```

解析器统一输出 `LyricDocument`，渲染层只认这个模型。**增强 LRC 的三行同时间戳规则**（栖弦 README 已总结，可直接照做）：
- 同时间戳三行 → 第 1 行注音、第 2 行原文、第 3 行翻译
- 单行含 `" / "` → 前半原文、后半翻译

### 5.3 歌词获取优先级
1. 本地同目录同名文件（`.qrc`/`.krc`/`.yrc` 优先，`.lrc` 次之）
2. 音频文件内嵌标签
3. 音源脚本/插件返回
4. 在线匹配服务（可选，M6）

### 5.4 同步与渲染
`LyricSync`：给定 `position`，二分查找当前行 + 逐字时按 `words` 计算进度（0..1），输出 `(lineIndex, wordIndex, wordProgress)`。UI 只订阅这个流，不自己算时间。

### 5.5 桌面歌词窗口
- 独立窗口（`desktop_multi_window`），无边框 + 置顶 + 可拖动 + 穿透点击可选
- 水平/垂直两种排布
- 与主窗口通过 method channel 或本地端口同步当前行
- 关闭主窗口时歌词窗行为可配置（跟随关闭 / 保留）

---

## 6. 下载域设计

```dart
class DownloadTask {
  final String id;
  final MusicInfo info;
  final Quality quality;
  final Uri? sourceUrl;
  final DownloadStatus status;  // queued/running/paused/completed/failed
  final int received, total;
  final int retryCount;
  final String? error;
}
```

- **并发上限 3**（可配置 1-5），超出排队
- 断点续传：HTTP Range，失败保留 `.part` 文件
- 重试：指数退避，最多 3 次；URL 过期时重新调用 `musicUrl` 拿新链接
- 完成后可选写入元数据（`audio_metadata_reader` 写歌名/歌手/专辑/封面/歌词）
- 命名规则：`{歌手} - {歌名}.{ext}`，冲突时追加序号
- 持久化到 `download_tasks` 表，重启后恢复队列（running → queued）

---

## 7. 数据持久化（drift schema 要点）

| 表 | 关键字段 |
|---|---|
| `tracks` | id, sourceKey, sourceTrackId, name, artists(json), albumName, albumId, picUrl, interval, localPath, addedAt |
| `playlists` | id, name, coverUrl, createdAt, sortOrder |
| `playlist_items` | playlistId, trackId, position |
| `download_tasks` | id, trackId, quality, status, received, total, retryCount, error, createdAt |
| `play_history` | trackId, playedAt, playDurationMs |
| `sources` | id, kind, name, version, scriptPath, capabilities(json), enabled, health, failureCount, lastError, lastCheckedAt, userVariables(json) |
| `user_variables_values` | sourceId, key, value（加密存储敏感项） |

迁移策略：drift `schemaVersion` 递增 + 显式 `MigrationStrategy`，每次结构变更必须写迁移并在 M0 建立迁移测试。

---

## 8. 错误处理与降级矩阵

| 场景 | 行为 |
|---|---|
| 源脚本初始化失败 | 标记 `broken`，源列表展示错误与诊断日志入口，不影响其他源 |
| 单次脚本调用超时（15s） | 标记 `hasTimedOut`，本次请求返回失败，实例保留；连续 3 次 → `degraded` |
| 音源未返回 URL / URL 失效（403/404） | 触发 `_retryAfterSourceFailure`，UI 显示"换源重试"，可手动切换其他源 |
| 播放加载超时 | 远程流 2s、本地文件 40s（栖弦的分级策略，直接沿用）；超时后 `stop()` 并抛 `PlayerLoadTimeout` |
| 切歌中途失败 | 回滚到上一首 + `processingState.error` + 显示错误 |
| 网络断开 | HTTP 层统一捕获，退避重试 3 次，仍失败则提示离线 |
| 源能力缺失 | UI 依 `manifest.capabilities` 隐藏入口，**不调用**该方法 |
| 歌词解析失败 | 降级为无歌词，不阻塞播放 |
| 数据库迁移失败 | 备份旧库为 `.bak` 并重建，提示用户 |

---

## 9. 测试策略

### 9.1 单元测试（纯 Dart，CI 必跑）
- 歌词解析：LRC / 增强 LRC / lxlyric / QRC / KRC / YRC 各 3+ 用例（含边界：空行、乱序时间戳、无翻译）
- `LyricSync` 时间轴计算：给定 position 断言行/字索引
- `PlayerCore` 状态机：用 `FakeAudioEngine` 驱动，覆盖切歌成功/失败回滚/世代守卫/重试
- `SourceManifest` 解析（lx 头部注释、能力位推导）
- 队列/shuffle/repeat 逻辑

### 9.2 集成测试（需 flutter_js 运行时）
- 用**固定 fixture 脚本**（不依赖外网）验证 RuntimeHost：注入桥、inited 握手、超时、串行、实例隔离、`\<` 转义修复
- 用 fake HTTP bridge 验证 `lx.request` 语义与取消函数

### 9.3 手工验证矩阵（每里程碑必过）
| 项 | Android | iOS | macOS | Windows | Linux |
|---|---|---|---|---|---|
| 本地播放 | ✓ | ✓ | ✓ | ✓ | ✓ |
| HTTP 播放（自定义 header） | ✓ | ✓ | ✓ | ✓ | ✓ |
| gapless 切歌 | ✓ | ✓ | ✓ | ✓ | ✓ |
| 后台/锁屏控制 | ✓ | ✓ | — | — | — |
| SMTC / MPRIS | — | — | 通知中心 | SMTC | MPRIS |
| 音源脚本加载 | ✓ | ✓ | ✓ | ✓ | ✓ |
| 桌面歌词窗 | — | — | ✓ | ✓ | ✓ |

### 9.4 真实脚本回归（M2/M3 出口条件）
维护一份**不随代码分发**的测试脚本清单（≥10 个真实流行 lx 脚本、≥5 个 MusicFree 插件），记录通过/失败与失败原因。**这是唯一能证明 QuickJS 兼容性的方式，不可省略。**

---

## 10. 构建与发布

| 平台 | 命令 | 附加要求 |
|---|---|---|
| Android | `flutter build apk --release --split-per-abi` | 签名 keystore；`usesCleartextTraffic` 视需求 |
| iOS | `flutter build ipa` | 开发者账号；`UIBackgroundModes: audio` |
| macOS | `flutter build macos --release` | entitlements：`network.client`、文件访问；签名+公证 |
| Windows | `flutter build windows --release` | VS2022 + C++ ATL（secure_storage）+ **CMake**（media_kit 下载预编译 libmpv）；**不需要 rustup**（ADR-012）；Inno Setup 或 MSIX |
| Linux | `flutter build linux --release` | `libmpv-dev`、`libsecret-1-dev`；打包需带 libmpv 或声明依赖 |

CI：GitHub Actions 五端矩阵，至少跑 `flutter analyze` + `flutter test` + 各平台 `build`（Linux/Windows 可只在 PR 跑）。

---

## 11. 已知坑与解法（照抄即可）

| 坑 | 现象 | 解法 | 参考位置 |
|---|---|---|---|
| QuickJS 严格正则转义 | `\<` `\>` 在 V8 静默通过，QuickJS 报 `SyntaxError: unexpected token '<'` | 执行前 `script.replaceAll(r'\<','<').replaceAll(r'\>','>')` | MusicWEP `core/runtime/plugin_runtime_instance.dart` |
| 多插件消息串台 | 两个源同时调用 bridge 时数据错乱 | 通道名加 `#$instanceId` 后缀，运行时改写 `sendMessage` | 同上 |
| 并发调用导致 QuickJS 乱序 | 偶发 Promise 不 resolve | 每实例 `_SerialQueue` 串行 | 同上 |
| 单次调用挂死 | 脚本死循环**永久阻塞引擎**（H6 实测：同步 evaluate 不可中断） | **isolate 池执行每次脚本调用**，超时杀 isolate 重建实例；宿主不受影响 | spike-lx.md §2 H6 |
| gapless 桌面表现 | 切歌有间隙 | media_kit 原生支持；勿用 just_audio 桌面路径 | §1.2 |
| macOS 网络权限 | 请求失败 | entitlements 加 `com.apple.security.network.client`；沙盒关闭以访问任意目录 | media_kit README |
| Windows 浮层 seek 失效 | 任务栏浮层进度条不动或不回传 | fms 的 `UpdateTimelineProperties` 需随播放持续推送（其 C++ L405-461 为完整参考）；`SeekTo` 走 `setActionHandler` 回调 | ADR-014 + fms 源码 `windows/flutter_media_session_plugin.cpp` |
| Linux libmpv | 运行时找不到库 | 打包随附或提示安装 `libmpv2` | media_kit README |
| flutter_secure_storage macOS | 写入成功但读不到 | 不需 App Group 时用 `MacOsOptions(usesDataProtectionKeychain: false)` 避免 keychain-sharing provisioning 需求 | pub.dev/packages/flutter_secure_storage |
| home_widget 仅 A+iOS | 桌面端调用报错 | 桌面分支不初始化，UI 隐藏入口 | pub.dev 平台声明 |

---

## 12. 参考实现索引（按需抄，注意许可）

| 要做的事 | 参考仓库 | 具体位置 | 许可 |
|---|---|---|---|
| lx 协议规范 | lyswhut/lx-music-desktop | 官方文档 `custom-source` 页 / `lxmusic.toside.cn` | Apache-2.0（可参考移植） |
| 播放状态机 / 世代守卫 / 切歌回滚 / 加载超时分级 | KevinllBin/CyShineMusic | `lib/features/player/player_audio_handler.dart` | **MIT（可抄）** |
| 逐字歌词解析与渲染、主题、业务 UI | 同上 | `lib/features/`、`lib/theme/` | **MIT（可抄）** |
| 五端播放 + 桌面集成工程化 | namidaco/namida | `pubspec.yaml` 中 media_kit / smtc_windows / window_manager / basic_audio_handler 用法；**注意它用了 smtc_windows（带 Rust），本项目不跟这一点** | 需核查（LICENSE 为 NOASSERTION，逐文件确认） |
| JS 宿主工程化（隔离/超时/串行/转义/包 shim） | WEP-56/MusicWEP | `flutter_app/lib/core/runtime/` | **AGPL，只读思路，不得抄代码** |
| MusicFree 插件协议与 shim 清单 | 同上 + maotoumao/MusicFree 插件文档 | 同上 | **AGPL，只读** |
| Desktop 音频引擎（若日后要 WASAPI/均衡器） | Empty-57/ZeroBit-Player | Rust+BASS 集成 | **GPL，只读** |
| 桌面歌词窗口 | lx-music-desktop | 独立 renderer 思路 | Apache-2.0 |

> **执行提醒**：每次引用参考实现，先确认该仓库 LICENSE；AGPL/GPL 只提取"协议规则"和"工程思路"，代码必须自己重写。

---

## 13. 实施里程碑与验收标准

### M0 · 骨架（2 天）
- `flutter create` 五端 + §2 目录 + §1.1 依赖
- 建立 drift schema 与迁移测试骨架
- 验收：`flutter analyze` 零告警；五端 `flutter build` 通过（不含业务）

### M1 · 播放域（1.5 周）
- PlayerCore + MediaKitEngine + 三 Cast + FocusPolicy 双实现
- 验收：
  - 五端均可播放本地文件与 HTTP URL（带自定义 header）
  - 播放/暂停/seek/倍速/gapless/shuffle 全部正常
  - 断网切歌失败能回滚并显示错误，恢复网络可重试
  - Android 来电暂停/结束恢复；macOS 通知中心；Windows SMTC；Linux MPRIS

### M2 · 音源宿主 + lx（2 周）★ 关键路径
- **✅ spike 已完成（2026-10-29）：有条件成立，见 docs/spike-lx.md**——剩余：补齐完整 lx API 面、六音类脚本初始化定位、载荷结构采用 info.musicInfo/info.type
- spike 通过后补齐 Buffer polyfill、zlib、crypto 桥
- 验收：10+ 真实 lx 脚本可导入、显示元信息、成功取 musicUrl；死循环被 15s 拦截；多源并发无串台

> **决策点 D1**：spike 失败率 > 30% → 改双轨：Android 保留原生 QuickJS（参考栖弦 `music_source_runtime`，MIT 可抄），桌面用 flutter_js，统一到 `MusicSource` 接口后。

### M3 · MusicFree 插件（1 周）
- 包 shim + 适配器；**先核实真实插件方法名**（§4.5 待核实项）
- 验收：官方插件仓库 5 个插件可完整搜索/播放/取歌词封面；`userVariables` 可配置

### M4 · 业务 UI（2-3 周，可从栖弦移植 MIT 代码）
- 搜索（含 §4.6 聚合）/ 歌单 / 下载队列 / 本地库 / 逐字歌词 / 主题
- 验收：功能对齐 lx-music 移动版；UI 无平台分支

### M5 · 桌面形态（1 周）
- 桌面歌词窗 / 托盘 / 窗口状态记忆 / 应用内快捷键（Space/←→/↑↓，Flutter Shortcuts 零依赖）
- 验收：macOS 与 Windows 均可用；关窗到托盘；歌词窗置顶无边框可拖动；媒体键经系统媒体层可控
- ~~全局快捷键~~（2026-10-29 裁剪：媒体键经 fms/SMTC 天然可用，自定义全局热键延后，见 M6）

### M6 · 可选补齐
- lx 内置官方源 API 移植（**若不做，用户装 lx 脚本只能播放不能搜索**，见 §4.3）
- 数据同步服务、开放 API（shelf）、Scheme URL、全局自定义快捷键（super_hot_key，若用户反馈需要）

**关键路径**：M2 的 spike。它决定整个音源策略，应最先验证。

---

## 14. 第一周行动清单（给接手的 AI）

1. `flutter create --platforms=android,ios,macos,windows,linux --org <your.org> aiwli_music`
2. 按 §1.1 写 pubspec，`flutter pub get`，逐平台 `flutter build` 验证依赖无冲突
3. 建 §2 目录骨架，写空实现（保证 `flutter analyze` 通过）
4. 定义 §3 全部接口与数据模型（不实现）
5. 建 drift schema + 迁移测试（§7）
6. **开始 M2 spike**：最小 flutter_js 工程，注入 `globalThis.lx` 的 `request/on/send` 三个桥 + 最小 buffer，跑 §附录A 的脚本
7. ✅ **已完成（2026-10-29）**：报告见 spike_lx/docs/spike-lx.md 与仓库 docs/spike-lx.md——**主路径有条件成立（60–90% 档）**，按其 §6 行动清单推进

---

## 15. 环境要求
- Flutter stable（**M0 实测：3.47.8 stable / Dart 3.13.7 全部依赖解析通过**，puro env）
- Dart ≥3.13（aiwli_git 同约束，两项目统一工具链）
- Windows 构建：VS2022 + C++ ATL（flutter_secure_storage）+ CMake（media_kit 拉预编译 libmpv）。**不需要 rustup**——SMTC 走纯 Dart `win32`（ADR-012）
- macOS 构建：Xcode 15+；公证需 Apple Developer
- Linux 构建：`libmpv-dev`、`libsecret-1-dev`

---

## 16. 待决问题（交接时需向发起人确认）

| ID | 问题 | 影响 | 建议默认 |
|---|---|---|---|
| Q1 | 是否商用？ | 决定能否参考 AGPL 生态、是否需完全自研音源协议实现 | 默认非商用；若商用，MusicWEP/MusicFree/any-listen 仅作思路参考 |
| Q2 | 是否要做 M6（lx 内置官方 API 移植）？ | 决定"装 lx 脚本能否搜索" | 先做 MusicFree 主生态，M6 延后决策 |
| Q3 | 是否要 iOS？（涉及后台音频、上架审核） | 增加 M1/M5 工作量 | 默认做 |
| Q4 | 内置源是否要预置（如社区规则） | 涉及合规 | 默认不预置，仅用户自行导入 |
| Q5 | 数据同步用自建服务还是 WebDAV？ | M6 范围 | 默认先不做 |

---

## 附录 A：lx 源脚本最小示例（用于 spike 测试）

```js
/**
 * @name 测试源
 * @description spike 用
 * @version 1.0.0
 * @author spike
 */
const { EVENT_NAMES, request, on, send } = globalThis.lx

const httpRequest = (url, options) => new Promise((resolve, reject) => {
  request(url, options, (err, resp) => {
    if (err) return reject(err)
    resolve(resp.body)
  })
})

const apis = {
  kw: {
    musicUrl({ songmid }, quality) {
      return httpRequest('https://example.com/x').then(d => d.url)
    },
  },
  local: {
    musicUrl(info) { return httpRequest('https://example.com/x').then(d => d.url) },
    lyric(info) { return httpRequest('https://example.com/y').then(d => ({ lyric: d.l, tlyric: null, rlyric: null, lxlyric: null })) },
    pic(info) { return httpRequest('https://example.com/z').then(d => d.url) },
  },
}

on(EVENT_NAMES.request, ({ source, action, info }) => {
  switch (action) {
    case 'musicUrl': return apis[source].musicUrl(info.musicInfo, info.type)
    case 'lyric': return apis[source].lyric(info.musicInfo)
    case 'pic': return apis[source].pic(info.musicInfo)
  }
})

send(EVENT_NAMES.inited, {
  openDevTools: false,
  sources: {
    kw: { name: '酷我', type: 'music', actions: ['musicUrl'], qualitys: ['128k','320k','flac','flac24bit'] },
    local: { name: '本地', type: 'music', actions: ['musicUrl','lyric','pic'], qualitys: [] },
  },
})
```

---

## 附录 B：术语

- **lx 源脚本**：洛雪自定义源，事件收发协议，能力仅 `musicUrl`（local 源另有 lyric/pic）
- **MusicFree 插件**：模块导出协议，能力完整（搜索/详情/歌词/封面）
- **any-listen 扩展**：lx 源脚本的隔离进程容器形态，非新协议
- **RuntimeHost**：本项目对 flutter_js 的封装，共享给两种协议
- **Cast**：媒体会话广播（通知栏/SMTC/MPRIS）
- **FocusPolicy**：音频焦点与中断策略（手机有、桌面空实现）
- **能力位（capability）**：源支持的功能声明，驱动 UI 降级