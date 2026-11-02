# X45：无界面组网、下载与跨设备后续

2026-10-13，worktree `x45-mesh-three`，分支 `next/x45-mesh-three`。
按主控最后更正，本轮负责实现与本机回环自动检查；工作站只编译准备。
未做真实三机联网、工作站下载或 DeepSeek 对话。运行移交见
[X45_RUNBOOK.md](X45_RUNBOOK.md)，完整证据在 [evidence/x45/](evidence/x45/)。

## 1. 完成了什么

- **无界面 Mesh**：使用现有 Rust mTLS transport 与协调服务协议，具有独立设备
  身份、测试账号保险库、加入/续证、心跳、设备查询和被调用能力。MCP 与 Mesh
  复用同一个 Harness；Windows、Linux 与 Mac 不需要 Flutter 引擎加载这套原生库。
  无界面节点强制回环监听。GUI 仍保留 Classic receiver 开关与设备审批。
- **无界面内置下载**：复用 `rust/src/api/torrent.rs` 的 librqbit，独立会话/DHT
  持久目录，支持种子、磁链、预览、文件选择、暂停/恢复/取消/会话移除。
  X40 的 checked-byte 逐文件观察、大小/路径校验、Next 文件登记、媒体身份读取和
  文件事件复用现有下载执行器；作品/剧集未知时保留 `identificationPending`。
  已补 `download.preview`、`download.directories`；无界面没有播放器与磁盘删除 Action。
- **跨设备后续**：Mac 对话的 `mesh.invoke(download.add)` 固定原设备/仓库/线程，
  下载节点将已登记文件与终态事实持久回传；Mac 接收后进入现有空闲对话分派器。
  工作站 hooks/定时程序的 `agent.wake` 按宿主 `agentDeviceId` 路由到 Nipa 设备；
  工作站不创建对话宿主。
- **设备事实与片库根**：`mesh.devices` 增加经认证的设备自我描述，包含角色、存储
  标签、宿主类型、片库根、默认下载目录；headless 对根目录与下载目录读取可用磁盘字节。
  新增 `media.library.roots.list/add/remove`，只登记只读路径，不扫描或移动文件。
  种子仅补设备/路径语义、`nipa --device`、回传与 wake 的事实。
- **平台准备**：Windows x64 与 WSL Linux x64 的原生 Mesh/下载库及纯 Dart AOT
  已在各自工作目录离线编译，未加载运行。Mac Debug 已构建并 ad-hoc runtime
  签名、严格验证；本轮未启动 GUI。主控运行说明包含协调服务、独立配置、测试账号
  stdin 登记、已知端口转发、日志状态、停止与清理。

没有 commit、push、pub get 或依赖升级；新 crate 复用现有依赖与本地缓存。
Flutter 固定 3.44.6，构建均在本 worktree，工作站输出只在 `nipaplay-next`。
构建生成的 `macos/Podfile.lock` 已恢复，原有 GeneratedPluginRegistrant 改动保留。
没有修改 `lib/next/ui/`，未启动安装版、触碰 `ui-demo`/主控实例、用户 Codex 进程
或配置、登录钥匙串、真实 NipaPlay 数据、服务/防火墙/网络模式/计划任务。
未向工作站放入模型密钥、CPA 配置、真实账号或开发 CA 私钥。

## 2. 决策与理由

1. **独立 C ABI 复用 Rust 源码。** Flutter 的 FRB adapter 和纯 Dart adapter 条件
   分离，后者使用 owned JSON C ABI。下载和 Mesh 仍是同一 Rust 实现，避免在没有
   Flutter 引擎的节点初始化平台插件。字幕事实也抽出纯接口，headless 读取既有
   持久事实，不挂 Classic 播放器；这使现有 ui_data 依赖图仍可纯 Dart 编译。
2. **连接、信任与身份由宿主守住。** `mesh.json` 启用同账号访问，签发者来自宿主
   明确配置，私钥/token 存独立 vault；没有密码或网络授权 Action。
   GUI 的 Classic 接收开关和信任表保持有效，仅同私钥的本机自调用不触发设备审批。
   无界面开发 AOT 显式接受开发 CA，GUI Release 仍仅使用内置正式 CA。
3. **正常网络能力保持。** 下载没有改为私有种子专用、回环 peers 专用或禁用公网。
   默认 DHT、tracker、本地发现启用，PEX/public peers 按 librqbit 工作；宿主可在
   `download.json` 选择开关和初始 peers。`broadcastDiscovery` 默认 **true**，保留
   原 UDP 32124 设计；false 不启动广播，续证也保留选择。GUI lab 原有不广播规则
   保留。回环夹具单独关闭广播/DHT/LSD，使用私有本机 tracker/peer，这是测试配置。
4. **下载回原会话，wake 回宿主 Agent。** 下载是已经发生的对话来源，不能因当前
   选中线程改变而漂移。Mac 提交前签发随机回传票据并落盘；接收端绑定 mTLS caller，
   Mac 收回时核对票据、来源设备、仓库和线程。wake 是新触发，目的设备由宿主指定，
   未指定 threadId 用那里持久主会话。两者不由 Agent 猜设备或给自己提升权限。
5. **先封存批次，再发送。** 目的端以来源设备/批次 ID 持久去重；ACK 丢失时源端
   重发相同批次。新文件进入另一批，避免已接收 ID 的内容被追加后丢失事实。
   网络失败留 ready，30 秒后重试交付，不自动重试下载提交或模型 turn/start。
   沿用现有数据库状态，源端 completed + `deliveryState:forwarded` 仅代表目的端
   持久接收；实际对话 turnId/turnStatus 保存在目的端。
6. **回传事实，文件留在源设备。** 路径、local/playable、文件身份都指向下载身体，
   没有跨机复制视频或声称 Mac 能本地播放。Mac 可消费回传文件事件和显式订阅，
   远端 jobId 仍需经目标设备读，不能作为 Mac 的本地 `when:{jobId}`。
7. **只读根与输出分开。** 下载输出检查词法关系与已有符号链接祖先，然后才 mkdir；
   不先写入再拒绝。动态根只登记现有目录并持久化，不能与实验数据目录相交。
   存储标签是自我描述，不是文件授权。

## 3. 自动检查与真实输出

全部运行检查只使用本机回环、合成账号与本机模拟服务；真实网站实验默认跳过。
Flutter 测试均通过 `lockf -k /tmp/nipa-next/flutter-test.lock` 排队，移除代理，
`NO_PROXY=127.0.0.1,localhost`、`CARGO_NET_OFFLINE=true`。

| 检查 | 结果 | 证据 |
|---|---|---|
| 相关 headless/X44/followup 约束 | 17 passed | [related-constraints.txt](evidence/x45/checks/related-constraints.txt) |
| 回传目标、丢 ACK、新批次、去重/重启、错误票据/peer、伪造 wake | 6 passed | [mesh-delivery-constraints.txt](evidence/x45/checks/mesh-delivery-constraints.txt) |
| 最终后续 schema/持久回执回归 | 9 passed | [followups-final.txt](evidence/x45/checks/followups-final.txt) |
| 只读根的符号链接祖先 | 1 passed；拒绝前没有 mkdir | [readonly-output.txt](evidence/x45/checks/readonly-output.txt) |
| 原 Mesh mTLS/吊销/跨账号/过期/重放 | 6 passed | [mesh-mtls.txt](evidence/x45/checks/mesh-mtls.txt) |
| Portable Rust 取消/超时/离线重复添加 | 4 passed | [rust-tests.txt](evidence/x45/checks/rust-tests.txt) |
| 全量 `test/next`，只跑一次 | 476 passed，4 skipped，1 文件加载失败，随后修复 | [test-next-full.txt.gz](evidence/x45/checks/test-next-full.txt.gz) |
| 修复后仅补 safety + Classic 下载会话/完成扫描 | 11 passed（5 Next + 6 Classic） | [classic-and-safety.txt](evidence/x45/checks/classic-and-safety.txt) |
| 相关 analyze | 0 error/warning，5 条花括号风格 info（4 条原有 ui_data） | [analyze.txt](evidence/x45/checks/analyze.txt) |
| SSH stdio relay 本机回环 | 2 TCP channels；未连接 SSH/工作站 | [stdio-relay-local.txt](evidence/x45/checks/stdio-relay-local.txt) |

全量中的失败是宿主拆分后 `authorizeMeshPeer` 不再从 runtime 导出，旧 safety 测试
因此无法编译；已恢复公开导出，5 项安全约束与 6 项 Classic 回归全部通过。
没有重复跑全量掩盖第一次结果。加上最后新增的 wake 来源约束，最终 Next 合计
482 项通过、4 项跳过；全量后只补跑受影响文件。
Rust 独立库保留复用模块未使用的播放器/删除函数告警，没有新增依赖来处理它们。

### 本机原生/AOT 回环检查

[local-summary.json](evidence/x45/local-summary.json) 是原输出摘录，完整记录
[local-loopback.json.gz](evidence/x45/local-native/local-loopback.json.gz)。
使用两个 Mac AOT headless 实例、真实开发 CA/mTLS、真实协调进程和模拟网关，
FFmpeg 自制三个 CC0 小视频，共 160180 字节；tracker/peer 只在本机回环。
其中一个实例只是**合成会话目标**，没有对话宿主或模型，票据/线程来自夹具。

互见真实输出摘录（省略能力 schema 与数据路径）：

```json
{"a":{"status":"online","devices":[
 {"name":"Local conversation fixture","online":true,"roles":["agent"]},
 {"name":"Local transfer fixture","online":true,"roles":["download","library"],
  "host":"headless","conversationHost":false,"downloadEngine":"librqbit"}]},
 "b":{"status":"online","devices":[
 {"name":"Local conversation fixture","online":true},
 {"name":"Local transfer fixture","online":true}]}}
```

实际远端片库/任务读调用：

```json
{"roots":{"roots":[],"readOnly":true},"files":{"files":[],"total":0},"tasks":{"jobs":[]}}
```

首文件回传时的源任务与目的记录：

```json
{"sourceJobState":"running","threadId":"original-synthetic-thread","state":"ready",
 "waitingFor":"Embedded chat host is not running.","event":"download.file_completed",
 "file":{"index":0,"expectedSize":34808,"actualSize":34808,"completedBytes":34808,
 "verification":"verified","imported":true,"playable":true,"identificationPending":true}}
```

终态输出：

```json
{"state":"succeeded","progress":{"completed":3,"total":3,"unit":"files"},
 "receiptVerification":"verified","downloadComplete":true}
```

源节点 wake 已进入配置目的设备的 ready 队列，来源设备保留；没有模型 turn。
三个本轮进程 PID `86160`、`86171`、`86189` 全部退出，夹具目录已删除。
这说明原生传输、逐文件登记与持久回传链在回环检查中连通；不能把它当作真实 Mac
Nipa 已被叫醒、三机互见或 Windows/WSL 运行通过。

### 编译准备

| 目标 | 构建事实 |
|---|---|
| Mac GUI Debug | `✓ Built build/macos/Build/Products/Debug/NipaPlay.app`；runtime 签名严格验证通过；allow-jit 开启，无 App Sandbox |
| Mac headless | AOT 生成，原生 `.dylib` 在可执行文件旁；回环检查实际使用 Rust 库 |
| Windows x64 | `D:\nipaplay-next\x45-headless\build\headless` 中 `.exe` + `.dll` 编译成功 |
| WSL Linux x64 | `/home/labuser/nipaplay-next/x45-headless/build/headless` 中 AOT + `.so` 编译成功 |

原始构建记录：[Mac](evidence/x45/checks/macos-build.txt)、
[签名验证](evidence/x45/checks/sign-verify.txt)、
[Windows](evidence/x45/checks/windows-native-and-dart-build.txt)、
[Linux](evidence/x45/checks/linux-native-and-dart-build.txt)。
字节大小与 SHA-256 在 [Windows manifest](evidence/x45/checks/windows-build-manifest.txt)、
[Linux manifest](evidence/x45/checks/linux-build-manifest.txt)。
所有工作站命令是复制必要源码/缓存、离线编译与只读取构建日志，没有节点、下载或对话。
没有安装工具到全局；编译器只读使用现有 Rust/Dart，Cargo home 和输出放工作目录。

### 意外与修正

- 初始模拟网关按完整 URI 比较，误拒绝合法 playhistory 查询参数；夹具改按 path 检查。
- 第一次片库文件调用漏了真实 schema 的 root/workId；只修正检查驱动输入。
- 原生初始化阶段 file_progress 可为空；backend 现在像 Classic 一样输出 nullable
  completedBytes，避免数组越界。修正后完成上述回环检查。
- 最后补正向票据接收测试时，简化夹具缺少批次截止时间，触发异步 sweep 类型错误；
  现在入口先验证交付时间/事实形状，夹具补齐真实批次字段。同时补了 wake 不能伪造
  自动下载回传、transfer-only 目的端拒绝 wake 的约束，最终 6 项通过。
- Mac 初次构建缺 Erika 预编译；使用已授权缓存 `/tmp/nipa-next/x2-erika-cache`
  成功，未修改依赖。三个失败片段和各自清理记录保留在 evidence 的 `failed-*` 目录。
- 读取过 Samba 配置的共享 path 项，但没有核实 Anime 共享路径；运行说明引用 X43
  已知 `/mnt/d/Anime/...`，要求主控确认，未读取 SMB 凭据、重新挂载或复制媒体。

## 4. 尚待主控验收与问题

待做：真实测试账号稳定身份声明确认、真实 Windows/WSL 原生运行、用户自有 SSH
转发（尤其 WSL stdio 路径）、三端互见与 Mac 两端调用、真实 DeepSeek 三条自然语言
轨迹、首集完成回原线程及脚本 wake 后的真实对话 turn。辅助账号登记程序与跨机转发
脚本只交付供主控运行，未用它们执行联网实验。

正式发布仍沿用 Mesh 既有缺口：GUI Release 的正式 CA 常量为空，声明名与正式 OID
需原 Mesh 主控流程确认；本轮没有改变服务器协议或放松账号约束。
无界面没有播放、完整账号管理、Classic 扫描识别或内嵌模型；这些不属于本轮目标。

需要主控决定的问题：**没有**。上述是真机验收移交与既有发布事项，没有新的实现决策阻塞。
