# X46：远程能力与设备程序运行

日期：2026-10-13。实现位于 `next/x46-remote-run` worktree；未 commit、未 push、未改依赖，未修改 `lib/next/ui/`。

## 完成了什么

- 扩展 Mesh 远端目录与调用范围，目标设备仍只提供自己实际注册的能力。宿主登录、退出、组网管理、信任、签发者、远程运行开关及全部远程设置写入没有开放。
- 新增 `program.run`，GUI 与 headless 共用 TaskEngine 后台任务。每台设备启动时读取本地 `program.json`，缺省关闭；设置注册表拒绝 program/remoteRun 与宿主 Mesh 配置键。设备描述提供 enabled、workingDirectory、defaultShell。
- 程序在执行设备 harness 工作目录、普通用户权限下运行。Windows 默认 cmd，可选无 profile 的 PowerShell；POSIX 使用 `/bin/sh`。有标题、运行中输出末尾、退出码、耗时、超时和取消，终态回执保存在任务中，activity 记录调用者来源、来源设备、执行设备和命令。
- 程序终态通过既有跨设备票据回到发起会话；远端 `followup.register` 也固定发起仓库和线程，保留用户登记的 instruction。支持持久去重、丢 ACK 重试和忙时排队。
- 新增 `nipa --device … sync-repository` 和 `program.repository.receive`：分块传输 Git bundle，目标当地 Git 可读取工具与脚本，不需要搬运整部视频。
- headless 增加字幕事实、同名外挂索引、持久导入、显式默认轨道选择；ffprobe 可提供内嵌字幕轨道事实。活动视图也可用于 headless。
- 更新 harness 种子事实、Mesh/HEADLESS 文档及三机运行说明。协调服务默认 JWT 账号指针改为 `/UserId`。Windows 节点监听 47832、仍广告 47822，Mac SSH 47822 转发终点改为 Windows 47832。

## 决策

### 远程范围及逐族理由

| 能力族/具体项 | 远程意义与边界 |
|---|---|
| `task.*` | 查询、等待、观察和取消发生在目标设备的后台工作；删除仍经过 destructive 入口和授权。 |
| `download.*` | 下载的数据与引擎属于目标节点，远程提交/观察已有实现继续保留。 |
| `media.*` | 目标媒体、版本、根目录和来源有设备归属；读写约束继续由目标 Harness 检查。 |
| `danmaku.*` | 目标媒体的弹幕获取和状态与当地播放/资料有关。 |
| `playback.*` | 控制目标播放器有意义；headless 没有播放器，目录不会伪装支持。 |
| `subtitle.*` | 字幕路径、内嵌轨道、导入副本和默认选择属于媒体所在设备，必须在当地操作。 |
| `history.*` | GUI 的观看记录可供跨设备查询和已授权操作；headless 没有 Classic 历史库，不制造空历史接口。 |
| `followup.*` | 目标事件的订阅和持久后续应驻留当地；会话登记通过票据回到原会话。 |
| `program.*` | 工具与脚本需要在媒体所在机器执行，由目标宿主独立授权。bundle 接收使用同一开关。 |
| `discover.*` | 搜索/发现结果同样可由目标已配置服务产生，目标实际注册项决定可用性。 |
| `sync.*` | 同步目标本地资料/来源有明确设备语义，沿用既有能力的约束。 |
| `ui.*` | 可在有界面的目标设备向用户呈现内容；headless 不提供界面能力。 |
| `state.query` | 读目标的实时状态，避免把路径、可播放性误当成 Mac 本地事实。 |
| `activity.report` | 目标脚本和远端操作可记录带来源的事实。 |
| `agent.wake` | 唤醒宿主配置的 Nipa 设备，沿用 X45 定向交付。 |
| `app.instance` | 识别目标宿主/实例、能力和运行事实。 |
| `settings.get/describe/history` | 读取当地配置与变更历史可解释目标行为；不开放远程设置修改。 |
| `accounts.status`、collections/episodes get-update、Bangumi sync-sync_status | 目标已登录账号的状态、收藏、观看状态与同步有用途；登录秘密、登录与退出仍由宿主处理。 |

按族放行适用于这些设备功能；settings/accounts 使用明确项目清单，避免宿主配置和登录入口随未来能力扩展进入远端。远端目录是实际能力的事实，不用固定数量宣称覆盖。

### 执行与仓库

选用 TaskEngine 执行器而非独立命令队列，因此任务观察、取消、回执、activity 和后续复用原有基础设施。默认超时 900 秒，上限 3600 秒；stdout/stderr 各保留最多 8192 字符，运行中每秒发布。重启后的中断任务记失败，绝不自动重放命令。

取消/超时停止普通进程树：Windows 用 `taskkill /T /F`，POSIX 根据进程树停止子进程。显式脱离父进程的 daemon 不保证可追踪。工作目录与环境选择不是 OS 沙箱；宿主打开能力即允许 Nipa 以该普通用户权限执行程序。

只继承目标 OS 的基础环境，并提供目标自己的 endpoint 文件位置；调用者环境、Mac 模型密钥、代理配置和 Codex 配置不随调用转移。输入 schema 对命令、标题与 bundle 载荷标记 secret，源端 Mesh 输入同样遮蔽，防止被拒绝的敏感输入进入 journal。成功任务/activity 留下可审计命令；识别为秘密的正文拒绝入库，输出使用现有脱敏器。当地秘密通过当地文件引用。

Git bundle 包含调用者选择的已提交引用及可达历史，不携带 `.git/config`、未提交文件或环境。每块最多 384 KiB、总计最多 64 MiB，校验 offset/SHA-256，调用者分区，重复同块幂等、冲突拒绝。保存为目标 harness `records/mesh-bundles/` 的内容寻址文件，不自动 checkout、合并或覆盖已有仓库。工具版本、合并与冲突选择留给 Agent；仓库本身及其历史必须不含秘密。

原会话返回沿用 X44/X45 已签发目标，绑定 peer、仓库与线程。手动订阅禁止选择不一致的发起线程；程序自动返回和相同事件订阅共享事实去重。`forwarded` 表示目标持久接收，实际模型 turn 状态由目标记录。

### headless 与 Classic

共用字幕能力契约和原有候选/语言逻辑，将 Flutter 原生匹配调用通过条件导入隔离，Flutter 仍使用原调用和 Dart fallback。headless 导入副本与显式选择持久保存；不读写 Classic 字幕偏好。文本字幕检查时间语法，VTT 使用现有转换器；没有宣称完整原生解析或播放器验证。无界面缺少 Classic 历史、播放器和完整账号管理的原因及真实能力范围已写入 HEADLESS。

不修改主控 UI；GUI 宿主可在隔离 profile 的 `data/next/program.json` 授权并重启，headless 在自己的 data 目录授权。删除、覆盖仍要求用户明确同意，种子只陈述能力、存储和授权事实。

转发自环采用运行说明防止：WSL 监听 47822 会被自动映射占据 Windows 47822，因此 Windows 节点改监听 47832；Mac `-L 47822` 的终点必须是 47832。开始前检查每条链最终落在节点/服务，不以绑定成功判断无环。

## 实验与证据

证据目录：[evidence/x46](evidence/x46/README.md)。已有观察没有重复执行；中断后仅补充新手动订阅观察，刷新受最终源码影响的构建。

### 本机功能观察

[主要回环记录](evidence/x46/local-loopback/local-loopback.json) 使用两台本机编译 headless、真实协调服务与 mTLS、合成账号/mock gateway；无真实账号、模型 turn、工作站连接或公网 BT。mock JWT 使用 `/UserId`，没有设置 pointer 覆盖，验证新默认值。

- 远端目录包含新增可用项，宿主设置修改入口缺席，关闭的程序能力返回明确拒绝。
- 900936 字节 Git bundle 多帧传输成功；在目标克隆并运行工具，未提交私有文件与源 `.git/config` 未传输。
- 目标脚本调用 ffmpeg 生成小 JPEG，程序成功退出，回执 exitCode=0、elapsedMs=390；实际 cwd 是目标 harness。目标 endpoint 可用，模型/Codex/代理环境没有继承，合成输出 token 被遮蔽。
- 目标 activity 含来源和命令；程序事实持久交付 `original-synthetic-thread`，源端记录 `forwarded`。这是合成原线程接收观察，没有真实模型响应。
- 取消停止父子进程；超时任务失败且 timedOut=true；退出 7 的程序失败且保留 exitCode=7。
- 远端 headless 字幕导入、选择与 sidecar 索引成功；两个轨道可见，删去合成原字幕后导入副本仍存在。
- 该轮 PID 4800/4810/4831 全退出，临时 fixture 已删除。

[新增手动订阅回环](evidence/x46/subscription-loopback/local-loopback.json) 仅运行 `sleep 2; echo subscribed`，自动回传关闭，验证远端 `followup.register` 的 custom instruction 与事实持久送回 `original-manual-thread`，目标记录 `meshSubscription`。无真实模型 turn/工作站连接。PID 50749/50760/50782 全退出，fixture 已删除。

### 自动检查与构建

| 检查 | 结果/证据 |
|---|---|
| 完整 `test/next`，本轮只跑一次 | 492 通过、4 跳过；[日志](evidence/x46/checks/test-next-full.txt)。此检查在最终手动订阅及源端 journal 修改之前，之后用相关文件补测。 |
| 最终手动后续/交付约束 | 23 通过；[日志](evidence/x46/checks/manual-returns-final.txt)。 |
| 程序、源端输入遮蔽与交付约束 | 16 通过；[日志](evidence/x46/checks/journal-and-manual-final.txt)。 |
| headless 字幕持久性与程序返回/丢 ACK | 9 通过；[日志](evidence/x46/checks/subtitle-and-return.txt)。 |
| Classic 字幕 manager/cache/Emby 回归 | 21 通过；[日志](evidence/x46/checks/classic-subtitle-final.txt)，此前 candidate 回归也通过。 |
| 最终相关静态分析 | No issues found；[日志](evidence/x46/checks/analyze-resumed.txt)。 |
| Mac GUI、headless AOT | 最新源码构建成功；[GUI](evidence/x46/checks/macos-build-resumed.txt)、[AOT](evidence/x46/checks/mac-headless-build-resumed.txt)。GUI ad hoc 签名与 strict 验证通过；[签名](evidence/x46/checks/sign-verify-resumed.txt)。没有启动 GUI。 |
| 协调服务与 Mac headless 原生库 | offline/locked 构建成功；[协调服务](evidence/x46/checks/coordinator-build.txt)、[原生库](evidence/x46/checks/native-build.txt)。 |
| Windows/WSL 最新 AOT | 编译成功，复用未变更的 X45 DLL/SO；[Windows](evidence/x46/checks/windows-compile-resumed.txt)、[WSL](evidence/x46/checks/linux-compile-resumed.txt)。未启动节点。 |

早期迭代遇到 export 位置编译错误、测试语法/未注册执行器 fixture 错误，已修复；失败日志保留在 checks，后续针对检查通过。既有 native/build phase/Swift Package Manager 提示仍存在，不影响本轮构建。构建产生的 Podfile.lock 变更已恢复；用户指明的 GeneratedPluginRegistrant 生成变更保留未处理。

Windows 最新 exe SHA-256：`313188a64b104f8d785a915cb55071842a9fe940d856e8076b2a8274840ed1dc`。
WSL 最新 AOT SHA-256：`7ab915fbbfe31d263cc6181f5c1f77e6b184d1c3e6ce158beed6c6e66fbe090e`。
工作站仅在批准的工作目录刷新公共源码与编译，编译命令已退出；没有启动节点、网络实验或真实对话，未触碰用户 Codex、download-harness 或系统配置。

## 还缺什么

- Windows cmd/PowerShell、WSL 真机程序执行、三机修正拓扑与真实 Nipa 原会话返回，留给主控亲自启动和监督验收。编译成功和本机合成交付不代替这些观察。
- headless 无 Classic 观看历史、播放器、完整账号管理或原生字幕播放解析；未配置 ffprobe 的内嵌轨道明确为 unavailable。没有伪造空能力。
- 任意程序可以访问普通用户有权访问的当地资源；未提供 OS 沙箱，显式 detached daemon 不是取消保证范围。开关的授权含义已写明。
- 本轮没有真实视频/SMB、真实账号、模型对话、工作站节点启动或 UI 观察；没有新增 GUI 开关界面，宿主通过可见配置文件授权。

主控运行说明：[X46_RUNBOOK](X46_RUNBOOK.md)，基础三机拓扑：[X45_RUNBOOK](X45_RUNBOOK.md)。

## 需要主控决定的问题

没有。
