# WebDAV / 局域网互连 技能树（skill-tree）

> 读者：后续接手 NipaPlay WebDAV/局域网模块的 Agent。
> 用法：按节点跳源码（均带 `文件:行号`，可直接 grep）。
> 行号基准：`61b15e2` + webdav 修复分支（2026-10-11）。
> 总览文档：[platform-matrix.md](platform-matrix.md)｜缺口：[implementation-gaps.md](implementation-gaps.md)

```
WebDAV / 局域网互连
├── 1. WebDAV 客户端（连别人的服务器）
├── 2. 目录浏览 UI
├── 3. 搜索
├── 4. 播放链路（WebDAV 源 → 播放器）
├── 5. 本机远程访问（做别人的服务器）
├── 6. 局域网发现（UDP 32123）
├── 7. WebDAV 同步备份
├── 8. 平台适配层
├── 9. 已知问题（状态看板）
└── 10. SOP：加一个新平台要改哪几处
```

## 1. WebDAV 客户端

| 节点 | 位置 | 说明 |
|------|------|------|
| 连接模型 | `lib/services/webdav_service.dart:18`（`WebDAVConnection`） | id/name/url/username/password；`fromJson:46` 含 UUID v5 迁移 |
| 服务单例 | `lib/services/webdav_service.dart:184`（`instance`）+ `:192`（`forTesting`） | 测试注入点：`forTesting(connectionValidator:)` |
| 客户端栈 | `lib/services/webdav_service.dart:755`（`_createClient`） | `webdav_client 1.2.2`（dio）；超时 15s（`:140` `_defaultTimeoutMs`） |
| 连接验证 BFS | `lib/services/webdav_service.dart:337`（`_validateConnection`） | 原 URL → 规范化 → 常见子路径（`_commonDavPathSuffixes:175`）→ HTTPS 降级（`_maybeDowngradeToHttp:812`）；⚠️ 测试注入 override 在 `:340` |
| 认证 | 主路径 Basic/Digest 自适应（401 驱动）；legacy 仅 Basic `:1015-1048` | 失败判定 `_isAuthorizationFailure:798` |
| PROPFIND 变体矩阵 | `lib/services/webdav_service.dart:148`（`_propfindVariants`） | 5 种 Depth×Content-Type 组合，顺序尝试 |
| 目录列表 | `:421 listDirectory`（过滤）→ `:436 listDirectoryAll` → `:469 _fetchDirectoryAll` | 失败回退 legacy `_legacyListDirectory:1162` |
| XML 解析 | `:1252 _parseWebDAVResponse` | ≥8KB 且 RustLib 就绪 → Rust quick_xml（`rust/src/api/webdav_multistatus.rs:19`）；否则 Dart `:1298` |
| 目录缓存 | `:199 _directoryCache` → `lib/services/process_memory_cache.dart:22` | 2min 新鲜期 + SWR + LRU 64/20000 + in-flight 合并 |
| 持久化 | `:136 _connectionsKey`；`_loadConnections:211` / `_saveConnections:246` | SharedPreferences；删除墓碑 `:137` |
| 回归测试 | `test/webdav_perf_baseline_test.dart` | mock 服务器 + 请求级断言（协议行为锁定） |

## 2. 目录浏览 UI

| 节点 | 位置 | 说明 |
|------|------|------|
| 浏览页 | `lib/pages/webdav_browser_page.dart:77`（`initState`→`_initializePage:89`） | 初始化 → 默认服务器（快捷设置）→ `_loadDirectory:122` |
| 陈旧响应防护 | `lib/pages/webdav_browser_page.dart:55`（`_directoryLoadGeneration`）+ `:146-151` | 代数 + 连接/路径双重校验 |
| 手动刷新 | `:688` / `:1275`（`forceRefresh: true`） | 绕过缓存 |
| 自动进入季度文件夹 | `:166-183` | `autoEnterSeasonFolder` 触发递归 `_loadDirectory` |
| 排序 | `lib/services/webdav_file_sorter.dart`（`WebDAVFileSorter.sortAsync`） | 预设来自快捷设置；测试 `test/webdav_file_sorter_test.dart` |
| 快捷设置 | `lib/providers/webdav_quick_access_provider.dart:110-134` | 18 个 SharedPreferences key（默认服务器/目录、排序、搜索参数等） |
| 连接对话框 | `lib/themes/nipaplay/widgets/webdav_connection_dialog.dart:420`（保存入口） | cupertino 变体 `cupertino_webdav_connection_dialog.dart:189` |

## 3. 搜索

| 节点 | 位置 | 说明 |
|------|------|------|
| 入口 | `lib/services/webdav_service.dart:1811`（`searchFiles`） | scope 三态（current_directory/current_with_depth/global），depthLimit 默认 3 |
| 遍历引擎 | `:1888 _searchBreadthFirst` | **有界并发 BFS**（`maxConcurrency` 默认 3，上限 8）+ 全局 `requestIntervalMs` 限速 + visited 去重（2026-10-11 由串行 DFS 改造，请求集合不变，证据 [perf-baseline.json](perf-baseline.json)） |
| 匹配 | `:2000 _matchesSearchTarget` | targets: all/folder/video |
| UI 调用点 | `lib/pages/webdav_browser_page.dart:1972` | 进度/结果回调/停止信号 |
| 性能数据 | `docs/webdav/perf-report.md` §3 | 串行 1101ms → 并发 608ms（1.81×） |

## 4. 播放链路（WebDAV 源 → 播放器）

| 节点 | 位置 | 说明 |
|------|------|------|
| 源解析 | `lib/services/playback_source_service.dart:60-77` | 从浏览页选中 → `PlaybackSource`（sourceLabel='共享媒体'分支区分） |
| 文件候选 | `lib/models/episode_file_candidate.dart` | WebDAV 文件 → 剧集候选 |
| 外挂字幕/音轨远程下载 | `lib/services/remote_subtitle_service.dart:1406/1925` | 走 HTTP 下载（'共享媒体库' 标签） |
| loopback 媒体代理 | `lib/services/plugin_media_proxy.dart:98`（`HttpServer.bind(loopbackIPv4, 0)`） | 本地随机端口反代 |
| ⚠️ 起播延迟/内存基线 | `docs/webdav/perf-baseline.json` → `unverified` | **未验证**：无测试设备；补测路径见 [perf-report.md](perf-report.md) §4 |

## 5. 本机远程访问（做别人的服务器）

| 节点 | 位置 | 说明 |
|------|------|------|
| HTTP 服务 | `lib/services/web_server_service.dart:350`（`startServer`） | 默认 :1180；绑定 `anyIPv4`（`:422`）；IPv6 开关 `:580` |
| 设置持久化 | `:14-17`（`web_server_auto_start`/`web_server_ipv6_enabled`/`web_server_port`） | 旧 key `web_server_enabled` 兼容迁移 `:305-314` |
| 启动失败文案 | `:325 _formatStartError` | 端口占用/权限按 errno 归类 |
| API 路由表 | `lib/services/web_api_service.dart:38-88` | `/api/info`、bangumi、danmaku、dandanplay、media、history、遥控；遥控鉴权 `lib/services/remote_control_access_guard_service.dart:73` |
| 设置 UI | `lib/settings/pages/remote_access_receiver_settings_section.dart:579`（`_buildRemoteAccessControl`） | 开关/端口/二维码/受信任设备；**UDP 发现告警 `:search _buildLanDiscoveryWarning`** |
| Web UI 资产 | `:49 _resolveWebUiRoot`（assets/web）；构建脚本 `build_and_copy_web.sh` | Flutter Web 构建作为远程 UI |
| 服务生命周期 | `lib/providers/service_provider.dart:15`（单例）+ `loadSettings` 自启 `:301-318` | |

## 6. 局域网发现（UDP 32123）

| 节点 | 位置 | 说明 |
|------|------|------|
| 协议常量与编解码 | `lib/services/nipaplay_lan_discovery.dart:6`（端口）、`:22 NipaPlayLanDiscoveryProtocol` | JSON v1：请求 `{"type":"nipaplay_discover","v":1}`；响应含 hostname/os/port。**线格式由测试锁定** |
| 应答器 | `:79 NipaPlayLanDiscoveryResponder` | 绑定 `anyIPv4:32123 reuseAddress:true`（`:92`）；**`start()` 返回 bool + `lastStartError`（2026-10-11 失败可见化修复）** |
| 测试注入点 | `:85 bindOverrideForTest`（@visibleForTesting） | 仅测试用 |
| 扫描端（发广播） | `lib/themes/nipaplay/widgets/shared_remote_lan_scan_dialog.dart:245 _discoverByUdp` | 3 发×220ms+800ms 等待；无果回退 HTTP 探测 `:191-227`（32 并发 × 254 IP） |
| 网段枚举 | 同文件 `:657 _resolveScanTargets` / `:692 _isPrivateIpv4` | 仅私网 IPv4 /24 前缀（局限见 GAP-4' 非 /24 掩码，[implementation-gaps.md](implementation-gaps.md)） |
| 遥控发现（同协议复用） | `lib/services/remote_control_client_service.dart:209 _discoverByUdp`、`:330` 回退探测 | 900ms 请求超时 |
| 回归测试 | `test/lan_discovery_responder_test.dart` | 线格式×2、5 秒回包、占用失败可见（4/4 通过） |
| 验证脚本 | `scripts/verify_webdav_discovery.ps1`（Local/Remote 模式，断言 ≤5s，-Repeat 3） | 证据 `docs/webdav/evidence/` |
| 防火墙放行 | `scripts/grant_nipaplay_firewall.ps1` | 管理员幂等创建 UDP 32123/TCP 1180 入站规则 |
| 根因文档 | `docs/webdav/win-discovery-rootcause.md` | RC1 防火墙（主）/RC2 静默失败（已修）/RC3 端口保留段 |

## 7. WebDAV 同步备份（AutoSync）

| 节点 | 位置 | 说明 |
|------|------|------|
| 传输层 | `lib/services/incremental_sync_transport.dart:44`（PROPFIND body/变体）、`:205 _propfind` | 绕过库的 OPTIONS 探测（`:205-261`）；3 个变体 `:51` |
| 超时/重试/限流 | `:88-90`（15s/60s/60s）、`:380-396`（3 次退避）、`:473-491`（503 冷却 30min） | `_rateLimitedUntilByServer:43` |
| 调度 | `lib/services/auto_sync_service.dart:68`、`:267/:592`（PROPFIND on iOS 注释） | main.dart `:540-543` 仅 !kIsWeb 初始化 |
| 连接墓碑 | `lib/services/incremental_sync_webdav_connections.dart` + `webdav_service.dart:314 applySyncTombstone` | 跨设备删除同步 |

## 8. 平台适配层（差异全表见 [platform-matrix.md](platform-matrix.md)）

| 平台 | 必改/必查位置 |
|------|--------------|
| Android | `android/app/src/main/AndroidManifest.xml:3-20`（INTERNET 已有；**GAP-1：无 CHANGE_WIFI_MULTICAST_STATE/MulticastLock**） |
| iOS | `ios/Runner/Info.plist:222 NSBonjourServices`（声明性预留）、`:231 NSLocalNetworkUsageDescription`、`:137 NSAppTransportSecurity` |
| macOS | `macos/Runner/DebugProfile.entitlements` + `Release.entitlements`（`network.server/client`，沙箱必查） |
| Windows | 无原生网络代码（纯 Dart）；部署侧 `scripts/grant_nipaplay_firewall.ps1` |
| Linux | 无特殊配置（标准模板） |
| HarmonyOS | `ohos/entry/src/main/module.json5`（requestPermissions）；`pubspec_overrides.ohos.yaml` |
| Flutter Web | `lib/themes/nipaplay/widgets/web_remote_access_gate.dart:27`；发现显式拦截 `shared_remote_lan_scan_dialog.dart:151` |

## 9. 已知问题（状态看板，链接修复任务）

| 编号 | 问题 | 状态 | 详情 |
|------|------|------|------|
| GAP-1 | Android 无多播锁，广播接收不可靠 | ⏳ 未修复（**未验证**：无 Android 测试设备） | [implementation-gaps.md](implementation-gaps.md) §GAP-1 |
| GAP-2 | UDP 应答器绑定失败静默 | ✅ 已修复（2026-10-11，回归测试通过） | [win-discovery-rootcause.md](win-discovery-rootcause.md) |
| GAP-3 | Windows 防火墙无自动配置 | ✅ 已有用户侧方案（grant 脚本+指引）；安装器级自动配置未做 | [win-discovery-rootcause.md](win-discovery-rootcause.md) §5 |
| GAP-4 | iOS NSBonjourServices 无消费者声明 | 📝 认知债，无功能影响 | [implementation-gaps.md](implementation-gaps.md) §GAP-4 |
| GAP-5 | Flutter Web 三链路不可用 | 📝 设计如此（能力边界） | [implementation-gaps.md](implementation-gaps.md) §GAP-5 |
| GAP-6 | HarmonyOS 广播兼容性未验证 | ⏳ **未验证**（无 OHOS 环境） | [implementation-gaps.md](implementation-gaps.md) §GAP-6 |
| GAP-7 | 搜索串行+固定间隔 | ✅ 已修复（有界并发 BFS，1.81×） | [perf-report.md](perf-report.md) §3 |
| — | 双机发现验收（稳定 PASS 3 次） | ⏳ **未验证**（单机环境） | [win-discovery-rootcause.md](win-discovery-rootcause.md) §3 |
| — | 起播延迟/内存曲线 | ⏳ **未验证**（无测试设备） | [perf-report.md](perf-report.md) §4 |

## 10. SOP：加一个新平台要改哪几处

NipaPlay 的 WebDAV/发现栈是**纯 Dart**（webdav_client + dart:io），新平台通常只需平台层配置，不需要新协议代码。按顺序核查：

1. **平台目录与权限**：新建 `<platform>/` runner 或 Flutter OHOS 式目录；
   声明网络权限（参照 AndroidManifest.xml:3 / module.json5 / Info.plist:231）；
   桌面沙箱平台（macOS 式）必须同时有 `network.server` + `network.client` entitlement
   （本机 HTTP 服务与 UDP 应答都要监听）。
2. **明文 HTTP**：WebDAV 源多为 http:// —— iOS 需 NSAllowsArbitraryLoads（Info.plist:137），
   Android 需 `usesCleartextTraffic`（AndroidManifest application 节点）。
3. **依赖可用性**：检查 `pubspec_overrides.<platform>.yaml` 模式（参照 pubspec_overrides.ohos.yaml），
   确认 webdav_client/dio/shared_preferences 有平台实现或适配包。
4. **kIsWeb 之外的运行时分支**：若新平台不支持 dart:io 的某能力（如 RawDatagramSocket 广播），
   参照 `shared_remote_lan_scan_dialog.dart:151` 的拦截模式加显式提示，不要静默。
5. **UDP 广播收发核查**（发现功能）：发送端 `broadcastEnabled`（shared_remote_lan_scan_dialog.dart:258）；
   接收端（做服务端）在 Android 系平台注意 GAP-1 多播锁；Windows 布置防火墙规则脚本。
6. **测试**：`test/lan_discovery_responder_test.dart`（协议+应答器）与
   `test/webdav_perf_baseline_test.dart`（请求模式）应在新平台 CI 原样通过；
   平台特有行为补到 `docs/webdav/evidence/`。
7. **CI 构建**：`.github/workflows/` 增加该平台 job（参照现有 build 矩阵）；分发走 GitHub Release。

## 验收自查

- 随机 5 节点抽查：`_createClient`(webdav_service.dart:755)、`_discoverByUdp`(shared_remote_lan_scan_dialog.dart:245)、
  `startServer`(web_server_service.dart:350)、`_propfind`(incremental_sync_transport.dart:205)、
  `NSBonjourServices`(ios/Runner/Info.plist:222) —— 均可直接定位。✅
- "加新平台改哪几处"：§10 七步清单。✅
