# MB 多平台弹幕

`DanmakuRuntime.create` 接收 NextCore 提供的 MA 身份存储，提供 `executors` 与
`capability`。NextCore 在 `engine.start()` 前调用 `attach` 注入唯一引擎，启动后由
`NextRuntime` 调用 `startRestoring(harness, player)` 绑定宿主播放器；监听播放状态
并从已提交缓存恢复轨道，监听不发网络请求。关闭时 Core 先 `stopRestoring` 停止
恢复及 GUI 控制，再关闭 Task Engine，最后 `close` HTTP client。完整接入顺序见
[应用组合点](../README.md)。

## 来源与宿主边界

`source.dart` 是不依赖 Flutter 的 Dart 插件端口。来源声明契约/实现版本、平台、
能力、域名、请求 profile、访问策略和预算；提供搜索、目录、定位、半开区间段计划、
可取消段获取和计划验证。每个注册来源得到独立 `ScopedDanmakuHost`，不能调用
其他来源的 profile。首期没有把来源端口接入现有 JS 插件清单或渲染桥接。

| 来源 | 定位与目录 | 获取与身份 |
|---|---|---|
| 弹弹play | episode ID、标题搜索、作品目录；未知时长由调用者依据本地媒体补齐 | 原始 comment JSON，withRelated=true；保留条目级 source、sourceVideoId、originalId，cid 单独记为 sourceEntryId |
| B 站 | 匿名 WBI 标题搜索返回 BV 候选；BV/av 的分 P、ep、ss、cid；URL 尾斜杠、`p` 和 `ep_id` 选集；歧义返回可执行 Decision | 360 秒 protobuf 段；专用有界 wire 解码，不新增库；ID 字符串化 |
| 优酷 | vid/公开视频 URL、show 的正片分页目录 | 60 秒段；宿主会话 profile 返回响应，严格检查 ret、data.result 和内层 data.result |
| local | 授权媒体目录中的明确 XML/JSON 路径；同名/相似名自动发现仍沿用 Classic | 共用 Classic 文件解析入口；从 chatserver/chatid 读取平台与视频身份；未知平台保持 unknown |

弹弹play 未提供条目级来源时保存 `platform=unknown`，不根据格式、cid 或用户 ID
猜平台。未识别的原始 source 仍保留在 originSource；没有原视频/原弹幕 ID 时，
不建立跨源身份等价。测试里的扩展字段是合成输入，不表示已验证真实服务器会返回
这些字段；真实 related 响应的来源字段仍需主控回放验收。

优酷参考仅采用分钟计划、嵌套结果结构和属性/时间映射机制。签名应在宿主
`YoukuSessionBridge.minute` 内完成，桥接必须校验凭据引用对应的会话、来源版本和
获准 profile，过滤响应中的会话材料，并支持取消/限额。macOS 由 NextCore 注入
`VaultYoukuSessionBridge`：用户在「设置 → 实验室 → 平台登录」的内置 WebView
完成登录，宿主在保险库中按平台保存会话。`sessions.status` 返回的 `accessRef`
可作为现有弹幕 Action 的 `credentialRef`。优酷 MTOP 签名与请求都在宿主中完成，
正常的 token 握手最多更新并重试一次；不读取浏览器 cookie 数据库或个人配置。
未登录或被平台拒绝时返回 authenticationRequired，并指明 NipaPlay 登录入口。
弹弹play 沿用已有宿主账号/应用签名边界；B 站匿名公开接口继续可用，登录后宿主
向固定 B 站 profile 自动附加会话，也接受准确的宿主引用；不请求历史弹幕。
平台登录的状态、存储与注销契约见 [平台会话](../sessions/README.md)。

宿主使用固定 URI 模板，拒绝跨域重定向及额外业务参数，逐来源串行限流；HTTP
响应最大 8 MiB，每次计划最多 120 段、两小时、100000 条。超时只取消本次 HTTP，
不会冒充任务取消。429 尊重有界 Retry-After；任务只对限流/传输失败重试三次。
正片范围内的结构变化、登录失效和访问拒绝立即停止。优酷不声明标题搜索，调用者用明确
URL/ID 或目录定位。B 站使用 `/x/web-interface/nav` 返回的公开 WBI 图像键签名
`/x/web-interface/wbi/search/type`；键缓存一小时，查询限第一页、20 个 BV 候选，
候选必须 resolve 到 cid 后获取。2026-10-11 的两次无 Cookie/Authorization 请求探测中，
nav 返回 `code=-101,isLogin=false` 且包含 WBI 键，搜索返回 `code=0`、空结果；这证明
匿名接口可用，不证明特定标题能搜到或所有网络均不触发限流。未实现验证码、会员/地区
限制绕过、全站抓取或历史查询。测试只使用合成响应，不重复线上探测。

## 追加存储

MA 的 v2 身份迁移保持原样，MB 在 `next_database.dart` 的迁移序列末尾追加 v3
（`migrateDanmaku`），不改已发布位置。新库与旧库共用同一序列，都执行到最新版本。

| 表 | 语义 |
|---|---|
| danmaku_bindings | 引用 MA File/Episode 与 media_external_objects；记录实体修订、启用、去重、绝对偏移、对齐、证据、宿主绑定者、绑定修订和已提交缓存 |
| danmaku_cache_chunks | 来源/视频/版本/宿主域名/访问引用摘要/内容选项组成 cache key；保存各段原始时间条目、覆盖及抓取时间；TTL 两小时 |
| danmaku_alignment_candidates | 存量对齐任务的锚点、固定偏移候选、残差、置信说明和显式选择；关联绑定修订 |
| danmaku_binding_events | 追加的 attach、控制、解绑与对齐选择审计记录；不抹去旧证据 |

MB 绑定不写入 MA 的元数据 bindings，也不投影 Classic 匹配字段，避免元数据解绑
意外撤销弹幕来源。文件内容修订变化会使旧 MB 绑定失效。Episode 通过 MA
FileEpisode 关系挂到播放器；一文件多集缺少明确 start/end 时不编造时间轴。

每段落盘后回读验证。获取完成只证明指定范围的当前弹幕池结构和缓存覆盖，
不证明完整历史、平台是否筛掉弹幕或身份语义正确。失败/取消回执列出已完成和缺失段。
整个正片范围验证后才给绑定赋已提交缓存并加载轨道。attach 自动记录当前本地视频时长，
fetch 也可明确传 `localDurationMs`。起点超出该时长的段失败时继续获取，其错误保留在
`outOfRangeFailures`；成功回执为 `status=localRangeComplete,localRangeComplete=true,
complete=false,partial=true`。与正片相交的段仍必须完整成功；未提供本地时长时仍要求
整个计划成功。失败来源保留可恢复缓存，不把空字段当成功。不同来源各自有 Job 和回执。

Task Engine 禁止提交副作用后进入 cancelled。MB 在取消前尚无提交时以 cancelled
结束；已有缓存/候选提交时停止调度，回读已提交部分，以 failed + verified receipt
结束，details.stopped=true、partial=true，并保留引擎的取消元信息。重启/暂停恢复
重新核对缓存和绑定，不依赖仅存在于内存的段计数。

## 对齐、显示与 GUI

原始 sourceTimeMs 永不累积改写。正 offsetMs 提前，负数延后；显示时间减去
offsetMs，GUI 秒数在宿主换成整数毫秒。`analyze_alignment` 只读当前绑定修订，
从最多 100 个手工锚点计算偏移的中位数（偶数个取上中位数），返回输入顺序的
偏移、绝对残差、最大残差、源时间跨度、证据、置信标签及限制。空锚点返回空数组和
null 估计；不修改绑定、不写候选、不创建任务或 Decision。至少三个锚点、源时间跨度
至少 60000 ms 且最大残差不超过 250 ms 时标记 consistentAnchors，否则为
insufficientEvidence。标签只表示锚点一致性，不证明集身份或语义对齐；首期只实现固定平移。

`update` 接受 1–100 个 changes，按输入顺序批量设置 enabled、offsetMs、displayFold。
每项指定 bindingId 或当前播放器 trackId，至少设置一个属性。绑定及有绑定的轨道
必须携带 expectedRevision；同一项的多属性和审计原子保存，修订只增加一次。
可采用估计，也可设置任何已有范围内的明确整数毫秒值（±7200000），无须 apply/keep。
返回每项 index、status 与 result/error；一个业务失败不回滚之前成功的项，后续项继续。
整个请求先做 schema 校验；结构/类型不合法时不执行任何项。reason 可选，记录到绑定
审计中；actor/origin 来自宿主 Invocation。未绑定轨道只修改当前播放状态，无持久绑定
revision；live timeline 不支持固定偏移。displayFold 只控制显示折叠，原始缓存不变。

旧 `set_enabled`、`set_dedup`、`offset` 保留原输入输出，分别转到同一属性更新实现。
`tracks` 同时提供 displayFold 与兼容字段 deduplicate。

### 旧对齐任务的恢复

- `align` 停止创建任务；已有 requestId/绑定/锚点组合仍返回原 jobId，新请求返回
  unavailable 并指明 `analyze_alignment` 与 `update` 的迁移入口。
- 已保存的 needs_decision 快照、选项和候选继续可读；`align_apply/align_keep` 只恢复
  这些存量选项，保持任务 revision、精确 ActionCall 和应用时的绑定 revision 检查。
  应用与审计仍原子写入，重启后已提交的 apply/keep 不会重复提交。
- 未选择的 queued/interrupted/恢复任务直接完成为分析回执，包含原 proposal、analysis、
  observedRevision 与 migration，不再产生 Decision，不改变偏移；已保存候选保留。
  暂停、取消及有 choice checkpoint 的任务继续按原引擎恢复与提交验证处理。
- 不迁移内核 JobState/Decision API，也不删除历史任务、候选和回执。

只使用播放器现有多轨注册表：Classic 与 Next 共用唯一的 `dandanplay` 轨道，
其余在线轨道使用 `next:<bindingId>`。每条来源轨道记录 origin、platform、
platformVideoId、文件路径或 bindingId。tracks 同时返回 Classic、本地和持久绑定；
同一平台/视频的 File 与 Episode 绑定也合为一条轨道，`bindingIds` 保留关联绑定 ID。
输入可以是 entityId、path 或 current，默认当前文件。缺少身份索引时只登记 File 与
FileLocation，不猜作品或剧集。同一平台/视频复用已有轨道，本地池存在时不重复在线获取；
弹弹play 复用会写入绑定，返回 `status=reused,jobId=null`。`refresh=true` 才获取并替换。
显式刷新使用独立的任务缓存，验证成功后才替换绑定的已提交缓存；失败不覆盖旧池。
自动加载策略仍由 Classic 设置决定，持久在线绑定在播放时从缓存恢复。
复用的弹弹play 绑定没有 Next 缓存时，可从现有 Classic 弹幕缓存恢复同一轨道，
不发网络请求、不重新触发识别或自动匹配。
装载校验播放路径与代次，接受合法空池；GUI 的轨道开关、偏移和删除通过宿主
调用相同 Harness Action，持久化成功后重建轨道。源专属映射抵消 Classic 全局
自动匹配偏移，只继续受用户全局手动偏移影响。

源内获取重复按来源条目 ID、原平台 ID 或有明确发送者的稳定指纹消重；匿名无 ID
条目不删除。跨轨显示只按可靠原身份折叠；未知 related 重叠对至少八个字符的
完全相同文本，在对齐后 100 ms 窗口内保守折叠。一个显示组最多接收同一轨道
的一条成员，保留成员与数量；可以用 set_dedup 关闭，原始缓存始终不变。
Classic 与 Next 的弹弹play 原始响应共用 `dandanplay_comments.dart` 解析；Classic
缓存和后续播放器解析保留 related 的平台、视频与原弹幕 ID。没有这些证据的旧缓存
仍按 unknown 处理，不猜平台。Classic 单独播放时仍走原合并逻辑。

## Action 目录

输入/输出 schema 的唯一事实来源是 `capability.dart`。视频引用包括 sourceId、
videoId、objectType、title、durationMs；durationMs=0 可以出现在定位结果中，
获取前必须由调用者补充有依据的时长。fetch 的 requestId 用于幂等重试；align 的
requestId 只用于存量任务查找。

| Action | Effect | 结果 |
|---|---|---|
| sources / search / episodes / resolve / tracks | read | 瞬时声明/候选/目录/明确视频/全部轨道与覆盖；tracks 可登记缺失文件位置，不建绑定、任务或弹幕缓存 |
| fetch | write | 立即返回 jobId；只获取缓存，不改播放轨道 |
| attach | write | 明确绑定及获取任务，或复用已有轨道；复用/已存在时 jobId=null，回执带 status/trackId |
| set_enabled / set_dedup / offset / detach | write | 绑定修订 CAS；绝对设置；解绑保留缓存 |
| analyze_alignment | read | 估计、逐锚点偏移/残差、证据、置信与限制；无持久化或任务 |
| update | write | 批量绝对属性修改，逐项结果；绑定 CAS、轨道播放状态、显示折叠 |
| align / align_apply / align_keep | write | 仅存量任务查找/恢复；新任务迁移到只读分析加属性更新 |
| export | write | 授权媒体目录中的新 JSON 文件；raw 或 mapped，按 bytes/SHA-256 回读；不覆盖现有文件 |
| cache_delete | destructive | 删除明确 cacheKey；活动获取任务引用该缓存时返回 conflict，先停止任务 |

上表各项带 `danmaku.` 前缀。export 的 mapped 指一条绑定映射后的源数据，不是
播放器经过过滤的最终显示列表，也不包含其他轨道。

## 离线验收

`test/next/danmaku_*_test.dart` 使用测试源码构造的 JSON/protobuf、MockClient、
临时 SQLite 与内存播放器端口；没有真实平台录制、账号内容或线上请求。
播放器原生内核、真实登录态以及三项真机场景留给主控端到端验收。
`danmaku_ergonomics_test.dart` 验证分析无写入、估计后一次 update 设置不同值、批量
失败、轨道/绑定属性、空与矛盾证据、旧任务重启恢复和退役错误。覆盖率基线保留旧
actions，另增 primaryActions、compatibility（alias/legacyRecovery）和 behaviorScenarios；
验收同时检查旧入口 Effect、新入口 Effect 和能力映射。

```sh
~/development/flutter-3.44.6/bin/flutter analyze --no-pub lib/next lib/utils/danmaku_source_merge.dart test/next
~/development/flutter-3.44.6/bin/flutter test --no-pub test/next test/danmaku_track_timing_test.dart test/danmaku_track_dialog_windowing_test.dart test/danmaku_track_overlay_entry_test.dart test/danmaku_track_popup_barrier_test.dart
git diff --check
```
