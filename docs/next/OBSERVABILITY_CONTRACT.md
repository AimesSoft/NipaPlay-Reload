# Next 的过程事实契约

2026-10-28，基于 `66bc3fb79` 的本轮修改。宿主保存可核查的事实，Agent 解释、判断与选择下一步。SQL 与专用能力并存；可观测性不能重新引入隐式 Classic 识别。

这是能力层的一部分：Agent 需要查询正在发生的步骤、事实来源、提交证据和恢复入口，才能决定等待、补资料、重新获取只读数据或恢复原请求。错误文案和调试日志不能替代这些结构化事实。

## 四种不能混为一谈的结果

| 问题 | 证据 | 不能推断什么 |
| --- | --- | --- |
| 请求是否到达设备 | 接收端 request_received；调用端认证响应；连接失败的阶段 | 本机 send 已调用不等于远端开始执行 |
| 能力是否执行完 | 相同 invocationId 的 action_started / action_completed / action_failed | Action 返回不等于事务、索引、播放器都完成 |
| 数据是否提交 | 数据同事务写入的领域回执，如 db_operations、media_work_merges | outcome_unknown、取消响应、断线不表示回滚 |
| Agent 是否拿到结果 | 调用端 response_received | 源端 response_handed_to_transport 不证明对端已收到 |

没有证据的状态必须是 unknown。目录旧、设备不可达、文件发生变化、附件缺失和操作已提交但响应未取回分别报告。

## 当前可用入口

- `diagnostics.operations`：全部经过 InvocationScopeCapability 的能力执行，以及 Mesh 出入站过程。桌面和 headless 共用入口，可经 Mesh 直接查询目标设备。按 invocationId、action、peerId、jobId、commitId 或原领域请求键 requestKey 查询。分页携带 session 和 after=next；sessionChanged、historyGap 明确表示进程更换或历史已淘汰，不能沿用旧游标推断没有新事件。出站记录的 parentInvocationId 指回本地能力，远端请求 ID 与接收端能力 invocationId 相同。诊断查询本身及其 tools/list 发现请求不写入过程记录，避免轮询挤掉待查证据。每进程最多 512 条、30 分钟，每条最多 12 个阶段；此入口是短期过程观察，不冒充持久日志。只记录阶段、时间和选定 ID，不保存 SQL、输入正文、凭据、临时授权 URL 或文件内容。
- `db.receipt {kind,requestKey}`：同一调用来源的持久 SQL 回执。write 的键是原 previewId，undo 的键是原 requestId。committed 由与 SQL 数据同事务的记录证明；result.postCommitPending 单独表明提交后的通知未确认完成。unknown 可能表示请求仍在执行、键/来源不符、没有记录；不能据此创建新请求重做。查询支持直接 Mesh 路由。
- `media.library.status`：立即读取缓存的目录观察，不发起网络/数据库操作、不等待正在进行的刷新；可在刷新阻塞时查看 refreshInProgress、各端 refreshing、最后成功版本和失败原因。observedAt 是读取观察的时刻，不是刚刚探测成功的证明。
- `media.library.refresh`：设备 reachability 与 catalogueFreshness 分开，返回目录版本、刷新尝试与成功时间、错误、artwork 完整度；结构发布不等待图片；图片有单独的 artworkStage、artworkUpdatedAt、artworkAssetId、artworkFailure，区分元信息、字节读取、写入、发布与完成。旧完整目录可保留并独立探测文件拥有者。`file_changed` 表示打开后文件标签变了，`file_range_incomplete` 表示响应长度不足。
- `mesh.devices`：runtime 给监听器、登录定时器、停止状态和防重放容量。只读传输与查询不占用持久写操作的防重放账本；重复写调用与容量不足、持久化失败具有不同 reason。
- 既有持久入口继续保留：task 状态和 job_events、事件/动态及 body_changes、领域提交回执、journal、播放器 state/info/kernel/failures、network observations、diagnostics.status/file_logs/errors。它们通过 invocationId / jobId / commitId 关联，各自声明观察范围。

## 重试规则

1. not_delivered：本次传输没有找到可交付连接；这不证明此前同领域请求没有执行。
2. outcome_unknown 或 response_continuation_unavailable：保留原设备和请求键，先查领域回执/任务；continuation 只取已生成结果，不执行原 Action。
3. db.receipt=committed：可读取回执或以同键取回原结果；不得把新的 previewId/requestId 当作“同一次重试”。
4. db.receipt=unknown：继续核查原请求及源端过程，不等同于未提交。没有持久幂等契约的写动作不能自动重做。
5. 目录、图片、文件字节等只读传输可重新获取；半途数据不作为完整目录发布。

## 明确的资源边界

目录接收：64 MiB、1024 页、2 分钟，检查逐页版本、总长度与连续偏移。源端最多 4 份、合计 128 MiB；分页读者有 2 分钟租约，活跃版本不会被新版本挤掉，无租约版本 5 分钟过期。新版接收端协商独立进度字段，进度变化不再要求传输同一份富目录；旧端保留旧协议。

响应 continuation：64 MiB、8 项、5 分钟、调用设备隔离、SHA-256；读取时清理过期项，Mesh 停止清空。过期不意味着原操作失败。

媒体文件块：1 MiB，原生读取等待 15 秒；目录/文件信息/响应分块/描述/探测等原生读取等待 30 秒，取消的是响应等待，不是已开始的领域操作。附件传输最多 16 个并发、单项 64 MiB，逐块刷新输出并检查关闭/期限，临时文件成功后才发布。暂停读取不靠固定播放器空闲超时来判断断开；HTTP 请求半关闭仍允许接收完整响应。

## 全应用仍需补齐的内容

| 范围 | 已有事实 | 尚未覆盖到的过程 |
| --- | --- | --- |
| 通用能力 | 输入校验后的开始、完成/失败、耗时、关联 ID；校验失败仍在既有 journal | 每个领域内部的排队、锁等待、子步骤；跨重启统一查询 |
| 媒体/SQL/Mesh | 提交回执、身份审计、任务、目录与字节失败、传输关联 | 所有写动作统一幂等/回执查询；逐来源元数据删除语义 |
| 播放器 | session、内核事实、错误阶段、失败历史与日志 | 内核未报告的缓冲原因、音频延迟、解码器决策，不能凭日志猜成事实 |
| 备份与迁移 | 原有迁移归档/恢复记录，外部安装对账 | 产品内完整 Next 备份/恢复能力；Mac 迁移阶段的结构化查询 |
| Harness | 实际分支/HEAD/目标版本与中断恢复文件；安全种子更新 | 中断后的自动恢复流程，当前保留锁并报告供检查 |
| 实机验证 | 本轮临时库、真实本机 TCP/TLS、故障注入和编译 | 两台正式客户端升级后的长播、暂停恢复、睡眠、真实换网；双向网络可达性 |

新的领域能力应提供拥有者、关联 ID、实际阶段、时间、失败依据、提交/结果状态、重试契约与保留边界。不能用通用调用记录冒充上述尚未实现的领域过程。

## 本轮可复核的场景

- 真正通过本机双向 TLS 发起调用，在源端按同一 invocationId 读到接收与执行阶段；输入正文不进入过程事实，连续诊断查询不会增加自身过程记录。
- SQL 已提交后切断调用端响应，用原 previewId 查询和恢复持久回执，不能执行第二次 SQL。
- 人为挂起目录响应，`media.library.status` 仍立即给出 refreshing 和 not_refreshed，不把未知可达性写成离线。
- 图片文件已落盘但缓存 Future 的清理回调返回自身，造成永不结束；阶段观察定位到写入后的收尾，修正为不返回被清理 Future。对应真实 TLS 图片及 Range/seek 回归覆盖完成路径。

这些是自动化与故障注入证据，不能替代两端正式安装包的长播、睡眠与换网验收。

## 2026-10-28 工作区验证

使用锁定依赖和 Flutter 3.44.6 / Dart 3.12.2：相关综合回归 41 个测试文件，370 passed、2 skipped；另补作品合并、身份来源、元数据写入、迁移与历史保留 8 个文件，41 passed。共 411 passed、2 skipped，属于本轮选定范围，不是仓库全部测试。headless AOT 编译通过；指定文件静态分析无 error/warning，9 项 info 风格提示。`git diff --check` 通过。

本轮验证基于 `66bc3fb79` 加工作区修改，不能用该提交号代表已包含这些修改的发行包；尚未更新两端 Release 安装包。
