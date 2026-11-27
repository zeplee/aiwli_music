# AiwliMusic 播放链路修复与功能补全实现规格

**版本** v1.0 · 2026-11-27 · 状态：施工依据
**适用范围**：v1.3.6（`aade1fb`）之后的修复批次
**读者**：本工程后续实现者（人类或 AI）。本文自包含，不需要回看对话。

本文不替代 `aiwli-music-design.md` / `ui-spec-aiwli-music.md`。那两份定义**应该是什么**；
本文定义**当前哪里坏了、怎么修、修完怎么验**。冲突时，架构与交互以原有两份文档为准，
本文只补充本次修复批次的实施细节。

---

## 0. 硬约束（违反即返工）

1. **零新增 pub 依赖**。只用工程已有包。`pubspec.yaml` 只允许版本号变更（见 §7）。
2. **五端不变**：Android / iOS / Linux / macOS / Windows。平台判断只允许在
   `lib/platform/**` 与 `main.dart`；业务层按尺寸断点分叉，不按 OS。
   本次修复**不新增任何平台分支**。
3. **播放引擎保持 media_kit**；**零内置取链**，播放取链只走 lx / MusicFree 脚本，
   内置 SDK 仅用于浏览（榜单/搜索/歌词/评论/分类/歌单曲目）。
4. **沿用现有交互范式**：三 Tab 外壳 + 全局迷你播放条 + 二级页 `Navigator.push`；
   Riverpod provider 集中在 `lib/app_providers.dart`；`SettingsStore` 原子写；
   玻璃页内可点区域必须用 `GlassTap`（`GlassContainer` 不是 Material 祖先，
   直接放 `InkWell` 会抛 `No Material widget found`）。
5. **UI 效果服从功能**：不引入 `prism_ui` / `heroine` / `bass_player` /
   `audio_service`（栖弦 patched 版）/ `music_source_runtime` / `music_home_widget` /
   `cached_network_image`。液态玻璃继续用 `liquid_glass_widgets 1.17.2`。
   理由见 `docs/dependency-evidence.md` 与本批次的依赖审计结论。
6. **不写复刻式测试**：新增测试必须 `import` 真实现并断言真实行为，
   禁止把生产逻辑复制一份到测试文件里再测副本。
7. **不擅自改变用户可见交互**：修复以「让现有交互合理顺畅」为目标，
   不新增导航层级、不替换控件体系、不重排既有页面。

---

## 1. 诊断结论（已核实的代码事实）

以下均为 2026-11-27 只读审计的确证结论，附文件:行号。

### 1.1 「有时候音乐不播放」

| # | 根因 | 位置 | 触发与表现 |
|---|---|---|---|
| P0-1 | `interruptionEnd` 是死代码：音频焦点策略只发 begin/duck，全工程无产生者 | `lib/player/audio_focus_policy.dart:42-49`、`lib/player/player_core.dart:130-142` | 来电/微信语音/导航播报/耳机中断结束后音乐一直暂停，必须手动点播放 |
| P0-2 | 音质降级只往更高档找，选无损/Hi-Res 时候选源清零 | `lib/core/models/quality_rank.dart:63-75`、`lib/player/playback_resolver.dart:429-439` | 设置高档音质后点播直接失败，切回标准音质即好 |
| P0-3 | 换源成功后 `_fallbackDone` 布尔标志把同一首歌后续真实错误全部吞掉 | `lib/player/player_core.dart:361-375` | 界面显示「正在播放」却无声、无红条、无日志 |
| P0-4 | 缓存命中时 `winnerId` 写成平台名，死源拉黑键永远匹配不上 | `lib/player/playback_resolver.dart:245-254` | 10 分钟缓存期内同一首歌反复踩同一个死链 |
| P0-5 | 非致命错误白名单优先于致命判定，「Failed to open … unknown format」被忽略 | `lib/player/media_kit_engine.dart:50-76` | 不换源、停在 loading 无声 |
| P0-6 | mpv `network-timeout=60`，且空 catch 包住 | `lib/player/media_kit_engine.dart:211-229` | 源站连上但不吐数据，长时间转圈 |
| P0-7 | 冷启动脚本 `waitInited()` 失败被空 catch 吞掉 | `lib/player/playback_resolver.dart:548-553` | 首播失败、过会儿再点又能播 |
| P0-8 | 并发胜出后对所有输家 `cancelPending()` 触发 JS 引擎重建 | `lib/player/playback_resolver.dart:511-513`、`lib/sources/runtime/runtime_host.dart:474-479` | 快速连点下一首时撞上重建窗口，延迟 5–8s 或取不到链 |
| P1 | `play()` 丢弃焦点获取结果，且先写 `playing:true` 再调引擎 | `lib/player/player_core.dart:557-562` | UI 显示播放中但无声 |

注：初版诊断曾怀疑 `pubspec.lock` 中 `audio_session` 为 0.1.3，复核后确认
`0.1.3` 属于相邻包，`audio_session` 实际锁定 `0.2.4`，与声明一致，无需改动。

已排除：`setQueue` 后未 play（`player_core.dart:397 → 456` 会自动 play）；
PlayerCore 被 Riverpod 重建（已单例）；media_kit 未初始化（有守卫）。

### 1.2 「评论只展示一页」

- `lib/sources/builtin/comment_sdk.dart:95`：`?limit=30&offset=0`，**offset 写死**，
  `fetch()` 无 page/cursor 参数。
- `:112-121`：`hotComments` 与 `comments` **二选一**，不合并。热门歌曲只显示 15 条热评，
  几百条普通评论不可见。
- `lib/app_providers.dart:299-304`：`CommentState` 无 `hasMore/offset/total`；
  `:312-327` `fetchFor` 不传分页参数；`:315` 同 key 且列表非空直接 return（无刷新路径）。
- `lib/features/player/player_page.dart:1114`：`ListView.separated` 无 ScrollController、
  无 NotificationListener、无加载更多、无到底提示。
- 切歌竞态：`:1052-1069` 只更新 `_key` 发新请求，不清空旧列表；
  `app_providers.dart:328` 的 key 守卫只在响应回来后生效 → 旧歌评论可能覆盖新歌并污染缓存。
- 错误混淆：网络超时 / JSON 解析失败 / 接口风控 / 确实无评论 → 统一显示
  「评论加载失败 · 换个音源试试」（而换音源仍走同一个网易接口）。
- `test/` 中 `comment` 关键词**零命中**：评论链路零测试。

### 1.3 「通知栏有时候全黑」

- `lib/player/player_core.dart:212`：`cast.init()` **未 await**，紧接着 `:230` `_pushToCast()`；
  `lib/player/cast/fms_cast.dart:42,68,84` 的 `_activated` 要等 `activate()` +
  `setAutoHandleInterruptions` + `setBackgroundKeepAlive` 三个 await 完成才为 true，
  未激活时 `updateNowPlaying` / `updatePlayback` 静默 `return`。
  `player_core.dart:251` 在推送**之前**就写 `_lastCastKey` → 该曲整个生命周期不再重推。
  这解释了「有时候」：取决于冷启动时 `activate()` 与首次状态推送的先后。
- 插件侧核实：`flutter_media_session-3.0.9` 有 `pendingMetadata` 兜底，
  但工程 Dart 层直接 `return`，插件连兜底都收不到。
- `lib/player/player_core.dart:57-62`：`PlayerItem.metadata` 只透传 `artUri`，
  **完全忽略 `artBytes`**；而本地歌曲（`lib/features/library/library_page.dart:209-218`）
  只设 `artBytes` 不设 `artUri` → 通知栏 artworkUri 恒 null。
  插件 Android 端 `MediaMetadata.Builder().setArtworkUri(...)` 无自定义 BitmapLoader、
  无默认占位图 → 大图黑/空。表现：**App 内有封面、通知栏全黑**。
- 网络封面：`Uri.tryParse` 失败静默返回 null、封面 URL 需 Referer、SVG 无法解码，
  同样落到黑洞。
- `PlayerItem.metadata` 还漏传 `album`（`fms_cast.dart:72` 的 `album` 恒 null）。
- **排除**：权限没问题。插件 manifest 自带 `POST_NOTIFICATIONS` /
  `FOREGROUND_SERVICE_MEDIA_PLAYBACK` / `WAKE_LOCK`，会合并进 App。

### 1.4 其他交互细节缺陷

| 问题 | 位置 | 表现 |
|---|---|---|
| 清空队列后声音继续播 | `player_core.dart:189-193`（只改 state 不 `pause()`） | mini player 消失但还在响 |
| 定时关闭「播完当前首」只改 UI 不停引擎，标志不复位 | `player_core.dart:382-385`、`sleep_timer.dart:44-50` | 通知栏显示暂停却仍有声；后续新歌结尾也自动停 |
| 进度条拖动回弹 / 串到新歌 | `player_page.dart:755-758,669,675` | 滑块跳回原位；切歌后新歌从旧位置开始 |
| seek 后通知栏进度不同步 | `player_core.dart:569`（不推 cast，去重 key 不含 position） | 锁屏进度停在旧位置 |
| 随机/单曲循环语义错 | `models.dart:49-52`（`RepeatMode.all` 反推成「播完停」），`play_mode_test.dart:56-57` 锁死了错误映射 | 图标写循环但播完即停 |
| K 歌伴奏竞态 | `player_page.dart:516-564`（await 前捕获旧 item、缺二次 `mounted`、失败无回滚） | 点 K 歌后立刻切歌，当前曲被换成上一首的伴奏 |
| SleepTimer Timer 泄漏 | `sleep_timer.dart:12,33-40` + `safe_notifier.dart:16-18`（dispose 不取消 Timer） | 热重启后「没设定时，播着播着自己停了」 |
| 播放键连点失灵 | `player_page.dart:628`、`mini_player_bar.dart:88`（用 build 时捕获的 playing） | 双击变成两次 play |
| WebDAV 重复 load | `lib/features/mine/webdav_page.dart:101-102` | 上传前重复读取，影响一致性 |

### 1.5 测试守不住（系统性隐患）

`player_cast_e2e_test.dart` 用立即就绪的假 Cast（测不到 init 竞态），只测「换源成功后
error=null」，未测「成功后再次失败」；评论零测试；`transport_centering_test.dart`、
`seekbar_geometry_test.dart`、`karaoke_filter_test.dart`、`search_tabs_order_test.dart`
等是复刻式假实现。`dart_test.yaml` 把 7 个 `@Tags(['network'])` 文件整体跳过，
连其中不需要网络的纯逻辑用例也一起跳了。

---

## 2. 修复方案（按依赖顺序）

### 批次 A · 播放链路 P0

| 项 | 改法 | 文件 |
|---|---|---|
| A1 焦点恢复 | `AudioFocusPolicy` 正确产生 `interruptionEnd` / `duckEnd`；`PlayerCore` 用它恢复播放并复位 `_wasPlayingBeforeInterruption`。`audio_session` 锁版本经复核无误，不改 | `lib/player/audio_focus_policy.dart`、`lib/player/player_core.dart` |
| A2 cast 初始化 | `init()` 改为可 await 并等待完成；`_lastCastKey` **只在推送成功后写**；激活完成后强制重推一次当前曲 | `lib/player/player_core.dart`、`lib/player/cast/fms_cast.dart`、`lib/player/media_session_cast.dart` |
| A3 封面 | `artBytes` 落成本地缓存文件后转 `file://` URI 传给 `artworkUri`（插件 `MediaMetadata` 只收 URI）；补传 `album`；网络封面失败时提供兜底（不引新包，复用现有占位图资源或本地文件） | `lib/player/player_core.dart`、`lib/player/models.dart`、`lib/player/cast/fms_cast.dart` |
| A4 取链稳定性 | `_fallbackDone` 布尔改成「本次错误是否属于已救回的旧 URL」的归属判断；音质降级方向修正（允许向低档找）；缓存命中保留真实 `winnerId`；`network-timeout` 降到 15s；非致命白名单改为「先判致命、再判 benign」；冷启动 `waitInited` 失败写日志并允许重试；`cancelPending` 不波及后续请求 | `lib/player/player_core.dart`、`lib/player/playback_resolver.dart`、`lib/core/models/quality_rank.dart`、`lib/player/media_kit_engine.dart` |
| A5 错误可观测 | 取链失败、换源失败、封面加载失败都写 `AppLog.w/e`；UI 保留现有红条语义，只补「真失败」的可见提示 | 同上 + `lib/features/player/player_page.dart` |

### 批次 B · 评论

- `CommentSdk.fetch` 增加 `offset`，返回 `hasMore/total`；`hot` 与 `normal` 合并去重
  （或提供切换，但默认必须能看到普通评论）。
- `CommentState` 增 `offset/hasMore/loadingMore/errorKind`；`CommentService` 增
  `loadMore()` 与 `refresh()`，用 requestId 守卫替代字符串 key 守卫。
- 切歌时立即清空 items；`_CommentsPage` 加 ScrollController 触发加载更多，
  底部显示「加载中 / 已到底 / 加载失败可重试」。
- 错误分三类文案：确实无评论 / 网络失败 / 解析失败，不再一律「换个音源试试」。
- 保持现有评论 Tab 位置与布局，不新增导航层级。

### 批次 C · 交互细节

清空队列真停引擎并 reset index；定时关闭真 `pause()` 且标志在下一首前复位；
进度拖动用「拖动中锁 + seek 完成后再解锁」，`_dragValue` 随切歌清零；
`seek()` 推一次 cast（去重 key 加 position 或单独调用）；循环模式语义与图标对齐
（同时修正 `play_mode_test.dart` 的错误断言）；K 歌用当前曲校验 + 二次 `mounted` +
替换失败回滚；`SleepTimerService.dispose()` 取消 Timer；播放键用读时状态并加防连点；
WebDAV 去掉重复 load。

### 批次 D · 功能补全（沿用现有交互，零新依赖）

| 功能 | 落点 | 说明 |
|---|---|---|
| 下载队列 + 历史 | `lib/core/services/download_queue.dart`（新，纯 Dart）+ `lib/app_providers.dart` 的 DownloadManager 委托 + `lib/features/downloads/downloads_page.dart` 双 Tab | 并发上限 2、入队去重、pause/resume/retry/remove/clearFinished；暂停真中断流式下载（CancelToken）；保持现有 MediaStore 落库链路 |
| 搜索联想 + 批量 | `lib/features/search/widgets/search_suggestions.dart`（新纯函数）+ `search_page.dart` | 250ms 防抖，只从本地历史/已有结果匹配，不新增网络请求；结果多选 → 加入歌单 / 批量下载；补「部分源失败 + 重试」 |
| 在线歌单增强 | `lib/features/discover/online_playlist_page.dart` | 详情内搜索过滤、多选、播放选中 / 批量下载 / 加入歌单、收藏整张歌单（`PlaylistService.create()` + `addEntries()`）、随机播放；保留酷我「暂不支持展开」空态 |
| 设置偏好 | `lib/core/services/app_settings.dart`（加 5 个字段，沿用 `SafeNotifier` + `SettingsStore.flush`）+ `lib/features/mine/settings_prefs_page.dart`（新）+ `mine_page.dart` 入口 | 默认搜索平台 / 启用搜索源（至少 1 个）/ 点击结果行为 / 下载音质（`Quality`）/ 文件命名；`toJson/fromJson` 纯函数 + 剪贴板文本导入导出；非法值逐字段回退 |

**明确不做**（Android 专属或需原生库，会破五端）：蓝牙歌词、车机/Pad 适配、
桌面小组件、vivo 系统对接、EQ 预设导入导出（如后续确认纯 Dart 可另议）。

---

## 3. 交互一致性规则

1. 所有新增入口放进**现有**「我的」列表或现有页面内的操作条，不新增 Tab、不新增路由层级。
2. 批量操作沿用曲库页已有的「多选 → 底部操作条」范式。
3. 新增设置项沿用 `AppSettings` 即时生效 + 原子落盘，不需要「保存」按钮。
4. 错误提示沿用现有 SnackBar / 红条 / 空态三件套，不引入 toast 库。
5. 加载态沿用现有骨架屏 / CircularProgressIndicator，不引入动画库。
6. 玻璃页内所有可点区域必须 `GlassTap`；普通 Material 页可直接 `InkWell`。

---

## 4. 测试规格

- 新增测试**必须 import 真实现**。纯逻辑抽到可独立实例化的类/函数，测试直接调用。
- 覆盖：焦点 begin→end 恢复播放、cast 初始化延迟时首推不丢、`artBytes → artworkUri`、
  评论分页/合并/requestId 竞态、队列 pause/resume/retry、偏好非法值回退与 toJson 往返、
  清空队列停播、定时关闭复位、循环模式映射。
- 修正 `play_mode_test.dart` 中被锁死的错误映射断言。
- 拆分 `dart_test.yaml` 的粗粒度 network tag，让同文件里的纯逻辑用例真正跑起来
  （真实网络用例仍默认跳过）。
- 禁止 `expect(true, isTrue)` 空断言。

## 5. 验证门槛

```
flutter analyze                          → No issues found
flutter test                             → 全绿，新增测试测真实现
flutter build apk / ios / linux / macos / windows  → 五端构建通过
git diff --stat                          → pubspec.yaml 除版本号外零改动；
                                           lib/platform/** 与 main.dart/app.dart 零改动
```

## 6. 回归清单（人工真机）

- [ ] 播放中接来电 / 语音播报，结束后自动续播
- [ ] 高档音质 + 只声明 128k 的脚本，仍能出声
- [ ] 冷启动立即播放，通知栏歌名/封面/进度正确
- [ ] 本地歌曲播放，通知栏有封面（App 内与通知栏一致）
- [ ] 死链换源成功后再次失败，红条可见
- [ ] 热门歌曲评论可翻页，切歌不串台，错误文案分得清
- [ ] 清空队列后彻底静音；定时「播完当前首」真停且下一首不受影响
- [ ] 拖动进度条不回弹、切歌后从 0 开始
- [ ] 下载暂停 / 继续 / 重试 / 历史双 Tab 正常
- [ ] 深色/浅色、手机/平板布局不回退

## 7. 版本与发布

- 版本号按用户规则**只涨最后一位**：`1.3.6+10` → `1.3.7+11`。
- `CHANGELOG.md` 新增 `[1.3.7]` 段落，按「修复 / 新增」分组记录用户可见变化。
- 提交并推送到 `origin/main`，本地与远端保持一致；tag 按需。
- 不发版公告、不改 README 模板之外的既有文档。

---

## 8. 施工顺序

A（P0 播放稳定性）→ B（评论）→ C（交互细节）→ D（功能补全）→ 测试补齐 →
五端构建 → 版本号/CHANGELOG → 提交对齐。

A 与 B/C/D 有共享文件（`player_core.dart`、`player_page.dart`、`app_providers.dart`），
**必须按批次串行**，不要并行改同一文件；批次内部可按文件边界并行。
