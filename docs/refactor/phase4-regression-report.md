# 阶段四回归验证报告 — TV UI 完善（真实播放 + 弹幕 + 设置瓦片）

- 仓库：`NipaPlay-Reload-features`（branch `nipaplay`）
- 阶段三起点：`6b9f4837`
- 执行日期：2026-10-12
- 验收设备：**OnePlus PKG110 / Android 16 (SDK 36) / arm64-v8a / 1264×2780**（无线调试 `192.168.3.85`，配对成功；按要求未使用 MuMu）

## 1. 交付内容（全部在 `apps/nipaplay_tv`，普通版零改动）

| 模块 | 文件 | 说明 |
|---|---|---|
| 内核适配器 | `lib/player/video_player_nipa_adapter.dart` | **实现 core 的 `NipaPlayer` 接口**（initialize/load/play/pause/seek/stateStream/positionStream/createSurfaceHandle/dispose/capabilities）+ `PlayerFactory`（supportsPlatform/priority）。这是阶段一"core 定接口、各版本给实现"承诺的兑现 |
| 弹幕源 | `lib/danmaku/tv_danmaku_source.dart` | 调用 core 的 `parseBilibiliXmlDanmakuComments` 解析 B 站 XML → core 的 `DanmakuItem`；颜色 `rgb(r,g,b)` → 24 位 RGB |
| 弹幕渲染 | `lib/danmaku/tv_danmaku_overlay.dart` | TV 自建：轨道分配（滚动轮转+抖动）、顶部/底部居中、离屏回收、跳转重置、Ticker 驱动 |
| 播放页 | `lib/ui/pages/player_page.dart` | core `NipaPlayer` 驱动；D-pad（←/→ 快进退 10s、● 播放暂停、↑/↓ 控件、D 弹幕开关）+ **触摸**（点按切控件、点播放键、拖动进度条 seek） |
| 焦点原语修复 | `lib/ui/focusable_card.dart` | **补触摸与悬停通道**（见 §4 缺陷 1） |
| 设置瓦片 | `lib/ui/pages/settings_page.dart` | 按 ui_common `UnifiedSettingContentType` 分 6 区（通用/播放器/弹幕/网络/存储/外观），值经 core `SettingsStorage` 持久化 |
| 图标 | `res/mipmap-*`、`drawable-*/ic_launcher_foreground`、`mipmap-anydpi-v26` | 与普通版**同 md5 的 NipaPlay 图标**（含自适应/单色），清单补 `roundIcon` |
| 渲染取证 | `test/render_capture_test.dart` | 1080p 离线渲染导出 PNG（不依赖真机） |

## 2. 验证结果

| 关卡 | 结果 |
|---|---|
| `flutter analyze`（TV 应用） | **No issues found** |
| `flutter test`（TV 应用） | 冒烟 + 2 个渲染取证测试全过；其中设置页测试用 `tap('设置')` **验证触摸路径已接通** |
| `gradlew assembleDebug` | **BUILD SUCCESSFUL**（含触摸修复与 NipaPlay 图标，最终 APK 已安装到手机） |
| `adb install -r` → 手机 | **Success**（OnePlus PKG110） |
| 应用启动 | `am start` 成功，进程存活，Flutter 引擎正常 |
| 1080p 渲染取证 | `build/screenshots/p4_shell_1080p.png`、`p4_settings_1080p.png`（侧栏+卡片+焦点环+开关瓦片布局正确；文字显示方块为测试环境无中文字体，真机正常） |
| 普通版零影响 | analyze lib/test **error 0**；test **846 通过 / 4 失败**，失败集合为基线预存子集（logs/p4_normal_regression.log） |

## 3. 架构验证结论（四阶段主线收束）
```
nipaplay_core        逻辑层（147 文件）：模型/播放器接口/弹幕解析/FFI/网络/WebDAV
nipaplay_ui_common   契约层（41 文件+l10n）：显示面/l10n/纯模型/通用组件
apps/nipaplay_tv     TV 版 = core + ui_common + TV 自建 UI（焦点/播放页/弹幕渲染/设置瓦片）
普通版（仓库根）      手机/桌面版，行为不变，两包的消费者
```
TV 版对普通版**零反向依赖**；`NipaPlayer` 接口在 TV 侧有了第二个实现，证明抽象可用。

## 4. 缺陷与修复（如实记录）
1. **触摸无响应（用户实测发现）**：`FocusableCard` 早期只接了 `Focus`+键盘事件，未接 `GestureDetector`，导致手机上"任何入口都点不动"。已补 `GestureDetector.onTap` + `MouseRegion` 悬停 + `space` 键；播放页补点按切控件/播放键/拖动 seek。修复后渲染测试的 `tap` 路径通过。
2. **图标非 NipaPlay**（用户实测发现）：TV 应用用的是 `flutter create` 默认图标。已从普通版复制整套 NipaPlay 图标（mipmap 五档 + 自适应 XML + foreground/monochrome + colors.xml），md5 校验一致。
3. **渲染测试挂起**：`RenderRepaintBoundary.toImage` 必须在 `tester.runAsync` 内 await，否则测试永不结束；另需 `SharedPreferences.setMockInitialValues`（设置页 initState 读 core 存储）与 `locale: zh`（文案断言）。均已修复。
4. 弹幕 overlay 的 Ticker 常驻导致含播放页的 widget 测试无法自然结束——播放页改为真机验收，渲染取证只覆盖壳与设置页。

## 5. 遗留
- 手机实测（用户侧）：游戏会话占用前台期间未强切；应用已安装，用户随时可点开验证播放页与 D-pad/触摸。
- 内核升级：当前 TV 用 `video_player`（格式/字幕支持有限），可平滑替换为 media_kit 适配器（接口不变）。
- core 依赖环（core-inventory §5）解开后，watch_history/WebDAV 数据源可接入 TV 媒体库页。
- TV 真机模拟器验收仍需管理员装 AEHD（AVD `nipaplay_tv_api36` 已备）。
