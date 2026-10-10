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
| B 站 | BV/av 的分 P、ep、ss、cid；分 P 歧义返回可执行 Decision | 360 秒 protobuf 段；专用有界 wire 解码，不新增库；ID 字符串化 |
| 优酷 | vid/公开视频 URL、show 的正片分页目录 | 60 秒段；宿主会话 profile 返回响应，严格检查 ret、data.result 和内层 data.result |

弹弹play 未提供条目级来源时保存 `platform=unknown`，不根据格式、cid 或用户 ID
猜平台。未识别的原始 source 仍保留在 originSource；没有原视频/原弹幕 ID 时，
不建立跨源身份等价。测试里的扩展字段是合成输入，不表示已验证真实服务器会返回
这些字段；真实 related 响应的来源字段仍需主控回放验收。

优酷参考仅采用分钟计划、嵌套结果结构和属性/时间映射机制。签名应在宿主
`YoukuSessionBridge.minute` 内完成，桥接必须校验凭据引用对应的会话、来源版本和
获准 profile，过滤响应中的会话材料，并支持取消/限额。当前应用没有现成的优酷
会话签名通道，默认不注入该 bridge；`sources` 如实返回 sessionAvailable=false，
获取任务返回 authenticationRequired。没有读取浏览器、添加登录流程或读取凭据文件。
弹弹play 沿用已有宿主账号/应用签名边界；B 站使用匿名公开接口，不请求历史弹幕。

宿主使用固定 URI 模板，拒绝跨域重定向及额外业务参数，逐来源串行限流；HTTP
响应最大 8 MiB，每次计划最多 120 段、两小时、100000 条。超时只取消本次 HTTP，
不会冒充任务取消。429 尊重有界 Retry-After；任务只对限流/传输失败重试三次。
结构变化、登录失效和访问拒绝立即停止。B 站和优酷不声明标题搜索，调用者用明确
URL/ID 或目录定位；未实现 WBI、验证码、会员/地区限制绕过、全站抓取或历史查询。

## 追加存储

MA 的 v2 身份迁移保持原样，MB 在 `next_database.dart` 的迁移序列末尾追加 v3
（`migrateDanmaku`），不改已发布位置。新库与旧库共用同一序列，都执行到最新版本。

| 表 | 语义 |
|---|---|
| danmaku_bindings | 引用 MA File/Episode 与 media_external_objects；记录实体修订、启用、去重、绝对偏移、对齐、证据、宿主绑定者、绑定修订和已提交缓存 |
| danmaku_cache_chunks | 来源/视频/版本/宿主域名/访问引用摘要/内容选项组成 cache key；保存各段原始时间条目、覆盖及抓取时间；TTL 两小时 |
| danmaku_alignment_candidates | 任务的锚点、固定偏移候选、残差、置信说明和显式选择；关联绑定修订 |
| danmaku_binding_events | 追加的 attach、控制、解绑与对齐选择审计记录；不抹去旧证据 |

MB 绑定不写入 MA 的元数据 bindings，也不投影 Classic 匹配字段，避免元数据解绑
意外撤销弹幕来源。文件内容修订变化会使旧 MB 绑定失效。Episode 通过 MA
FileEpisode 关系挂到播放器；一文件多集缺少明确 start/end 时不编造时间轴。

每段落盘后回读验证。获取完成只证明指定范围的当前弹幕池结构和缓存覆盖，
不证明完整历史、平台是否筛掉弹幕或身份语义正确。失败/取消回执列出已完成和缺失段。
只有整个请求计划验证后才给绑定赋已提交缓存并加载轨道；失败来源保留可恢复缓存，
不把空字段当成功，也不加载半轨。不同来源各自有 Job 和回执。

Task Engine 禁止提交副作用后进入 cancelled。MB 在取消前尚无提交时以 cancelled
结束；已有缓存/候选提交时停止调度，回读已提交部分，以 failed + verified receipt
结束，details.stopped=true、partial=true，并保留引擎的取消元信息。重启/暂停恢复
重新核对缓存和绑定，不依赖仅存在于内存的段计数。

## 对齐、显示与 GUI

原始 sourceTimeMs 永不累积改写。正 offsetMs 提前，负数延后；GUI 秒数在宿主
换成整数毫秒。对齐任务取手动锚点偏移的中位数，保存最大残差和时间跨度；即使
锚点一致也不自动应用，持久 Decision 提供 apply/keep。应用检查原绑定修订并
原子保存选择、映射和审计事件。首期只实现固定平移，不宣称自动音画/字幕对齐或
分段/比例映射已完成。

轨道 ID 为 `next:<bindingId>`，与受保护的 Classic `dandanplay` 轨道分开。
装载校验播放路径与代次，接受合法空池；GUI 的轨道开关、偏移和删除通过宿主
调用相同 Harness Action，持久化成功后重建轨道。源专属映射抵消 Classic 全局
自动匹配偏移，只继续受用户全局手动偏移影响。

源内获取重复按来源条目 ID、原平台 ID 或有明确发送者的稳定指纹消重；匿名无 ID
条目不删除。跨轨显示只按可靠原身份折叠；未知 related 重叠对至少八个字符的
完全相同文本，在对齐后 100 ms 窗口内保守折叠。一个显示组最多接收同一轨道
的一条成员，保留成员与数量；可以用 set_dedup 关闭，原始缓存始终不变。
Classic 单独播放时仍走原合并逻辑。既有 Classic 聚合轨道丢失来源信息，加入
Next 轨道时只作为未知来源做显示折叠。

## Action 目录

输入/输出 schema 的唯一事实来源是 `capability.dart`。视频引用包括 sourceId、
videoId、objectType、title、durationMs；durationMs=0 可以出现在定位结果中，
获取前必须由调用者补充有依据的时长。fetch 与 align 的 requestId 用于幂等重试。

| Action | Effect | 结果 |
|---|---|---|
| sources / search / episodes / resolve / tracks | read | 瞬时声明/候选/目录/明确视频/持久绑定与覆盖；不建任务或缓存 |
| fetch | write | 立即返回 jobId；只获取缓存，不改播放轨道 |
| attach | write | 明确绑定及全片池获取任务，返回 bindingId + jobId |
| set_enabled / set_dedup / offset / detach | write | 绑定修订 CAS；绝对设置；解绑保留缓存 |
| align / align_apply / align_keep | write | 持久对齐任务和可直接执行的选择 |
| export | write | 授权媒体目录中的新 JSON 文件；raw 或 mapped，按 bytes/SHA-256 回读；不覆盖现有文件 |
| cache_delete | destructive | 删除明确 cacheKey；活动获取任务引用该缓存时返回 conflict，先停止任务 |

上表各项带 `danmaku.` 前缀。export 的 mapped 指一条绑定映射后的源数据，不是
播放器经过过滤的最终显示列表，也不包含其他轨道。

## 离线验收

`test/next/danmaku_*_test.dart` 使用测试源码构造的 JSON/protobuf、MockClient、
临时 SQLite 与内存播放器端口；没有真实平台录制、账号内容或线上请求。
播放器原生内核、真实登录态以及三项真机场景留给主控端到端验收。

```sh
~/development/flutter-3.44.6/bin/flutter analyze --no-pub lib/next lib/utils/danmaku_source_merge.dart test/next
~/development/flutter-3.44.6/bin/flutter test --no-pub test/next test/danmaku_track_timing_test.dart test/danmaku_track_dialog_windowing_test.dart test/danmaku_track_overlay_entry_test.dart test/danmaku_track_popup_barrier_test.dart
git diff --check
```
