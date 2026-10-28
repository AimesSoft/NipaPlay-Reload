# 媒体身份、资料与合并

目标是把正确文件关联到正确作品和集，而不是仅凭相似标题做自动判断。先查目标 `nipa describe media`、对应 Action 和 `app.capabilities`；在线来源与凭据可用性不等于实际网络成功。

1. 用 `media.library.search_merged` 查 Next 目录，`media.library.work`、`media.files.list` 和 `media.identity.get` 核对作品、文件位置、已有绑定及证据。扫描 `media.library.scan` 只登记和探测文件，是会产生任务的写操作；`media.files.list` 可读取文件并探测，视目标描述了解开销。
2. 用 `media.hash.match`、`media.metadata.search_batch/get_batch` 取候选，核对来源、作品、季、集和文件区间。候选、标题相似或 hash 信号都不是已确认身份。外部 ref 的 provider、objectType、externalId、scope 应沿用真实来源结果；外部对象 ID 不是显示集数。
3. 证据足够后，用 `media.identity.bind_batch` 保存明确身份与理由；需要影响预览时用 `media.management.bind_batch/unbind_batch`，核对预览后按目标 describe 提交。跨设备先用 `media.management.targets` 取得拥有者的原始 ID，在拥有者执行。保留 requestId、来源、输入和回执；身份不明时保留候选，向用户说明。
4. `media.metadata.put`、`media.metadata.import_batch` 和 `media.metadata.override_batch` 分别处理展示资料、来源快照和文字覆盖；先查 `media.metadata.ui_facts` 及来源，注意图片获取失败、revision 与原子性等目标契约。普通识别不应顺便提前下载弹幕。

Next 启动、扫描与下载完成不会隐式运行 Classic 识别。旧 Classic 身份仅在用户需要兼容导入时显式调用 `media.library.import_history`；目标 headless 不提供此入口。Next 已提交绑定可按 outbox 契约投影给 Classic，投影状态与绑定事务分开观察，不把回读当作导入其他身份。

## 整理交付与批量工作

用户交付的范围内，先让马上要看的集具备正确文件关联和可播事实，再检查中文标题、简介、海报、背景、Logo、剧集标题与截图，保留丰富资料来源。优先核实 TMDB 身份，动画尽量补 Bangumi 与准确弹弹play 剧集身份；来源缺失时保留真实本地实体并报告缺项，不伪造 ID 或阻塞已有可播内容。`media.metadata.ui_facts` 给资料缺项，媒体库和来源能力给可播事实，字幕与弹幕能力给实际轨道；它们不能互相替代。

多作品、多集优先查批量接口和[并行分工](automation-memory.md#批量工作与并行分工)。独立来源查询可以并行，同一作品的身份、合并与覆盖写入由一个负责人协调。普通刮削不提前下载弹幕；需要时使用准确剧集身份按弹幕能力契约准备。

## 重复作品与恢复

完整合并用 `media.management.merge_work`：先预览，检查受影响实体、文件区间、来源冲突，并显式指定季/集映射；不要按名字或集号猜映射。确认后携原预览返回的 expectedPlan 提交；关系变化会使预览失效。`media.management.bind_batch` 只处理绑定，不等于完整合并。需要撤回时用 `media.management.undo_merge` 先预览；后续关系修改可能阻止撤回。

合并及撤回有同来源、同 requestId 的持久回执契约：响应丢失时保留目标设备与完全相同输入，按该 Action 契约取回原结果，不换键重做。其他动作先检查各自幂等及任务回执；没有该契约不能自动重试。SQL 可通过 `db.describe/query/write/undo/receipt` 在目标库预演、提交和核查；SQL 与专用能力并存，回执 unknown 不等于未提交。

参考：[媒体能力实现说明](../../../../lib/next/media/README.md)、[合并实现](../../../../lib/next/media/work_merge.dart)、[过程事实契约](../../OBSERVABILITY_CONTRACT.md)。
