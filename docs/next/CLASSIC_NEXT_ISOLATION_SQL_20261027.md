# Classic / Next 隔离与跨设备 SQL

日期：2026-10-27。开发基线：`5830634a8`。本轮落实用户确认的两项边界：Next 识别由 Agent 决定，SQL 保留并直接支持 Mesh。已有媒体身份、文件、弹幕和进度没有清理；没有对用户真实库执行扫描或修复。

## 本轮实现

- Next 界面不再隐藏挂载 Classic。模式许可绑定代次，切到 Next 后，旧 Classic 匹配即使返回也不能写入；切回 Classic 不会复活旧请求。扫描专用 SQLite 事务将新匹配与旧进度记录迁移一起提交或回滚，普通播放进度写入保持原路径。
- 首次扫描若早于旧 JSON 观看历史迁移，会先保留旧记录再提交新匹配；取消或中断后可恢复。迁移完成凭据与历史同事务提交，避免重启覆盖新进度或复活已删除记录。旧 JSON 保留，Classic 的 `watch_history` 表结构和 `user_version` 不变，按需新增单行 `watch_history_legacy_import` 凭据表。清理临时标记失败不会阻止读取已提交历史。
- `library.startupScanEnabled` 保留原设置键，含义变为 Next 纯文件索引；等待根目录加载后提交 `media.scan`，不请求身份候选。诊断区分已提交索引任务和实际完成，记录跳过原因。
- 界面添加/扫描目录只提交 Next 索引任务，不再回退到 Classic 识别。扫描状态从当前模式的任务读取，Next 不展示旧 Classic 扫描的结果。
- 下载完成只登记已校验的文件。桌面 Next 与 headless 共用 `IndexedDownloadLibrary`，统一文件/作品/剧集事实，标记与 Classic 的“已扫描下载”分开。未知身份仍为 `identificationPending`，由 Agent 查询候选后绑定或使用 SQL。
- 去除启动、Classic 历史通知、bind/unbind/restore 和投影回读的隐式 `importLegacy`。显式 `media.library.import_history` 保留；restore 只核验选中旧观察是否仍有效。明确绑定的 Classic outbox 交付与可撤回 journal 保留，交付不再接受新身份。
- 投递时保存本机路径别名证据，避免 `/var` 与 `/private/var` 等路径造成重复 Classic 行；重试和撤回仍指向原行。别名缺失、改指向或多重等价时拒绝写入。一次绑定批次共用路径索引，避免每集重复遍历整个历史库。
- Next 接管启动文件和 iOS 文件打开事件，关闭后释放订阅；启动路径只消费一次，回到 Classic 不重播。
- `media.management.bind_batch` 的能力说明明确它是绑定预览/提交包装，不是完整 work merge。SQL 仍是正式通用入口。

## 远程 SQL 契约

`db.describe/query/write/undo` 通过现有 Mesh 认证和 `mesh.invoke` 直接进入目标 `DbService`；不需要经 `program.run` 绕行。操作目标设备自己的 `next.db`，使用该设备原始实体 ID，不对接收端合并视图写 SQL，也不提供跨节点分布式事务。

示例（`previewId`、`commitId` 使用实际返回值）：

```sh
./nipa --device cs9140 call db.describe '{"tables":["media_entities","db_operations"]}'
./nipa --device cs9140 call db.query '{"sql":"SELECT id,kind FROM media_entities ORDER BY id","limit":20}'
./nipa --device cs9140 call db.write '{"previewId":"dbp-实际预演ID"}'
./nipa --device cs9140 call db.undo '{"commitId":"dbcommit-实际提交ID","requestId":"banG-undo-001"}'
```

仍先用 `db.write {statements:[...]}` 预演。未提交预演绑定调用来源，在目标进程内存保留约 10 分钟；重启或过期后需重新预演。成功提交时，SQL、审计和回执在同一事务保存。相同来源用同一 `previewId` 重试，返回原回执而不重放 SQL；提交时提供的语句和 reason 必须保持一致。

远程实际 `db.undo` 需要稳定 `requestId`，相同来源用相同 `requestId`、`commitId` 和 reason 重试取回原结果。本地旧调用可省略 requestId，dryRun 无须提交键。查询、写入结果沿用大响应 continuation。

Next schema 升至 **v24**，只追加只读 `db_operations` 回执表，原有表与数据保留。主键为 `(kind, origin, request_key)`；`request` 保存重试核对信息，`commit_id` 关联 `db_commits`，`result` 保存回执。调用设备互相不能消耗预演，回执恢复不产生第二次审计。

提交后的通知与视图刷新仍在 SQL 事务之外。若进程在这一窗口退出，恢复回执明确返回 `committed:true, postCommitPending:true`；重试不会重放 SQL 或冒充已完成刷新。直接 SQL 不自动生成领域绑定历史或 Classic outbox，这些语义由 `db.describe` 公开。

## 验证与交付边界

最终合并回归运行 35 个测试文件：**339 项通过、7 项跳过、0 项失败**。覆盖模式切换、在途识别拒绝与事务回滚、旧 JSON 历史迁移/中断恢复、显式导入、投影/撤回、路径别名、下载、界面与文件打开、DB 升级及 Mesh。跳过项受平台或独立进程测试环境配置限制，不计作通过。真实 TLS 故障注入确认：目标 SQL 已提交后断开调用端，调用得到 `outcome_unknown`；重新加入后用同一 previewId 取回回执，审计仍只有一次。

headless 可执行文件编译通过，`git diff --check` 通过。改动文件静态分析无新增问题；观看历史文件仍有原有 unused 与 empty-catch 提示。自动化验证使用临时数据库、临时目录及本机测试节点，没有执行 BanG 的生产扫描或远程 SQL 写入。

本轮没有构建或安装两端 Release。真实 Mac/Windows 的界面切换、系统“打开方式”、BanG 重复扫描防护和跨设备 SQL 验收仍需用新构建完成。先前架构审核中的 Mesh 防重放容量、合辑投影、Harness、迁移与 Erika 等其他问题，不属于本轮已修范围。

## 后续补齐：作品合并与撤回

用户随后要求补齐专用工具，已新增 `media.management.merge_work` 与
`media.management.undo_merge`。上文 v24 和 339 项是第一轮隔离/SQL 的验证记录；
本次在其上追加 **v25** 的 `media_entity_aliases` 与 `media_work_merges`，没有运行
存量数据自动清理。完整参数与示例见 [媒体能力原语](../../lib/next/media/README.md#重复作品合并)。

合并先预览、再携 `expectedPlan` 原子提交；来源与目标为同一拥有者设备的原始 work ID，
季和集由 Agent 明确映射，不按名称或集号自动猜。预览列实体迁移、外部身份、文件区间、
资料取舍和冲突。未映射子实体保留 ID 并迁入目标层级；同文件不同区间、同来源冲突身份、
矛盾的季/集对应、弹幕设置冲突和活动弹幕任务均阻止提交。

一起迁移身份绑定、文件关联、手工覆盖和剧集弹幕；保留磁盘文件、文件 ID、字幕、
文件/区间进度、来源快照与绑定证据。旧实体保留合并标记和别名，读取、播放和 Mesh
投影继续解析旧 ID；目录修改要求当前 ID。合并不调用 Classic 识别、历史导入或投影。
撤回核验相关行仍等于合并后镜像，之后有关系变更则拒绝；当前观看进度不被恢复覆盖。
两个工具均支持 Mesh，requestId 按来源隔离，提交与回执同事务持久保存。
SQL 四个工具继续保留；两个新增映射/回执表只读，防止单独修改破坏撤回证据。

补齐后的最终回归：**53 个测试文件，459 项通过、7 项跳过、0 项失败**。
包含 BanG 形状的 13 集重复样本、冲突与过期预览原子拒绝、故障回滚、合并/撤回后旧 ID
读取、进度和字幕保留、首次弹幕下载阻止合并、下载途中目标变化拒绝迟到挂载、数据库升级，
以及真实本机 TLS 节点的跨设备合并/撤回和目标重启后回执恢复。仍包含第一轮隔离与 SQL 回归。
headless 编译与 `git diff --check` 通过；相关静态分析无 error/warning，仅既有 info 提示。

能力说明与官方 harness 种子已更新。此处验证的是工作区代码与临时测试库；尚未提交、推送或
安装新的两端 Release，没有改用户实际 harness 或真实媒体库。工具要随新构建运行才可供
Agent 调用，种子按现有启动同步流程更新；真实 Mac/Windows 验收及其他 Mesh 审核项仍另行记录。
