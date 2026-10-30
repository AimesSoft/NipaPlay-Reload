# 媒体身份、资料与合并

目标是把正确文件关联到正确作品和集，而不是仅凭相似标题做自动判断。先查目标 `nipa describe media`、对应 Action 和 `app.capabilities`；在线来源与凭据可用性不等于实际网络成功。

1. 用 `media.library.search_merged` 查 Next 目录，`media.library.work`、`media.files.list` 和 `media.identity.get` 核对作品、文件位置、已有绑定及证据。扫描 `media.library.scan` 只登记和探测文件，是会产生任务的写操作；`media.files.list` 可读取文件并探测，视目标描述了解开销。
2. 用 `media.hash.match`、`media.metadata.search_batch/get_batch` 取候选，核对来源、作品、季、集和文件区间。候选、标题相似或 hash 信号都不是已确认身份。外部 ref 的 provider、objectType、externalId、scope 应沿用真实来源结果；外部对象 ID 不是显示集数。
3. 证据足够后，用 `media.identity.bind_batch` 保存明确身份与理由；需要影响预览时用 `media.management.bind_batch/unbind_batch`，核对预览后按目标 describe 提交。跨设备先用 `media.management.targets` 取得拥有者的原始 ID，在拥有者执行。保留 requestId、来源、输入和回执；身份不明时保留候选，向用户说明。
4. `media.metadata.put`、`media.metadata.import_batch` 和 `media.metadata.override_batch` 分别处理展示资料、来源快照和文字覆盖；先查 `media.metadata.ui_facts` 及来源，注意图片获取失败、revision 与原子性等目标契约。普通识别不应顺便提前下载弹幕。

Next 启动、扫描与下载完成不会隐式运行 Classic 识别。旧 Classic 身份仅在用户需要兼容导入时显式调用 `media.library.import_history`；目标 headless 不提供此入口。Next 已提交绑定可按 outbox 契约投影给 Classic，投影状态与绑定事务分开观察，不把回读当作导入其他身份。

## 整理交付与批量工作

用户交付的范围内，先让马上要看的集具备正确文件关联和可播事实，再补齐来源资料及中文标题、简介、海报、背景、Logo、剧集标题与截图。TMDB、Bangumi、弹弹play 中已收录且能核实的身份与资料都要补齐；完成一个来源不代表其余来源已完成。电影、真人剧不强求动画站点。来源缺失时保留真实本地实体并报告缺项，不伪造 ID 或阻塞已有可播内容。`media.metadata.ui_facts` 给资料事实，媒体库和来源能力给可播事实，字幕与弹幕能力给实际轨道；它们不能互相替代。

多作品、多集优先查批量接口和[并行分工](automation-memory.md#批量工作与并行分工)。独立来源查询可以并行，同一作品的身份、合并与覆盖写入由一个负责人协调。普通刮削不提前下载弹幕；需要时使用准确剧集身份按弹幕能力契约准备。

## 每个来源都完成：身份 → 获取 → 保存 → 回读

弹弹play 哈希匹配可以确认动画文件与剧集，不能代替 TMDB、Bangumi 资料获取。作品已经有 TMDB ID，也不能证明简介、演职员、制作公司、播出资料、外部链接等 TMDB 详情已入库。

1. 核实各来源的作品、季、集对应关系。TMDB 的作品、季、集是独立对象；不能只补作品 ID，也不能仅按显示集号跨站批量绑定。电影使用 movie 对象，不要求虚构季集身份。
2. 给已有实体补另一来源时，用 `media.identity.bind_batch` 的 `ref + entityId` 直接模式，复用原实体。它**只绑定身份，不获取、不保存详情**；回执 `entries[].metadata` 明确说明本次获取与保存情况。目录模式会获取目录，新绑定保存对应记录；复用已有绑定也不刷新详情，子记录可能只是摘要。
3. 已有可靠且适用的详情可复用。对需要补资料的已接受身份，用 `media.metadata.refresh_batch` 显式提交每个已核实的作品／季／集 ref。保存每项 requestId 和 job，等待终态及回执，处理逐项失败。刷新作品只保存该对象快照，不会自动为本地各季各集补身份或刷新它们的详情。
4. 外部补充也可先 `get/get_batch`，再 `import_batch` 提交。`get` 是只读，返回数据不等于入库；导入要保留标题、简介等公共字段和 `details` 中的丰富资料、`providerData`、来源及时间，不能只摘图片和评分。`put/override` 是展示覆盖，不代替来源快照。
5. 回读 `ui_facts/ui_facts_batch` 的 `sourceCoverage`、`review` 及全部 `missing` 分组；按来源检查 `metadata.sources`，需要原始证据时读 `metadata.snapshots`。合并字段可能来自其他站点，`missing.fields=[]`、有演员或有海报均不能证明 TMDB 数据已收集。

`sourceCoverage` 区分身份与已存资料，并保留对象类型、scope、语言及获取证据：

| 状态 | 含义与处理 |
| --- | --- |
| `identity_only` | 有接受的身份，没有该对象的已存快照；需要显式获取并保存。 |
| `search_only` / `catalogue_only` | 存的是搜索或目录摘要；需要核对该对象的详情。 |
| `snapshot_unverified` | 已存旧快照或外部导入，但没有获取方式记录。先检查保存的内容与来源，不能断言没抓过，也不要求无条件重抓。 |
| `detail_partial` | 详情请求已保存，但请求的部分未返回或失败；看 `unreceivedSections`、获取记录及原始响应。 |
| `detail_fetched` | 已保存该对象请求的详情部分。空数组、空值仍可能是来源的真实回答；它不保证所有字段有值、资料永久最新或下级对象已完成。 |

作品与季的来源情况在顶层；各集在 `episodes.items[].sourceCoverage`。`missing.sourceDetails`、`missing.episodes.withoutTmdbIdentity`、`tmdbDetailsToReview` 与其他身份、中文、字段、逐集缺项一并进入 `review.gapCounts`。`review` 只是资料检查入口，不是播放或整项任务验收证书。新图片快照不会抹掉历史详情获取记录；新的详情部分失败也不会被旧成功记录遮住。Mesh 使用发布的相同证据，旧设备没有获取记录时保持待核实。

“来源没有”须有查询依据。交付时分别说明：尚未核实身份、已绑定但未取资料、已读但未保存、获取失败、已保存但来源字段为空。TMDB 季条目不提供的系列级字段，应核对所属 tv 对象并保留来源；不要把同一 tv 对象强行绑定到多个不同本地作品，或编造简介填空。来源确实缺失、匹配有歧义、网络失败时报告实际缺项，继续其他已授权工作。

## 重复作品与恢复

完整合并用 `media.management.merge_work`：先预览，检查受影响实体、文件区间、来源冲突，并显式指定季/集映射；不要按名字或集号猜映射。确认后携原预览返回的 expectedPlan 提交；关系变化会使预览失效。`media.management.bind_batch` 只处理绑定，不等于完整合并。需要撤回时用 `media.management.undo_merge` 先预览；后续关系修改可能阻止撤回。

合并及撤回有同来源、同 requestId 的持久回执契约：响应丢失时保留目标设备与完全相同输入，按该 Action 契约取回原结果，不换键重做。其他动作先检查各自幂等及任务回执；没有该契约不能自动重试。SQL 可通过 `db.describe/query/write/undo/receipt` 在目标库预演、提交和核查；SQL 与专用能力并存，回执 unknown 不等于未提交。

参考：[媒体能力实现说明](../../../../lib/next/media/README.md)、[合并实现](../../../../lib/next/media/work_merge.dart)、[过程事实契约](../../OBSERVABILITY_CONTRACT.md)。
