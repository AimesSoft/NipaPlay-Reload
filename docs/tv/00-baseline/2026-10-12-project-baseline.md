# NipaPlay TV 项目基线报告

- 报告日期：2026-10-12 ｜ 编制：TV 端技术规划与知识管理架构师
- 数据来源：代码实测（`flutter analyze` / `flutter test` / 构建产物拆解 / 用户真机截图）
- 基线仓库：`NipaPlay-Reload-features`（branch `nipaplay`），TV 应用位于 `apps/nipaplay_tv`

## 1. 总体现状

| 维度 | 状态 | 证据 |
|---|---|---|
| 应用框架 | Flutter 3.44.6 / Dart 3.12，仅 android，applicationId `com.aimessoft.nipaplay_tv` | `apps/nipaplay_tv/pubspec.yaml` |
| 构建产物 | release APK **54.8 MB**（arm64 单 ABI），debug 168.8 MB | `build/app/outputs/flutter-apk/` |
| 代码质量 | `flutter analyze lib test` **0 issues**；`flutter test` **13/13 通过** | 本次实测 |
| 播放内核 | **仅 Erika 0.2.1**（用户要求，为体积移除 media_kit/MDK/video_player） | `tv_player_kernel_registry.dart` |
| 依赖链 | TV → `nipaplay_core`（逻辑）+ `nipaplay_ui_common`（契约/本地化/组件） | 两包 path 依赖 |

## 2. 功能模块清单

| 模块 | 文件 | 现状 | 优先级 |
|---|---|---|---|
| 焦点壳 | `ui/tv_app_shell.dart` | 侧栏导航 + 内容面板；切页移交焦点；PopScope 返回键；失焦兜底监听 | 已完成 |
| 首页 | `ui/pages/home_page.dart` | Bangumi 排行榜新番 Top10 + 最近播放；刷新按钮 | 已完成 |
| 媒体库 | `ui/pages/library_page.dart` | 添加来源 8 类（本地/WebDAV/Emby/Jellyfin/SMB/弹弹远程/URL）；番剧卡片视图；钉选到侧栏；连接测试；自动/手动加载内容 | 已完成 |
| 番剧详情 | `ui/pages/anime_detail_page.dart` | 全屏背景、标题、评分、简介、剧集网格、评论 | 已完成 |
| 我的 | `ui/pages/profile_page.dart` | 弹弹登录/登出、账号状态、登录后能力说明 | 已完成 |
| 设置 | `ui/pages/settings_page.dart` | 6 分区瓦片（通用/播放器/弹幕/网络/存储/外观），经 core `SettingsStorage` 持久化；Bangumi 镜像填写 | 已完成 |
| 播放页 | `ui/pages/player_page.dart` | 经 `NipaPlayer` 接口驱动，D-pad + 触摸 | 已完成 |
| 数据层 | `lib/data/tv_trending_client.dart` 等 | 弹弹网关客户端（排行/详情/评论）、媒体源加载器、账号服务、本地存储 | 已完成 |

## 3. 关键实测结论（非臆测）

1. **弹弹网关鉴权**：`/api/v2/*` 一律要求 `Authorization: Bearer <token>`；无 token 返回 `errorCode:401 请先登录弹弹play账号`；假 token 返回 `登录已失效`。换镜像地址不能绕过——这是**账号鉴权**。
2. **用户弹弹服务可达**：`192.168.3.39:30000` `/api/v1/welcome` → `Hello dandanplay! v18.1.3.0`，`tokenRequired:false`；`/api/v1/library` 返回 **1248 条**真实番剧。
3. **Bangumi 主站不可达**：`api.bgm.tv` 从本机请求为空。故封面/榜单必须走弹弹网关镜像。
4. **封面加载失败根因**：卡片曾误用 `WebRemoteAccessService.imageProxyUrl()`（普通版依赖本地 web 服务器，TV 没有）。已改为直连 + `User-Agent` 头。
5. **键盘遮挡根因**：Android 15 edge-to-edge + `AlertDialog` 不可滚动，actions 被键盘顶出屏幕。已统一 `TvInputDialog`（可滚动 + 扣除 `viewInsets.bottom` + 85% 高度上限）。
6. **失焦根因**：`FocusableCard` 早期仅接键盘事件无触摸；选中态与焦点态未分离。已补 `selected` 常驻态 + 壳层失焦兜底。

## 4. 体积构成（优化后 release 54.8 MB）

| 模块 | 体积 | 占比 | 说明 |
|---|---|---|---|
| `liberika_capi.so`（arm64） | 35.4 MB | 65% | Erika 内核（自带解码+HDR 管线），最大单项 |
| `libflutter.so` | 11.1 MB | 20% | Flutter 引擎，不可压 |
| `libapp.so` | 5.4 MB | 10% | 全部 Dart 代码（core+ui_common+TV） |
| 资源/dex | ~0.9 MB | 1.6% | 已 icon tree-shaking |

## 5. 已知技术债（详见 `02-tech-debt/tech-debt-register.md`）

| ID | 技术债 | 等级 | 风险 |
|---|---|---|---|
| TD-001 | watch_history 模型受依赖环阻塞，TV 用轻量本地记录替代 | 中 | 数据模型与手机版不统一 |
| TD-002 | `DandanplayRemoteService` 为单例，无法多端口并存 | 中 | 已用独立 HTTP 请求绕过（未根治） |
| TD-003 | 本地 TV 镜像构建（无 AVD 硬件加速，仅手机实测） | 低 | 覆盖机型有限 |
| TD-004 | 番剧详情评分/简介依赖弹弹网关详情接口，主站不可达 | 低 | 失败时回退榜单自带字段 |

## 6. 硬件适配约束

- TV 遥控器 D-pad 是**唯一主输入**，任何操作不得导致焦点丢失。
- 触摸/鼠标为**增强通道**（手机实测、触屏 TV）。
- 键盘/地址栏需适配软键盘高度，actions 永不被遮挡。

## 7. 下一版本基线

- 起始 commit：`fbcdb112`（阶段四）→ 当前工作分支含焦点修复与多源支持。
- 目标：用户侧验收通过（排行榜出图、媒体库列番剧、钉选侧栏可点入、剧集+评论加载）。
