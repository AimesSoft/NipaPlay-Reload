# WebDAV/局域网 实现缺口清单（implementation-gaps）

> 基于同目录 [platform-matrix.md](platform-matrix.md) 的盘点结果。
> 每条缺口附证据与影响面；"建议"仅为方向，落地前需按任务约束补回归测试。

## GAP-1 ｜ Android 无多播锁，UDP 广播接收不可靠（影响：Android 作为服务端）

- **现状**：AndroidManifest 未申请 `CHANGE_WIFI_MULTICAST_STATE`，代码未持有
  `WifiManager.MulticastLock`（AndroidManifest.xml:3-20；全仓 grep multicast 仅命中
  `web_server_service.dart:531` 的地址类型过滤）。
- **影响**：在多数 Android Wi-Fi 驱动上，未持 MulticastLock 时内核会过滤广播/多播入包。
  NipaPlay 的 UDP 发现请求是定向广播（`nipaplayLanDiscoveryPort=32123`，
  nipaplay_lan_discovery.dart:6），Android 设备**作为被扫描方**时可能收不到广播 →
  其他设备扫描不到它（Android 热点/部分 ROM 上尤甚；`255.255.255.255` 受影响概率低于
  /24 定向广播，依驱动而定）。
- **注意**：Android 作为**扫描方**只发不收等待回包（回包是单播，走已建 socket 状态），
  基本不受此影响。
- **建议**：申请权限 + 在 `NipaPlayLanDiscoveryResponder.start`（nipaplay_lan_discovery.dart:85）
  成功后持有 MulticastLock、stop 时释放。属协议无关的平台适配，需真机回归（**当前无测试设备，未验证**）。

## GAP-2 ｜ UDP 发现应答器绑定失败静默（影响：全平台，Windows 最显著）【已修复 2026-10-11】

- **现状（修复前）**：`NipaPlayLanDiscoveryResponder.start` 捕获所有异常仅 `debugPrint`
  （nipaplay_lan_discovery.dart:117-119）；`WebServerService.startServer` 不感知结果
  （web_server_service.dart:429）。
- **影响**：UDP 32123 被占用（同机双开）或落在 Windows Hyper-V/WSL 的 UDP 端口排除段
  （`netsh interface ipv4 show excludedportrange protocol=udp` 可复核）时，HTTP 服务正常
  但发现死掉，用户视角 = "开启了但搜不到主机"，且无任何提示。
- **修复状态**：✅ 已修复 —— `start()` 返回 bool 并记录 `lastStartError`，
  `WebServerService` 暴露 `lanDiscoveryRunning/lanDiscoveryError`，设置页显示红色告警；
  回归测试 `test/lan_discovery_responder_test.dart`（4/4 通过）。
  根因分析与证据：[win-discovery-rootcause.md](win-discovery-rootcause.md)。

## GAP-3 ｜ Windows 防火墙无自动配置（影响：Windows 作为服务端）

- **现状**：windows/runner 无任何网络初始化代码（platform-matrix §1），安装包（zip 分发）
  不预置防火墙规则；本机实测 `Get-NetFirewallApplicationFilter -Program '*nipaplay*'`
  返回空（2026-10-11）。
- **影响**：Windows 首次绑定 0.0.0.0:1180 / 0.0.0.0:32123 时弹"允许访问"对话框，
  用户点"取消"或网络profile为"公用"时，入站 TCP 1180 与 UDP 32123 同时被拦 →
  UDP 发现与 HTTP 回退探测**双双失败**，扫描端表现为"未发现任何设备"
  （shared_remote_lan_scan_dialog.dart:523）。
- **修复**：用户侧指引 + `scripts/grant_nipaplay_firewall.ps1`（管理员一键放行），
  详见 [win-discovery-rootcause.md](win-discovery-rootcause.md) §修复与指引。

## GAP-4 ｜ iOS NSBonjourServices 为无消费者的声明（影响：无功能影响，属认知债）

- **现状**：`ios/Runner/Info.plist:222-226` 声明 `_http._tcp.`/`_https._tcp.`，
  但全仓无 NSNetService/NSNetServiceBrowser 代码（grep 零命中）。
- **影响**：无功能损失（发现走自研 UDP），但会误导后续开发者以为有 Bonjour 能力；
  本地网络权限弹窗实际由 `NSLocalNetworkUsageDescription`（:231-232）+ 首个本地连接触发。
- **建议**：保留（无副作用），或在 platform-matrix 引用处标注"预留"。

## GAP-5 ｜ Flutter Web 端三条链路全部不可用（影响：Web 运行时）

- **现状**：WebDAV 客户端/UDP 发现/本机服务均依赖 dart:io，无 Web 实现；
  扫描入口显式拦截（shared_remote_lan_scan_dialog.dart:151-155），遥控发现返回空
  （remote_control_client_service.dart:43）。
- **影响**：Web 构建只能作为"远程访问 Web UI"被服务端使用（main.dart:1166-1174 的 Gate）。
- **定性**：设计如此，非缺陷；列为能力边界。

## GAP-6 ｜ HarmonyOS 为纯 Dart 直译，无平台加固（影响：OHOS 设备）

- **现状**：`ohos/entry/src/main/module.json5` 仅申请 `ohos.permission.INTERNET` 等，
  无 UDP 广播收发相关的 ohos 权限（如分布式多播）专项处理；`pubspec_overrides.ohos.yaml`
  不涉及 WebDAV 依赖。
- **影响**：与 Android GAP-1 同类的广播接收可靠性风险，且 OHOS Flutter fork 对
  `RawDatagramSocket` 广播行为的兼容性未验证（**未验证：无 OHOS 测试环境**）。
- **建议**：真机验证后再决定是否需要 ohos 专属加固。

## GAP-7 ｜ 递归搜索全串行 + 100ms 间隔（影响：WebDAV 搜索耗时）【已修复 2026-10-11】

- **现状（修复前）**：`_recursiveSearch`（webdav_service.dart）深度优先逐目录 await，
  目录间强制 `requestIntervalMs=100`（1922-1924）。
- **影响**：深目录树搜索耗时线性叠加（例：3 层 × 10 目录 ≈ 3s 纯间隔开销）。
- **修复状态**：✅ 已修复 —— 改为有界并发 BFS（`maxConcurrency` 默认 3）+ 全局 `requestIntervalMs`
  速率限制（对服务端平均速率不高于串行版）；请求集合与结果集与串行版逐条一致，
  由 `test/webdav_perf_baseline_test.dart` 硬断言锁定。数据：
  [perf-baseline.json](perf-baseline.json)（串行 1101ms → 并发 608ms，1.81×）、
  [perf-report.md](perf-report.md) §3。

## 平台 × 能力差异速览

| 能力 | Windows | macOS | Linux | Android | iOS | HarmonyOS | Flutter Web |
|------|---------|-------|-------|---------|-----|-----------|-------------|
| WebDAV 客户端（Basic/Digest 自适应 + legacy 兜底） | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌（dart:io 不可用） |
| UDP 发现广播发送（扫描方） | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌（显式拦截） |
| UDP 发现应答（服务端 :32123） | ✅ | ✅ | ✅ | ⚠️ GAP-1 无多播锁 | ✅ | ⚠️ GAP-6 未验证 | ❌ |
| 本机 HTTP 服务（:1180，0.0.0.0） | ⚠️ GAP-3 无防火墙配置 | ✅（沙箱 entitlement 已配） | ✅ | ✅ | ✅ | ✅ | ❌ |
| WebDAV 同步备份 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| mDNS/SSDP/NetBIOS | ❌ | ❌ | ❌ | ❌ | ❌（仅 Info.plist 预留声明） | ❌ | ❌ |
| 目录缓存（2min SWR + LRU） | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | 同左（栈可用性除外） |
