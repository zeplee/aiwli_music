# 选型证据附录（已降级，非施工文档）

> **本文档不再具有施工效力。** 施工请以 [`aiwli-music-design.md`](./aiwli-music-design.md) 为准。
> 本文档保留的唯一价值：**记录每个选型决策背后的实测证据**，供后人追溯"为什么这么选"，避免重复调研或重新提议已被否决的方案。
>
> 采集时间：2026-10-27。数据会过期，若要重新评估某选项，请按下方"复核方法"重查。
>
> **2026-10-28 修订注记**：本文 §1 中 `smtc_windows`（依赖 flutter_rust_bridge）的记录仍为当时的调研事实，但**已不再作为施工结论**——ADR-012 决定改用纯 Dart 的 `win32` 自实现 SMTC，Windows 构建链因此不需要 rustup。相关实测证据补充见 [`dependency-evidence.md`](./dependency-evidence.md) §2。

---

## 1. 已定选型（结论只在施工文档 §1.1，此处仅列证据）

| 选型 | 版本 | 实测证据 | 复核方法 |
|---|---|---|---|
| **media_kit** | 1.2.6 | 1.8k★ GitHub，media-kit 组织维护，2026-08 有 push；pub 平台矩阵 Android/iOS/macOS/Windows/Linux/Web 全绿；namida(6.7k★)、harmonoid(4.8k★) 生产使用 | `pub.dev/packages/media_kit` 看 Platform 行；`api.github.com/repos/media-kit/media-kit` 看 pushed_at |
| **flutter_js** | 0.8.7 | 542★，MIT；pub 平台声明 android/ios/linux/macos/windows **五端齐全**（无 web）；最近提交 2026-01-27 为性能修复（UTF-8 memcpy 批量拷贝）；81 open issues；**2025-09→2026-01 有四个月空窗** | `pub.dev/api/packages/flutter_js` 看 latest.flutter.plugin.platforms；`api.github.com/repos/abner/flutter_js/commits` |
| **audio_service** | 0.18.19 | 1.33k likes；pub 平台 Android/iOS/macOS/web，**Windows 缺失**；官方 README 说 Linux 经 audio_service_mpris | `pub.dev/packages/audio_service` |
| **audio_session** | 0.2.4 | 366 likes；平台 Android/iOS/macOS/web，**Windows/Linux 缺失** | `pub.dev/packages/audio_session` |
| **smtc_windows** ⚠️ | 1.1.0 | 13 likes；Windows 专属；依赖 flutter_rust_bridge（**已被 ADR-012 改为纯 Dart `win32`**） | `pub.dev/packages/smtc_windows` |
| **audio_service_mpris** | 0.2.1 | Linux 专属，补 audio_service 的 MPRIS 实现 | `pub.dev/packages/audio_service_mpris` |
| **audio_metadata_reader** | 1.8.1 | 13 天前发版；**纯 Dart**；平台 Android/iOS/Linux/macOS/Windows 全绿；支持 ID3/Vorbis/ILST 读写 | `pub.dev/packages/audio_metadata_reader` |
| **dio** | 5.11.1 | 8.37k likes；flutter.cn 官方；平台全绿 | `pub.dev/packages/dio` |
| **flutter_secure_storage** | 11.2.0 | 4.5k likes；五端+web | `pub.dev/packages/flutter_secure_storage` |
| **home_widget** | 0.10.0 | 2.22k likes；160 满分；**仅 Android+iOS**（桌面不支持） | `pub.dev/packages/home_widget` |
| **flutter_rust_bridge** | 2.13.0 | 664 likes；Flutter Favorite；smtc_windows 的底座 | `pub.dev/packages/flutter_rust_bridge` |
| **native_dio_adapter** | 1.8.0 | **仅 macOS/iOS/Android 真用原生栈，Windows/Linux 回退 dart:io** | 其 README 明示 |

---

## 2. 已否决方案与证据（**不要再提，除非证据发生变化**）

### 2.1 just_audio 作为统一引擎 —— 否决

| 证据 | 内容 |
|---|---|
| `just_audio` 本体 | 0.10.6，4.15k likes，ryanheise 维护，平台 Android/iOS/macOS/web（**桌面 Windows/Linux 无官方实现**） |
| 桌面桥 `just_audio_media_kit` | Pato05 维护，**GitHub 14★ / 32 fork / 5 open issues**；pub 版本 2.1.0 **最后发版 2025-04（18 个月前）**；pub 标注 **unverified uploader** |
| 桥的已知缺陷（README 自承） | `shuffleOrder` 被忽略（官方建议手动洗队列）；`SilenceAudioSource` 不支持；**gapless 需开实验性 `--prefetch-playlist`（"Use at your own risk"）**；HTTP header 支持标注 "(untested)" |
| 桥的底层 | 仍调用 `media_kit` —— 垫一层却削减能力 |

**判决**：音乐播放器的三大刚需（gapless / shuffle / 自定义 header）在桌面端全部踩在桥的短板上；而桥底下就是 media_kit，**不如直用 media_kit**。

### 2.2 flutter_qjs —— 否决
最终发版 0.3.7（2022-05-19），SDK 约束 `>=2.12.0-0 <3.0.0`，无法在现代 Flutter 使用。虽然平台声明覆盖五端，但工程已死。

### 2.3 自研 BASS 原生插件（栖弦做法）—— 否决
需分别写 Windows/macOS/Linux 三套原生桥（2-3 周）；BASS 商用需 un4seen 授权（非商业才免费）；media_kit 用 libmpv（LGPL）无此问题。
参考：ZeroBit-Player 是完整 BASS 桌面实现（GPL-3.0，仅可看思路）。

### 2.4 flutter_audio_tagger —— 否决
5.1.3，pub 上**所有版本均只注册 android 平台**。栖弦用它做本地库标签读写，桌面端直接不可用。

### 2.5 WebView 跑音源脚本 —— 否决
桌面 webview 生态分裂（`webview_flutter` 不支持桌面）、内存开销大、与 Dart 交换结构化数据困难、调试困难。

### 2.6 为 any-listen 单独做第三套适配器 —— 否决
证据：`any-listen/any-listen-extension-lx-api-source-loader` 的 `config.ts`：

```ts
contributes: {
  resource: [
    { id: 'kw', name: '{kwName}', resource: ['musicUrl'] },
    { id: 'tx', name: '{txName}', resource: ['musicUrl'] },
    { id: 'wy', name: '{wyName}', resource: ['musicUrl'] },
    { id: 'kg', name: '{kgName}', resource: ['musicUrl'] },
    { id: 'mg', name: '{mgName}', resource: ['musicUrl'] },
  ],
},
buildConfig: { isIsolateMode: true },
grant: ['internet', 'isolate_context'],
```

与 lx 官方规范"非 local 源 `actions` 固定为 `['musicUrl']`"**完全一致**；`isIsolateMode` + `isolate_context` 表明是**隔离进程容器**。

**判决**：any-listen 扩展 = lx 源脚本的新打包形态，不是新协议。**不为它单独写适配器**；若将来其能力面扩展为宽协议，再在 `sources/` 加第三个 adapter（架构已预留）。

---

## 3. 参考工程实测档案

| 工程 | ★ | 栈 | 音源机制 | 许可 | 对本项目的价值 |
|---|---|---|---|---|---|
| lyswhut/lx-music-desktop | — | Electron 42 + Vue3 | Node 侧跑 JS 源脚本 | Apache-2.0 | **lx 协议权威规范**；内置官方源 API 可参考移植 |
| lyswhut/lx-music-mobile | — | React Native 0.73 | `react-native-track-player` | Apache-2.0 | 仅 Android/iOS，参考价值有限 |
| any-listen/any-listen | 4.6k | pnpm workspace，桌面+Web | 扩展机制（隔离进程 + message2call） | **AGPL-3.0 + 明确禁止商用** | 扩展架构思想参考；**代码不可抄** |
| maotoumao/MusicFree | 28.0k | React Native | JS 插件（axios/cheerio/crypto-js…） | AGPL-3.0 | **插件协议最完整**，驱动本项目主生态设计 |
| maotoumao/MusicFreeDesktop | 9.1k | Electron + React | 同上 | AGPL-3.0 | 同上 |
| WEP-56/MusicWEP | 20 | **Flutter** | `flutter_js` + 自建 shim（10 个 npm 包 polyfill） | AGPL-3.0 | **唯一验证过"Flutter 跑插件音源"的工程**；工程化细节（隔离/超时/串行/转义）值得照抄**思路** |
| namidaco/namida | 6.7k | Flutter | 无自定义音源 | NOASSERTION（需逐文件确认） | media_kit 五端 + SMTC + 桌面集成范本 |
| harmonoid/harmonoid | 4.8k | Flutter | 无 | NOASSERTION | FFI 直连 libmpv 参考 |
| Empty-57/ZeroBit-Player | 285 | Flutter + Rust + BASS | 无 | GPL-3.0 | BASS 桌面 + SMTC + WASAPI 参考（只读） |
| KevinllBin/CyShineMusic | — | Flutter（Android） | 原生 QuickJS 桥 | **MIT** | **可复制**：播放状态机、逐字歌词、业务 UI 结构 |
| WEP-56 之外 | — | — | — | — | — |

### 3.1 MusicWEP 关键事实（已验证）
- 插件运行时：`flutter_app/lib/core/runtime/plugin_runtime_instance.dart`（22KB）
- 运行时选择：`Platform.isWindows || isLinux || isAndroid → QuickJsRuntime2`，否则 `getJavascriptRuntime()`（iOS/macOS 走 JSC）
- 包 shim 清单：`axios / cheerio / crypto-js / dayjs / big-integer / qs / he / webdav / @react-native-cookies/cookies / musicfree/storage`
- 已知 workaround：QuickJS 正则 `\<` `\>` 转义、`#$instanceId` 通道隔离、`_SerialQueue`、15s 超时
- 状态：3 次提交全叫"初始化"，集中在 2026-06-22/23，**实际是未经验证的骨架**，但 `custom_source_engine.dart`（52KB）的协议桥思路可用

### 3.2 MusicWEP 之外，曾考虑但排除的
- `yingjunda/LX-Music-Flutter-Mobile`（6★）：3 次提交全"初始化"，README 宣称支持 macOS 但从未验证，不可作基座
- `airshu/lx_music_flutter`（41★）：README 自承 lx-mobile 音源接口失效，只跑 Android/iOS
- `cnmusic-hub/Musicgo`：README 称 Flutter，实际是 React Native 工程（metro.config.js），1★，可排除

---

## 4. lx 官方源脚本协议要点（权威，来自 lxmusic.toside.cn）

> 完整细节见施工文档 §4.2。此处只记最易被误解的一条。

**lx 自定义源脚本的能力边界**：非 local 源 **只支持 `musicUrl`**。搜索、榜单、歌单导入由 App 内置 API 提供，与脚本无关。

这条事实决定了本项目的音源策略：**以 MusicFree 插件（能力完整）为主生态，lx 脚本作兼容层**。若要让 lx 脚本用户也能搜索，必须自行移植 lx 内置官方源 API（Apache-2.0 允许），列为可选里程碑 M6。

---

## 5. 复核方法（数据会过期，重查用）

```bash
# 包平台支持与版本
curl -s https://pub.dev/api/packages/<name> | jq '.latest.flutter.plugin.platforms, .latest.version'

# 包维护状况（GitHub）
curl -s https://api.github.com/repos/<owner>/<repo> | jq '{stars:.stargazers_count, pushed:.pushed_at, issues:.open_issues_count}'

# 最近提交
curl -s "https://api.github.com/repos/<owner>/<repo>/commits?per_page=5" | jq '.[].commit.message'
```

判据建议（本项目采纳）：
- **活跃**：pushed_at 距今 < 6 个月
- **可持续依赖**：有组织/多维护者，或单人但有稳定发版节奏（一年 ≥2 次）
- **平台完整**：pub 的 platforms 声明覆盖目标五端，且不是"名义支持"（要核实底层是否回退，如 native_dio_adapter 的 dart:io 回退）