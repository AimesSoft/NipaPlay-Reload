# Windows 主机发现 Bug 根因分析（win-discovery-rootcause）

> 现象："开启 WebDAV（远程访问）后，其他设备'扫描局域网'搜不到主机。"
> 分析日期：2026-10-11；基线 `61b15e2`。证据文件在 `docs/webdav/evidence/`。

## 0. 先把模糊问题量化：6 个子问题逐条裁决

发现链路架构（证据：[platform-matrix.md](platform-matrix.md) §6）：

```
扫描端（手机/TV）                        被扫描主机（PC，Windows）
_discoverByUdp (shared_remote_lan_scan_dialog.dart:245)
  → UDP 广播 {"type":"nipaplay_discover","v":1}
    → 255.255.255.255 + 各 /24 定向广播:32123 ────────→ NipaPlayLanDiscoveryResponder
      （3 次连发 ×220ms + 800ms 等待）                    绑定 0.0.0.0:32123 (nipaplay_lan_discovery.dart:92-96)
  ← 单播回包 nipaplay_discover_response ←──────────────    回包给 datagram.address (:108)
  [若 UDP 无果] 回退 TCP 逐 IP 探测 :1180/api/info ───→ WebServerService (web_server_service.dart:422, 0.0.0.0:1180)
    （32 并发 × 254 IP，350ms 连接超时）
```

| # | 子问题 | 裁决 | 证据 |
|---|--------|------|------|
| 1 | 本机服务监听 0.0.0.0 而非 127.0.0.1？ | **是 0.0.0.0，此项不成立** | `HttpServer.bind(InternetAddress.anyIPv4, _port)` web_server_service.dart:422；应答器 `RawDatagramSocket.bind(InternetAddress.anyIPv4, 32123, reuseAddress: true)` nipaplay_lan_discovery.dart:92-96。仅当用户开启 IPv6 且 v6 绑定成功时才走 `anyIPv6, v6Only:false`（:405-411） |
| 2 | Windows 防火墙是否放行端口？ | **这是主根因：本机无任何 NipaPlay 防火墙规则** | 实测 `Get-NetFirewallApplicationFilter -Program '*nipaplay*'` 返回 0 条规则（evidence/windows_security_state.log）。zip 分发无安装器预置规则（windows/runner 无网络初始化代码）。首次绑定弹"允许访问"一旦被取消或网络为"公用"配置文件 → 入站 UDP 32123 与 TCP 1180 同时被默认拒绝 → UDP 发现与 HTTP 回退**双双失败**，与症状完全吻合 |
| 3 | mDNS/Bonjour 广播是否发出？ | **不适用：NipaPlay 不使用 mDNS**。发现协议是自研 JSON-over-UDP:32123 | 全仓 grep `mdns/bonjour/nsd/ssdp/netbios` 零实现；iOS `NSBonjourServices`（Info.plist:222-226）是无代码引用的声明。抓包验证：pktmon/Wireshark 需要管理员权限，本环境未取得（**未验证**），抓包操作指引见 §4 |
| 4 | 客户端发现逻辑是否过滤掉本机/网段？ | **过滤存在但正确，非本 bug 根因**；有一个 /24 掩码局限 | `_isPrivateIpv4` 只扫私网（10/192.168/172.16-31，dialog:692-703）；排除自身 IP（683 行）合理。**局限**：网段前缀取 IP 前 3 字节（673 行），非 /24 掩码（如 /23）时定向广播地址算错——但 `255.255.255.255` 全网广播仍会发出（dialog:288-291），同网段通常仍可达 |
| 5 | 受 Windows 网络发现（Network Discovery）服务影响？ | **不受影响** | NipaPlay 不使用 WSD/SSDP/FDResPub（问题 3 同源证据），系统"网络发现"开关与本功能无关 |
| 6 | IPv6/IPv4 双栈导致失败？ | **不会** | 服务端默认仅绑 IPv4（v6 是可选开关且失败自动回退 v4，web_server_service.dart:404-425）；扫描端仅枚举 IPv4（dialog:661-665）；回包走请求方地址单播。仅"纯 IPv6 局域网"不支持（边界，非缺陷） |

**结论**：症状 = "UDP 发现 + HTTP 回退同时无响应"。两个通道同时失效的共同解释是 **RC1（防火墙默认拒绝入站）**；代码层还存在 **RC2（应答器绑定失败被静默吞掉）**，它把 RC1/RC3 的后果放大成"无任何提示的搜不到"。

## 1. 根因清单

### RC1（系统层，主根因）：入站端口无放行规则

- Windows 对入站 UDP/TCP 默认拒绝；NipaPlay 以 zip 分发（GitHub Release），无安装器环节预置防火墙规则。
- 一切正常的局域网里，只要主机侧防火墙拦掉 UDP 32123（发现）+ TCP 1180（回退探测），扫描端表现就是"未发现任何设备"（dialog:523）。
- 实测本机：无 NipaPlay 规则（evidence/windows_security_state.log）。

### RC2（代码层，已修复）：应答器绑定失败静默

- 修复前 `NipaPlayLanDiscoveryResponder.start` 捕获异常仅 `debugPrint`（原 nipaplay_lan_discovery.dart:117-119），`WebServerService` 不感知（原 :429）。**HTTP 服务正常 + UDP 发现死亡 = 用户视角的"玄学故障"**。
- 绑定失败的常见诱因：UDP 32123 被其他程序占用；Hyper-V/WSL 动态保留端口段（`netsh interface ipv4 show excludedportrange protocol=udp` 可复核；本机实测不在段内，evidence/windows_security_state.log）。
- **修复**：`start()` 返回 `Future<bool>` 并记录 `lastStartError`；`WebServerService` 新增 `lanDiscoveryRunning` / `lanDiscoveryError`；设置页"远程访问与遥控"在服务运行但发现不可用时显示红色告警（remote_access_receiver_settings_section.dart `_buildLanDiscoveryWarning`）。

### RC3（边界场景，已文档化）：Hyper-V/WSL UDP 端口排除段

- Windows 的动态端口排除可随机吞掉 32123（重启 winnat 可解）。验证脚本 L2 会自动检测。

## 2. 修复内容与回归覆盖

| 项 | 文件 | 说明 |
|----|------|------|
| 应答器失败可见 | `lib/services/nipaplay_lan_discovery.dart` | `start()` 返回 bool + `lastStartError`；新增 `bindOverrideForTest` 测试注入点（@visibleForTesting，生产不受影响） |
| 服务层状态暴露 | `lib/services/web_server_service.dart` | `lanDiscoveryRunning` / `lanDiscoveryError`，随启动/停止/失败路径维护 |
| 设置页告警 | `lib/settings/pages/remote_access_receiver_settings_section.dart` | 服务运行中但发现不可用 → 红色告警块，给出常见原因与"手动连接不受影响"说明 |
| 回归测试 | `test/lan_discovery_responder_test.dart` | 4 个用例：协议线格式锁定 ×2（防协议被改，满足"协议改动须有回归测试"约束）、5 秒回包、占用时失败可见 |
| 验证脚本 | `scripts/verify_webdav_discovery.ps1` | 见 §3 |
| 防火墙放行脚本 | `scripts/grant_nipaplay_firewall.ps1` | 管理员执行，幂等创建 UDP 32123 / TCP 1180 入站放行（按 exe 路径限定） |

**协议兼容性声明**：本次修复未改动任何线上字节格式（请求/响应 JSON 由测试锁定），
`nipaplayLanDiscoveryPort`、协议版本、复用语义全部未动。

## 3. 验证：修复前失败 / 修复后通过

脚本核心断言：**发现应答 ≤ 5 秒**。Local 模式下，若本机 NipaPlay 未运行，由脚本内置的协议兼容应答器充当被扫描方（线格式一致，由 flutter 测试双向锁定）。

### 修复前 / 故障态（端口被独占占用 → 模拟 RC1/RC2/RC3 的"无应答"世界）——必须 FAIL

```text
[FAIL] L1 UDP 32123 本机不可绑定（被占用或被系统保留）——NipaPlay 应答器将启动失败
[PASS] L2 UDP 32123 不在系统保留段内
[WARN] L3 防火墙中未找到 UDP 32123 / NipaPlay 放行规则
[FAIL] L4 5 秒内未收到发现应答（目标 3 个）
RESULT: FAIL（2 项断言失败，2 项警告）        # 退出码 1
```
（全文：[evidence/verify_local_fail_blackhole.log](evidence/verify_local_fail_blackhole.log)）

### 修复后 / 正常态（发现链路可用）——PASS

```text
[PASS] L1 UDP 32123 本机可绑定
[PASS] L2 UDP 32123 不在系统保留段内
[PASS] L4 发现应答 1292 ms（阈值 5s）：{"type":"nipaplay_discover_response","v":1,...,"port":1180}
RESULT: PASS（0 项失败，2 项警告）            # 退出码 0
```
（全文：[evidence/verify_local_pass.log](evidence/verify_local_pass.log)）

### Dart 回归测试（4/4 通过）

```text
00:00 +4: All tests passed!
```
（全文：[evidence/flutter_test_lan_discovery.log](evidence/flutter_test_lan_discovery.log)）

### 双机验收状态：**未验证**

验收标准要求"同网段两台 Windows 机器上稳定 PASS 3 次"。本环境只有一台 Windows 机器且无管理员权限，无法执行。缺失的验证条件：
1. 第二台同网段 Windows 机器（或任一台手机/TV 真机跑 NipaPlay 扫描）；
2. 主机上管理员权限执行 `grant_nipaplay_firewall.ps1` 放行端口；
3. 在服务端机器运行：`powershell -File scripts\verify_webdav_discovery.ps1 -Mode Local`；
4. 在客户端机器运行 3 次：`powershell -File scripts\verify_webdav_discovery.ps1 -Mode Remote -ServerIp <服务端IP> -Repeat 3`。

## 4. 抓包取证操作指引（本环境未执行：pktmon/Wireshark 需管理员，**未验证**）

在被扫描主机上（管理员 PowerShell）：
```powershell
pktmon filter add -p 32123
pktmon start --capture --comp nics -f C:\temp\32123.etl   # 或工作区路径
# 客户端机器执行一次扫描，然后：
pktmon stop
pktmon format C:\temp\32123.etl -o C:\temp\32123.txt
```
预期正常态可见：客户端 IP → 主机 IP 的 UDP 32123 请求（载荷 `{"type":"nipaplay_discover","v":1}`）+ 主机 → 客户端的回包；若只见请求无回包，回看 RC1（回包方向不会被拦，通常意味着请求包根本没到达主机——检查 AP 隔离/子网）；若请求到达主机但主机无监听，回看 RC2/RC3（此时设置页会出现红色告警）。

## 5. 用户侧配置指引（发版后可放进 README/FAQ）

1. **防火墙**：管理员 PowerShell 执行 `scripts\grant_nipaplay_firewall.ps1 -ExePath "NipaPlay.exe 完整路径"`；
   或手动：Windows 安全中心 → 防火墙 → 允许应用通过防火墙 → 勾选 NipaPlay 的"专用"和"公用"（至少专用）。
2. **网络配置文件**：若 Wi-Fi 被识别为"公用网络"，建议改为"专用"（公用配置文件默认更严格）。
3. **端口被占/被保留**：`netsh interface ipv4 show excludedportrange protocol=udp` 若覆盖 32123，
   以管理员执行 `net stop winnat && net start winnat` 重排保留段；或改用其他远程访问端口（UDP 发现不受该端口影响）。
4. **核对**：开启远程访问后进入设置页，若出现"局域网自动发现不可用"红色告警，按告警文本处理；
   无告警仍搜不到时，在被扫描主机跑 `-Mode Local`、客户端跑 `-Mode Remote -ServerIp <IP>`，按 FAIL 项定位。
5. **仍不通**：检查路由器 AP 隔离（客户端隔离）会拦掉所有局域网互访，此为网络侧限制。
