# WebDAV 性能基线与优化报告（perf-report）

> 数据文件：[perf-baseline.json](perf-baseline.json)（由
> `flutter test test/webdav_perf_baseline_test.dart` 生成，重跑即刷新）。
> 环境：Windows 主机 + 本地 loopback mock WebDAV 服务器（每个 PROPFIND 引入 60ms
> 模拟往返延迟），被测对象为真实 `WebDAVService`（webdav_client 1.2.2/dio 全链路，
> 未注入任何测试替身）。基线日期 2026-10-11，`61b15e2` + 本轮修复。

## 1. 指标基线与目标对照

| 指标 | 目标 | 基线实测 | 判定 |
|------|------|---------|------|
| 单次目录遍历 HTTP 请求数 | ≤1（理想 1 次 PROPFIND） | **1**（`PROPFIND path Depth:1`，冷态） | ✅ 达标 |
| 切换/返回目录重复请求 | 0 | **0**（2 分钟缓存窗口内回访任意已浏览目录） | ✅ 达标 |
| 进入目录到列表就绪时延 | <500ms | **85ms**（含 60ms 模拟服务器往返；纯协议+解析开销 ≈25ms） | ✅ 达标（本地骨架）⚠️ 真实网络未测 |
| 全局搜索（12 目录树） | —（无明确目标，属"臃肿"感知点） | 串行 **1101ms** | 基线 |
| 全局搜索（优化后） | 快于串行且请求集合不变 | 并发 **608ms**（1.81×） | ✅ 本轮唯一优化项 |
| 播放起播延迟 | <2s | **未验证**（无测试设备，见 §4） | ⛔ |
| 播放中内存曲线 | 无持续上涨 | **未验证**（同上） | ⛔ |

## 2. 瓶颈定位（哪一步耗时最长、哪个请求重复最多）

对 7 个场景逐一计时与逐请求记录（见 JSON `scenarios`）：

- **目录浏览路径没有请求浪费**：冷态每目录恰好 1 次 PROPFIND（webdav_client 主路径直发，
  无前置 OPTIONS）；连接添加 2 次（OPTIONS ping + PROPFIND 根目录）为设计最小值。
  重复请求为 0 的原因是 `ProcessMemoryListCache`（2 分钟 SWR + 并发 Future 合并，
  process_memory_cache.dart:22-29/95-107）。
- **真正的耗时大头在搜索**：`searchFiles` 旧实现为深度优先串行——每个目录
  `await listDirectoryAll` 串行等待完整往返，且目录间强制 `requestIntervalMs`（默认 100ms）
  间隔。12 目录 ×（60ms 往返 + 50ms 间隔）≈ 1.1s；目录树越深越线性恶化，
  间隔开销在深树中占比可达 45%。
- **播放路径**（起播延迟、内存）在本环境不可测，未定位（见 §4）。

## 3. 本轮优化：搜索从串行 DFS 改为有界并发 BFS

### 改动

- `webdav_service.dart`：`_recursiveSearch`（117 行）替换为 `_searchBreadthFirst`：
  - 广度优先任务队列 + `visited` 集合（每目录仍恰好请求一次，并防环）；
  - 并发度 `maxConcurrency`（新可选参数，默认 3，上限 8）；
  - **全局限速**：请求发出前统一按 `requestIntervalMs` 节流（旧实现是"每次递归 sleep"，
    新实现是"全局每 interval 至多 1 个新请求"），对服务端的平均请求速率不高于串行版；
  - 停止信号/超时/进度回调语义保持一致；`searchFiles` 其余参数与返回结构不变，
    UI 调用点零改动（默认值生效）。

### 协议兼容性（约束 4）

请求集合逐字节不变：串行与并发的 (method, path, depth) 指纹完全一致
（`search_request_pattern_identical: true`），结果集一致（`search_results_identical: true`）。
两个断言已写进测试硬校验，防止后续回归。

### 预期收益 vs 实测收益

| 项 | 预期 | 实测 |
|----|------|------|
| 搜索耗时（12 目录树，60ms 往返，50ms 间隔） | ~0.65s（限速下界 11×50ms+1 往返） | **608ms**（串行 1101ms → 1.81×） |
| 深树收益上限 | min(并发数, 间隔允许速率) × 往返重叠 | 与一致；真实收益随单请求 RTT 增大而放大（RTT 越高，重叠价值越大） |
| 服务端压力 | 不高于串行版（全局每 interval ≤1 新请求） | 请求集合与串行逐条相同，仅时间分布更均匀 |

### 优化前/后对比数据

同场景同 JSON 对比（见 `verdicts.search_speedup.actual`）：
`{"serial_ms": 1101, "parallel_ms": 608}` —— 重跑测试即可复现刷新。

## 4. 未验证项（显式声明）

| 指标 | 原因 | 补测路径 |
|------|------|---------|
| 播放起播延迟（<2s） | 需 WebDAV 源+播放器 UI 真实起播；本机无 Android/iOS 测试设备（用户声明"没有测试平台"，MuMu 被明确禁用），Windows 端到端起播未自动化 | 真机 + mitmproxy/Charles 记录 PROPFIND→GET→首帧时序 |
| 播放内存增长曲线 | 同上，需真机长稳观测 | DevTools memory / HapRay 长稳 30min |
| 真实网络下的目录时延（<500ms） | 本基线为 loopback+固定 60ms 模拟延迟，不含真实 RTT/抖动 | 对真实 NAS/Alist 采集同场景 |
| HapRay / flutter-devtools-mcp 采集 | 环境中未部署该工具链 | 有设备后按上表补测 |
