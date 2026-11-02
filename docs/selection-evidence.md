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
| **media_kit** | 1.2.6 | 1.8k★ GitHub，media-kit 组织维护，2026-08 有 push；pub 平台矩阵 Android/iOS/macOS/Windows/Linux/Web 全绿；多个成熟 Flutter 播放器生产使用 | `pub.dev/packages/media_kit` 看 Platform 行；`api.github.com/repos/media-kit/media-kit` 看 pushed_at |
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

### 2.3 自研 BASS 原生插件 —— 否决
需分别写 Windows/macOS/Linux 三套原生桥（2-3 周）；BASS 商用需 un4seen 授权（非商业才免费）；media_kit 用 libmpv（LGPL）无此问题。

### 2.4 flutter_audio_tagger —— 否决
5.1.3，pub 上**所有版本均只注册 android 平台**，桌面端直接不可用。

### 2.5 WebView 跑音源脚本 —— 否决
桌面 webview 生态分裂（`webview_flutter` 不支持桌面）、内存开销大、与 Dart 交换结构化数据困难、调试困难。

### 2.6 为其他脚本生态做第三套适配器 —— 否决
社区宽能力插件生态多为方法导出式协议，与 lx 事件收发协议不同源。引入将成倍扩大隔离/兼容测试面，且多绑定 AGPL 许可工程（代码不可引入，仅协议思路可读）。

**判决**：协议面锁定 lx 脚本（ADR-005）。`MusicSource` 接口与协议无关，将来若出现许可证友好、声明式宽能力的开放标准，在 `sources/` 加新 adapter 即可（架构已预留）。

---

## 3. 同类方案实测结论（调研摘要，2026-10）

调研了 Electron / React Native / Flutter 三类技术栈的十余个开源音乐播放器与脚本音源宿主，结论：

- **脚本宿主选型**：Flutter 侧执行脚本音源，flutter_js（QuickJS/JSC）是唯一可用路径；WebView 方案桌面生态分裂、内存大、数据交换难。
- **运行时分工**：Android/Windows/Linux 走 QuickJS，iOS/macOS 走 JavaScriptCore（flutter_js 内建分流）。
- **Node 环境缺口**：脚本普遍依赖 `request`/`crypto`/`buffer` 等 Node 风格全局，必须做包 shim（axios→dio 桥、crypto-js→pointycastle 桥、其余纯 JS polyfill）。
- **必踩坑清单**：QuickJS 严格正则转义、`#$instanceId` 通道隔离、串行队列、调用超时——详见主文档附录 A。
- **基座可得性**：现有 Flutter 实现要么 Android-only、要么未验证跨平台、要么已停更，无可直接复用的基座（→ ADR-001 从零新建）。
- **许可边界**：多数宽能力插件生态绑定 AGPL 许可；本工程只读协议思路、不引入代码（→ ADR-005 协议面锁定 lx 脚本）。

## 4. lx 官方源脚本协议要点（权威，来自 lxmusic.toside.cn）

> 完整细节见施工文档 §4.2。此处只记最易被误解的一条。

**lx 自定义源脚本的能力边界**：规范能力为 `musicUrl`。本工程在此之上扩展约定：脚本可声明 `lyric` / `pic` / `musicSearch` / `boardList` / `boardSongs` 等能力，壳内零内置源，能力声明驱动 UI 显隐（ADR-004）。

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