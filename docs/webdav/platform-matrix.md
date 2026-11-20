# NipaPlay 全平台 WebDAV 实现盘点（platform-matrix）

> 盘点基准：工作区 `fix/tv-menu-switch-focus` 分支 @ `61b15e2`（2026-10-11）。
> 每个结论均带 `文件:行号` 证据，可直接 grep 定位。盘点方法：全仓 grep + 逐文件通读，
> 由只读子智能体完成初扫、主智能体复核关键文件全文。

## 0. 术语澄清（与用户口中的"WebDAV"对齐）

NipaPlay 里与"WebDAV / 主机发现"相关的其实是 **三条独立链路**：

| 链路 | 角色 | 核心代码 |
|------|------|---------|
| WebDAV 客户端 | 连接外部 WebDAV 服务器（Alist 等）浏览/播放 | `lib/services/webdav_service.dart`（2075 行） |
| 远程访问（本机服务） | 本机起 HTTP 服务 + UDP 局域网发现，供其他设备"扫描局域网"连接 | `lib/services/web_server_service.dart` + `lib/services/nipaplay_lan_discovery.dart` |
| WebDAV 同步备份 | 把播放进度/设置备份到用户自己的 WebDAV | `lib/services/incremental_sync_transport.dart` |

**本机服务不是标准 WebDAV 服务器**：全仓 `PROPFIND` 服务端实现为零，
`/api/*` 路由表见 `web_api_service.dart:38-88`，仅服务于自家 Web UI 与 App 互连。

## 1. 平台矩阵总表

| 平台 | 发现方式 | 客户端库 | 认证方式 | 并发模型 | 缓存策略 | 源码入口 |
|------|---------|---------|---------|---------|---------|---------|
| Windows | 手动输入 URL（WebDAV 连接对话框）；本机服务发现=自研 UDP 广播 32123（255.255.255.255 + /24 定向广播，3 次×220ms+800ms 等待），无结果回退 TCP 逐 IP 探测 `:1180/api/info`（32 并发）；mDNS/SSDP/NetBIOS **未实现** | `webdav_client ^1.2.2`（dio 栈，pubspec.yaml:88）+ 自研 legacy HTTP 兜底（`package:http`） | 主路径 Basic+Digest 自适应（库收到 401 读 `WWW-Authenticate` 切换，webdav_service.dart:755-770）；legacy 仅 Basic（1015-1021）；匿名=空凭证 | 目录列表/搜索全串行（递归搜索带 100ms 间隔，1922-1924）；仅 LAN 扫描用 32 并发 `Future.wait`（shared_remote_lan_scan_dialog.dart:204-227） | 目录列表 `ProcessMemoryListCache`：2 分钟新鲜期 + stale-while-revalidate + LRU 64 entries/20000 items + 并发 Future 合并（webdav_service.dart:199-201, 448-467；process_memory_cache.dart:22-29）；连接配置 SharedPreferences `webdav_connections`（136 行） | `lib/services/webdav_service.dart`（`_createClient`:755, `_validateConnection`:337, `_fetchDirectoryAll`:469, `_legacyListDirectory`:1162）；`lib/services/web_server_service.dart`（`startServer`:350）；`lib/services/nipaplay_lan_discovery.dart`（`NipaPlayLanDiscoveryResponder.start`:85）；`lib/themes/nipaplay/widgets/shared_remote_lan_scan_dialog.dart`（`_discoverByUdp`:245） |
| macOS | 同 Windows（纯 Dart，全平台同一套发现代码）；mDNS/SSDP/NetBIOS **未实现** | 同上 | 同上 | 同上 | 同上 | 同上三文件；平台差异仅在 `macos/Runner/DebugProfile.entitlements` + `Release.entitlements`：`com.apple.security.network.server=true`、`com.apple.security.network.client=true`（沙箱内允许监听+出站）；`macos/Runner/Info.plist:27-29` NSAllowsArbitraryLoads |
| Linux | 同 Windows（纯 Dart）；mDNS/SSDP/NetBIOS **未实现** | 同上 | 同上 | 同上 | 同上 | 同上三文件；`linux/` 目录无任何网络特殊配置（标准模板 main.cc/my_application.cc） |
| Android | 手动输入 URL；本机服务发现=同上自研 UDP；**未申请 `CHANGE_WIFI_MULTICAST_STATE`、未持 MulticastLock**（AndroidManifest.xml:3-20 权限列表中无此权限，全仓 grep multicast 仅命中地址过滤代码）→ 部分 Wi-Fi 驱动下收不到广播包，见 implementation-gaps.md GAP-1 | 同上 | 同上 | 同上 | 同上 | 同上三文件；`android/app/src/main/AndroidManifest.xml`（INTERNET:3、ACCESS_NETWORK_STATE:4、ACCESS_WIFI_STATE:5、usesCleartextTraffic 允许 HTTP 明文）；SMB 走独立 FFI 插件 `packages/nipaplay_smb2`（libsmb2 C 库，与 WebDAV 无关，nipaplay_smb2.h:20-27） |
| iOS | 手动输入 URL；本机服务发现=同上自研 UDP；`Info.plist:222-226` 声明 `NSBonjourServices`（`_http._tcp.`/`_https._tcp.`）但**全仓无任何 Bonjour 代码引用**——仅为本地网络权限弹窗的声明性预留；`Info.plist:231-232` `NSLocalNetworkUsageDescription`；`Info.plist:137` NSAllowsArbitraryLoads=true | 同上 | 同上 | 同上 | 同上 | 同上三文件；`ios/Runner/Info.plist`（NSBonjourServices:222、NSLocalNetworkUsageDescription:231、NSAppTransportSecurity:137） |
| HarmonyOS | 同 Android（纯 Dart 栈随 Flutter OpenHarmony fork 运行）；无 ohos 专属发现/WebDAV 代码；mDNS/SSDP/NetBIOS **未实现** | 同上（`pubspec_overrides.ohos.yaml` 仅覆盖 shared_preferences/path_provider/file_selector/desktop_multi_window，不涉及 WebDAV） | 同上 | 同上 | 同上 | `ohos/entry/src/main/module.json5`（requestPermissions：`ohos.permission.INTERNET` 等）；WebDAV 全栈复用 `lib/services/webdav_service.dart`；迁移状态 `docs/HARMONYOS_MIGRATION_STATUS.md` |

**Flutter Web 特例（第 7 种运行时）**：WebDAV 客户端/UDP 发现/本机服务**全部不可用**——
`shared_remote_lan_scan_dialog.dart:151-155` 显式提示"Web 端暂不支持局域网扫描"，
`remote_control_client_service.dart:43` 发现直接返回空，`webdav_service.dart` 的 dart:io 依赖在 Web 上无法实例化；
Web 构建定位是"远程访问 Web UI"（`main.dart:1166-1174` 的 `WebRemoteAccessGate`，
`lib/themes/nipaplay/widgets/web_remote_access_gate.dart:27`）。

## 2. 发现方式逐项确认（对照强制要求）

| 发现方式 | 是否实现 | 证据 |
|---------|---------|------|
| 手动输入 URL | ✅ | `webdav_connection_dialog.dart:420`（保存入口调 `upsertConnection`，先验证后落盘 webdav_service.dart:272-298） |
| mDNS / Bonjour | ❌ 未实现 | 全仓 grep `mdns|bonjour|nsd|zeroconf`（lib/、pubspec、原生目录）：除 iOS Info.plist 声明外零命中 |
| SSDP | ❌ 未实现 | 同上 |
| NetBIOS | ❌ 未实现 | 同上 |
| WebDAV Discovery（RFC 6764 风格 /.well-known 探测） | ❌ 未实现（有相近物：连接验证时对常见子路径 `/dav`、`/webdav` 的顺序探测，`_commonDavPathSuffixes` webdav_service.dart:175-180、`_buildCommonDavUrls`:879-899） | webdav_service.dart |
| 系统文件管理器挂载 | ❌ 未实现 | 无相关代码 |
| 自研 UDP 广播发现（32123 端口，NipaPlay→NipaPlay） | ✅ 唯一自动发现机制 | 协议 `NipaPlayLanDiscoveryProtocol`（nipaplay_lan_discovery.dart:22-77，JSON `{"type":"nipaplay_discover","v":1}` → 响应含 hostname/os/port）；应答端 `NipaPlayLanDiscoveryResponder.start`（79-120，绑定 `anyIPv4:32123, reuseAddress:true`，92-96 行）；扫描端 `_discoverByUdp`（shared_remote_lan_scan_dialog.dart:245-330） |

## 3. 认证方式细节

- **主路径（webdav_client 1.2.2 / dio）**：`WebDAVService._createClient` 把用户名密码交给
  `webdav.newClient`（webdav_service.dart:755-770）。库默认 `AuthType.NoAuth`，首个请求收 401
  后按 `WWW-Authenticate` 头自动切换：含 `digest` → DigestAuth，含 `basic` → BasicAuth
  （pub 缓存 webdav_client-1.2.2/lib/src/webdav_dio.dart:88-116）。即 Basic + Digest 自适应，
  匿名（空凭证）也可。
- **legacy 兜底路径（自研）**：`_legacyAttemptConnection`（991-1119）手工
  `base64Encode(utf8.encode('$username:$password'))`，请求头 `Authorization: Basic ...`
  （PROPFIND 1046-1048 / OPTIONS 1132-1137 / 列目录 1196-1201）。**无 Digest**。
  触发条件：主路径 `_fetchDirectoryAll`（469-512）失败后回退 `_legacyListDirectory`（1162-1248）。
- **鉴权失败判定**：401/403 → `_isAuthorizationFailure`（798-801），错误文案
  `_buildAuthorizationErrorMessage`（803-810）。
- **URL 自愈链**：连接验证 BFS（`_validateConnection`:337-419）：原 URL → `_normalizeUrl`
  （1761-1790）→ 常见子路径（/dav、/webdav 等）→ HTTPS 握手失败自动降级 HTTP
  （`_maybeDowngradeToHttp`:812-837，识别 "wrong version number"）。

## 4. 并发模型细节

- 目录列表、递归搜索、连接验证全部**串行**：`searchFiles`/`_recursiveSearch`
  （1810-1997）逐目录 `await`，`requestIntervalMs` 默认 100ms（1922-1924），
  `timeoutSeconds` 默认 30（1817），`onStopRequested` 停止信号。
- 全仓仅有的并发请求在 **LAN 扫描**：`shared_remote_lan_scan_dialog.dart:204-227`
  （32 worker 处理 254×N 个候选 IP）与 `remote_control_client_service.dart:330-358`（同款）。
- PROPFIND 变体矩阵 `_propfindVariants`（148-174）：Depth 1/0 × 两种 Content-Type ×
  带体/空体共 5 种，**顺序尝试**直到成功（这是连接验证阶段请求数偏高的直接原因，见 perf-baseline）。

## 5. 缓存策略细节

- **目录列表缓存**：`_directoryCache` = `ProcessMemoryListCache`（webdav_service.dart:199-201），
  key 为 (连接名, url, username, password, path) 五元组 record（127-133）。
  实现 `lib/services/process_memory_cache.dart`：`maxAge=2min`（22-29），新鲜期内直接命中；
  过期走 **stale-while-revalidate**（56-61：先回旧值再后台刷新）；相同 key 并发合并同一 Future
  （`_inFlight`:38/64-69/95-107）；>20000 条目的大目录不入缓存（117-119）；LRU 64 entries。
- **失效点**：`clearDirectoryCache`（535-542）在 `upsertConnection`（290）、`removeConnection`（307）、
  `applySyncTombstone`（324-326）、`updateConnectionStatus`（671）时调用。浏览器页刷新按钮
  `forceRefresh: true`（webdav_browser_page.dart:688、1275）。
- **连接配置持久化**：SharedPreferences key `webdav_connections`（136），载入 `_loadConnections`
  （211-244，含 id 迁移），删除墓碑 key `incremental_sync_webdav_connection_tombstones`（137-138）。
- **浏览页防陈旧**：`_directoryLoadGeneration` 代数计数（webdav_browser_page.dart:55、128-149）
  + UI 100ms 节流（73、1987、2012）。
- **快捷入口设置**：`webdav_quick_access_provider.dart:110-134` 定义 18 个 SharedPreferences key
  （默认服务器/目录、排序、季度文件夹模式、搜索范围与超时等），每个 setter 即时写盘（335-729）。

## 6. 本机"远程访问"服务（发现链路的服务端）

- 绑定：默认端口 1180，`HttpServer.bind(InternetAddress.anyIPv4, _port)`
  （web_server_service.dart:422，即 0.0.0.0，非 127.0.0.1）；开启 IPv6 时先绑
  `anyIPv6, v6Only:false`（405-411），失败回退 IPv4（415-420）。
- UDP 响应器随服务启动（429 行 `_lanDiscoveryResponder.start(webPort: ...)`），
  **绑定失败被静默吞掉**（nipaplay_lan_discovery.dart:117-119 仅 debugPrint）——
  UI 仍显示服务已开启，这是"开启后搜不到主机"的代码层隐患之一，根因分析见
  [win-discovery-rootcause.md](win-discovery-rootcause.md)。
- 路由表：`web_api_service.dart:38-88`（`/api/info`、Bangumi、弹幕、弹弹play、媒体库、
  遥控等约 40 条路由）；除遥控有设备批准机制
  （`remote_control_access_guard_service.dart:73-130`）外**无全局鉴权**。
- 访问地址枚举：`getAccessUrls`（web_server_service.dart:500-559），私网地址优先排序
  （`_accessUrlSortWeight`:454-490）。

## 7. 源码入口 grep 索引（验收用）

```bash
# WebDAV 客户端
grep -n "_createClient" lib/services/webdav_service.dart          # :755
grep -n "_fetchDirectoryAll" lib/services/webdav_service.dart     # :469
grep -n "_legacyListDirectory" lib/services/webdav_service.dart   # :1162
# 本机服务 + 发现
grep -n "startServer" lib/services/web_server_service.dart        # :350
grep -n "class NipaPlayLanDiscoveryResponder" lib/services/nipaplay_lan_discovery.dart  # :79
grep -n "_discoverByUdp" lib/themes/nipaplay/widgets/shared_remote_lan_scan_dialog.dart # :245
# 同步备份
grep -n "_propfind" lib/services/incremental_sync_transport.dart  # :205
# 平台权限
grep -n "NSBonjourServices" ios/Runner/Info.plist                 # :222
grep -n "INTERNET" android/app/src/main/AndroidManifest.xml       # :3
grep -n "network.server" macos/Runner/Release.entitlements
grep -n "INTERNET" ohos/entry/src/main/module.json5
```

能力差异速览与缺口清单 → [implementation-gaps.md](implementation-gaps.md)
