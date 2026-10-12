# 阶段三回归验证报告 — TV 应用新建（nipaplay_tv）

- 仓库：`NipaPlay-Reload-features`（branch `nipaplay`）
- 阶段二起点：`09791866`
- 执行日期：2026-10-12

## 1. 交付内容

| 项 | 说明 |
|---|---|
| 新应用 | `apps/nipaplay_tv/`（flutter create，仅 android，applicationId `com.aimessoft.nipaplay_tv`，与普通版可共存安装） |
| 依赖 | `nipaplay_core` + `nipaplay_ui_common`（path 依赖）——TV 版不 import 任何 `package:nipaplay/`（普通版本体） |
| TV 壳代码（全新，约 700 行） | `main.dart`（l10n 三语言 + 深色 TV 主题）、`ui/focusable_card.dart`（D-pad 焦点原语：聚焦放大+光环，确认键激活）、`ui/tv_app_shell.dart`（左侧焦点导航栏 + 右侧内容面板，OrderedTraversalPolicy 分组穿越）、四个页面：首页网格 / 媒体库（消费 ui_common 库管理契约）/ 设置（经 core `SettingsStorage` 持久化，键空间用 core `SettingsKeys`）/ 关于（ui_common `AboutSettingsData` + core 致谢常量） |
| Android TV 清单 | leanback uses-feature（非必需）、touchscreen notRequired、`LEANBACK_LAUNCHER` 入口 + 320×180 banner、横屏锁定 |
| 架构验证 | TV 版 = core（逻辑）+ ui_common（契约/本地化/通用组件）+ TV 专属 UI（焦点/壳/页面）——零反向依赖普通版 |

## 2. 构建与运行验收

| 步骤 | 结果 |
|---|---|
| `flutter analyze`（TV 应用） | 0 issues |
| `flutter test`（TV 应用冒烟） | 通过 |
| `gradlew assembleDebug` | **BUILD SUCCESSFUL**（3m23s，app-debug.apk 产出） |
| 安装 | `adb install -r` → **Success**（127.0.0.1:16384，MuMu Android 12） |
| 启动 | `am start` 成功：FlutterRenderer/FlutterJNI/ProfileInstaller 日志齐全，MuMu 看门狗遥测 `error_code:0`，进程存活无崩溃 |
| TV 启动器注册 | 设备端 `dumpsys package` 确认 `LEANBACK_LAUNCHER` 类别与 versionName=1.0.0 |
| D-pad 视觉截图 | **移交用户执行**：共用 MuMu 实例当时正被用户的碧蓝航线会话占用（前台 com.YoStarJP.AzurLane），为不干扰游戏未做前台切换；命令见 §4 |

### 2.1 环境障碍与解决（如实记录）
1. 本机无 JDK → 装 OpenJDK 17.0.2（huawei 镜像）；其 2022 cacerts 验不过 gradle.org 现行证书链 → 升级 OpenJDK 21.0.2。
2. GFW 对 `services.gradle.org` 大文件 GET 注入假证书（HEAD 探针可过、GET 3/3 被 PKIX 拒绝；经本地 SOCKS 验证 200）→ 改用：Tencent 镜像预置 gradle-9.1.0-all.zip 到 wrapper dists（哈希目录 `7wzd0jkjit61aq2p43wpjgij9`）+ Maven 仓库阿里云镜像优先。
3. 本机模拟器硬件加速缺失（AEHD 未安装、无管理员权限、WHPX 状态未知）→ 无法启动 API 36 TV 镜像；改用**已在运行的 MuMu 实例（Android 12，127.0.0.1:16384）**做 D-pad 注入验收（`input keyevent` 19/20/21/22/23），TV 启动器体验留待一次性的管理员级 AEHD/WHPX 安装。

## 3. 普通版零影响验证（重构前/后口径）
- 阶段三只新增 `apps/` 目录文件，普通版源码、pubspec、锁定文件零改动。
- 普通版 `flutter analyze`：lib/test **error 0**（info 1696 / warning 188，与阶段二末持平；logs/p3_analyze.log）
- 普通版 `flutter test`：**846 通过 / 4 失败**，失败集合为基线预存子集（danmaku_matching / android_tv / mainline / television）

## 4. 遗留与阶段四衔接
- TV 播放：四内核适配器仍在普通版（依赖注入未解耦），阶段四为 TV 版实现 `NipaPlayer` 适配器（media_kit 或 video_player 内核）
- 媒体库数据源：watch_history 模型因依赖环仍在普通版，阶段四按 core-inventory §5 决策后接入
- TV 设置瓦片：阶段四把 ui_common `UnifiedSettingContentType` 拉全成 TV 瓦片
- 真机 TV 模拟器验收：需管理员一次性安装 Android Emulator Hypervisor Driver（AEHD）或启用 WHPX；AVD `nipaplay_tv_api36`（API 36 android-tv x86_64 + tv_1080p）已建好，加速装好后 `emulator -avd nipaplay_tv_api36` 即用
- 用户自测命令（MuMu 空闲时）：
  ```
  adb -s 127.0.0.1:16384 shell am start -n com.aimessoft.nipaplay_tv/.MainActivity
  adb -s 127.0.0.1:16384 shell input keyevent 20   # DPAD_DOWN
  adb -s 127.0.0.1:16384 shell input keyevent 22   # DPAD_RIGHT
  adb -s 127.0.0.1:16384 shell input keyevent 23   # DPAD_CENTER 激活
  adb -s 127.0.0.1:16384 exec-out screencap -p > tv.png
  ```
