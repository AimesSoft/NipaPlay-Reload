# Next 与 Mesh 架构审核

日期：2026 年 10 月 27 日。审核基线：`37c756a27310eae155ad652ffd6554dffa9b3fdf`。

后续实施记录：[Classic / Next 隔离与跨设备 SQL](CLASSIC_NEXT_ISOLATION_SQL_20261027.md)。下文保留审核时的代码与验证结论；其中“尚未修改源码”指审核阶段，不能据此判断后续实现状态。F01–F12 等其他问题未因本轮隔离/SQL 修改而自动解决。

Next 的基本方向是 Agent 决策，宿主执行并保存事实，各设备拥有自己的数据。Classic 与 Next 只按明确契约共享数据，不能据此共享自主识别逻辑或继续隐藏运行 Classic 界面。当前的主要问题在系统边界：Classic 自动匹配可以进入 Next 身份库，媒体读取与控制调用共用防重放容量，目录把资料与图片准备绑在一起，跨设备投影重新实现身份和弹幕规则，迁移把目录非空当作数据完整。继续只修单个报错会反复遇到同类故障。

本轮确认四项应优先处理的缺陷：媒体读取能耗尽整个节点的 RPC 防重放容量；合辑文件的不同作品片段会被合并并串写进度；Harness 更新能覆盖被 Git 忽略的个人文件；仅有缓存的沙盒候选能替换包含有效数据库的普通目录。另有一条高置信 Erika 主线程等待环尚需实机验证。

## 审核范围与证据

历史修复与当前实现一起检查，覆盖用户指定的九个交界面。三个 Astra 子审核分别检查 Mesh 传输、身份与弹幕、宿主生命周期；主审核整合证据，补充跨作品分段合并复现及 BanG 实例只读核验。

审核期间仓库 HEAD 前进到 `53429eb6f`，相对基线只改六个界面、版本展示和相关测试文件；本报告引用的后端、迁移和补丁文件未变。原有未提交内容没有纳入基线，没有改动产品源码、修复真实数据库、触发 Classic 扫描或重新安装应用。

证据分为三类：

- **执行复现**：运行真实领域实现或从基线原样提取的处理函数，使用临时数据库、受控调度或本机 TCP。它证明指定条件下的行为，不代表用户已在实机遇到。
- **静态确认**：完整代码路径支持结论，但尚未做对应故障注入或设备验收。
- **设计风险**：缺少明确预算、冲突规则或恢复契约，具体故障规模仍待测量。

用户已有实机事实单独保留：原故障是 Mac 播放端与 Windows 来源端在内网使用时，单条作品超过旧页限制，目录同步失败后被误标离线，尚未开播。故障发生时没有可靠的两端构建号记录。修复后两端确认安装过 `2708=b8b855ab3`，目录刷新、HEAD 200、Range 206 和正确字节、MDK/Erika 播放及 Erika 约 80 秒播放后 seek 到约 85 秒均有记录。最新两次后端修复没有据此获得实机验收。

## 用户澄清后的架构边界

本节是同日补充，核对时 HEAD 为 `5830634a8`。用户明确要求保留 SQL，并强调 Classic 与 Next 隔离、Next 的刮削判断由 Agent 通过能力层完成。本报告初版把共享媒体数据解释得过宽，过于侧重 Classic 导入的 adopt 和增加专用协调操作，未把自主识别入口本身列为首要问题；这里修正该判断。以下区分现状与建议，尚未修改产品源码。

### 共享数据不等于共享决策与生命周期

[RESEARCH.md:21](/Users/sakiko/Desktop/NipaPlay-Reload/docs/next/RESEARCH.md:21) 明确“基础设施负责执行、续传与回执；Agent 负责决定”；[media/README.md:22](/Users/sakiko/Desktop/NipaPlay-Reload/lib/next/media/README.md:22) 明确“Next 的媒体识别判断属于 Agent”。更晚的 [player-core.md:17](/Users/sakiko/Desktop/NipaPlay-Reload/docs/next/design/player-core.md:17) 用户决定写明“两边隔离，只共用数据层”，并明确不借用 Classic 的播放器、界面和叠层。研究纲领里尚未拥有 Next 独立界面时的“两张脸”描述，不能用来推翻这项后续决定。

当前有四条需要一起处理的代码路径：

1. **界面只隐藏，没有隔离。** [next_ui_gate.dart:91](/Users/sakiko/Desktop/NipaPlay-Reload/lib/next/ui/shell/next_ui_gate.dart:91) 在 Next 下仍挂载 Classic；该文件的 `Offstage` / `TickerMode` 只控制显示与动画，不会阻止初始化、订阅或后台 Future。Classic 页的首帧回调仍会启动扫描。应让共享服务独立于界面存在，Next 不以隐藏 Classic 页面维持服务。
2. **Next 默认允许 Classic 启动识别。** [next_core.dart:466](/Users/sakiko/Desktop/NipaPlay-Reload/lib/next/next_core.dart:466) 的判定是 `!nextOpen || automatic.startupScanEnabled`，而 [system_settings.dart:30](/Users/sakiko/Desktop/NipaPlay-Reload/lib/next/settings/system_settings.dart:30) 默认值为 true。随后 [scan_service.dart:240](/Users/sakiko/Desktop/NipaPlay-Reload/lib/services/scan_service.dart:240) 进入 Classic 智能刷新、哈希匹配与历史写入。这不是 Next 的纯文件索引。已有测试只覆盖把此开关设为 false，未证明默认 Next 隔离。
3. **下载完成仍自动调用 Classic 匹配。** [download_library.dart:91](/Users/sakiko/Desktop/NipaPlay-Reload/lib/next/downloads/download_library.dart:91) 调用 `scanCompletedFiles`，后者使用 `ConcurrentVideoProcessor` 选择匹配并写 Classic 历史。该适配器没有 Next/Classic 识别模式隔离；共享下载执行器在文件完成及整项完成时调用它。Next 应登记完成文件、校验、索引并产生事实，由 Agent 或其已配置的自动化决定是否识别及绑定。
4. **Classic 观察被隐式提升为 Next 身份。** [media_runtime.dart:32](/Users/sakiko/Desktop/NipaPlay-Reload/lib/next/media/media_runtime.dart:32) 在历史通知后同步，创建时也同步；[media_service.dart:528](/Users/sakiko/Desktop/NipaPlay-Reload/lib/next/media/media_service.dart:528) 在显式 bind 之前导入；[projection.dart:10](/Users/sakiko/Desktop/NipaPlay-Reload/lib/next/media/projection.dart:10) 在投递前后再次导入；下载 lookup 也会同步。只关闭启动开关或一个 listener 不足以隔离。进度同步、投影回读确认、旧库显式导入与新身份接受应分清，不能顺带创建或恢复 Next 作品归属。

以上是当前调用链证据，不等于已确定 BanG 事故究竟由哪个入口触发；空 invocation/job 字段仍不足以还原该次调用。已有 `classic_match` 数据应保留并提供迁移/显式导入路径，不能用删除用户现有库来实现隔离。

补充执行验证：[默认 Next 启动策略夹具](/tmp/nipa-next-classic-boundary-probe_test.dart) 使用真实 `NextCore` 策略和 `ScanService.startStartupRefresh`，将 Next 两个开关设为开启，其余采用默认值；Classic startupAction 实际执行一次。`flutter test --no-pub --reporter expanded /tmp/nipa-next-classic-boundary-probe_test.dart`：1 项通过，断言的是现有越界行为。夹具仅用临时数据库及替代扫描 action，没有扫描真实媒体，没有访问元数据服务；没有将此结果当作 BanG 原事故的触发记录。

Next 正常识别流程已有对应原语：文件枚举/探测/哈希 → `media.hash.match`、`media.metadata.search/get` 提供候选 → Agent 作判断 → `media.identity.bind_batch` 或 SQL 写入明确计划 → 宿主验证、审计、回执与界面/Mesh 投影。宿主可以自动执行确定的工作，例如已选身份的资料刷新、已授权下载和按既定设置取弹幕；这些不应顺带推断新的作品归属。隔离要求不是让 Agent 逐条参与视频 I/O，也不是取消已有明确授权的自动化。

### SQL 是正式通用能力，跨设备应直接提供

`e39ab12d7` 明确写过 “Not offered to mesh peers”，[runtime.dart:29](/Users/sakiko/Desktop/NipaPlay-Reload/lib/next/mesh/runtime.dart:29) 当前也未允许 `db.*`。这是历史实现决策；用户现在的要求是保留 SQL，并让 Mesh 支持直接使用目标设备数据库，不能以旧限制作为拒绝理由。通过 `program.run` 绕到本地 CLI 证明该任务确有需求，也使“禁用远程 DB”没有形成一致的使用边界。

建议为 `db.describe/query/write/undo` 注册直接远程契约，使用目标设备同一 `DbService`、同一写入队列、现有预演/冲突核对/事务/审计/undo 和刷新机制。远程 SQL 作用于目标设备自己的 next.db，使用目标原始实体 ID；它不是对接收端合并视图或多个设备执行一个分布式事务。能力发现应准确显示这四项可路由，用户无需启用任意程序执行来完成 SQL 操作，也无需为同一已授权工作重复人工确认。

不能只加入白名单就声称可靠远程写入已完成。当前 [db/service.dart:583](/Users/sakiko/Desktop/NipaPlay-Reload/lib/next/db/service.dart:583) 消耗内存 preview 后提交；响应丢失时重试该 preview 只会得到“已使用、过期或重启”，不能区分已提交与未提交。远程契约应补持久的操作键与可查询回执，将 preview 与目标/调用来源关联，并覆盖提交成功但响应丢失、目标重启、重复提交、过期预演及大响应。查询与提交结果沿用分块能力，断开不能表示撤销。这里是要补齐的行为，不是当前已经具备的保证。

### bind_batch 不是通用 work merge，SQL 不因领域原语增加而退出

`media.management.bind_batch` 目前是身份绑定的影响预览与 `expectedPlan` 包装，可以进入现有精确 adopt 分支；它没有合并两个 work 的所有引用、覆盖、轨道、进度、别名及回收旧实体的完整语义。Agent 对这个 API 的疑问是合理的，应在能力说明中明确边界。

常见合并流程可以在 harness 中先形成可复用脚本，或在证据表明需要宿主原子性时提供专用协调原语；二者均不能替代、收窄或废除 SQL。SQL 的表语义、写后失效通知与审计契约需要完善，使 Agent 能自行表达当前专用 API 尚不支持的整理，而不是每遇到一个新任务都等待宿主新增工具。

**修复顺序调整：** 先封闭 Next 中未授权的 Classic 自主识别及身份回灌入口，保留共享持久数据和显式导入；同时保留并补齐跨设备 SQL。adopt 继续作为存量数据协调和明确导入的保护，不能作为继续后台运行 Classic 识别的理由。F01–F04 等数据与播放问题仍须修复。

## 优先处理的缺陷

### F01 媒体块耗尽整个节点的调用容量

**P1，执行复现。**

[runtime.dart:1650](/Users/sakiko/Desktop/NipaPlay-Reload/lib/next/mesh/runtime.dart:1650) 为所有 RPC 设置一小时 deadline。[runtime.dart:1948](/Users/sakiko/Desktop/NipaPlay-Reload/lib/next/mesh/runtime.dart:1948) 每接受一次请求保存 invocation ID 和 nonce 两项，达到 20000 项就拒绝新请求，并在分派前追加日志、执行 flush。[library.dart:917](/Users/sakiko/Desktop/NipaPlay-Reload/lib/next/mesh/library.dart:917) 每读取最多 1 MiB 视频就发一次这样的 RPC。

因此，所有调用设备合计每个未过期窗口最多接受 10000 次调用，目录、presence、continuation 和视频共享额度。仅计算满块视频，约 9.77 GiB 或一小时平均约 23.3 Mbit/s 就用尽；实际还需扣除目录等开销。之后连小型可达性探测也被拒绝，错误表现为 `Invalid or replayed Mesh request`，并非设备真的离线。

复现直接调用原 `MeshRuntime._dispatch`，注入相当于 9999 次历史调用的 19998 条未过期记录；第 10000 次读取执行，第 10001 次不再进入领域读取，presence 同样被挡。压缩后未过期记录仍全部保留；令两项过期后读取恢复。FFI stub 只接收响应，没有代替防重放逻辑。这不是 10000 次真实 TLS 压测。

建议把高吞吐只读数据传输与持久写操作去重拆开：共享身份认证，分别管理请求窗口和资源预算，为控制请求保留容量。不要只把 20000 调大，也不要取消写操作的持久幂等保护。

### F02 相同合辑文件把不同作品片段合并并串写进度

**P1，执行复现。**

[library_projection.dart:593](/Users/sakiko/Desktop/NipaPlay-Reload/lib/next/mesh/library_projection.dart:593) 在作品合并时只加入 `file:<sample>`，丢弃文件时间范围；随后 [library_projection.dart:668](/Users/sakiko/Desktop/NipaPlay-Reload/lib/next/mesh/library_projection.dart:668) 按季集号合并剧集，没有阻止不同明确身份被同一编号连在一起。

复现输入：两台设备保存相同合辑文件。A 将 `[0,60000)` 绑定到 TMDB TV 作品 100 的 S1E1；B 将 `[60000,120000)` 绑定到作品 200 的 S1E1，两集有不同 provider episode ID 与各自 scope。范围输入符合现有绑定契约，跨设备也没有禁止此种归属。

实际 `LibraryWorker.compose` 输出：两部作品变成一部，两集变成一集，两个源设备实体指向同一 mergedEpisodeId。再记录这条合并集的 0.5 进度，两个源引用都得到 0.5，见 [library_projection.dart:255](/Users/sakiko/Desktop/NipaPlay-Reload/lib/next/mesh/library_projection.dart:255) 和 [library_projection.dart:737](/Users/sakiko/Desktop/NipaPlay-Reload/lib/next/mesh/library_projection.dart:737)。已经超出显示去重，可能选错片段、污染续播和混淆管理目标。

建议把文件摘要当作内容线索，连同时间范围、发行上下文和明确身份检查后才能建立等价关系；季集号只能在已确认同一作品与发行的范围内比较。不同明确身份存在冲突时保留分离并报告冲突，禁止传递合并跨越它。这个反例也说明不能用“同 fileId 一律折叠”修复 BanG 的重复。

### F03 官方种子更新覆盖被 Git 忽略的个人文件

**P1，执行复现。**

[harness_repository.dart:264](/Users/sakiko/Desktop/NipaPlay-Reload/lib/next/harness_repository.dart:264) 调用 `git merge --ff-only`，未指定 `--no-overwrite-ignore`。

在临时仓库中，让用户的 `tools/private.py` 被 `.gitignore` 忽略，随后官方种子增加同路径 tracked 文件。实际更新返回 `updated` 并声称保留个人文件，内容却被官方版本替换；原文件没有 Git 历史副本。普通 untracked 文件保护不能覆盖这个场景。

建议显式禁止覆盖 ignored 文件，补文件、目录与路径类型冲突的回归；回执只能在文件保护确实成立时声称保留。

### F04 非空沙盒不等于有效完整数据来源

**P1，执行复现。**

[SandboxMigration.swift:496](/Users/sakiko/Desktop/NipaPlay-Reload/macos/Runner/SandboxMigration.swift:496) 用 `containsData` 决定是否接管整个数据组，[SandboxMigration.swift:528](/Users/sakiko/Desktop/NipaPlay-Reload/macos/Runner/SandboxMigration.swift:528) 以整个 `Documents/nipaplay` 发布。`9a18a82c4` 处理了完全空目录，但任意缓存文件仍可使候选有效。

使用真实 Swift 迁移实现的临时夹具：沙盒只有 `cache/image`，普通目录有有效 `next/next.db`。运行后普通目录被归档，活跃路径下的 Next 数据库消失。原字节仍在归档，不是不可恢复的物理删除，但用户会再次看到数据消失。

第二个已复现子场景为 **P2**：[SandboxMigration.swift:523](/Users/sakiko/Desktop/NipaPlay-Reload/macos/Runner/SandboxMigration.swift:523) 只检查当前 SQLite family 是否存在；0 字节 current DB 会阻止旧布局中的有效 DB 被选中。另有非空配置时，最终发布的历史库仍为 0 字节。

建议按数据库、配置、身份及凭据引用、持久弹幕、个人 Harness 等持久域检查有效性和代际一致性。缓存不能决定数据库来源；SQLite DB/WAL 必须作为同一代整体处理。保留现有归档、校验及中断恢复机制。

### F05 Erika 显示器通知绕过媒体操作门控

**P1，高置信静态风险，未做实际播放器死锁复现。**

[erika_media_io.rb:121](/Users/sakiko/Desktop/NipaPlay-Reload/macos/patches/erika_media_io.rb:121) 为五个 surface 入口加入等待门控，但当前依赖生成的 Swift 中，屏幕变更 observer 仍在主线程直接调用 `reportDisplayHeadroom()`，后者取得同一 `nativeCallLock`。

触发条件：播放器已有 NSView、相关 headroom native 符号可用，open/seek worker 持锁等待 Dart loopback 数据；此时跨屏移动或改变显示器参数，使主线程再次等该锁。该路径可重建原来的等待环。已有约 80 秒播放及 seek 成功不覆盖这个通知入口。

建议建立统一的 native 操作调度，涵盖 open、seek、close、换源、surface、屏幕通知与销毁；不能依赖枚举几个入口加 gate。当前 Ruby anchor 校验能在上游文本变化时明确失败，这一点应保留。

## 其他已复现问题

### F06 HTTP 半关闭被误判为放弃响应

**P2，执行复现，属于 `37c756a27` 新增路径。**

[library.dart:912](/Users/sakiko/Desktop/NipaPlay-Reload/lib/next/mesh/library.dart:912) 把 Socket 读方向 EOF 设置为 `disconnected`。客户端完整发送 GET 后只关闭发送方向、继续接收响应时，这个 EOF 不代表其放弃响应。

从基线原样提取 `_serve`，仅用延迟数据替代远端 `_bytes`，以真实本机 TCP 对照：普通客户端得到 2 MiB 正文；发送端 half-close 得到 HTTP 200 但正文 0 字节，声明的 Content-Length 不变，`lastError` 仍为 null。应按写失败、连接重置或明确取消处理响应消费者退出，保留在途读取的有界期限。

### F07 停止期间启动续体重新创建登录定时器

**P2，执行复现。**

[runtime.dart:303](/Users/sakiko/Desktop/NipaPlay-Reload/lib/next/mesh/runtime.dart:303) 的 stop 先取消 watcher，再等操作队列；[runtime.dart:415](/Users/sakiko/Desktop/NipaPlay-Reload/lib/next/mesh/runtime.dart:415) 的启动在 await 返回后无 generation 检查便创建 watcher。

受控顺序为 start → token 读取阻塞 → stop → token 返回 null。两者完成后实际为 `status=disabled, loginWatchActive=true, coordinator=null`。之后的 tick 可改写禁用状态，或使用已清空的 coordinator。完整生命周期需要串行化或在每个异步边界检查 generation。

### F08 Mesh 再次用稀疏来源覆盖完整来源

**P2，执行复现。**

[library_projection.dart:36](/Users/sakiko/Desktop/NipaPlay-Reload/lib/next/mesh/library_projection.dart:36) 按对象与语言选择较新的一整条 source。设备 A 有 actors，设备 B 的同对象较新但只有 title/imageUrl，合并 sources 后演员消失。数据库原始快照未被删除。

`b8b855ab3` 的单机逐字段补齐没有沿用到跨设备投影。应共用带来源时间和字段 provenance 的合并规则，而非整条 latest-wins。

### F09 明确空数组在综合视图中被历史值填回

**P2，执行复现。**

[identity_store.dart:1115](/Users/sakiko/Desktop/NipaPlay-Reload/lib/next/media/identity_store.dart:1115) 跳过空列表和空 Map。旧快照 actors 非空，新快照 actors=[]，实际 `sources.fields.actors=[]`，而综合 `fields.actors` 仍为旧演员。

应区分未提供、明确空值、明确删除和抓取失败。已证实的是 `[]` 两视图矛盾；没有假定当前协议中所有 null 都代表来源删除。

### F10 自动哈希等待期间新增的准确身份未被重新检查

**P2，执行复现。**

[automatic.dart:141](/Users/sakiko/Desktop/NipaPlay-Reload/lib/next/danmaku/automatic.dart:141) 等待 hash 后，只重新检查弹幕绑定，没有重新读取媒体身份与 FileEpisode 关系。

复现：文件原先无准确身份，hash 挂起；期间确认 Dandanplay episode 9999；hash 返回候选 7101。实际仍自动绑定并抓取 7101，之后可能持续优先复用这条错误弹幕绑定。自动提交应核对媒体身份修订和关联集合，并让后来明确确认的身份胜出。

### F11 Mesh 弹幕恢复与本机选轨规则不同

**P2，执行复现。**

[service.dart:523](/Users/sakiko/Desktop/NipaPlay-Reload/lib/next/danmaku/service.dart:523) 的远端分支逐条安装，绕过本机 [service.dart:630](/Users/sakiko/Desktop/NipaPlay-Reload/lib/next/danmaku/service.dart:630) 的同视频选择。[library.dart:601](/Users/sakiko/Desktop/NipaPlay-Reload/lib/next/mesh/library.dart:601) 把 File 和 Episode 的 accepted 绑定都打包。

相同平台/视频的 File 与 Episode 两份持久池，本机挂 1 条，远端挂 2 条。旧池、不同偏移或控制状态可能重新参与；显示层可能折叠部分内容，不能据此保证绑定语义一致。应共用一个带来源优先级、时间范围和控制状态的播放挂载计划。

### F12 Harness 最后校验与 merge 之间仍有分支竞态

**P2，确定性调度复现。**

[harness_repository.dart:259](/Users/sakiko/Desktop/NipaPlay-Reload/lib/next/harness_repository.dart:259) 校验 HEAD 和 branch 后另起进程执行 merge。临时 Git wrapper 在此边界切到 other 分支，结果原 main 未更新、other 被 fast-forward，回执仍为 updated。

这不是自然并发概率测试。它证明末尾一次检查不是工作区事务。需要明确更新期间的工作区所有权、目标 ref 和提交，并在回执中记录实际更新对象。

## BanG 历史事故的独立核对

用户提供的 Agent 记录及 [个人记忆](/Users/sakiko/nipaplay-harness/memory/mesh-remote-library.md) 是事故线索，不能将其中全部推论视为已经证实的根因。

2026 年 10 月 27 日约 18:21（台北时间），通过现有 Nipa CLI 对工作站做只读核验：

- `media.identity.get`：`work-bangdream` 有 TMDB TV 300112、Bangumi subject 583729、Dandanplay anime 19566 三个 accepted、explicit_binding 作品身份，conflicts 为空。
- `state.query library.episodes`：该源作品当前确实有 13 个原始 episode，结果未截断。
- `media.metadata.ui_facts`：total=13、titles=13、stills=13、danmaku=13，所报告的缺身份、缺字段、缺集级 Dandanplay ID 均为空。这是保存事实及界面投影读回，不是 13 集逐个实际播放验收。

没有执行扫描、绑定、解绑、SQL 写入、undo 或远端程序。CLI 对大响应自动保存的本地 records 文件只是查询输出。

| Agent 的判断或建议 | 当前独立结论 |
| --- | --- |
| Classic 在已有显式归属旁创建重复作品 | 历史问题有代码依据。实际身份写入点是 `IdentityStore.importLegacy`；`classic_match` 和空 invocation/job 字段证明 Classic 观察来源，不能单独定位到某一个扫描器直接写表。 |
| 建作品前按 fileId 采用已有作品 | `228b55c7d` 已加 `_classicFileTarget`：仅唯一显式整文件集、且无冲突身份时采用。条件不能放宽成无条件按 fileId 合并。 |
| 所有同文件冲突应直接复用 | 当前 `_checkObjects` 只在旧 owner 是 classic_match、且双方文件及范围集合完全相同时接管，并记 adopt 审计；这是合理的安全条件。 |
| 原子批次导致 40 集全回滚，所以应取消原子性 | 回滚本身是保护。应提前逐项预检，明确冲突条目；独立作品或不相互依赖的项可由调用者分批。不能让一个绑定计划半提交后仍被理解为完整成功。 |
| 展示层缺少按 fileId 去重 | 当前已有按文件摘要和范围的剧集合并。13→15 的具体两集缺口需要事故时的集身份、编号和范围，不能仅凭汇总记忆归因。只按 fileId 折叠会破坏合辑。 |
| outcome_unknown 是设备忙锁或超时太短 | 证据不足。历史大响应超帧已有明确失败路径；当前普通调用上限是一小时，媒体的 15 秒短限只用于 file read。需要实际失败阶段与字节数，不能直接归因为数据库锁。 |
| db.* 不跨设备可能是遗漏 | 是明确边界：`e39ab12d7` 提交说明写着 “Not offered to mesh peers”。当前 Mesh 白名单没有 db，`app.capabilities.remoteCallable` 才表示远程可调用；本机能力存在不等于远程可用。 |
| media.management.bind_batch 是合并两个 work 的操作 | 它是 bind/unbind 的预览与 expectedPlan 包装，见 `management.dart:169`；不是通用实体 merge。它可走已有 adopt 路径，但不负责合并两个 work 的所有覆盖、引用、轨道和旧实体。 |

存量重复仍需要专门协调。新增临时测试证明：Classic 与 TMDB 两套层级已存在时，重复 import 不修复；改变 Classic 标题后 import 仍不修复。相同 fingerprint 会直接跳过，外部对象仍由旧 Classic owner 持有时，导入继续复用旧 owner。

另一个测试证明：Classic work 有 2 个文件、目标 work 只有其中 1 个时，`[work adopt, episode adopt]` 在上层采用处拒绝且完全回滚；独立提交那个精确匹配 episode 可以成功。对 BanG 的两边同 13 文件、同范围情况，完整预览后按 work → release → episode 组织采用有对应实现，但不应声称它自动清除所有旧实体。

身份协调计划应列出保留实体、迁移绑定、文件范围、冲突、需保留的弹幕/字幕/手工覆盖/历史别名及将退休的空壳，原子提交并留下可审计的恢复依据。Agent 可以用 SQL 或已有原语表达计划，再按真实使用证据决定是否沉淀专用工具。直接 SQL 有预演与 undo；[db/table_docs.dart:250](/Users/sakiko/Desktop/NipaPlay-Reload/lib/next/db/table_docs.dart:250) 也明确它不写 Classic 投影 outbox，不自动生成完整领域事件或递增所有修订。这些是需要公开并完善的语义，不能据此撤掉 SQL 或要求所有整理只能使用专用原语。

### 个人记忆中的错误推论会影响后续 Agent

当前记忆仍保留几条与代码不符或已被后续证据推翻的解释：

- “Mesh RPC 经 coordinator 中继”：实际工具调用和文件都在设备间直连，协调服务提供身份与地址。
- “presence.at 不动说明心跳冻结”：它表示状态变化时间，不是每次心跳时间。
- “fileProxyPort=0、not_started 证明代理坏了”：0 表示自动端口，代理在发放远端可读地址时按需启动。
- “两设备 mergedEpisodeId 不同必然是坏数据”：投影 ID 属于当前节点视图，远端修改必须使用 owner 原始 ID。
- “源端弹幕不能供接收端使用，因此必须两边再绑定”：当前有源端 play bundle 和接收端附件加载路径，不能继续将旧绕行方法当作通用要求。

这些陈述中有些曾是调查假设，后来却以“最终结论”继续留在记忆里。Next 若依赖 Agent 记忆来工作，应记录观察事实、假设、证据、适用 SHA/版本和被哪条结论替代；新证据需要使旧诊断失效。界面和公开状态也应直接解释这些字段，减少 Agent 凭字段名猜测。此轮未修改个人记忆。

## Mesh 仍需收紧的设计边界

**目录提交不应依赖全部图片成功。** [library.dart:210](/Users/sakiko/Desktop/NipaPlay-Reload/lib/next/mesh/library.dart:210) 在发布新目录前等待所有 artwork/still 缓存。单张图片源文件缺失，就能阻止新目录发布；首次同步没有旧目录时，视频即使可读也没有可用的新目录。路径静态确认，未另做集成注入。应原子发布已验证的结构目录，图片独立加载并报告局部失败。

**内容目录、富资料与进度需要分开版本。** [library_projection.dart:160](/Users/sakiko/Desktop/NipaPlay-Reload/lib/next/mesh/library_projection.dart:160) 把 progress revision 放进目录版本，每个新版本重新包含全部 records 和 watch observations；接收端每五秒轮询。持续播放会反复搬运富元数据，并额外消耗 F01 的 RPC 容量。可按内容 revision 同步目录，按对象 revision 获取富资料，按独立游标传播进度观察。

**固定版本需要活动传输租约和字节预算。** 当前只保留最近 4 份 publication，无活动传输 pin、总字节预算或 TTL。慢接收方的版本可被其他设备的新请求淘汰。现实现会拒绝并保留旧目录，不会静默混合版本；风险是反复失败和无法收敛。

**目录接收需要全程上限。** [library_transfer.dart:37](/Users/sakiko/Desktop/NipaPlay-Reload/lib/next/mesh/library_transfer.dart:37) 连续保存 base64 页面，到收完后才检查总长度；没有总页数、总字节数和整个同步 deadline。多个表示还会同时占内存。按设备串行刷新，以及 close 先等待同步，使一个慢来源影响其他来源和关闭。应提前验证声明长度、逐页累计计费、支持取消和整轮时限。

**Continuation 是有界滞留，仍需生命周期清理。** `response_chunks.dart` 有 64 MiB、8 条总预算、设备隔离及 5 分钟有效期，读取检查长度和 SHA256。过期数据只在下一次 describe 或 close 时清除，stop 不清；不能称无限泄漏，但应主动回收。Continuation 只获取已完成结果，不重新执行原操作，这个设计应保留。

**协调额度需要对应真实计费范围。** 客户端退避按 peer，地址上报最小间隔按设备；服务端地址上报与查询共用每账户额度。并发首次查询缺少同 peer 在途合并。每台设备各自守两分钟并不保证整个账户额度充足；此轮未新增额度压力注入。

**在线、可见、可读、可播放是不同观察。** 保留旧目录与独立探测是正确修复，但单个 online 布尔值仍不足以解释：来源可达、目录陈旧、具体文件已变、附件失败、播放器失败。应向 GUI 与 Agent 提供同一个分阶段状态和最后成功时间；不要要求 Agent 从 presence、端口、目录版本自行拼出故障链。

## 对整个 Next 的判断与调整顺序

“Agent 决策、宿主负责执行与验证”仍然适合 Next。现在宿主已经拥有多写入来源、多设备投影、持久任务和恢复语义，需要把这些规则作为基础设施维护。共享数据库不能自动保证共享语义；领域规则必须在 Classic 导入、GUI、Agent、Mesh 和 SQL 修复之间有明确边界。

建议保留统一 Capability、通用 SQL、任务回执、明确外部身份、原始快照及 provenance、明确调用的 Classic 兼容投影和每设备独立数据库。首先执行上文的 Classic/Next 控制权隔离及跨设备 SQL 契约，其他调整重点如下：

1. **先保护数据与播放。** 修 F01–F04，补 F06/F07；核实并修 Erika 未门控锁入口。每项先留下失败复现，再修复并验证。
2. **统一身份与播放计划。** 导入是来源观察，显式身份是用户/Agent 接受的归属，Mesh 是只读投影；三者都调用同一个等价/冲突判定。元数据合并与弹幕挂载也共享领域规则。支持 Agent 通过 SQL 及领域原语协调存量重复，并按真实需求沉淀可复用流程。
3. **拆分传输工作。** 控制命令、目录结构、富资料、进度、图片附件、视频流可共用身份，但独立预算和失败状态。视频不要逐 MiB 消耗持久写请求的防重窗口；进度不要触发全资料重传。
4. **统一生命周期与诊断。** start/stop/close 用 generation 和单一所有权管理；操作状态区分已发送、已执行、结果尚未取回，断开不冒充撤销。公开状态包含实际失败阶段、请求/结果字节数、队列和预算，不只是一句 outcome_unknown。
5. **把记忆更新和数据恢复纳入研究方法。** Agent 经验必须能被新证据取代；迁移、备份与恢复覆盖整个 Next 持久数据组。现有 Classic backup/sync 不包含完整 next.db 与弹幕正文，不能把“已有备份能力”视为 Next 完整恢复能力。

界面当前生命周期也需在产品契约中保持清楚：[next_core.dart:781](/Users/sakiko/Desktop/NipaPlay-Reload/lib/next/next_core.dart:781) 关闭 Next 会暂停其服务并停止 Mesh。这是当前明确行为，不是本轮认定的 bug；若要“打开 Classic 仍持续作为媒体来源”，需明确改变宿主服务寿命，不能仅靠发现层补重连。

## 九个范围的审核结果

| 范围 | 主要结论 | 后续验收 |
| --- | --- | --- |
| 大传输和目录一致性 | 字节分页、continuation、完整接收后发布有效；F01 和目录预算/图片依赖仍需处理 | 大库、多接收方、版本淘汰、持续播放 |
| 在线、地址、代理与恢复 | 真实 TLS/地址回归通过；F06 半关闭、F07 生命周期可复现 | 换 Wi-Fi、睡眠、暂停恢复、长背压 |
| Mac Erika | 工作队列修复有效果；F05 仍有未门控入口 | Mesh seek 中跨屏、拔插屏幕、关闭/切源 |
| 身份与归属 | 本机事务/adopt 保护可用；历史重复不自动协调；F02 投影可绕过归属隔离 | BanG 扫描回归、合辑负例、不同文件集合 |
| 元数据 | 来源字段补齐有效；F08/F09 在跨设备和明确空值处不一致 | 7 个待刷新 TMDB 对象另行回填核对 |
| 弹幕 | 当前普通 prune 保留持久正文；F10/F11 破坏自动优先级和两端一致性 | 正常 UI 播放、手工控制、同视频两份池 |
| Harness | 普通冲突与脏区保护、Agent 加载更新有证据；F03/F12 仍有缺口 | ignored 碰撞、并发 checkout/第二实例 |
| Mac 迁移 | 既有中断恢复测试强；F04 表明选源仍不充分 | 多候选完整对账、回退再升级策略 |
| 续播与稳定身份 | 稳定 locator 和串行保存未找到独立新反例；F02 会污染关联进度 | 多设备进度冲突、旧别名、换内核及同集重开 |

## 本次验证记录

主审核重新运行的既有测试：

- 目录分块、响应分块、library worker、身份、快照、自动弹幕、Harness、播放来源及 ui.open 共 9 个文件：**82 通过、1 跳过**。
- Mesh integration 与 LAN resilience：**26 通过、1 跳过**，包括实际本机双向 TLS、协调服务、文件 Range 与超时故障注入。
- Classic revoke/projection 与 DB service/core 共 4 个文件：**52 通过**。
- `cargo test --manifest-path rust/mesh/Cargo.toml`：**4 通过**。此前误用其他 crate 或过滤词产生的 0 tests 结果没有算入验证。

子审核另运行 Harness/endpoint 26 项、原生迁移 45 项，均通过；Harness 组与上述部分重叠，不能直接相加。真实 DSH runtime + 本地 Responses fixture 证明重启后 AGENTS 更新进入下一轮请求。Ruby 补丁可应用当前依赖，改变 anchor 后明确失败。

临时新增复现断言的是现有错误行为，不代表缺陷已修：

- [Mesh replay 容量](/tmp/nipaplay-mesh-review-astra/replay_probe.dart)、[HTTP 半关闭](/tmp/nipaplay-mesh-review-astra/http_eof_probe.dart)、[stop 竞态](/tmp/nipaplay-mesh-review-astra/stop_probe.dart)。从仓库根用 `dart --packages=.dart_tool/package_config.json <脚本>` 执行；replay probe 使用同目录的临时 FFI stub。
- [跨作品分段合并与进度](/tmp/nipa-next-range-identity-probe_test.dart)：1 项；[元数据与弹幕边界](/tmp/astra_identity_probe_test.dart)：4 项；[Classic 存量采用](/tmp/astra_classic_adoption_probe_test.dart)：2 项。从仓库根用 `flutter test --no-pub --reporter expanded <脚本>` 执行。
- [Harness ignored 文件](/tmp/nipa-lifecycle-audit.V0JHWl/harness_probe.dart)、[分支竞态](/tmp/nipa-lifecycle-audit.V0JHWl/harness_race.dart)、[迁移夹具](/tmp/nipa-lifecycle-audit.V0JHWl/MigrationProbe.swift)。均只操作临时目录。
- [Erika 生成源](/tmp/nipa-lifecycle-audit.V0JHWl/ErikaFlutterPlugin.swift:2353) 保留本轮检查的显示器锁入口；它不是产品源码修改。

临时脚本用于当前会话证据，正式修复时应把相应反例转成仓库测试。真实切网、睡眠恢复、长时间播放、两端完整数据保留对账、统一元数据补齐及全平台最终候选验收仍未完成。没有把编译通过、合成回归或只读实例查询记作这些验收通过。
