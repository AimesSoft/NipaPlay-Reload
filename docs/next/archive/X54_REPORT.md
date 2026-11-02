# X54：目录、播放、字幕与正在看的内容

2026-10-13，Asia/Taipei。worktree `~/Desktop/nipaplay-next-wt/x54-catalog`，分支 `next/x54-catalog`。本次实现 G02/G03/G04/G07/G12/G13 的能力入口；G07 的内嵌字幕文本与位图 OCR 仍有缺口，具体边界如下。没有改 Next 界面。

## 完成了什么

| 范围 | 能力与结果 |
|---|---|
| G02 本地目录 | `media.entities.put_batch` 原子建立、修改 work → release → episode 和已有文件关系，不要求外部身份。`remove_batch` 默认返回影响预览，执行解除关联、隐藏 tombstone，保留文件、进度和来源。`restore` 撤回移除；操作回执跨重启幂等。 |
| G03 播放观察与恢复 | `playback.state` 增加 sessionId、ready、buffering、bufferedPositionMs、error/recoveryAction、supportedControls、observedState/observedAt。`open` 区分命令 accepted 与实际观察。`playback.wait` 有界等待 ready/playing/paused/buffering/error，最长 30 秒，报告 timeout/error/session_changed。`retry` 重载最后一次播放请求，可保留或清零位置，并保留暂停状态。 |
| G04 字幕生命周期 | `subtitle.update` 修改导入轨的语言、标题和来源；`remove` 解除关联并保留副本；`reset_selection` 恢复自动选择；`select_batch` 批量明确选择或禁用。持久事实、当前播放器与动态一同更新。`copy_delete` 只删除明确指定且全库未引用的托管副本，必须返回 NeedsDecision 并核对内容指纹。GUI 与 headless 共用事实变更逻辑。 |
| G07 字幕和弹幕内容 | `subtitle.cues` 读取当前活跃外挂文字字幕的当前行、前后行或区间，保留语言、来源和轨 ID，计入全局和每轨延迟。`danmaku.entries` 读取当前合并、过滤后的渲染时间线，支持时间窗口、分页与列表版本校验，保留能观察到的来源。 |
| G12 图片和文字 | `media.artwork.clear` 原子清除图片覆盖、保留副本和审计，恢复来源图片。`media.metadata.override_batch` 原子批量文字覆盖，保留持久修正/随刷新失效/清除语义及语言生命周期。另有 `refresh_batch` 和 `ui_facts_batch`。 |
| G13 播放导航 | `playback.chapters` 返回容器章节、当前章节和识别的片头片尾；`navigate` 执行章节、逐帧或当前跳过段；`playlist` 读取实际播放详情来源的列表与顺序。复用 Classic 操作，不根据目录自行编造播放列表。 |

相关质量修复：

- 外部播放器无法观察的位置、时长、暂停和倍速在顶层也返回 null；缓冲遥测不支持时返回 null。
- 加载失败给出真实、脱敏的内核错误和 `playback.retry` 恢复入口。保留最后一次请求，解决 Classic 在失败后清空 currentVideoPath 导致重试失去来源的问题。
- 字幕导入的逐项失败保留 index、inputTrackRef、code、retryable 与 recoveryAction；批量选择避免逐文件调用。
- 解除字幕导入后记录 detachedPaths，避免 Classic 已登记外挂轨在下次 reconcile 时重新出现；自动选择的回调不会误写成显式禁用。外挂轨按路径去重并保留运行时语言/来源。
- 图片设置回执直接返回已保存的 path、sha256、source 和 effectiveKind，减少事后查询。
- `subtitle.tracks` 增加可选 limit/afterFileId 和 nextAfterFileId，使用文件 ID 顺序分页；省略 limit 保留原完整结果契约。
- Classic 历史同步不会再把没有外部绑定的显式 local_catalog 文件关系清掉；库视图隐藏已移除实体。本修复位于 Next 身份存储，不改变 Classic 历史。

## 决策与理由

1. **本地目录 ID 与平台 ID 独立。** 调用者提供稳定 entityId，可复用家庭视频、自编合集等现有标识；代码只校验真实层级、文件存在和修订，不推断标题、季数或匹配来源，不制造负数平台身份。创建和更新同用 put_batch；文件关系只在 episode 上声明。同一文件可以关联多集、多作品，沿用现有多对多模型，不强加一文件一集规则。
2. **关联移除可恢复。** 修改已有目录先返回影响预览，expectedPlan 校验实体、文件关系及来源；移除保留前像和 undoId，restore 拒绝后续冲突，不覆盖新进度。预览的进度来自当前 Classic watch_history，仅选取位置、比例、时长和观看时间；没有当前观察就返回 observed:false/null。持续播放的进度变化不使预览失效，因为本操作保留进度。实际提交在动态中记录当时的前后事实。
3. **原子性按领域声明。** 目录、文字和图片覆盖批次原子提交；字幕每文件独立提交并返回全部逐项结果，atomic:false。目录 requestId 有持久回执；字幕修改用 expectedRevision 防止覆盖并发事实。沿用现有表，没有 schema 迁移。
4. **解除关联与磁盘删除分开。** 本地目录和字幕关联解除不走 NeedsDecision；字幕可用保留副本重新导入，目录可撤回。copy_delete 是 Effect.destructive：核对所有文件事实、VobSub companion、转换 VTT、符号链接、存储范围和 SHA-256；导入与删除共用存储锁。源字幕文件不在托管副本删除范围内。
5. **状态描述观察，命令描述受理。** sessionId 包含进程及请求/播放代次；有界等待不会把后一集的成功当成前一集成功。重试是显式原语，代码不替调用者安排恢复流程。外部控制/遥测的未知值保持 null。
6. **内容读取描述时间线。** cues 与 entries 保留时间、来源和分页信息，不声称观察了实际像素。逐帧回执报告 native_frame_step 或 approximate_42ms_seek，与现有内核实际动作一致。
7. **族描述放在 describe。** 新增 `catalog_family_descriptions.dart`，为 media、media.entities、subtitle、playback、danmaku 提供领域语义，并在本 worktree endpoint 的族 describe 中返回描述与实际 ActionSpecs。种子不加入能力细节；对 X50 的共享族系统应由主控合并适配。

## 实验与验证

使用本 worktree Debug 构建，adhoc hardened-runtime 签名，allow-jit、无 app-sandbox，deep/strict 验证通过。直接运行可执行文件，以独立临时 NIPAPLAY_PROFILE 和临时 harness/CODEX_HOME 操作 HTTP 能力入口；实例默认安静，没有激活窗口或像素点击。视频为本实验生成的 45 秒、320×180、24fps H.264 testsrc2，字幕和弹幕为自写内容，统一以 CC0-1.0 提供，生成脚本可复现。

| 真实观察 | 输出与含义 |
|---|---|
| 无外部身份的作品播放 | 建立 CC0 Home Videos/Test Collection/Test Pattern 层级，关联扫描所得 fileId。playback.wait 返回 matched，ready:true，随后位置推进。 |
| 失败与重试 | 故意写入损坏 mp4，观察 ready:false、status:error、`Failed to recognize file format.`。只修复临时测试文件，retry 后 ready:true、buffering:false、durationMs:45000。旧 session 的 wait 返回 session_changed；保留位置重试保持约 7000ms 且暂停，清零重试回到约 0ms 且暂停。 |
| 字幕修改与解绑 | 修改为 zh-Hant、修正标题/来源；reset 后 selection.basis 不再为 explicit。解除关联后当前播放器不再选中该导入轨；重新打开视频，事实中仍没有该导入轨。 |
| 当前台词 | 10 秒处当前行为 “This is the current line.”，区间 8000–16000ms；上一行 “A public domain test pattern.”，下一行 “The next line preserves context.”，current 标记符合时间。 |
| 附近弹幕 | 返回 10000ms 的 “CC0 current comment” 和 11500ms 的 “CC0 nearby comment”。 |
| 历史同步后的移除与撤回 | 同一视频关联正片与特典两集；播放后显式 import_history，preview 中仍有 relation:local_catalog 的文件。进度为 lastPosition:10000、watchProgress:0.2222222222222222、duration:45000、observed:true。移除时视频存在，restore 后两集的共享文件关系恢复。 |

实验曾暴露两个实现问题，均已修正并仅重跑受影响部分：第一次重试因为 Classic 清空路径失败；第一次目录移除时文件关联已被 Classic 同步清理，早期撤回仅恢复了空关系。不能把早期空关系撤回当成完整验收。最终目录专项实验验证了真实关系和当前进度。

证据：

- [完整播放与字幕输出](evidence/x54/operations.json)、[执行日志](evidence/x54/experiment-final.log)。
- [重试专项输出](evidence/x54/operations-retry.json)、[执行日志](evidence/x54/experiment-retry-final.log)。
- [目录最终专项输出](evidence/x54/operations-catalog.json)、[执行日志](evidence/x54/experiment-catalog-final.log)。
- [完整 Next 及相关 Classic 测试](evidence/x54/full-tests.log)：563 passed，7 skipped。报告前完整套件只跑一次；之后修复只跑相关文件。
- [后续播放相关测试](evidence/x54/post-full-playback-tests.log)：66 passed；[目录与 Classic 投影最终回归](evidence/x54/catalog-shared-delivery-tests.log)：25 passed，覆盖共享文件、部分/整树移除撤回及后续关系变更冲突；[字幕和图片最终回归](evidence/x54/quality-delivery-tests.log)：14 passed。
- [最终构建](evidence/x54/build-shared-delivery.log)、[签名](evidence/x54/signature-shared-delivery.log)、[目录/质量静态检查](evidence/x54/analyze-catalog-quality.log)、[共享文件最终静态检查](evidence/x54/analyze-shared-delivery.log)：No issues found。较广静态检查保留未改 companions_io/subtitle_match_io 的六条既有 info，无 error/warning，见 [analyze-final.log](evidence/x54/analyze-final.log)。
- [证据说明与限制](evidence/x54/README.md)、[实验脚本](evidence/x54/experiment.py)。每次实验 finally 按本脚本拥有的 PID 退出并删除自己的临时目录，cleanup 均为 true。
- [交付检查](evidence/x54/delivery-checks.json)：diff --check 通过，Next UI/Podfile.lock 无差异，实验目录已删除，证据秘密模式扫描为零。

## 还缺什么与合并接口

- **G07 内嵌文字字幕尚未抽取，位图字幕尚无 OCR**；cues 返回 embedded_text_not_extracted/bitmap_requires_ocr。本实验只验证外挂 SRT，没有声称所有字幕格式/内核都能读台词。时间线读取也不证明弹幕或字幕此刻可见于像素。
- 逐帧后退及部分内核的逐帧前进沿用 Classic 约 42ms 定位；无章节/识别段时返回空事实，跳过动作须有当前识别段。直接打开裸文件没有播放详情上下文时 playlist 返回 supported:false，不能编造列表。
- **Next GUI 尚需接入这些能力。** 主控应安排本地实体建改、预览/移除/撤回入口；字幕语言标题来源编辑、自动选择重置、副本清理决定；播放器 ready/buffering/error/recovery、章节/片头片尾、播放列表及当前内容读取。数据和能力接口已提供，未改 lib/next/ui/。
- X50 合并时接入族描述与远程 describe；本 worktree 只对 endpoint 做集中小改，未改种子、nipa、next_core、next_runtime 或 headless core。已有 MediaCapability/SubtitleCapability 的组装自然包含新事实能力；实时播放器能力只在具备 inspection port 的宿主注册。远程调用没有新增限制；本次未做跨设备或无界面真实播放实验。
- 本次没有扩展弹幕 fetch/attach/import 的批量入口，也没有改媒体服务器进度写入回执；相关能力在其他领域实现中，报告中的这些质量条目仍需对应负责人接续。

依赖未改，未 commit/push/pub get；只在本 worktree 构建。构建生成的 Podfile.lock 恢复基线，既有 GeneratedPluginRegistrant.swift 生成变化按任务约定保留。没有访问安装版应用、真实数据目录、登录钥匙串、用户 harness/配置、媒体服务器账号或 /Volumes/Media；没有打扰 ui-demo 或其他实验实例。

中断后续接核对：工作分支仍为 next/x54-catalog，代码、报告及最终证据完整保留。报告的 18 个证据链接全部存在，当前构建再次通过只读 deep/strict 签名验证；三个已记录的实验目录均已删除，证据秘密模式扫描仍为零，diff --check 通过。没有重新构建、启动实例或重复已有实验及测试。

## 需要主控决定的问题

没有。上述未覆盖部分是实现与集成缺口，需要接续工作，无需新增产品决定。
