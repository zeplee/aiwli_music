# Aiwli Music 五端交互与复用规格

**版本** v1.0 · 2026-10-28
**读者**：接手本项目的 AI 或人类工程师。
**关联**：[`aiwli-music-design.md`](./aiwli-music-design.md)（架构）、[`ui-spec-aiwli-music.md`](./ui-spec-aiwli-music.md)（基础交互）、[`prototype/index.html`](./prototype/index.html)（可交互原型）

> 核心命题：**Android / iOS / macOS / Windows / Linux 五端，一套代码，最大程度复用。**
> 本文档定义复用的**边界**：什么必须共用（零差异），什么必须按平台定制（外壳与惯例），以及如何用一个参数驱动切换。

---

## 1. 复用模型：三层结构

这是「五端最大复用」的工程答案。三个层次用不同策略应对平台差异：

```
┌─────────────────────────────────────────────────┐
│  L1 · 平台无关层（占比 ~85%）                     │
│  领域模型 / 状态机 / 数据访问 / 音源宿主 / 业务逻辑  │
│  策略：100% 共用，不做任何平台分支                   │
├─────────────────────────────────────────────────┤
│  L2 · 自适应布局层（占比 ~10%）                    │
│  断点驱动的单套响应式布局 + 共享组件                │
│  策略：一套代码，靠 breakpoint 参数分叉             │
│        （不是 per-platform，是 per-size）            │
├─────────────────────────────────────────────────┤
│  L3 · 平台外壳层（占比 ~5%）                       │
│  窗口装饰 / 侧栏 vs 底部tab / 菜单 / 快捷键 / 触觉   │
│  策略：必须按平台定制，但接口统一                    │
└─────────────────────────────────────────────────┘
```

**关键认知**：L2 的要诀是**用「尺寸」而非「平台」做判断**。因为：
- macOS 窗口可以拉窄到手机宽度 → 此时应切移动布局
- iPad / Android 平板是移动 OS 但需要双栏布局 → 此时应切桌面布局
- 只有 L3（窗口装饰、菜单栏、键盘快捷键）才真正与 OS 绑定

---

## 2. 五端差异矩阵

### 2.1 布局与导航

| 维度 | Android | iOS | macOS | Windows | Linux |
|---|---|---|---|---|---|
| 默认断点 | Compact | Compact | Expanded | Expanded | Expanded |
| 主导航 | 底部 Tab（5 项） | 底部 Tab（5 项） | 左侧栏（可折叠） | 左侧栏（可折叠） | 左侧栏（可折叠） |
| 页面转场 | 共享轴/Z 轴 + 涟漪 | 横向滑动 push | 无动画/淡入 | 淡入 | 淡入 |
| 二级页面 | 全屏 push | 全屏 push（右滑返回） | 同窗分栏 or 覆盖 | 同窗分栏 | 同窗分栏 |
| 返回方式 | 系统返回键 | 边缘右滑 | ⌘[ / 工具栏 | Alt+← | Alt+← |

### 2.2 输入与指针

| 维度 | Android | iOS | macOS | Windows | Linux |
|---|---|---|---|---|---|
| 主输入 | 触摸 | 触摸 | 触控板/鼠标 | 鼠标 | 鼠标 |
| 悬停态 | 无 hover | 无 hover | 有 hover | 有 hover | 有 hover |
| 右键菜单 | 长按 | 长按 | 右键 | 右键 | 右键 |
| 双击 | 无 | 无 | 双击播放 | 双击播放 | 双击播放 |
| 拖拽排序 | 长按拖起 | 长按拖起 | 直接拖 | 直接拖 | 直接拖 |
| 滚动条 | 隐藏 | 隐藏 | 覆盖式（悬停显） | 常显可拖 | 常显可拖 |
| 快捷键 | 无 | 无 | ⌘ 系 | Ctrl 系 | Ctrl 系 |
| 触觉反馈 | 轻/重 | 轻/重 | 无 | 无 | 无 |

### 2.3 外观与系统集成

| 维度 | Android | iOS | macOS | Windows | Linux |
|---|---|---|---|---|---|
| 顶部安全区 | 状态栏 inset | 状态栏 + 灵动岛 | 窗口标题栏 | 标题栏 | 标题栏 |
| 底部安全区 | 手势条 inset | Home indicator | 无 | 无 | 无 |
| 系统媒体 | 通知栏/锁屏 | 控制中心/锁屏 | Now Playing | SMTC | MPRIS |
| 托盘/后台 | 前台服务 | 无 | 菜单栏图标 | 系统托盘 | StatusNotifier |
| 桌面歌词 | — | — | ✅ | ✅ | ✅（Compositor 支持时） |
| 文件关联 | 无 | 无 | .mp3 等 | .mp3 等 | .mp3 等 |
| 拖放文件 | 无 | 无 | ✅ | ✅ | ✅ |

### 2.4 内容密度

| 断点 | 宽度 | 曲目行高 | 封面网格 | 字号基准 | 播放条 |
|---|---|---|---|---|---|
| Compact | <600 | 56px | 2 列 | 14px | 迷你（可上滑） |
| Medium | 600–904 | 60px | 3-4 列 | 14px | 迷你 |
| Expanded | ≥905 | 64px | auto-fill 158px | 14px | 完整三段式 |

---

## 3. 自适应实现：一个 Parameter 驱动

### 3.1 断点定义

```dart
// lib/platform/layout_class.dart
enum LayoutClass { compact, medium, expanded }

LayoutClass layoutClassOf(BoxConstraints c) {
  if (c.maxWidth < 600) return LayoutClass.compact;
  if (c.maxWidth < 905) return LayoutClass.medium;
  return LayoutClass.expanded;
}
```

**注意**：`LayoutClass` 只看宽度，不看平台。这样才满足「iPad 用 expanded 布局、macOS 窄窗用 compact 布局」。

### 3.2 平台能力（真实需要 OS 判断的部分）

```dart
// lib/platform/platform_caps.dart
// 只有这里允许 Platform.is*，且只描述"能力"而非"UI"
class PlatformCaps {
  bool get hasPointerHover   => isDesktop;   // 悬停、右键
  bool get hasKeyboardShortcut => isDesktop;
  bool get hasWindowChrome   => isDesktop;   // 自绘标题栏
  bool get hasTray           => isDesktop;
  bool get hasDesktopLyric   => isDesktop;
  bool get hasHapticFeedback => isMobile;
  bool get needsSafeArea     => isMobile;
  bool get usesSystemBackButton => isAndroid;
  String get shortcutModifier => isMacOS ? '⌘' : 'Ctrl';
  // 仅桌面：窗口最小尺寸（避免布局塌陷）
  Size get minWindowSize => const Size(760, 520);
}
```

**规则**：UI 层不直接 `Platform.isXxx`；需要时读 `PlatformCaps` 的**语义化能力位**。这样布局组件可单测（注入 fake caps）。

### 3.3 单套布局骨架

所有平台跑**同一个** `AppShell`，只是 3 个插槽的实现不同：

```dart
class AppShell extends StatelessWidget {
  final Widget content;        // 各页面，完全共用
  final Widget playerBar;      // 完全共用

  Widget build(context) {
    final lc = layoutClassOf(...);
    return switch (lc) {
      LayoutClass.compact  => _CompactShell(content, playerBar),
      LayoutClass.medium   => _MediumShell(content, playerBar),
      LayoutClass.expanded => _ExpandedShell(content, playerBar),
    };
  }
}
```

- `_CompactShell`：内容 + 播放条 + 底部 Tab（移动双端共用，仅转场动画按 `isIOS` 微调）
- `_ExpandedShell`：左侧栏 + 内容 + 播放条（桌面三端共用，仅窗口装饰按 `isMacOS` 微调）
- `_MediumShell`：左侧栏收窄为图标 + 内容（平板/窄桌窗）

**页面本身（DiscoveryPage / SearchPage / ...）在所有 shell 中完全相同**——这是复用的关键，页面不认识平台。

---

## 4. 共享组件清单（L2）

以下组件一套代码，通过参数适配，不按平台分叉：

| 组件 | 自适应参数 | 说明 |
|---|---|---|
| `TrackRow` | `density`, `showSourceChip`, `showIndex` | 移动端隐藏源标签，加高点击区 |
| `CoverGrid` | `minTileWidth` | `auto-fill` 自动列数 |
| `MediaCard` | `hoverable` | 桌面才有 hover 上浮 |
| `PlayerBar` | `compact` 布尔 | compact 时只留封面+曲名+播放 |
| `SegmentedChips` | `scrollable` | 窄屏改横向滚动 |
| `SourceCard` | `capabilityStyle` | 能力位划掉/隐藏取决于可用宽度 |
| `SettingsGroup` | `trailingStyle` | 桌面显示右箭头+当前值，移动显示纯箭头 |
| `EmptyState` | `compact` | 移动端缩小插画与文案 |

### 4.1 输入语义抽象（关键）

不写 `onContextMenu` 和 `onLongPress` 两套。定义一次意图，按平台分发：

```dart
// lib/core/ui/input_intent.dart
class IntentDetector extends StatelessWidget {
  final Widget child;
  final VoidCallback? onPrimary;      // 单击/轻触
  final VoidCallback? onSecondary;    // 右键/长按
  final VoidCallback? onActivate;     // 双击/回车

  Widget build(context) {
    final caps = PlatformCaps.of(context);
    Widget w = child;
    if (onSecondary != null) {
      w = caps.hasPointerHover
        ? GestureDetector(onSecondaryTap: onSecondary, child: w)
        : GestureDetector(onLongPress: onSecondary, child: w);
    }
    if (onActivate != null && caps.hasPointerHover) {
      w = GestureDetector(onDoubleTap: onActivate, child: w);
    }
    ...
  }
}
```

**收益**：`TrackRow` 里只写"次要操作 = 加入歌单"，不再关心是长按还是右键。

---

## 5. 必须分叉的部分（L3，占比 ~5%）

| 项 | Android | iOS | macOS | Windows | Linux | 复用方式 |
|---|---|---|---|---|---|---|
| 窗口装饰 | 系统 | 系统 | 自绘标题栏（红绿灯） | 自绘标题栏（Win 控件） | 自绘（跟随 GTK） | `WindowChrome` 抽象，三实现 |
| 导航容器 | BottomTab | BottomTab | SideRail | SideRail | SideRail | 由上节 `LayoutClass` 决定，非平台 |
| 应用菜单 | 无 | 无 | 原生菜单栏 | 无（用内嵌菜单） | 无 | `AppMenu` 抽象，macOS 有实体、其他 no-op |
| 快捷键 | 无 | 无 | ⌘ 系 | Ctrl 系 | Ctrl 系 | `ShortcutMap`，按 modifier 生成 |
| 转场动画 | Material | Cupertino | 淡入 | 淡入 | 淡入 | `PageTransition` 按 `isIOS/isAndroid` 选 |
| 触觉 | ✅ | ✅ | no-op | no-op | no-op | `Haptics` 接口 |
| 托盘 | 通知 | — | ✅ | ✅ | ✅ | `TrayService` |
| 桌面歌词 | — | — | ✅ | ✅ | ✅ | `DesktopLyric`，仅 expanded+desktop |

---

## 6. 各平台专属交互

### 6.1 macOS
- 红绿灯按钮由我们自绘（无边框窗口），但位置与行为遵循 HIG
- 菜单栏：File / Edit / Playback / Window / Help；Playback 含播放控制与快捷键提示
- 触控板双指横滑 → 切歌
- 关闭窗口 = 隐藏到菜单栏（可配置为退出）
- Now Playing（控制中心）与键盘媒体键

### 6.2 Windows
- 标题栏自绘，右上角最小化/最大化/关闭遵循 Windows 规范
- 任务栏缩略图工具栏（播放/暂停/上一首/下一首）
- SMTC 集成 + 系统音量混音器显示应用名
- `Alt+←` 返回；`Ctrl+,` 打开设置

### 6.3 Linux
- 跟随 GTK 主题（可选强制深色）
- MPRIS（`org.mpris.MediaPlayer2`）供桌面环境媒体控件
- StatusNotifierItem 托盘（GNOME 需扩展）
- 若合成器不支持透明，桌面歌词窗自动降级为不透明

### 6.4 iOS
- 全屏播放器支持**下拉关闭**（sheet 手势）
- 长按曲目 = 上下文菜单（原生 context menu 样式）
- 安全区适配（灵动岛/Home indicator）
- 控制中心 + 锁屏 + CarPlay（后续）
- 无返回按钮，用边缘滑动

### 6.5 Android
- 系统返回键/手势 → 必须正确响应（`PopScope`）
- 涟漪反馈（Material ink）
- 前台服务媒体通知 + 锁屏
- 支持分屏/画中画式小窗（音频继续）
- 平板/折叠屏自动进入 Medium/Expanded 布局

---

## 7. 转场与动效（按平台）

| 场景 | Android | iOS | 桌面 |
|---|---|---|---|
| 进入二级页 | SharedAxis X + fade | 横向 push（右滑回） | 淡入 + 轻微上移 |
| 打开全屏播放器 | 自底部上滑 | 自底部上滑（可下拉关闭） | 淡入覆盖 |
| 列表项点击 | 涟漪 + 轻微缩放 | 高亮闪一下 | 背景变色 |
| 主题切换 | 色板动画 300ms | 色板动画 300ms | 色板动画 300ms |
| 减少动效 | 跟随系统 → 全部降至 150ms/无位移 | 同 | 同 |

统一原则：**动效时长与曲线共用**（`--ease`、`--t-*`），只有转场"形状"按平台变。

---

## 8. 原型使用说明

`prototype/index.html` 右下角提供 **五端切换器**：

| 按钮 | 模拟 | 观察点 |
|---|---|---|
| Android | 412×915 | 底部 Tab、涟漪、无 hover、紧凑密度、安全区 |
| iOS | 393×852 | 底部 Tab、右滑返回提示、下拉关闭播放器、iOS 转场 |
| macOS | 1280×800 | 左侧栏、红绿灯、菜单栏、hover、双击播放、桌面歌词 |
| Windows | 1280×800 | 左侧栏、Windows 标题栏控件、SMTC 提示、Ctrl 快捷键 |
| Linux | 1280×800 | 左侧栏、GTK 风格标题栏、MPRIS 提示 |

切换器同时改变：断点、导航容器、行高、悬停行为、标题栏样式、快捷键文案、可用功能（如桌面歌词只在桌面出现）。

---

## 9. 复用率核算（工程预算）

| 层 | 代码量占比 | 五端共用 | 需分叉 | 说明 |
|---|---|---|---|---|
| L1 领域/业务/音源 | ~85% | 100% | 0 | 零平台分支 |
| L2 自适应 UI | ~10% | 一套 | 0（靠参数） | 页面组件完全共用 |
| L3 平台外壳 | ~5% | 接口 1 份 | 5 份实现 | 窗口/菜单/快捷键/托盘/触觉 |
| **合计** | 100% | **~95%** | **~5%** | |

对比「per-platform 三套 UI」方案（移动一套、桌面一套、平板一套）：代码量约 2.6 倍，且修 bug 要改三处。本方案的关键在于**把"平台"问题转化为"尺寸"问题**，只在 L3 保留真正的 OS 差异。

---

## 10. 验收清单（五端）

**布局**
- [ ] 同一窗口宽度下，五端布局一致（证明 L2 与平台无关）
- [ ] 桌面窗口拉窄到 <600px 自动切底部 Tab 布局
- [ ] 平板/折叠屏自动进入 Medium/Expanded

**输入**
- [ ] 曲目行：移动长按 / 桌面右键 均弹出同一菜单
- [ ] 桌面双击播放，移动单击播放
- [ ] 桌面 hover 有效，移动无 hover 残留
- [ ] 快捷键在 macOS 显示 ⌘、Windows/Linux 显示 Ctrl，且均可用

**平台外壳**
- [ ] macOS 红绿灯可用，菜单栏有 Playback 项
- [ ] Windows 标题栏控件符合规范，任务栏缩略图有播放按钮
- [ ] Linux MPRIS 被桌面媒体控件识别
- [ ] Android 返回键/手势正确返回，不退出应用
- [ ] iOS 边缘右滑可返回，播放器可下拉关闭

**复用**
- [ ] 页面组件（Discovery/Search/Library/...）内无任何 `Platform.is*`
- [ ] `PlatformCaps` 可被 fake 注入，布局组件有单测
- [ ] 新增第六端（如 Web）只需加 shell + caps，不改页面