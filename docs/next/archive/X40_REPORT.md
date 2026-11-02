# X40：下载管理与逐文件交付

## 1. 完成了什么

- `download.read` 返回完整 manifest 的逐文件索引、选中状态、引擎已校验字节、完整状态、完整本地文件的 `playable`、引擎的 `streamable`。完整文件另核对实际大小；初始化时未知进度是 null，不拿预分配文件大小冒充已下载字节。
- `download.play` 对单个完整本地文件直接核对路径 / 大小并从磁盘播放；即使整个任务还没结束或已暂停，也不为播放第一集恢复其余下载。未完成文件保留原来的流式播放方式。
- `download.add.fileIndices` 原子地传给 librqbit 的 `only_files`；`download.select_files` 支持单任务和批量替换选择，包括空选择。保留落盘路径和数据，并读回核对。引擎没有普通文件优先级接口，明确报告 `filePrioritySupported:false`。
- 每个完整文件先核对引擎校验状态、规范路径、实际大小，再沿用下载入库适配器登记本地视频；开启自动扫描时复用 Classic 扫描器。持久记录在任务的 `checkpoint.completedFiles`，不必等整任务成功。无身份的文件仍登记，不虚构作品。
- 新事件 `download.file_completed`，对象为 `JOB_ID:FILE_INDEX`，`data` 为 `{jobId, infoHash, file}`。同名 hook 与 X25/X31 后续使用同一个完成事实；无 hook 程序也可登记后续。重启恢复完成事实，保留实际完成时间，不把登记前的旧完成当成新的后续。已提交的同一文件 hook 不重跑。
- 文件完成事实只授权对应的规范本地文件，覆盖下载中、暂停或随后取消的任务。未完成邻居和下载目录不获授权，替换指向别处的符号链接也不继承授权。整任务回执的语义保留。
- 健康事实包括 live/seen/connecting/queued/dead peer、各 live peer 的实际传输/校验计数、确实提供过字节/校验片段的连接数、采样间字节变化与无进展时长。`lastProgressAt` 在观察到增加前为 null；观察范围不跨进程重启。所在盘的可用字节来自 Unix `statvfs.f_bavail` / Windows `GetDiskFreeSpaceExW`，失败返回 null 和实际错误。
- 种子只补充下载事实和「下载交给你以后，管理它也是你的工作」的目标，没有增加安排顺序、换源、轮询或通知的步骤。

未改 UI、字幕、依赖、数据库版本或持久历史；未 commit / push。共享下载 service 只增加默认省略的可选文件选择参数，Classic 调用保持原来的全部文件选择。媒体授权的两处查询与事件程序的启动恢复接线是逐文件交付所需的集成修改。

## 2. 决策

**文件完成是持久事实，父任务仍表示当前选中文件的整体交付。** 文件校验记录随父任务保存，事件使用文件索引定位。现有成功回执不改写。对已完成选择再加入未完成文件，创建新的观察任务并返回其 jobId，继续使用同一个 native handle / 哈希 / 目录；携带此前的文件完成记录及原事件对象，不重发第一集事件。重复 add 仍返回当前哈希已有任务。

**控制与观察要协调，完整任务扩选还要重新打开 native storage。** 选择修改前让父任务观察 worker 退出，暂停 native torrent；改选并读回后恢复此前的运行状态。librqbit 对已完成任务增加文件需要 pause / unpause 来重新打开文件，因此终态任务也经过这一步。这里没有在代码中决定选择什么、先下载什么。

**登记与识别分开。** 完整视频通过已有 `AppDownloadLibrary.lookup` 登记并读回 fileId；自动扫描是独立的已有设置。逐文件识别使用自己的完成扫描标记，最后的整任务扫描不重复尝试它们。识别待定不阻塞完成事件，不冒充有作品身份。

**来源的分类不能猜。** librqbit 9.0.1 公开统计没有 tracker 做种数，也没有 peer bitfield / 片段可用分布。`seeders` 和 `pieceAvailability` 保持 null，并附原因；连接数或提供过数据的连接数不改名为做种数。这个范围仍缺真实做种数和当前可供片段的精确事实，需引擎开放相应统计才能补齐。

## 3. 实验与真实输出

### 隔离与合法材料

全部实例直接运行本 worktree 的 Debug 可执行文件，临时 profile、独立数据库 / 下载目录 / harness。没有启动安装的应用，没有按应用名查找，没有访问登录钥匙串或真实数据目录，没有访问 `/Volumes/Media`，没有激活窗口或像素点击。实验默认安静。

三集材料由实验者用 FFmpeg `lavfi testsrc2` 自制，不含第三方素材，明确以 CC0-1.0 交付并允许分发：702,145、780,978、865,025 字节，总计 2,348,148 字节。临时 BT peer / tracker 只监听回环地址，应用实际使用 librqbit 下载和校验。它验证多文件下载身体，不证明公网 BT 可达性，也不是某个商业动画的匹配实验。

实验配置照 X23：只在 profile 复制 Codex 配置和认证文件，配置模型 `deepseek-v4.1-flash`，复制公共 CA，设置 `CODEX_HOME`、CA 路径及 `NO_PROXY`；不修改用户的 `~/.codex`。保存输出前对当前认证副本、端点令牌及敏感环境值进行替换。

脚本和输出在 [evidence/x40](evidence/x40/)；`body/operations.json` 是已有选择 / 进度证据，`delivery/operations.json` 是补上的完成 / hook / 后续 / 扩选证据，`agent/` 是正确 harness 上的真实模型回合。`agent-setup-failure/` 保留先前准备错误的轨迹。

### 身体：逐文件读数与中途改选

`body` 的实际内置引擎初始选择为 `[0,2]`；`download.select_files` 读回变为 `[0,1]`，任务号、哈希和落盘目录保持一致。随后读数：

```json
{"files":[{"index":0,"included":true,"completedBytes":131072,"expectedSize":702145,"complete":false},{"index":1,"included":true,"completedBytes":0,"expectedSize":780978,"complete":false},{"index":2,"included":false,"completedBytes":0,"expectedSize":865025,"complete":false}],"health":{"connectedPeers":1,"seenPeers":1,"deadPeers":0,"checkedBytesChange":131072,"sampleSeconds":4.001,"seeders":null,"pieceAvailability":null},"disk":{"availableBytes":197654192128}}
```

这个脚本随后误读了公开任务中不存在的私有 `checkpoint` 字段，发生 `KeyError`，停止并清理。没有把它归为身体失败，也没有重跑这段已成立的选择 / 进度实验。后续 `delivery` 只补未完成的阶段。

### 身体：第一集独立完成、hook 与后续

`delivery` 初始选择 `[0,1]`。受控 seed 暂时保留第一集之后的完整片段，便于观察第一集和整体完成之间的边界；共享边界片段中的下一集字节是引擎真实行为。16:24:14 UTC，父任务仍为 `running`：

```json
{"files":[{"index":0,"completedBytes":702145,"expectedSize":702145,"complete":true,"playable":true,"actualSize":702145},{"index":1,"completedBytes":2367,"expectedSize":780978,"complete":false,"playable":false},{"index":2,"completedBytes":0,"expectedSize":865025,"complete":false,"playable":false}]}
```

同一时点 `library.files` 只有第一集，`available:true`、实际本地 locator、`episodeId/workId:null`。没有把不完整的第二集登记为可播作品。

登记的后续已由文件完成证据触发，`state:ready`，触发数据包含：

```json
{"event":"download.file_completed","objectId":"job-3c4053dd3aac3837f6361408243903d5:0","file":{"index":0,"expectedSize":702145,"actualSize":702145,"completedBytes":702145,"complete":true,"verification":"verified","imported":true,"media":{"fileId":"file-bf9a0ce7-4296-4305-a233-51276999b73f","workIds":[],"identificationPending":true}}}
```

这个身体阶段主动关闭了实验聊天宿主，因此 ready 的原因是等待宿主，不声称已经启动 Agent 回合。同名 hook 随后成功，回执 `exitCode:0`、`verification:verified`、`elapsedMs:415`，stdout 是上述标准事件对象。真实 Agent 派发观察见下一节。

释放剩余 seed 后，前两集于 16:24:24 UTC 完成。把终态选择扩展为 `[0,1,2]` 返回新任务 `job-2d9202687280a4e13ba82c79f0ddbaec`，仍使用 handle `0` 和原目录；第三集于 16:24:39 UTC 完成。脚本逐字比较旧 receipt 的规范 JSON，保持相同。最后 hook 任务只有索引 0、1、2 各一次，前两集扩选后没有重跑。

### 真实 DeepSeek：她选择全选并轮询，没有登记后续

首次准备错误的 harness 没有 `AGENTS.md` 或 `nipa`，模型尝试自写 BT 客户端，宿主出现 `FormatException: Missing extension byte (at offset 1)` / stdout broken pipe。它不用于判读 Nipa 的内置下载管理。该实例已按 PID 退出并删除 profile。

正确 harness 安装完整种子并初始化 git。自然语言目标是「把这套 CC0 三集动画合集下下来，第一集好了就告诉我」，只另给种子 / 许可证位置和隔离边界，没有给下载、改选或后续步骤。服务端确认模型 `deepseek-v4.1-flash`、provider `cpa`。

后续在同一实例、任务和线程中继续观察；实验 seed 初始每连接延迟 90 秒超过引擎请求超时，已在同一回环端口修复响应，torrent 字节保持完全相同。没有重启应用、重新提交下载或另发用户回合。

时间线全部是 2026-10-12 UTC（本地为 2026-10-13，UTC+8），原始命令 / 消息在 `agent/chat-events.jsonl`，身体快照在 `agent/operations.json`，15 秒宿主采样在 `agent/liveness-samples.json`：

| UTC 时间 | 实际观察 |
| --- | --- |
| 16:32:49 | 原始自然语言回合开始，实际模型 `deepseek-v4.1-flash`。 |
| 16:33:09 | 核对 CC0 许可证、种子 manifest 和能力后调用 `download.add`；没有给 fileIndices，三集全选。她说「三集都很小，我先盯着它」。没有改选或登记后续。 |
| 16:34:04–16:37:29 | 她读到 0 字节、连接变 dead、长时间无进展，查询本地 tracker，做原始 BT 握手 / 数据请求，并只读 seed 程序。tracker 的 `complete:1` 是她直接查询得到的来源事实，不是 `download.read.seeders`。 |
| 16:37:03 | 实验者修复 seed，保持同一端口、torrent 字节、应用 PID `52337`、jobId 与线程；此时仍是原用户回合。 |
| 16:37:48 | 她自行调用暂停 / 恢复，重新连接后开始传输。没有由身体规定这项处理。 |
| 16:37:54 | 首次身体采样看见第一集 702,145 / 702,145、`complete:true`、`playable:true`，第二集仅 2,367 字节、第三集 0，父任务 `running`。没有已登记后续。即时文件索引查询还为空，这个采样发生在引擎完成和下一次入库观察之间；不能把 native 完整时间当成索引提交时间。 |
| 16:38:13 | 她在当前回合的消息里说「第一集已经下完（702145 字节完整），正在下第二集。继续等」。首次告知用户发生在整套完成之前。 |
| 16:38:39 | 实验者释放剩余 seed gate；应用 / 任务继续运行。 |
| 16:39:44 | 第二集完整，第三集 122,509 字节；连接来源计数真实提供过校验片段。该 peer 的计数为 3 次连接 / 2 次错误。 |
| 16:39:50 | 三集引擎字节都完整。 |
| 16:40:06–16:40:13 | 她核对成功回执、逐文件大小 / fileId，使用 ffprobe 检查 H.264、640×360、8/9/10 秒，最终告诉用户三集已完整可播。原回合完成于 16:40:14；共 43 条命令，约 444 秒，包含实验 seed 故障及诊断时间。 |
| 16:40:51–16:40:52 | 最终索引有 3 个 `available:true` 文件、无作品 / 剧集绑定；获取当前实例 JPG，再按 PID 关闭应用并删除 profile。 |

健康 / 空间的真实补充读数（第一集完整时）：

```json
{"health":{"connectedPeers":1,"seenPeers":1,"deadPeers":0,"secondsWithoutProgress":0,"seeders":null,"pieceAvailability":null},"sources":{"connectedPeersWithCheckedPieces":1,"connectedPeersWithFetchedBytes":1,"checkedPieces":43,"fetchedBytes":704512},"disk":{"availableBytes":194048499712}}
```

**排列与通知的观察**：她没有优先选择第一集，而是根据合集小选择全选；第一集先到也受实验 seed 的片段供应控制，不能声称是她安排了优先级。她先在当前回合告知了第一集完成，其余确实由 librqbit 后台继续；她本人仍保持回合、通过 shell sleep / 多次读取等待。`followup.list` 始终为空，没有 `followup.register`、没有同名 hook，也没有文件后续唤醒回合。身体阶段已证明登记的文件后续会变 ready，但本轮自然语言实验**没有证明真实 DeepSeek 被文件后续叫醒**。

**准备观看的观察**：三个文件登记、校验、可播事实成立，Agent 也检查了视频格式；没有实际打开 NipaPlay 播放器验收解码。她没有建立作品 / 剧集身份、摆观看入口或交付展示卡片，最后还问用户是否要登记作品和补资料。[最终截图](evidence/x40/agent/result.jpg) 已打开核对：首页为空，没有作品入口。因此本轮完成的是下载文件交付和通知，不是「第一集在首页已准备好」的完整观看交付。

**不采纳没有证据的诊断**：她的最终答复把「引擎不自动重连」当成原因并泛化暂停 / 恢复经验。这个结论不成立：seed 最初每次连接都重新延迟 90 秒；恢复传输后 peer 计数还显示了多次连接。真实输出能确认无进展、连接失败、seed 修复和她暂停 / 恢复后的进展，不能从这轮推出一般性的引擎重连缺陷。没有因此改 Classic 或增加自动恢复策略。

收尾额外的派发核验尝试发现该 profile 已完成清理，未执行任何登记或新回合；没有为补出成功的唤醒轨迹重复实验。

### 验证与收尾

- 相关下载 / 后续 / hooks / X35 授权测试：57 项通过；新增完成、选择及重启约束组合：35 项通过；恢复时间语义相关：10 项通过。
- 完整 `test/next` 加受影响的 Classic 下载 service、完成扫描、任务控制和 session storage 测试只运行一次，470 项通过、4 项跳过，耗时 1 分 33 秒。
- 最后检查发现 `download.play` 原来仍按整任务 finished 决定磁盘 / 流播放，已补上文件级磁盘分支。独立约束测试检查父任务暂停时不恢复剩余下载、大小改变拒绝播放、符号链接越界拒绝播放。最终相关测试 35 项通过，证据为 `verification/download-delivery-final.txt`。这个修正只跑相关测试 / analyze / 构建，没有重跑媒体或对话实验；实际播放器解码仍未声明验收。
- Rust `cargo check --locked` 通过；保留既有 warning。最终 Dart analyze 无 error / warning，仅 `media_service.dart:42` 的既有花括号风格 info。
- 最终 Debug `--no-pub` 构建成功，最终产物重新 adhoc 签名及 `codesign --verify --deep --strict` 通过，allow-jit / 无 app-sandbox 验证通过（`verification/signature-final.txt`）。构建生成的 Podfile.lock 恢复；按约定保留 GeneratedPluginRegistrant 生成变化。
- 证据秘密扫描：8 个已知敏感值零匹配，认证字段模式零匹配，见 `verification/secret-check.json`。
- 4 个实际应用 PID `43623`、`43901`、`44314`、`52337` 已退出，对应 profile 均删除；收尾按这些 profile 的完整路径检查，存活进程数为 0。只为修复 seed 而结束原 driver PID，应用及 Agent 始终保留到正常回合完成。

## 4. 问题

需要主控决定的问题：没有。

仍缺引擎未公开的真实做种数与 peer 片段可用分布；当前工具明确给出未知值及来源限制。没有通过观察计数推断“卡住应该怎么办”，也没有新增依赖或修改引擎版本。

自然语言实验还有两项未成立：Agent 自行登记并收到文件后续，以及把第一集准备成界面上的观看入口。事实、选择与事件工具均已提供；没有把这些判断和步骤硬编码到身体里。
