# X55：任务、事件与系统能力

2026-10-13；worktree `x55-system`，分支 `next/x55-system`。没有 commit、push、pub get 或依赖变更，没有修改 `lib/next/ui/`、种子和 `nipa`。以下区分已实现的能力、实测事实和仍需补齐的宿主实现。

## 1. 完成了什么

| 范围 | 交付 |
|---|---|
| G05 | `task.control` 批量暂停、恢复、取消；`task.resources` 查询容量、占用和排队；三个并发设置；Classic 扫描改为持久任务；内置 librqbit 会话真实限速 |
| G06 | 持久事件游标、过滤和有界等待；补播放、任务、附件、来源、设置、网络、空间、缓存和窗口事件；同一事实触发 hook 和已登记 followup |
| G09 | 网络来源/错误/上次成功/路由/代理/UA 事实，批量检查来源；注册独立媒体服务器 UA 和官方网关模式 |
| G10 | 应用、Next、附件、下载和媒体根的实际用量/卷空间；分类回收预览与执行；保护唯一导入、用户文件和活动引用；显式空间阈值订阅 |
| G11 | 启动扫描、同名弹幕索引和字幕探测独立开关；返回启用、执行、队列、上次运行/错误；复用既有自动匹配、自动加载弹幕和下载完成导入策略 |
| G14 | 健康/资源/构建/播放器安全事实、持久日志脱敏分页、日志重启、投影核对和索引器检查；`state.query` 错误补来源、阶段和恢复提示 |
| G15 | 立即检查更新、读取上次检查、打开已核对的公开发布页；失败不伪装成“没有更新” |
| G16 | macOS 原生通知状态/发送/列表/取消，系统分享预览/面板，Classic UDP 局域网发现，主窗 bounds 读写和变化事件 |
| 设置键 | 调研的 22 个 SettingsKeys 与 3 个 literal 全部逐项处理，见下表；秘密只公开 configured 布尔事实 |

主要实现拆到 `lib/next/tasks/`、`events/`、`network/`、`system/` 和 `settings/system_settings.dart`。共享文件里的修改集中在能力注册、生命周期与现有事实变化接线。没有增加一套网络客户端、任务数据库或事件数据库。

### 能力契约与命名

| 能力 | 输入与返回要点 | 决策理由 |
|---|---|---|
| `task.control` | `entries:[{jobId,command,expectedRevision?}]`，1–100 项；返回 `results:[{index,jobId,command,accepted,controlSupported?,job?,draining?,reason?,error?}]` | 一次管理多项；错误留在对应项。`accepted` 是受理事实，`draining` 明示正在排空。`expectedRevision` 核对读取时的快照，不承诺与异步执行器之间的原子 CAS |
| `task.resources` | `pools` 的 capacity/active/queued、Classic 识别容量、下载限速支持与 actual | 调整复用 `settings`，不引入第二套配置；只改变后续派发，不杀已运行工作 |
| `media.library.scan_classic` | 保留原输入名称/目录语义，立即返回 `jobId`；任务类型 `media.scan_classic`；回执列目录、实际尝试识别的文件、识别结果/失败和文件保留事实 | 掉线后仍能按任务号查询；识别失败不等于目录枚举失败，更不冒充成功匹配 |
| `download.limits.get/set` | 字节/秒；set 接 `downloadBytesPerSecond`、`uploadBytesPerSecond` 任意一个或两个；省略方向保留。返回 supported/sessionInitialized/applied/actual/scope/appliesTo/lifetime | 分开读写 effect；直接读写既有 Session 的 `ratelimits`，不创建第二会话。0 为无限制，正值至少 16384、至多 u32 上限：令牌桶须能容纳 torrent 数据块。不改变网关/账号限流 |
| `events.describe/wait` | wait 接 afterCursor/events/entityId/limit/timeoutMs；最多 1000 项、等待最多 60 秒；返回 events/nextCursor/truncated/replay | 复用 `followup_hook_events` 的持久 sequence。重启重读事实；不重跑 hook。过滤、分页不会跳过并发提交 |
| `network.status/check` | status 给路由、来源观测关联、最近错误与 lastSuccessAt；check 的 targets 支持已登记 sourceId 或 dandanplay，返回逐项 index/source/latency/facts/error | 复用 Classic transport 和官方网关客户端；不可见的 DNS/TLS 阶段如实标未暴露。只记录 origin，路径、query、header、原始异常不进入观测 |
| `storage.status/watch/unwatch` | status 给 directories/volumes/observedAt；watch 接登记根或应用路径、thresholdBytes/intervalMs；首次和 above/below/unobserved 转换发事件 | 父目录包含子目录，不能合计相加。阈值是显式订阅，没有预设自动策略；取消排空当前采样，返回后不再发新事件 |
| `cache.plan/prune` | plan 接 kinds/maxBytes，返回 planId/entries/retained/reclaimableBytes；prune 返回 removedBytes、逐项结果及保留/失败 | 计划仅当前进程有效，不接受任意删除路径；执行重新核对 size/mtime、引用与正在读写的缓存。maxBytes 是所选可重取缓存的合计预算，保护项可能使预算无法达标 |
| `media.indexers.status` | workers、startupScan、现有自动匹配/加载/导入 policies | 把策略值与工作器实际状态分别报告；关闭保留队列、排空当前文件，显式 reconcile 仍可执行 |
| `diagnostics.status/file_logs/recover` | status 给 quick_check、投影积压、RSS、build/OS/Dart、播放器安全信息；file_logs 按受限 fileId/行游标分页；recover 接显式 operation | 不输出实际播放认证 URL；日志单页有界且先脱敏后过滤，PEM 块跨页仍隐藏；恢复没有暗含登录、迁移、路由调整或用户文件删除 |
| `app.update.check/status/open` | check 给当前/最新版本、hasUpdate、发布信息、时间和 error；status 读本进程上次检查；open 只用本进程成功核对过的公开 GitHub 发布页 | 复用 UpdateService；错误时 hasUpdate/latestVersion 为 null。没有杜撰应用内下载安装能力 |
| `notification.status/send/list/cancel` | status 给 permission/alertsEnabled/soundsEnabled；send 给 deliveryState/reason；list 区分 pending/delivered | macOS UNUserNotificationCenter；默认不请求授权，显式 requestPermission 才询问系统。声音遵守系统设置；受理不等于用户看见横幅。ID 加 profile 命名空间 |
| `share.prepare/open` | prepare 接 text/url/filePath/subject，返回内容预览、planId、支持状态；open 返回 panelOpened/publication | 文件在媒体授权范围或应用 temp/exports 中；排除数据库/保险库/端点文件；再次核对预览后的文件变化。由 OS 面板让用户选择目标，不能把打开面板说成已发布 |
| `media.sources.discover` | timeoutMs 有界发现，返回未验证 candidates/时间/protocol | 复用 Classic UDP 协议，不自动登记、登录或接受对端声明为已验证来源 |
| `window.bounds.get/set` | get 为 read；set 必填 x/y/width/height，返回本进程 main 窗口读回值 | 准确坐标用 window_manager 逻辑像素；不激活窗口。已有 fullscreen/PiP/托盘仍复用 window.control |

并发设置为 `tasks.scanConcurrency`、`tasks.metadataConcurrency`、`tasks.helperConcurrency`，只要求正整数。Classic scanner 自身固定一个目录任务，因为它只有一份可变 diff/progress 状态；新 Classic 扫描的识别并发可调，既有请求间隔和服务端限流保留。宿主帮手容量可调，原生 Codex 子代理容量由 Codex 管理。

可安全暂停/恢复的是扫描、资料刷新、投影、下载和宿主帮手。宿主帮手恢复在同一线程继续原任务；持久 resumeToken/resumeDispatched 避免未获 ack 时盲目重放。原生 Codex 帮手、hook 和 program 不声称能安全暂停。终态回执保持不变，取消不删除文件。Next 扫描恢复跳过已持久记录的 scan items；Classic 中断目录恢复重新核对 diff，可能再次识别该目录里已尝试的文件，没有逐文件 exactly-once 承诺。

### 事件与动态

新增 `playback.ended/failed/state_changed/seek_requested`、`settings.changed`、`media.assets.changed`、`media.sources.state_changed`、`media.scan.completed`、`task.state_changed`、`network.state_changed`、`cache.pruned`、`window.bounds_changed`、`storage.space_changed`。保留原四种事件兼容字段和去重语义；新事件按 occurrence 触发。

统一 payload 含 eventId/event/entityId/occurredAt/revision/changedFields/facts。播放位置不逐帧叫醒，seek_requested 只表示请求，不伪装成已经到达目标位置。身份、弹幕和相关附件事务在 commit 后发事件，rollback 不发成功变化；任务 hook 自身状态不再递归产生 task.state_changed。followup 与 hook 使用同一事实管道。

能力族描述在 `lib/next/system/families.dart`；`AgentEndpoint` 增加小范围 fallback，让本机 `nipa describe <族>` 可得到描述和已注册工具。能力细节没有写进种子。

### 25 个设置键逐项去向

| 物理键 | 最终入口或保留理由 |
|---|---|
| clear_danmaku_cache_on_launch | 新增 `storage.clearDanmakuOnLaunch`。与 Classic 设置相同：启用即清一次 Classic 可重取缓存；不清 Next 唯一导入 |
| danmaku_auto_match_on_play | 保留既有 `danmaku.autoLoadStrategy` 与 skipMatching 兼容关系，不开两个互相覆盖的权威值 |
| media_server_connection_user_agent_v1 | 新增 `network.mediaServerUserAgent`，复用 MediaServerTransport getter/setter，空串恢复默认；新 API/图片/同步请求生效 |
| auto_check_updates_on_about_page | 既有 `general.autoCheckUpdates` 读取/迁移旧键，不新增独立控制 |
| show_remote_access_qr_code | 新增 `appearance.remoteAccessQrVisible`；只保存 Classic 显示偏好，restart_app；不返回二维码内容/认证链接、不打开监听 |
| labs_show_remote_access_qr_code | 上项兼容读取旧键，独立写口不开放 |
| labs_enable_agent_endpoint | 不开放自授权设置写口，沿用宿主授权；运行/端点事实已有 app.instance。连接秘密不返回 |
| torrent_recent_download_directories | 保留 download.directories/forget_directories 领域入口，不用任意设置写列表 |
| torrent_recent_download_directories_migrated | 内部迁移标记，不允许 set 伪造迁移事实 |
| media_library_selected_section | 新增 `appearance.classicLibrarySection`，校验真实 section IDs；restart_app，实时导航用 ui.open |
| media_library_section_order | 新增 `appearance.classicLibrarySectionOrder`，真实 section IDs、无重复；restart_app，不丢新来源 |
| downloader_verified_scanned_completed_task_keys | 验证/回执事实，不允许任意 set；读取任务/download.read，显式重扫用 download.import |
| downloader_auto_scanned_completed_task_keys | Classic 旧导入事实，不允许任意改写；策略已有 download.autoScanCompletedTasks |
| danmaku_supersample | 既有 danmaku.supersample 权威为 v2 字符串，兼容旧 double/维护双写，不开第二入口 |
| tvos_erika_danmaku_outline_default_migrated_v1 | 内部 tvOS 默认迁移标记；有效选择是 danmaku.outlineWidth |
| danmaku_kernel | 废弃键不开放；现代权威为 danmaku.renderEngine/pluginRenderer。旧 API 仍可读写该键，不能声称现代入口兼容读取它 |
| spoiler_ai_use_custom_key | 当前代码固定规范为 true，不开放无效 false；在 configured 说明中披露当前语义 |
| spoiler_ai_api_key | 只读新增 `danmaku.spoilerAiConfigured` 布尔；不 get/set 原值，用户自身设置窗口录入 |
| show_canvas_danmaku_collision_boxes | Debug 构建注册 `diagnostics.canvasDanmakuCollisionBoxes`，复用 Classic provider |
| show_canvas_danmaku_track_numbers | Debug 构建注册 `diagnostics.canvasDanmakuTrackNumbers`，Canvas 专属 |
| show_gpu_danmaku_collision_boxes | Debug 构建注册 `diagnostics.gpuDanmakuCollisionBoxes`，GPU 专属 |
| show_gpu_danmaku_track_numbers | Debug 构建注册 `diagnostics.gpuDanmakuTrackNumbers`，GPU 专属 |
| anime_detail_display_mode（literal） | 新增 `appearance.animeDetailDisplayMode`，simple/vivid，Classic restart_app |
| debug_log_auto_scroll（literal） | 新增 `diagnostics.logViewerAutoScroll`，日志窗口重建/重启后加载 |
| debug_log_show_timestamp（literal） | 新增 `diagnostics.logViewerShowTimestamp`，同上；不影响 Agent 日志时间事实 |

另外注册 `network.dandanplayMode`：auto/hongKong/china 可写；custom 只读现有用户信任选择，普通设置不能把凭据改送第三方 origin。只读条目在注册表明确 writable=false，拒绝 set/reset，不留下虚假的设置变化。未绑定当前 provider 的显示偏好明确标 restart_app，不宣称已经影响当前窗口。

### Classic 和删除边界

Classic scanner/识别器只增加可选 continuation、回调和并发参数；原调用不传参数时沿用原计算。网络 transport 增加事实观察，不改认证、代理、请求间隔和网关行为。图片缓存只增加活动读写/引用的查询接口。缓存串行维护复用原 manager，避免清理与读写并发。

启动策略只在 `labs_use_next_interface=true` 时生效；Next 关闭时，即使 labs Agent endpoint 仍开着，Classic 启动扫描照常运行。新增约束测试覆盖这一组合。

可重取缓存回收不走 NeedsDecision。字幕、导入弹幕、下载、mesh-assets、无法证明可重取的 artwork 等仅返回保留原因，不让 cache.prune 夹带用户文件删除。用户文件删除/覆盖继续走既有磁盘删除/mesh 文件 NeedsDecision。元数据解绑与改匹配的预览、动态、撤回由 X54 所属入口完成；本组只接变化事件，没有新增删文件的副作用。没有为远端新增特殊禁止；Mesh 的统一路由接入由 X53 合并。

## 2. 实验与验证

实验脚本为 `scripts/next/x55_experiment.py`，分 all/system/verify/bandwidth 阶段。每次直接运行本 worktree Debug 可执行文件，ad-hoc 签名、runtime options 与 DebugProfile entitlements，独立 NIPAPLAY_PROFILE、独立临时 harness 和空 Codex home。fixture shell 只提供进程环境或退出，未运行模型宿主，也未读取用户 shell/Codex 配置。视频为自行 ffmpeg 生成的 CC0 testsrc2。未访问用户媒体账号、真实目录或登录钥匙串，未启动安装版应用，未激活窗口、像素点击或触碰 ui-demo/其它 LAB。

### 真实观察

| 实验 | 输出与判断 | 证据 |
|---|---|---|
| 真实 Next 扫描暂停/恢复 | running 时已扫 7 文件、revision 16；暂停后两次间隔 1.5 秒观察均 paused、7 文件、revision 17；恢复后 succeeded、193 文件、revision 393、verified 回执 | [operations.json](evidence/x55/operations.json) |
| 事件触发 hook | UA 设置变化产生 settings.changed；hook succeeded，exitCode=0，354ms，中性 stdout。登记 followup 收到同一 trigger，进入 ready；模型宿主缺席，未执行后续模型回合，之后显式取消 | [operations-system.json](evidence/x55/operations-system.json) |
| 缓存回收与空间 | 图片缓存实际 1966080→0 字节，removedBytes=1966080。复核实验卷 availableBytes 482826022912→482827980800；系统同时有其它活动，不能把整卷差值精确归因缓存 | [operations-verify.json](evidence/x55/operations-verify.json) |
| 立即检查更新 | currentVersion=1.11.10，latestVersion=1.11.9，hasUpdate=false，error=null，发布日 2026-10-02；只查公开 GitHub 信息，没有打开发布页/下载安装 | [operations-system.json](evidence/x55/operations-system.json) |
| Classic 持久扫描 | scan_classic 立即返回 jobId，最终 succeeded/verified；1 个测试文件实际尝试识别，identified=false，原因未登录。回执没有把成功扫描目录说成成功匹配 | [operations-verify.json](evidence/x55/operations-verify.json) |
| 网络/诊断/空间订阅 | 查询成功；Bangumi 的来源正确为 bangumi，origin 为 api.bgm.tv，有最近成功；空间 watch 创建/取消成功 | [operations-verify.json](evidence/x55/operations-verify.json)、[operations-system.json](evidence/x55/operations-system.json) |
| 中性系统通知 | permission=notDetermined，alertsEnabled/soundsEnabled=false；send 返回 blocked/system_authorization，list=[]，取消自己 profile 的 ID。**没有实际投递成功证据**；没有为实验弹系统授权询问或更改系统设置 | [operations-verify.json](evidence/x55/operations-verify.json) |
| 原生下载限速 | 尚无会话时 supported=true/sessionInitialized=false，查询没有启动下载器。显式启用隔离下载器后 actual=0/0；设为 131072/65536 并 get 读回相同值；只改上传为 0 后 actual=131072/0；最后恢复 0/0。只核对引擎预算，未测真实 torrent 吞吐 | [operations-bandwidth.json](evidence/x55/operations-bandwidth.json) |
| 窗口只读 | window.bounds.get 返回当前实例 main bounds，未移动或激活窗口 | [operations-bandwidth.json](evidence/x55/operations-bandwidth.json) |

各记录含 finally cleanup：只按自己 PIDs 68356、68856、84353、21233 等退出；对应 profileRemoved=true。早期脚本失败实例也已清理，没有留下实验目录。

### 测试、构建及失败记录

按 TEAM 排队、去代理，所有 Flutter 命令使用 3.44.6 和 --no-pub。测试守容量、终态回执、事务提交、游标、引用、只读设置和 Classic 等价行为；功能成立依据上面的真实实验。

- [focused-tests.log](evidence/x55/focused-tests.log)：62 通过，含相关 Next、Classic transport/network/cache/startup。
- [final-focused-tests.log](evidence/x55/final-focused-tests.log)：60 通过，含 TaskEngine/等待及 helper 恢复约束；临时测试 runner 已删除。
- **完整 test/next 仅跑一次**，加相关 Classic 文件：[next-and-classic-tests.log](evidence/x55/next-and-classic-tests.log)，546 通过、7 跳过、7 失败。失败均为 download_runtime_test 缺 Flutter binding/SharedPreferences mock；新增设置加载揭露了测试宿主前提。补齐后只重跑相关文件，[corrected-final-tests-verified.log](evidence/x55/corrected-final-tests-verified.log) 22 全通过，覆盖该文件全部 7 项及 system/Classic startup/torrent scan。
- [domain-final-tests.log](evidence/x55/domain-final-tests.log)：40 全通过，含 local operations、ui_data、identity 和 system 约束。
- [bandwidth-focused-tests.log](evidence/x55/bandwidth-focused-tests.log)：51 通过、1 失败，发现两个限速方向误用互斥 oneOfRequired；修正后 [bandwidth-corrected-tests.log](evidence/x55/bandwidth-corrected-tests.log) 的下载执行器 35 全通过。其它该轮相关文件全部通过。
- [classic-startup-guard-tests.log](evidence/x55/classic-startup-guard-tests.log)：13 全通过，含 Next 关闭但 endpoint 开启的 Classic 保持测试和 startup_phase2。
- [rust-bandwidth-tests.log](evidence/x55/rust-bandwidth-tests.log)、[headless-bandwidth-tests.log](evidence/x55/headless-bandwidth-tests.log)：两个本 worktree Rust crate 的新约束测试各 1 项通过，--locked --offline，无依赖更新；验证非法第二项不部分修改第一项、省略/取消限速保持语义。
- [analyze-final.log](evidence/x55/analyze-final.log)：无 error/warning，4 条已有 style info；[analyze-delivery.log](evidence/x55/analyze-delivery.log)：最终核心、资源、系统、下载与 headless 下载接口无问题。
- [build-final-delivery.log](evidence/x55/build-final-delivery.log)：最终 macOS Debug 构建成功；[signature-delivery.log](evidence/x55/signature-delivery.log)：deep/strict 验证通过。构建产生的 Podfile.lock Erika 漂移已恢复基线，GeneratedPluginRegistrant 初始改动未处理。

保留意外与纠正记录：初轮扫描完成后脚本把 public job 顶层 objectId 错读为 details，第二轮同类 KeyError；改为顶层读取后 system 成功。早期 Classic 回执误用 acknowledged 导致成功校验失败，已改为 verified 并复核。state.query 只读测试计数受先前待提交事件影响，增加 hooks.drain 后核对；查询自身不写数据。一次新增缓存 getter 漏括号导致构建失败，一次测试 Map cast 导致加载失败，均已修复。通知旧 authorization 字段被通用脱敏误遮，已改 permission，复核能看到 notDetermined。失败文件未删除，不能把全部轮次描述成全绿。

### 中断后的续接核对

2026-10-13 续接时，代码、最终构建/签名/analyze、相关复测和上述实验记录均已落盘。重新读取证据，核对扫描终态与暂停稳定性、hook 回执、缓存字节差、更新结果、通知被系统阻止和限速读回；没有重复实验或完整测试。原报告的 24 个证据链接均存在，5 个本组实验 profile 目录均已删除；依赖锁、界面与种子没有改动，git diff --check 通过。核对结果见 [resume-audit.json](evidence/x55/resume-audit.json)。

## 3. 还缺什么与合并交接

以下是实现/验证缺项，不是待定产品权限问题：

- 系统通知目前只有 macOS 后端，其它平台返回 unsupported；此次实验系统未授权，实际投递未验证。分享面板、LAN 对端发现、窗口写入未在安静实验中触发；通知投递/展示仍受 OS 策略控制。
- Windows 卷空闲空间尚无后端，availableBytes=null 并给原因；Linux df 接口已实现但此次未在 Linux 实测。Linux 迁移只读 needed/applySupported=false，尚无逐文件冲突预览与 apply/recovery。
- 原生下载预算已核对，没有 torrent 吞吐测量；设置是当前内置 session 的预算，进程/会话重建默认无限制，不持久、不调整远端第三方下载器。
- 网络观测仅当前进程；Classic 客户端不提供完整 DNS 分阶段计时，TLS 仅在握手失败时可观察。空间阈值订阅、缓存/分享计划仅当前进程有效。
- 诊断尚未列出所有 Flutter/native player 依赖的精确版本。宿主帮手暂停/恢复已有代码和恢复约束测试，未用真实模型回合实验；此次 followup 只证明触发事实保留。
- LAN 仅现有 UDP responder 协议，旧无 UDP responder 的服务未做兼容 TCP 扫描。Classic 中断目录可能重复尝试识别，前述边界应在界面如实展示。
- X53 合并本组的新能力族到 headless core，并接统一远程路由/目录；本组没有编辑 headless core 或 Mesh 放行列表。`lib/next/headless/downloads.dart` 与 `rust/headless/src/lib.rs` 仅新增原生限速的小接口，Rust crate 已验证；其它系统族尚未在无界面/远程真实实例实测。
- X50 将 `systemFamilyDescriptions` 合并到正式族 describe 机制，并让远端 describe 具备同样上下文；当前 endpoint fallback 是集中小改动。种子/nipa 未改。
- X54 的解绑、移除元数据、字幕更新/删除等需要保留 BodySignals/changeHistory 的 commit 后事件接线；避免重复发同一提交，也不要把本组的可重取缓存回收当成用户文件删除接口。

界面需要的数据：task.control 的逐项受理/不支持/draining、task.resources 的实际池占用及新容量；下载 limits 的 supported/sessionInitialized/actual/lifetime；事件 cursor/facts；network 来源关联、最近错误/上次成功和未观察阶段；storage 目录重叠/空闲空间及 cache 预览/保留原因；indexers 的策略与执行队列；diagnostics 的受限日志分页/恢复回执；更新错误与 unknown 状态；通知 permission/blocked/pending/delivered；分享预览/panelOpened；bounds 的读写分离。没有修改界面文件，由主控安排对应入口。

## 4. 需要主控决定的问题

没有。以上合并点和未完成宿主后端均已明确，不需要再决定远端特殊限制或可重取缓存的同意规则。
