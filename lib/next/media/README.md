# 媒体能力原语

`media.management.bind_batch/unbind_batch` 是多作品管理预览协议：与 identity 原语
同 entries/requestId，省略 expectedPlan 返回受影响实体、剧集、来源和进度；带回
expectedPlan 执行。关系改变使预览失效，播放进度变化不失效。操作保留文件和进度，
原身份及操作审计保留，可用 bind_batch 重建，不需要 NeedsDecision。底层 identity
原语维持现有幂等契约，供扫描及持久任务使用。
`media.management.targets {workIds}` 将合并作品映射到拥有者设备的原始 work/episode/
file IDs；离线保留对象及原因。远程操作经 mesh.invoke 在拥有者执行，支持范围以
目标能力目录为准。`media.files.reveal {paths}` 在本机文件管理器定位，逐项报错；
远程调用定位的是目标设备桌面。

`media.management.merge_work/undo_merge` 是完整作品合并与撤回入口，
`bind_batch` 仍只改身份绑定。合并在拥有者设备内完成，sourceWorkId 归入
targetWorkId；调用者显式提供 release/episode 的 `mappings`，未映射子实体
保留原 ID 并迁入目标层级，不按标题或集号猜对应关系。可通过 Mesh 调用，
SQL 的 `db.describe/query/write/undo` 同时保留并支持 Mesh。

本地自编目录不需要外部身份：`media.entities.put_batch` 原子保存 work → release →
episode 与已有 fileIds。调用者给稳定 ID，修改要求 revision 与影响预览。
`remove_batch` 默认只返回预览，执行保留实体前像、文件和观看进度，`restore` 按
移除后的修订检查撤回；库视图隐藏 tombstone，实体审计仍保留。它不伪造 Classic
或来源平台的编号。文字覆盖、来源刷新、资料完整情况各有 batch 接口；图片清除
只收回覆盖，副本保留。详细契约与理由在 `nipa describe media` 和 X54 报告中。
Classic 历史同步保留显式 local_catalog 文件关系。影响预览从当前观看历史读取进度，
未观察到的值为 null；进度变化不使关联预览失效，实体和文件关系变化仍使它失效。

Next 的媒体识别判断属于 Agent。代码提供文件信息、外部元数据和显式绑定，
不解析文件名，不推断集号，不生成识别 Decision，也不把一个季的选择级联到目录文件。
Classic 的扫描和匹配只在 Classic 模式运行；Next 不挂载隐藏的 Classic 页面，也不隐式导入 Classic 身份。已有数据保留，旧库导入使用显式 `media.library.import_history`。Next 的启动扫描与下载完成只登记/探测文件事实，身份由 Agent 通过候选查询、显式绑定或 SQL 决定。

## 工具契约

Action id 是 Harness 名称；MCP 名称把点替换为下划线。输入输出以
`media_capability.dart` 的 schema 为准。

| 名称 | Effect | 语义 |
|---|---|---|
| `media.files.list` | read | 一次返回目录递归视频列表或作品的全部索引文件位置，含大小、时长、头哈希和当前绑定。 |
| `media.hash.match` | read | 对多个文件查询弹弹play hashOnly 候选，返回逐项结果或错误。 |
| `media.metadata.search_batch` | read | 批量搜索 TMDB、Bangumi、弹弹play等已注册来源。 |
| `media.metadata.get_batch` | read | 批量查询作品、季或集的详情，同一调用中的相同引用只请求一次。 |
| `media.identity.bind_batch` | write | 原子保存显式指定的文件、集、季、作品绑定及理由、证据。 |
| `media.identity.unbind_batch` | write | 原子撤销多个实体的全部或指定显式绑定，保留来源审计；点名文件的 `classic_match` bindingId 时只在 Next 撤销 Classic 的自动识别。 |
| `media.identity.restore_classic_batch` | write | 恢复被 `unbind_batch` 撤销、且仍是 Classic 当前观察的自动识别。 |
| `media.management.merge_work` | write | 先预览，再携 expectedPlan 原子合并重复作品、明确映射的季和剧集；迁移身份、文件关联、覆盖与弹幕，保存旧 ID 别名及撤回前像。 |
| `media.management.undo_merge` | write | 先预览，再携 expectedPlan 原子恢复合并前状态；受影响关系有后续修改或活动弹幕任务时拒绝撤回。 |
| `media.metadata.search` | read | 保留单次来源搜索。 |
| `media.metadata.get` | read | 保留单个外部对象详情查询。 |
| `media.identity.get` | read | 读取身份、位置、来源审计、合成元数据，以及 Classic 历次观察和当前冲突。 |
| `media.library.works` | read | 读取共享作品及季、集、文件结构，包含 Classic 弹弹play匹配，支持非弹弹play身份。 |
| `media.library.work` | read | 读取一部 Next 作品的结构与元数据。 |
| `media.library.search_merged` | read | 有索引的本机 + Mesh 搜索；标题、原名、已有别名、年份与剧集标题；返回 Next workId/episodeId。 |
| `media.library.import_history` | write | 显式导入并对账 Classic 文件与有效匹配，保留来源事实与冲突，不推断绑定者；不会在启动、历史通知或其他身份写入时自动执行。 |
| `media.library.scan` | write | 提交枚举、探测、哈希和文件索引任务，不请求元数据来源。 |
| `media.metadata.override` | write | GUI 与 Agent 均可编辑；宿主记录 actor/origin。mode=persistent 刷新保留，correction 被新快照替代，clear 清除编辑。省略 mode 保持持久覆盖兼容语义。 |
| `media.metadata.refresh` | write | 沿用元数据快照刷新任务，不改变身份。 |
| `media.metadata.import_batch` | write | 追加任意来源的结构化快照，宿主记录来源、交入时间、actor/origin/invocationId；保留其他 JSON 字段。原子且 requestId 幂等。 |
| `media.metadata.put` | write | Agent 一次交一部作品的资料（作品文字/类型/三种图片，各集标题/简介/播出日期/时长/截图，按 episodeId 或 season+number 指定，缺的集建为本地目录集；episodeId 同时给 season/number 即写该集的季号集号，回执列 before/after，同一 release 内季号加集号不得重复）。整批原子、requestId 幂等，图片先取到并解码；存为与 override/artwork.set 相同的持久覆盖并记录 source，优先于所有来源快照，刷新后保留。 |
| `media.metadata.snapshots` | read | 读取实体对应的全部来源快照、原始字段和历史，包括已撤销身份的快照。 |

目录列表、批量哈希和元数据查询不创建绑定或任务；详情候选不保存来源快照。
在线 `media.metadata.search/search_batch` 的每个候选带 nullable `workId`，按已接受
exact/contains 的作品或发行身份读取本机 + Mesh 合并目录，不按同名推断。
首次搜索可能准备可重建的目录/图片投影；不登记来源文件或接受身份。
`media.library.search_merged` 与原 `media.library.search` 分开：后者仍返回 Classic
观看记录的弹弹play animeId，调用者语义和结果不变。能力族事实以
`nipa describe media.library` 与 `nipa describe media.metadata` 为准。
目录列表没有分页，未索引文件的 `fileId` 为 null；绑定可直接使用它的 `path`。
作品列表返回全部已关联文件位置及存储的探测值，远端或尚缺探测值的字段为 null。
大小单位是字节，时长单位是毫秒，`headMd5` 是文件前 16 MiB 的 MD5。
时长使用已有 fvp/MDK 读取，不启动播放；无法读取或超时则为 null。
文件名只作为原始数据和 hashOnly 请求字段传递，不产生身份信号。
弹弹play上游没有这里可用的多文件匹配接口，批量 Action 内部逐文件发 hashOnly；
一次 Action 的语义仍是返回所有输入文件的独立信号。

## 绑定与不变量

### 重复作品合并

先通过 `media.management.targets` 查来源设备 ID，在同一拥有者设备调用：

```json
{
  "sourceWorkId": "duplicate-work",
  "targetWorkId": "surviving-work",
  "mappings": [
    {"sourceId": "duplicate-release", "targetId": "surviving-release"},
    {"sourceId": "duplicate-episode", "targetId": "surviving-episode"}
  ],
  "requestId": "merge-confirmed-duplicate-001",
  "reason": "已核实为同一作品、同一集与相同文件区间"
}
```

新请求不带 `expectedPlan` 只预览，返回 `canCommit`、`expectedPlan`、实体迁移、
外部身份、文件区间、未合并子实体、相同文件区间的候选对应及冲突。核实后原输入
加 `expectedPlan` 提交；数据变化使预览失效。候选对应不会自动采用，集对应必须
与已指定的季对应一致。不同来源身份可共同保留，同一来源的冲突身份原子拒绝。
同文件的 start/end/ordinal 不同不能折叠，弹幕设置冲突或活动下载/对齐任务也阻止提交。

`metadataPolicy` 默认为 `reject`；属性或覆盖不同须明确选 `prefer_target` 或
`prefer_source`，预览列双方值，撤回快照保留原值。该选项不忽略身份、文件区间或
弹幕冲突。文件、字幕选择、文件/区间进度和来源快照正文不改，绑定证据与弹幕池
保留。原实体保留合并标记和别名，旧 ID 在读取与播放中解析到保留实体；目录删除
和修改要求当前 ID，避免通过旧 ID 误操作。没有 Classic 识别、历史导入或投影写入。

撤回使用 `undo_merge {mergeId,requestId,reason}` 预览，再携返回的 `expectedPlan`
提交；受影响实体、身份、文件关联、覆盖、弹幕或别名有后续修改则整批拒绝。
播放进度变化不阻止撤回，也不会被旧值覆盖。两个工具的 requestId 均按调用来源
隔离，提交与回执同事务保存；重启或 `outcome_unknown` 后以完全相同输入重试
恢复原回执。已提交的 requestId 即使省略 expectedPlan 也返回回执，重新规划须用
新 requestId。撤回后重试旧合并返回 `mergeState: undone`，不再次合并。

每次最多捕获 1000 个层级实体、4 MiB 关系与审计快照；不跨设备提交分布式事务。
schema v25 追加只读 `media_entity_aliases` 与 `media_work_merges`，SQL 可查询它们。

### 身份绑定

`bind_batch.entries` 的 `kind` 是 work/release/episode/file。
本地层级为 work → release → episode；文件通过关联指向 episode。目录模式中
kind=episode 已保存所选集及其作品、版本；同批的作品、版本条目复用同一身份。
省略本地 ID 时按来源 ref 建立或复用；entityId 是条目自身，workId/releaseId 是父实体，
不是外部编号。Bangumi subject、弹弹play anime 的 releaseRef 可省略（复用 workRef）；
TMDB TV 的非 work 条目必须给出 season releaseRef。work ref.scope 为空字符串，
弹弹play episode.scope 为 `anime/<animeId>`，Bangumi 为 `subject/<subjectId>`，
TMDB season 为 `tv/<tvId>/season/<number>`，episode 在其后追加 `/episode/<number>`。
外部集编号使用实际 object ID，不用显示集数。完整输入示例和字段语义在 `nipa describe` 中。
除内置目录模式外，`kind` + 既有 `entityId` + `ref` + `reason` 可以直接绑定
work/release/episode 的任意外部对象：不请求 provider、不建立父实体或文件关联。
直接模式回执 `entries[].metadata` 返回 `fetched:false`、`persisted:false`；
收集资料时随后显式 `metadata.refresh_batch` 获取并保存各已核实的作品／季／集，
等待逐项任务终态，再回读。目录模式的 `metadata.records` 标明获取类型和本次是否保存：
已有绑定复用不会重新写入所获取的快照，不能把重复绑定当作刷新。
宿主仍校验实体层级、同来源身份冲突、同种本地实体的外部对象唯一归属，并记录理由与证据。
直接绑定不能混入 `workRef` 等目录模式字段。任意来源的外部目录关系由 Agent 判断，宿主保存其证据。

文件也可使用 `kind=file` + 既有 `entityId` + `ref` + 单个 `localEpisodeIds`。
该 ref 必须已经 accepted 在指定的本地 Episode 上（可在同一 batch 的前一条显式绑定）；
宿主核对这个关联，不请求来源或创建空快照，不允许覆盖另一组文件集关联。
这样任意 HTTPS 来源的 opaque 身份也能关联本地或远程文件，仍复用同一身份、证据、回执与撤销。

新来源的 `ref.provider` 使用 HTTPS origin，例如 `https://movie.douban.com`，
禁止自由昵称；大小写、空白、默认 443 端口、末尾斜线与 hostname 末尾点统一。
路径、查询、fragment、userinfo 不属于来源命名空间；内置 `tmdb` / `bangumi` / `dandanplay` 保持原名。
不同 host 或非默认端口表示不同 authority，不猜测站点别名；复用身份读回的 canonical provider。
`objectType`、`externalId` 和 `scope` 都是该 authority 内的 opaque 字符串，不改写它们。

文件目标使用 `entityId` 或 `path`；其他层级可用 `entityId` 绑定既有本地实体，
省略时按外部对象建立对应实体。每条输入明确给出 `workRef` 和理由：
TV 的季身份使用 `releaseRef`，文件或集的身份使用 `episodeRefs`。
Movie 本身就是对应播放单元。Bangumi subject、弹弹play anime 是各自的集目录。

远程文件先通过 `media.sources.browse/sync` 登记，绑定使用返回的 `fileId`（输入字段
`entityId`）。SMB、WebDAV、共享 HTTP 流与 Jellyfin/Emby 均使用同一绑定事务、来源与证据。
远程绑定保存已登记位置和已有 probe，不要求下载、读取字节或登录服务器；本地文件仍执行
内容探测与批量提交前的修订校验。哈希匹配仍需要本机内容。

远程发现的 `media_locations.source` 是来源作用域（`sourceId`；Jellyfin/Emby 另包含实际 serverId），文件按来源、设备、locator 隔离。
播放 path 保持 Classic 格式。同一路径对应多个来源时，按 path 绑定返回 conflict，要求使用
浏览返回的 fileId。旧的无服务器归属位置保留为独立证据，不自动归到当前连接。
已登记远程路径唯一时可直接按 path 绑定；未登记远程路径返回 not_found。

`workId`、`releaseId`、`localEpisodeIds` 显式指向跨来源共用的本地身份；
代码校验层级和父实体，不猜测不同来源的映射。只建立输入涉及的集及其父实体，
不会按目录或文件名扩展绑定，也不会接受未选择的整个集目录。
`episodeRefs` 可含多集，多个文件可指向同一集。可选时间段保留在 FileEpisode 中。

文件可访问性、内容修订、外部季属于作品、外部集属于季、已接受身份冲突和
FileEpisode 的关系/时间段由宿主校验。违反不变量返回稳定 Failure code、
带 `/entries/<index>` 的 violation 和具体原因；整批绑定写入回滚。
绑定、FileEpisode、快照、理由、证据、投影 outbox 和幂等回执在同一事务中保存。

绑定的 `boundBy` 由宿主从 Invocation.origin 写入，GUI 为 user，其余外部调用为 agent；
输入 schema 不接受调用者自报的 boundBy。解除绑定保留原绑定的来源字段，
追加撤销操作的 origin、invocationId、boundBy、理由和证据。
文件绑定证据同时保存实际内容 probe 和文件修订。

`requestId` 按 Action 与 origin 隔离，回执跨重启保存。同一请求重试返回原结果，
同一 requestId 的不同输入返回 conflict。已有冲突不会静默替换；解除绑定属于
可恢复的 write，不删除文件或观看进度。

仅明确单集的弹弹play绑定投影到 Classic。身份提交与 Classic 不在同一数据库事务；
outbox 只有回读确认后才完成。投影失败返回对应条目错误，并明确身份已经提交、
投影仍待完成；重试和启动恢复都使用同一持久 outbox。

显式导入时，Classic 有效匹配按现有媒体库来源筛选函数进入实体、绑定及 FileEpisode 表，
`source=classic_match`、`boundBy=null`。清除后保留的 ID 和远端服务自己的身份仍为历史证据。
只有显式调用 `media.library.import_history` 才导入并同步；匹配变化保存追加观察，
撤销旧的 Classic 文件绑定而不改动 Agent/user 绑定。按弹弹play外部对象复用既有实体，
不按标题或文件名合并。不同来源指向不同集时均保留关联，`identity.get.conflicts` 可见。
跨来源的同一集可由 Agent 明确提供 `localEpisodeIds` 表达。
文件—剧集关联各自来自哪里由 `IdentityStore.linkSources` 报告（下载的 `media.episodes[].identitySources`
用它）：每条是站在该关联后面的已接受文件绑定 `{bindingId, source, boundBy, origin?}`，
`source=classic_match`（`boundBy` 为 null）是 Classic 自动识别，其他是显式绑定，`boundBy` 为 `agent`/`user`，
`origin` 取自写入它的调用；`local_catalog` 关联记为 `{source: local_catalog}`；没有绑定支撑的关联列表为空。
`unbind_batch` 省略 `bindingIds` 只撤销显式绑定。`classic_match` 绑定（Classic 的自动识别）只在被点名时撤销：
可以点名文件上的，也可以点名它所建的剧集、版本、作品上的。这只改 Next：Classic 的观看记录（进度、
animeId/episodeId）和 Classic 界面不变，也不向投影 outbox 写任何行（文件条目的 `classicProjectionId` 为 null）。
撤销都追加 `unbind` 审计（调用的 origin、理由、`revoked: classic_match`）。
撤销文件上的：只由它支撑的文件—剧集关联移除（显式绑定及 `local_catalog` 关联不受影响）；它所来自的 Classic
当前观察改记为 `provenance=classic_match_revoked`（指纹不变，`identity.get.classicObservations` 可见）。
之后的显式导入看到指纹相同，不再挂回；Classic 对该文件记下不同的识别（指纹变了，包括记录被删除后重新识别）才按
一般规则导入新的观察，旧绑定不会被再次撤销。文件条目的结果带 `remainingClassicBindings`：失去该文件关联的剧集，
以及它们的版本、作品上仍已接受的 `classic_match` 绑定 `{entityId, kind, bindingId}`；未被点名的都保持原样。
撤销剧集、版本或作品上的：影响片库里对应一层的显示。片库按现有规则（mesh/library.dart）不显示既无已接受绑定、
其下也无文件的非 localOnly 作品；所以只撤销文件时，Classic 建的作品仍在片库里（`media.library.works` 也一样），
点名作品、版本、剧集的 `classic_match` 绑定后，其下没有别的已接受绑定或文件的作品才离开片库。实体、快照和进度仍保存。
`restore_classic_batch` 恢复，同样按点名：条目是 `entityId` 与 `bindingIds`（`unbind_batch` 返回的 ID）；文件条目可省略
`bindingIds`，恢复该文件被撤销的识别。文件的绑定仅当它仍是 Classic 对该文件的当前观察（`classic_match_revoked`）
且对应剧集有已接受的身份时恢复，否则 conflict、整批不改动；恢复文件绑定、文件—剧集关联，观察改回
`provenance=classic_match`，审计事件 `restore`。剧集、版本、作品只恢复点名的绑定。不碰 Classic 记录和 outbox。
`requestId` 幂等，可再次撤销。要把这一集记成她自己的决定，用 `bind_batch`，那是显式绑定，另一类事实，并会按规则投影到 Classic。
`classic_match` 绑定仍跟随 Classic 的匹配记录：该路径的 Classic 观看记录被删除（`history.remove`，
观看进度随之删除）或匹配改变后，下一次显式 `media.library.import_history` 撤销它的文件绑定，
并移除不再有绑定支撑的文件—剧集关联。显式绑定及其关联不受影响。

Classic 已有不同匹配时，outbox 标为 `conflict`，显式绑定仍已提交，Classic 保持原值。
再次调用原 requestId 可重试该文件的投递；启动只恢复 `pending`，不自动处理 `conflict`。
Classic 已有相同 ID 时仅确认，不重写其标题；无匹配时仅填写匹配列，保留历史其他列。
标题取同一外部对象的非空 provider 快照；缺少时保留 Classic 对应非空原值，仍缺少则报告冲突，不写空标题。
解除显式绑定不清除独立 Classic 匹配；投递回读不会再制造一个独立 Classic 匹配。

Classic 写事务同时向 `next_classic_projection_journal` 追加该 projectionId / 路径的
匹配字段前像、后像、行 ID 和行存在标记。撤销仅在原行 ID 及四个匹配字段逐值仍与后像一致时恢复前像；
用户改标题、重匹配或删除行都会保留 Classic 并返回 conflict，Next 撤销仍已提交，
`identity.get.conflicts` 可见。进度、时间等字段不参与比较，也不被恢复覆盖。
同一匹配因另一来源绑定而再次投影时，通过 `previousProjectionId` 继承仍有效的
原始撤销前像；已有 Classic 编辑则保留撤销冲突，不把再次确认当成独立 Classic 匹配。
原先不存在的行撤销后保留历史行和后续播放数据，匹配 ID 恢复 null，标题为原路径文件名。
已有独立匹配只记录 unchanged，不撤销它；未投递的新版投影记录 not_written。
旧投影缺少原子撤销证据时保留 Classic 并报告 conflict，不从旧观察猜测前像。
`bind_batch` / `unbind_batch` 文件条目含可空 `classicProjectionId`，生产 Classic 端口返回
`classicProjection` 的逐路径 status / restored；成功回执持久保存，旧 requestId 重试返回
该操作的原确认结果，不会撤销后续绑定。投影日志保留供恢复和审计，不清理原 outbox。

Jellyfin/Emby 的单集弹弹play投影使用既有 `${type}_dandanplay_mapping` 和
`${type}_episode_mapping`，服务器 profile、实际 serverId 与 item ID 组成作用域键。Classic 映射服务按当前
profile/serverId 读回作用域映射，返回实际服务器 item ID；无新版映射时沿用旧查询。
连接配置改指另一台服务器时，即使 profile ID 没变，也不会复用原服务器的文件和新版映射。
无 SeriesId 的独立文件用 `item:<itemId>` 作为目录锚，不推断它所属的系列。
完整映射行与前像、后像在同一 Classic 事务写入 `next_remote_projection_journal`；
撤销核对原行（含 ID 与字段），删除自己新建的集映射，最后一个引用退出时收回自己新建的目录。
独立同集映射保持 unchanged；被 Classic 修改的映射保持原值并报告 conflict。
旧的无服务器归属剧集映射不能安全认领；Next 身份提交后投影返回 conflict，要求先在 Classic
处理旧映射。TMDB、Bangumi 等不向 Classic 写映射。

## 存储与升级

### 任意来源快照与作品视图（X9）

先绑定外部身份，再调用 `media.metadata.import_batch`：

```json
{
  "requestId": "changan-douban-2026-10-11",
  "entries": [{
    "ref": {"provider": "https://movie.douban.com", "objectType": "subject", "externalId": "26849758", "scope": ""},
    "language": "zh-CN",
    "fetchedAt": "2026-10-11T00:00:00Z",
    "url": "https://movie.douban.com/subject/26849758/",
    "fields": {
      "overview": "豆瓣简介",
      "rating": {"value": 8.1, "max": 10, "count": 520049, "label": "豆瓣"},
      "directors": ["曹盾"],
      "actors": ["雷佳音", "易烊千玺"],
      "otherFacts": {"preserved": true}
    }
  }]
}
```

`rating` 的 value/max 为有限数值，`0 <= value <= max`、`max > 0`；count 为非负整数或 null。
来源由宿主从 ref.provider 填入，不接受调用者替评分声明其他来源。
title/originalTitle/overview/imageUrl/year、导演、演员、类型有字段类型；未知字段完整保存。
宿主交入时间控制提交快照的新旧，fetchedAt 保留为来源报告的采集时间。
重复 requestId 返回原回执；不同内容复用 requestId 返回 conflict；失败整批回滚。

`media.identity.get`、`media.library.work(s)` 以及 `media.entities` / `library.works` /
`library.seasons` / `library.episodes` 的 `metadataView` 返回真正的 JSON fields/provenance/ratings。
旧 `metadata` 文本数组保持兼容；结构化消费者使用 `metadataView`，原始及历史信息用 snapshots 读取。
`state.query` 显式开放的 JSON 对象保留其属性，并延续 URL 去认证信息的公共视图规则。

work 与其所有 release 共用一个作品视图，episode/file 仍保留各自元数据。
源字段优先取 work 的服务/提交快照，按时间从新到旧，缺项再从 release 补充；
Classic 观察排在服务/提交事实之后。同一对象/语言只使用最新提交快照；所有历史仍可读取。
ratings 独立保留各对象/语言的最新评分，不因另一来源评分而消失。
work/release 已有编辑不迁移：读取时按 changed_at 取该字段最新有效编辑，平时不改任何旧行。
persistent 始终保留；correction 被作品范围的新快照替代；clear 明确清除该作品范围的该字段编辑，
原编辑日志保留。季专属标题/简介等原始事实仍在 snapshots 中，不需要再写两层 overview。

Classic 完整详情按已绑定的弹弹play身份读同一作品视图；只有其他身份的本地文件，
播放器详情通过 FileEpisode 读取同一作品视图。展示简介、标题、海报、类型、主创、评分和评价人数，
沿用已有的评分与制作信息布局；评分投影为 Classic 的十分制，原始满分仍在身体里。
Classic 的详情持久缓存和用户个人评分不改写；没有对应概念的字段留在事实中。
本次没有 schema 迁移：沿用 v8 表，以追加 JSON 快照和幂等回执扩展存储，不重写旧数据。

数据库仍由 NextCore 提供唯一连接；MediaRuntime 仅提供 Capability 和基础设施执行器。
存储保持 Work → Release → Episode、File、FileLocation、FileEpisode 的身份模型，
以及独立 external objects / bindings / evidence / snapshots / overrides。

v5 迁移移除 media_candidates、media_identifications，以及 scan_items 中的子识别任务列，
新增 media_binding_operations 保存幂等请求指纹和结果。
既有 entities、locations、bindings、evidence、snapshots、overrides、FileEpisode、
legacy history、Classic projection outbox 均保留，不重算身份或修改 boundBy。
旧非终态 media.identify / media.apply_release 任务标记为明确失败并追加任务事件，
历史终态任务保持不变；升级不会恢复旧判断流程。
补充时长等 probe 信息不改变文件内容修订，也不撤销原绑定。

v8 只追加 `media_classic_observations` 和 `media_classic_current`，原表和数据不变。
该历史迁移为 v8；当前 Next schema 版本以 `next_database.dart` 为准。Classic 的投影日志在首次投递的事务内可重入创建，
Classic `user_version` 和 `watch_history` schema 不变，Next 启动不导入 Classic 身份。
首次同步保留原 `media_legacy_history`，每个文件的观察、身份和当前指针同事务提交；
中断后可重试显式导入，已提交的相同指纹不重复写入。进度不参与指纹。
Classic 标题快照带来源及未知语言 `und`，不会覆盖来源服务快照或持久用户编辑；
所有原始标题仍可从观察读取。Classic 删除文件后，下一次显式导入撤销其来源关联，保留历次观察与结构实体。

## 验证边界

测试使用离线构造的来源 fixture、MockClient 和注入的时长探测端口，不访问线上 API，
不含真实凭据。两项 48 集测试通过 InvocationObserver 断言 Harness 调用次数：
无哈希匹配目录为 1 次完整列表、2 次元数据调用、1 次批量绑定；哈希匹配目录为
1 次批量哈希、1 次批量绑定。调用次数是工具能力的测试事实，不规定 Agent 的调用顺序。
真实来源响应和 native MDK 时长在真机上验收。

### 丰富资料与多来源身份

跨站搜索和判断由 agent 完成，宿主保留 exact/contains 身份、提供方独立快照、
字段来源和手动覆盖。metadata.get 的 details 保存 TMDB 演职员/制作/播出资料、
Bangumi 公开 staff/characters/infobox、Dandanplay 作品资料及完整 providerData。
Bangumi 公开资料无需账号。metadata.sources 返回各外部对象的最新资料，评分分来源；
手动覆盖和提交资料优先，普通快照的中文标题优先 Bangumi，同语言简介取更完整来源，
其余汇总字段优先 TMDB。具体来源仍在 provenance，不改写原始快照。

`get/get_batch` 返回资料但不入库。`refresh/refresh_batch` 保存请求对象的快照，
不递归为本地子实体补身份或分别获取详情。提供方记录的 `acquisition` 将搜索、目录摘要
与详情请求分开，详情的 `sections` 标明 received / not_returned / failed；
TMDB TV/movie 请求演职员、外部 ID 与关键词，season/episode 请求演职员及外部 ID。
这些状态说明请求范围，不证明来源提供了所有字段。原始响应继续保留在 providerData。

ui_facts 的 `sourceCoverage` 独立于合并页面字段：有身份无快照、摘要、获取范围未知、
详情部分返回、详情已返回分别报告；各集也有自己的 sourceCoverage。历史与外部导入
缺少获取证据时标为 snapshot_unverified，内容仍保留，不能仅据此判定未抓取。
按外部对象及语言保留最近详情获取记录，新的图片快照不覆盖它；新的部分失败详情
不能被旧成功记录遮住。Mesh 合并来源证据时遵循相同规则。
`review.gapCounts` 汇总所有 missing 分组，包括来源详情与逐集身份，不使用
missing.fields 为空或已有 ID 来推断全部资料齐全。字段来源的快照和时间仍由
fieldProvenance 描述，可能与详情获取记录不同。任务流程见
[媒体整理指南](../../../docs/next/development/guides/media-identity.md)。

ui_facts 还报告三站身份与动画的建议补全目标。刮削不下载弹幕；正式剧集身份在播放时
由 AutomaticDanmaku 使用，跨季、SP、合集不能仅按编号推断。
文件扫描同时保存 technical（容器、码率 bit/s、视频和音轨），files.list 返回它；
详情页按来源展示演职员、角色声优、评分、资料表及已探测的文件信息。
