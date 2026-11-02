# X53：无界面在线准备与远程覆盖

日期：2026-10-13。worktree：`~/Desktop/nipaplay-next-wt/x53-headless`；分支：`next/x53-headless`。没有 commit 或 push。

## 完成了什么

G01 的本地媒体在线准备已接通：GUI 与 headless 共享同一个 provider 工厂，支持弹弹play hash 匹配、在线资料搜索/读取/绑定、Bangumi 资料和弹弹play弹幕搜索/获取/持久轨道。弹弹play继续使用 `NipaplayServerRouter`、`DandanplayHttpClient`、`DandanplayGateway`；主备选择、授权域和 `/dandanplay` 前缀沿用现有实现，没有新增上游签名客户端。

新增 `app.capabilities {}`。本机目录、远端 CLI 目录和经过认证的 Mesh 自描述读取同一份动态事实：宿主/平台、功能支持、provider/source 可用前置、非秘密 credentialRef、宿主准备、实际 settingsKeys、Action 的 effect/remoteCallable/availability/用户在场条件/lifecycle。缺 token 的 hash、未授权的 program.run/仓库接收、退役的 danmaku.align 都明确标注不可用。参数相关的资料/弹幕能力明示 provider/source 条件，不把安装了适配器当作已经联网成功。

G08 开放现有本机能力族的远程调用，保留每个目标 Action 原来的输入验证、副作用和宿主授权。新增的覆盖包括 settings.set/reset、state.describe、accounts、window、app、diagnostics、backup、plugins、chat/agent.dispatch、memory，以及 Mesh 查询/转发。没有新增远程秘密录入或修改信任配置的能力。目录只列目标宿主实际注册的能力；无界面端没有的 Classic 部件仍如实缺席。

与无界面有关的质量缺口同时处理：

- 没有 Classic 历史的宿主用 `DetachedClassicMetadataPort` 标识，投影 outbox 收尾为 `not_applicable`。绑定成功的回执明确 Next 身份/资料已持久保存，避免先写成功、再因不存在的 Classic 投影报失败。真实 Classic 投影路径保留原逻辑。
- 新增 `danmaku.fetch_batch/attach_batch/import_batch`；一次 1–100 项，先验证全部 schema，每项返回 index 和完整 outcome，包括 jobId/bindingId/NeedsDecision/error。`atomic:false`，后项失败保留前项已提交内容；没有批处理判断编排。
- 弹幕网络错误增加安全 reason，区分 timeout、request_aborted、http_client、socket 错误码等，不返回可能带认证信息的原始异常。
- `danmaku.align*` 目录标 `legacyRecovery`，指向 `analyze_alignment/update`，保留旧持久决定恢复入口。
- headless roots 的 readOnly 明示作用域为索引/下载目的目录；文件通道仍按节点进程权限执行，删除/覆盖保留 NeedsDecision。没有把 readOnly 描述成全进程禁写。
- 修复真实远程设备查询触发的帧超限：Mesh tools/call 保留完整 structuredContent，text 仅指出它的位置。`mesh.devices` 增加 `deviceIds` 与 `includeCatalog:false`，用于筛选设备或省略完整 schema；省略参数维持原完整目录语义。

能力族说明放在 `lib/next/capability_families.dart`，可用本机或远端 `nipa describe app/danmaku` 读取。种子只有远程同契约原则的一处更新，能力细节没有写进种子。没有修改 `lib/next/ui/`。

## 决策及理由

### 同一客户端、不同宿主端口

保留现有客户端和路由器的名字及算法，用条件 import 替换 Flutter 通知、偏好存储和 GUI 登录/relay 端口。纯 Dart 宿主的三个小 adapter 位于 `lib/next/headless/`；Flutter 分支仍读取原来的服务与 SharedPreferences。`DandanplayHttpClient.authorization` 改为 FutureOr，使 headless 可以逐请求读取保险库，GUI 的同步闭包仍适用。

`network.json` 只承载现有路由键及主备缓存；默认自动选择官方网关，custom 地址由宿主显式配置，不接受 userInfo/query/fragment。TMDB 与 Bangumi 的 provider、请求 transport、解析代码也由 GUI/headless 共用。元数据和弹幕各有自己的弹弹play客户端，避免一个服务关闭传输时影响另一个服务。

凭据引用保留 `preferences/dandanplay_token` 与 `metadata/tmdb`。headless 图片服务由 NoVault 改接真实宿主 vault；新增宿主命令 `--enroll-credential-stdin --credential-namespace … --credential-key …`，stdin 的秘密不进入参数、Action、settings 或 journal。原 token 登记命令继续存在；只有 token trim，一般凭据原样保存。登记仅接受已初始化的隔离 headless 数据目录。

本次公开影片从本地文件完成全部准备，不依赖媒体服务器浏览、Classic 登录管理或更新日历，因此没有为了本任务搬入 `media.sources.* / accounts.* / discover.* / sync.*` 的 Classic 服务。它们在 headless 的功能事实中明确 unsupported、说明原因及可用 GUI 宿主；弹弹play在线准备本身不依赖这些 GUI 部件。此选择完成 G01 的在线准备路径，没有声称整个 Classic 服务集合已移植。

### 事实与目录

采用报告建议名 `app.capabilities`：它描述整台宿主，与 `app.instance` 的进程身份互补。`supported` 表示实现存在，`available` 表示声明的宿主前置满足；`readinessScope` 明示这不是实时网络探测，逐请求才产生网络结果。动态 credential readiness 只检查引用存在与非空，不证明 token 有效、TMDB key 正确或服务器可达。

保留同名 Action 和现有输入输出，在目录附加可用性与语义事实。这样无需为 headless 创造第二套 hash/metadata/danmaku 工具，也不会将不存在的播放器、Classic 历史或自动识别当成完整实现。`download.import` 在 headless 的事实是校验后索引，不自动判断身份；roots.remove 是取消根登记，保留索引事实和文件；settingsKeys 逐键给出实际范围。

批量弹幕命名沿用现有领域的 `_batch` 风格，每一项重用单项契约；外层结果明确非原子，便于读取部分成功而不丢失回执。没有改磁盘删除/覆盖协议，也没有承接 X54 的解除关联/字幕撤销工作。

### 远程范围

主控已经决定远程写与本机一致，因此现有能力族整体开放；不按“目标是另一台设备”再造限制。每项能力的可用前置仍归目标宿主，Mesh mTLS、effect 检查、program.json、文件 NeedsDecision 等不变。

| 范围 | 开放理由与目标事实 |
|---|---|
| state/diagnostics、app.capabilities | 能读本机事实就应能读认证目标的事实；诊断沿用现有脱敏 |
| settings、appearance、shortcuts、webdav_quick | 使用目标注册表及 denylist，只能写已公开的非秘密设置 |
| accounts、media.sources、discover、sync | GUI 的既有服务也可成为远端身体部件；需要登录/文件选择交互时事实标 requiredUserPresence；headless未注册这些 Classic 部件 |
| window、app.quit | 用户授权后的目标窗口/进程操作与本机一致；quit 会结束端点，窗口操作会影响目标用户，本次安静实验没有执行它们 |
| backup、plugins | 原来的恢复/安装实现、effect 与结果继续适用；本次没有对真实数据执行恢复或安装 |
| chat、agent.dispatch、memory | 作用于目标宿主已有会话服务，不把 headless冒充对话宿主；本次没有调用真实模型 |
| mesh.devices/invoke/invoke_destructive | 可以从远端节点查询其拓扑或继续转发，每一跳重新执行认证、effect 和目标授权；只读设备查询已实测，多跳转发未实测 |
| program、任务/后续、媒体/弹幕/字幕等既有族 | 保留此前开放范围和目标数据约束；程序授权仍只由目标宿主 program.json 决定 |

未开放的是没有远程契约的其他 ID，事实返回原因；秘密登记、网络加入、签发者/监听策略/执行授权本来就不是这些 Action 的可写配置。`credentials.status/retry` 沿用既有宿主流程，retry 需要目标用户处理保险库交互。远程没有绕过同意；磁盘删除/覆盖继续由目标产生原 NeedsDecision。

## 实验与观察

全部运行实验在本机回环完成，使用本 worktree 构建、独立临时数据、安静 GUI profile 和自有 PID。没有启动安装版应用，没有操作用户 ui-demo、钥匙串、真实媒体服务器或用户 harness；没有读取 `/Volumes/Media`。Windows/WSL只编译，没有启动节点。实验脚本和证据索引见 [evidence/x53/README.md](evidence/x53/README.md)。

### 公开影片与真实服务

输入为 Blender Foundation 的 **Big Buck Bunny**（CC BY 3.0），从[官方压缩包](https://download.blender.org/peach/bigbuckbunny_movies/BigBuckBunny_320x180.mp4.zip)取出视频，64,657,027 bytes；SHA-256 为 `f78f39603e6774907f2faafabf26a667f4a6fc31769ec304a8a8f7c62d280508`，头部 MD5 为 `660f9b30903922b42135b6430e88d5ca`。使用临时测试账号，由现有 GUI 账号服务登录，headless通过 stdin 登记同一 token；证据只记录登记状态，没有保存秘密值。

| 观察 | GUI | headless |
|---|---|---|
| 弹弹play hash | 成功，candidates=[] | 首次去代理环境超时；按宿主代理环境复验成功，candidates=[] |
| 弹弹play片名搜索 | 成功，records=[] | 按宿主代理环境复验成功，records=[] |
| Bangumi识别/资料 | “大雄兔”，subject 49696，episode 912433，scope subject/49696 | 同一身份、中文标题与简介 |
| 文件绑定/保存 | Next持久身份及资料；有Classic投影 | Next持久身份及资料；Classic投影 not_applicable |
| 弹弹play弹幕搜索 | 成功，results=[] | 最终复验成功，results=[] |
| 两条实验者 CC0 弹幕导入 | 保存2条 | 保存2条，轨道内容一致 |

`completion.json` 对比身份、标题、简介、596458 ms 时长、导入条数，`equal:true`。没有取得这部片的非空公共弹弹play弹幕池；两条导入弹幕来自实验者，不冒充公共池或在线 fetch。Bangumi返回封面 URL，未把取到 URL 说成所有图片已下载齐全。

意外及失败均保留：`online.json` 的第一次整体搜索比较为 false，headless弹弹play请求确实超时，并非只因 fetchedAt 不同；Bangumi当时正常。`preparation.json` 与 `completion.json` 也保留弹幕搜索失败。定位发现 GUI 去掉进程代理变量后仍使用 macOS 系统代理，而纯 Dart 宿主使用进程代理环境。恢复 headless宿主 HTTP/HTTPS_PROXY，并保留 NO_PROXY 回环后，`source-check.json` 最终记录 hash、资料搜索、弹幕搜索全部成功；两次成功 hash 都无候选。能力事实已披露这个宿主网络差异。后来重取公开视频时 Python 经代理下载遇到 HTTP 403，curl直连官方包成功，视频摘要一致。

最终 `verification.json` 还逐字段核对：GUI初验与headless最终资料搜索仅排除fetchedAt后完全一致，包括空的弹弹play候选和10条Bangumi搜索记录；并复核所有JSON可解析、临时profile清理和证据无秘密值字段/私钥/JWT/认证URL命中。

### 回环网关的非空在线弹幕

`x53_gateway_experiment.py` 在临时回环网关提供合成 hash/资料目录和2条实验者 CC0 comments，输入视频仍为同一真实开放影片。两端使用真实客户端完成 hash→读取资料→身份绑定→弹幕搜索→attach_batch→fetch任务→持久轨道。两端身份相同、fetch任务都 succeeded、同 cacheKey/content hash、count=2、coverage=relatedPool；loaded=false，因为本实验没有播放。

网关记录16次请求，全部保留 `/dandanplay` 前缀、携带正确宿主凭据；证据只保存 `expectedCredential:true`，没有记录凭据。夹具验证非空获取与持久准备的实现路径，不证明真实弹弹play对这部影片有内容。服务、GUI profile和headless数据全部删除。

### 能力事实与远程

`final-facts.json` 观察缺 token、未授权程序、退役 align 的明确目录标注；宿主 stdin 登记合成 TMDB credential后，provider available 动态改变，秘密不出现在 facts。错误宿主标记的 enrollment拒绝且未写 vault。没有真实 TMDB key、live TMDB取图实验。

`mesh/` 使用真实 TLS 1.3双向证书、临时协调服务与合成账号：远程 settings.set/get成功；授权/默认禁用程序分别成功/拒绝；字幕、Git bundle及原会话回传保留原实验事实，modelTurns=0、workstationConnections=0。它不等同于工作站真机运行。

补跑 scope 时，远程 `mesh.devices {}` 首次失败，target native log为 `invalid frame size`。两台设备的原紧凑JSON结果为498,090 bytes；按旧MCP格式重建双份结果为1,064,803 bytes，超过1,048,576上限。修复重复文本后，`mesh-scope-success/` 完整设备查询成功；单设备/无catalog查询也成功，远程CLI正确区分两台设备的 program权限并标注legacy，远端 `describe app/danmaku` 正常。失败证据保存在 `mesh-final/`，没有提高Rust帧上限。

### 测试和构建

- 完整 `flutter test --no-pub test/next` **515 passed、5 skipped**，只跑一次；跳过项为需要显式构建路径的独立AOT实验。帧修复后只跑相关约束测试，19 passed。
- 相关 headless/媒体/弹幕/程序和 Classic 客户端/路由器测试通过；最终组合50 passed。额外 Classic统一网络设置和服务器对话框5 passed。早期 storage测试的夹具断言问题修复后2 passed，原失败日志保留。
- 最终 analyze：0 error、0 warning、5条现有info（media_service花括号和network_settings print）。
- macOS headless AOT编译成功，native在本worktree离线编译；GUI Debug构建成功，使用runtime ad hoc签名，strict验证通过，allow-jit/无App Sandbox。
- Windows x64编译成功，SHA-256 `7abfeb99da9790659160f2a0dae1edd81df320692a010f9d0bfff4f8fd1a7048`；WSL Linux x64编译成功，`c4a48637d0d29465746757f735097429c93abc9cc63db81a11afd00a0748ca57`。只传公共纯Dart图并编译，native没有修改，nodeStarted=false。

## 还缺什么与合并说明

无界面仍没有播放器/窗口、Classic账号管理/历史、媒体服务器来源、更新日历、sync和对话宿主。本次已完成独立本地影片的在线识别、资料与弹幕准备路径；未把上述GUI服务缺席说成全应用对等完成。TMDB live图片和非空公共弹弹play池、GUI远程窗口/退出/备份恢复/插件安装/账号交互、多跳mesh转发，均未实测。Windows/WSL真机运行留给主控。

Mesh仍有1MiB响应边界，大量设备的完整schema或其他大结果仍可能超限；deviceIds/includeCatalog用于限制设备查询大小，没有全面分页所有领域查询。本次解决的是实测的两设备重复文本失败，没有宣称G01之外的大结果质量问题全部消失。

界面需要的数据已在 `app.capabilities`：features/providers/sources的 supported/available/reason/requiredHostSetup、Action可用性与用户在场条件、settingsKeys、network、semantics。主控可安排UI展示宿主准备和远端限制，避免将headless缺失的部件显示成可操作。没有改UI代码。

共享文件改动集中：`headless/core.dart` 是providers/来源/vault/facts组装；`next_runtime.dart` 只追加AppCapabilities；没有修改next_core.dart。`agent_endpoint.dart` 追加族describe和目录facts；`nipa` 追加远端目录facts及两个族describe；种子只一处原则段。X50合并族说明时保留这里的app/danmaku内容；X54/X55追加Action后它们会从catalog自动进入facts，宿主特殊可用前置仍需补相应规则。Mesh runtime的族开放和text去重需一起保留。Classic三文件的条件import必须与三个headless adapter一起合并。

所有本次实验进程按自有PID退出，临时profile、节点数据、网关与视频实验目录删除；Python缓存清理。构建生成的Podfile.lock已还原，GeneratedPluginRegistrant按任务要求保留。没有新增依赖或接触真实数据。

## 需要主控决定的问题

没有。
