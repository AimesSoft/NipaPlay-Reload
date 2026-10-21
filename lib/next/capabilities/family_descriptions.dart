import 'package:nipa_harness/nipa_harness.dart';
import 'classic_action.dart';

/// Versioned body facts; the catalogue always comes from the receiving host.
JsonMap describeFamily(String family, Iterable<ActionSpec> catalog) {
  final specs =
      catalog.where((spec) => spec.id.startsWith('$family.')).toList();
  if (specs.isEmpty) {
    throw Failure(FailureCode.notFound,
        'Unknown or unavailable capability family: $family. Run ./nipa list on this device.');
  }
  final parent = family.split('.').first;
  return {
    'family': family,
    'description': familyFacts[family] ??
        familyFacts[parent] ??
        'Use the live action descriptions for this family.',
    'actions': [
      for (final spec in specs)
        {'id': spec.id, 'title': spec.title, 'effect': spec.effect.name}
    ],
    'next':
        './nipa describe ACTION for input/output schemas; ./nipa call ACTION JSON or @file.',
  };
}

final class FamilyDescriptionCapability implements Capability {
  FamilyDescriptionCapability(Iterable<ActionSpec> Function() catalog)
      : actions = [
          ClassicAction(
            const ActionSpec(
              id: 'capability.describe',
              title: 'Describe a capability family',
              description:
                  'Read versioned body facts and the receiving host’s live action list. Use a family prefix such as download, danmaku, media, subtitle or mesh. Individual action schemas are available through nipa describe ACTION.',
              effect: Effect.read,
              input: ObjectSchema({'family': StringSchema(minLength: 1)},
                  required: ['family']),
              output: ObjectSchema({}, additionalProperties: true),
            ),
            (input, invocation) async =>
                describeFamily(input['family'] as String, catalog()),
          ),
        ];
  @override
  final List<Action> actions;
}

const appFamilyDescription =
    'Live host facts: app.instance identifies the process; '
    'app.capabilities reports supported features, provider/source readiness, '
    'credential references and required host setup, settings keys, action effects '
    'and remote policy. supported means an implementation exists; available means '
    'its declared host prerequisites are met, not a successful network probe. '
    'No secrets are accepted or returned. Remote writes follow local semantics; '
    'disk deletion/overwrite keep their existing NeedsDecision contract. '
    'On headless hosts indexing and download destinations treat media roots as '
    'read-only; file-channel operations use actual process permissions. '
    'A headless host has no Classic history/player/UI. download.import indexes verified files '
    'without inferring identity; roots.remove unregisters the root without deleting '
    'indexed facts or disk files. settings exposes only returned keys.';

const danmakuFamilyDescription =
    'Persistent danmaku sources, caches and tracks. '
    'Both GUI and headless use the same NipaPlay Dandanplay gateway/client, '
    'host vault reference preferences/dandanplay_token and local import parser. '
    'sources reports installed adapters; app.capabilities reports credential readiness. '
    'Headless prepares persisted tracks without mounting a player; supply entityId '
    'or path because current playback is absent. Metadata identity, acquisition '
    'and binding are independent facts. attach binds to an episode entityId '
    'whether or not its file exists yet; search results carry durationMs 0, '
    'which NipaPlay measures from the file or, for dandanplay, does not need. '
    'Empty title/hash results mean no source '
    'candidate, not a broken host. A successful fetch task proves acquisition; '
    'an existing track alone does not. fetch_batch, attach_batch and import_batch '
    'accept 1–100 entries matching the single action schema, validate all schemas '
    'first, then return input index and complete outcome for every entry. '
    'atomic=false; failure retains earlier committed results. Credentials never '
    'enter inputs. Task/binding IDs and per-item decisions/errors are preserved. '
    'align/align_apply/align_keep are legacyRecovery; new analysis uses '
    'analyze_alignment and update. Positive offsetMs advances comments: '
    'displayTime=sourceTime-offsetMs. Headless exports are under data/exports.';


const familyFacts = <String, String>{
  'media.management': r'''targets 批量将合并 workIds 分解为拥有者设备的 work/episode/file IDs；离线保留对象与 source_device_offline 原因。远程管理通过 mesh.invoke 转发拥有者的原始 ID，具体支持以目标目录为准；接收端执行与本机同样的写入和决定。bind_batch/unbind_batch 与 identity 的 entries 相同，省略 expectedPlan 返回受影响实体、剧集、来源和观看进度的预览；带 expectedPlan 执行，关系变化使预览失效，播放进度变化不失效。修改保留文件、观看进度、来源审计和 Classic 投影回执；可以用预览的原始身份重新绑定。local_catalog 移除/撤回使用 entities.remove_batch/restore。底层 identity 原语保留既有幂等契约供现有客户端与持久任务恢复。''',
  'media.files': r'''list 返回索引文件位置；管理合并作品先用 management.targets 找拥有者原始 ID，再在目标身体调用 list。reveal 接收本机授权路径，macOS/Windows 在文件管理器定位文件，Linux 打开父目录，逐项报告受理或失败；系统窗口按用户请求打开。远程调用会在目标设备定位。磁盘删除仍走 media.mesh_files.delete 的 NeedsDecision；不能将接收端转换 URL 当源设备路径。''',
  'accounts.collections': r'''list(provider,statuses?,limit?,cursor?) 批量列出账号动画收藏，返回 items:[{workId,status,rating}] 与 nextCursor。workId 是提供方编号，不是合并 ID；通过 media.bindings 的已接受身份映射。Bangumi 使用同一个 Classic 鉴权客户端的分页列表，弹弹play复用官方网关的收藏列表，不逐部拉详情。弹弹play列表未提供评分时 rating=null；未知不伪造 0。状态用各提供方词汇。分页观测远端实时列表，Bangumi 远端改动可能改变偏移量；界面应继续读取所有 nextCursor。get/update 保留现有批量逐项结果。''',
  'sync': r'''status 返回 WebDAV 配置、hasPassword（是否已保存）、启用、当前阶段和最近结果，不返回密码。configure 修改地址/用户名会清除旧密码；login 由用户在 NipaPlay 输入并测试后保存。enabled/configuration 是领域设置，适合专用界面而非普通数值控件。run 返回可等待的同步任务。''',
  'media.indexers': r'''status 返回自动附件索引器的启用值、正在执行、排队、上次运行与错误。library.*Enabled 是独立策略开关；关闭排空当前文件、保留队列，显式检查保持可用。自动匹配、弹幕加载和下载完成导入沿用各领域已有设置。''',
  'window': r'''bounds.get 读取、bounds.set 设置本进程主窗准确位置与尺寸，读写 effect 分开；不激活窗口，变化发 window.bounds_changed；已有 window.control 管 fullscreen/PiP/托盘。坐标为 window_manager 逻辑像素。目标不会按应用名查找。''',
  'share': r'''prepare 预览文字、公开 URL 或授权本地文件；open 打开该计划的系统面板，由用户选目的地。会核对预览后文件变化。不以打开面板冒充已分享，也不自动上传日志。''',
  'notification': r'''当前 macOS 宿主有原生 OS 通知：status 读取系统设置，send 受系统授权、声音及系统展示策略管理，list 区分 pending/delivered，cancel 请求移除。未授权默认 blocked，requestPermission 明确请求系统询问用户。accepted 不等于用户看到了横幅；其他平台如实返回 unavailable。''',
  'diagnostics': r'''status 给健康、版本、资源、日志和迁移观察；file_logs 用受限 fileId 与行游标读取脱敏摘录。recover 只执行显式的日志重启、投影核对、索引器检查，不自动修改用户数据或登录。日志公开发布必须有明确目标与内容；本族不上传。''',
  'cache': r'''plan(kinds,maxBytes) 返回实际回收对象、估计字节和保留原因，prune(planId) 重新核对引用与变化并返回逐项结果。仅可重取缓存回收无 NeedsDecision。Next 弹幕池复用引用感知回收；正在获取时推迟。计划是当前进程的预览，不允许夹带任意路径。''',
  'storage': r'''status 给目录真实用量和卷可用空间。父目录包含子目录，不相加。watch 显式订阅空间阈值、unwatch 取消；仅当前进程有效，转换发 storage.space_changed。可重取缓存用 cache.plan/prune；字幕、导入弹幕、用户下载与无法证明可重取的图片保留。磁盘用户文件删除/覆盖沿用 media.mesh_files 的 NeedsDecision。''',
  'network': r'''status 给路由、代理、故障转移、媒体服务器连接 UA 及来源最近错误/上次成功。check 显式检查已登记来源或官方网关 healthz，不更换路由或登录。观测历史只覆盖当前进程，未观察值不宣称可达。第三方凭据去向仍由用户设置；秘密不进输出。''',
  'events': r'''身体变化共用 hook 与 followup 的持久事实日志。describe 列出事件；wait(afterCursor) 有界等待和分页，游标跨重启；只重读事实，不重跑脚本。followup.register 订阅下一次事件；hook 名称就是事件名。播放位置不逐帧发事件；seek_requested 是受理意图，settlement 必须另核对。''',
  'download.limits': r'''get 读取原生内置下载会话限速，set 调整上传/下载字节每秒预算并返回引擎读回值。0 为无限制，正值至少 16384；省略方向保留现值。不自动初始化会话；applied=false 不能宣称已限速。只影响本机内置会话，重建后恢复默认无限制，不改变服务端限流。''',
  'media.entities': r'''Local catalog entities have stable caller-supplied IDs and expectedRevision on update. parentId is an actual local parent, never an external ID. fileIds on an episode replace its local associations. Removal includes descendants, retains tombstones and exact relationship before-images, and returns undoId; restore refuses subsequent conflicting changes. These operations do not manufacture Classic platform matches.''',
  'ui':
      r'''- **两套界面**：Classic 是原来的界面；在「设置 → 实验室」开启 Next 后，主界面换成 Next。你工作的结果显示在 Next 里。两套界面共用同一个播放器。
- **首页**：
  - **主视觉**：一部作品，显示背景图、片名 Logo、评分、年份、类型、集数、两行简介，以及“播放”“详情”两个按钮；左上角是 Nipa 的一句话。你用 `ui.shelves.put` 摆上的 hero 优先；没有时依次取最近准备好的作品、最新的可播作品、继续观看的第一部。
  - **输入栏**：就是和你对话的入口。
  - **书架**：继续观看；今天更新（用户在追、今天出了新集的作品，需要弹弹play 身份）；你摆的书架；最近添加（最新 20 部作品）。
- **发现**：弹弹play 的每日放送与推荐。
- **片库**：
  - 角落菜单先列“本地”（本机和组网设备合并的目录），再列各个 SMB、WebDAV、Jellyfin、Emby。一个来源一页，形式是书架或类别卡片。
  - 每个来源有原始结构：本地只有“全部”，Jellyfin/Emby 是已选的服务器库及其层级，共享是文件夹。用户要求时，你用 `ui.library.*` 整理类别；原始结构和整理可以切换，切回原始会保留整理。
  - 类别有三种内容：条件（本机持续计算，新作品自动进来，不需要你在线）、手选（一串作品）、来源原样（某个库或文件夹）。已绑定身份的服务器作品可以和本地作品进同一个条件类别。
  - 分类由用户提出，不要自作主张地分类。
  - 原始类别的重排和隐藏只在本机生效，不改服务器或共享；`ui.library.restore` 恢复隐藏。离线来源显示上次读到的目录，作品不能播放。
  - 用户在界面上的直接操作和你用的是同一套能力，记入动态。
- **动态**：你和 NipaPlay 做过的事，以及发现。
- **详情页**：
  - 背景图、Logo 或标题、资料、简介；
  - 各季剧集：截图、集号、标题、时长、观看进度、弹幕热度线、能否播放；
  - 集数不全或有不能播放的集时，出现“下载全部”按钮，按下等于用户对你说了这句话。
- **对话**：首页展开的对话页，和其他页面的侧栏，是同一个会话。你用 `ui.present` 摆的卡片出现在回复下方，状态实时更新。卡片有：作品（workId 或 ref）、剧集（episodeId）、候选作品（items，每项 workId 或 ref）、任务（taskId）、准备进度（title 与 steps，每步引用任务、实体或后续）、选项（`choices`：可选的 question，2–6 个 options，每项 label、可选 detail 和 recommended）。用户点选项卡片中的一项，等于在对话里说出它的 label。
  - 片库外的作品用 ref：`{provider, objectType, externalId, scope:""}`，和 `media.metadata.search/get` 返回的一样；可以是 tmdb 的 tv/movie、bangumi 的 subject、dandanplay 的 anime。卡片和片库作品一样显示海报、标题、年份、集数和评分，点开是它的作品页，页上是“让 Nipa 准备”而不是播放。资料在摆的时候向来源读一次并留给卡片；来源读不到这部作品，整批卡片都不摆。片库里已有同一身份（已接受的绑定）的作品，卡片就是片库里那部；之后入库的，卡片也会变成片库里那部。
- **右上角的进度环**：NipaPlay 的后台任务。
- **播放器**：播放能播放的集（本地文件或媒体服务器上的文件），叠加弹幕和字幕。
- **界面刷新**：界面随时读取最新数据，交给 NipaPlay 的东西马上可见。
- **普通公开链接**会原样返回；带登录凭据、令牌、签名或访问密钥的链接会被脱敏。`ui.capture` 默认返回长边不超过 1280 像素的截图，传 `originalSize:true` 返回原尺寸。
- **想让用户在 NipaPlay 里看到的，可以用 `ui.present` 和 `ui.shelves.put` 摆给他**：这些文字是给观众看的，用自然的短句，不写 ID，也不写过程。''',
  'media':
      r'''Files, local catalog, identity, metadata and artwork are independent facts. Local-only works use entities.put_batch without fabricated provider IDs. Catalog hierarchy is work → release → episode, with indexed fileIds on episodes. Batches declare atomicity. Changing/removing catalog associations requires a revision/impact preview and retains files, progress, prior facts and source audit. Removed local entities can be restored using undoId. Text and artwork clear reveal source facts and retain edit history; clearing an override is not deleting a disk file.
NipaPlay 自己会做一部分：作品有 TMDB 身份时取图，同步 Classic 识别的结果，把下载完成的文件登记入库，发现并记录视频旁的同名 XML/JSON 弹幕、内嵌字幕轨和匹配的外挂字幕。`media.metadata.ui_facts` 告诉你一部作品现在还差什么。你的工作是：
`media.metadata.ui_facts` 读的是和界面同一份数据，按作品给出下面每一项有没有、来自哪里；不必截图去猜。

- **文件与剧集的对应**：一个文件对应到某一集，那一集才能播放。本地文件在片库根目录（`media.library.roots.*`）内，或是 NipaPlay 已验证完成下载的文件，才在 Next 中可访问；文件仍须实际存在。对应关系由 `media.identity.bind_batch` 写入；Classic 识别成功的文件会自动同步过来。
- **身份**：作品与弹弹play、Bangumi、TMDB 或其他 HTTPS 来源的绑定。本地作品也可用 media.entities.put_batch 建立，不要求外部身份。用 `bind_batch` 和 `unbind_batch` 修改。文件可以同时有 Classic 自动识别的剧集关联（`source=classic_match`，`boundBy` 为 null）和显式绑定的关联，两者指向不同的集时都保留，`identity.get.conflicts` 列出差异。`unbind_batch` 只撤销显式绑定，不动 `classic_match`；`classic_match` 跟随 Classic 的匹配记录：Classic 里该路径的观看记录被删除（`history.remove`，观看进度随记录一起删除）或匹配改变后，下一次同步撤销它的文件绑定，并移除不再有绑定支撑的文件—剧集关联；显式绑定及其关联不受影响。
- **资料**：各来源的快照合并而成，你的覆盖优先。界面显示标题、原名、简介、年份、类型、制作公司、集数、评分。
  - 标题和简介以简体中文优先；没有中文时显示已有的语言，不会自动翻译。
  - 缺标题时显示“未命名作品”；缺简介就没有简介正文；其他项缺了就省略。
  - 用 `media.metadata.import_batch` 交入来源快照，用 `media.metadata.override` 覆盖标题和简介（可以注明 `language`），用 `media.metadata.refresh` 刷新。
- **图片**：
  - 横版无文字背景图：用于首页主视觉、横版卡片和详情背景；缺了用竖版海报代替，两者都没有时显示主色。
  - 竖版海报：用于竖版卡片和片库。
  - 透明底片名 Logo：缺了显示文字标题。
  - 每集截图：用于剧集卡片和继续观看。
  - 主色：从背景图计算，没有背景图时从海报计算。

  背景图、透明 Logo 和每集截图只有在作品有 TMDB 身份并配置了 TMDB 凭据时才由 NipaPlay 自己取；只有弹弹play 或 Bangumi 身份的作品不会有这三项。`media.metadata.ui_facts` 的 `identities` 和 `missing` 如实列出有没有 TMDB 身份，以及缺哪些图片、中文标题或简介、哪些集缺标题或截图。
  有 TMDB 身份并配置了 TMDB 凭据时，NipaPlay 会自己取图。已经保存的 `artworkUrls` 各角色图片、其他来源的 `imageUrl` 和显式图片覆盖，不因缺少 TMDB 凭据而隐藏。`imageUrl` 在作品上是海报，在集上是截图；它没有横版或透明 Logo 的语义。`media.artwork.set` 可以把链接或本地文件，连同来源，设为任意一种图片。
- **一次交一部作品的资料**：`media.metadata.put` 一次提交一部片库作品的标题、原名、简介、年份、类型、海报、背景、Logo，以及按 `episodeId` 或（`season`，`number`）指定的各集标题、简介、播出日期、时长、截图；字段都可省略，省略的不动。图片先取到并能解码才提交，任何一项失败则整批不写。不存在的集按本地目录规则建出来（可以没有文件）。资料来源 `source` 与 actor、origin、invocationId 一并记录；写入的是和 `override`、`artwork.set` 同一份持久覆盖，刷新来源快照后仍在，并优先于所有来源快照。同一 `requestId` 重放结果不变。
- **剧集列表**：作品下各季的集，只包含绑定过的集。
- **Classic 同步**：保留识别标题与已有的详情缓存，包括标题语言、简介、海报、背景、类型和集数。未缓存的资料不会自动补抓；没有声明语言的识别标题仍是 `und`。Next 的显式覆盖优先，不修改 Classic 的详情缓存。
- **扫描**：`media.library.scan` 只建立索引，不做识别；支持指向授权根目录内视频文件的符号链接，不递归跟随目录链接。新增文件在下一次扫描时进入索引；身份、资料、图片、弹幕是独立的事实。
- **本地文件读取**：扫描和按根目录调用 `media.files.list` 会逐个读取视频、计算头部哈希并探测时长，并非只枚举文件名。`state.query` 的文件视图读取已有索引与对应关系，不重新探测视频。
- **搜索**：`media.library.search_merged` 只读搜索本机与组网设备合并片库的中文名、原名、已有别名、年份和剧集标题；返回能打开 Next 的 workId/episodeId、年份、本机图片路径、设备和可播放事实，按 limit/episodeLimit 分别限制作品和剧集。索引随目录刷新，首次建立后逐字查询不扫全库。原 `media.library.search` 仍是 Classic 观看记录系列，返回弹弹play animeId，不能当 Next workId。`media.metadata.search/search_batch` 的候选带 nullable workId：只有已接受的 exact/contains 作品或发行身份算已入库，包括组网设备；同名不算身份。
- **你的工具**：这个仓库里的脚本，或别人的开源工具，负责在外面找东西：RSS、站点、API、文件。找到的结果交给 NipaPlay，才算进入了这个系统：
  - 下载：`download.add`；
  - 身份：`bind_batch`；
  - 资料：`media.metadata.put`、`import_batch` 或 `override`；
  - 图片：`artwork.set`；
  - 弹幕：`danmaku.import`。
- **媒体身份可以来自多个来源**：弹弹play、Bangumi、TMDB 等。弹弹play 没有收录，不等于无法识别；电视剧、电影常常只有 TMDB 身份。内容哈希匹配只能给出弹弹play 的 ID。文件名需要你自己理解，NipaPlay 不会替你解析。
- **你取得的结果都可以交给 NipaPlay 保存**（弹幕、元数据、身份），它会记录来源并检查一致性。缺少入口时，如实告诉用户。
- **专用原语之外，也可以直接读写库**：`db.describe` 列出 next.db 的表、含义、可写范围和跨表规则（classic_match 如何随同步重新导入、覆盖优先于快照、图片覆盖存在哪）；`db.query` 用 SQL 只读查询；`db.write` 先预演再提交，`db.undo` 撤回。专用原语仍是便捷入口，已有身份、资料、绑定的契约不变；直接写入不往 Classic 投影。''',
  'db': r'''next.db 的直接读写入口，与 media.*、danmaku.* 等专用原语并存。凭据不在这个库里。
- **读**：`db.describe` 给每张表的列、主键、外键、索引、含义，以及它可不可写、为什么；还给跨表规则（`semantics`）。`db.query` 执行一条 SELECT（含 WITH … SELECT），`?` 按位置绑定 params。SQLite 自己保证只读：非 SELECT 在语法层被拒，连接处于 query_only。结果受 limit 与 maxBytes 限制，被截断时 `truncated` 为 true，`nextOffset` 是续读位置（自己加 ORDER BY 让分页稳定）；过长的单元格被截短。值里的凭据被遮蔽。
- **写**：`db.write` 一次提交一批 INSERT/UPDATE/DELETE（至多 100 条，同一事务）。不带 previewId 只预演：事务回滚，按表返回插入、更新、删除的行及前后值（太多时给计数和样例）和 `previewId`。带 `previewId` 提交的就是预演过的效果：这些行在预演后被改过，就拒绝并什么都不写，重新预演即可。previewId 只在内存里，约 10 分钟有效，用一次即失效。
- **边界由 SQLite 执行**：只有 describe 标为可写的表能改（别的表的写入被 SQLite 触发器中止）；DDL、PRAGMA、ATTACH、事务控制、多条语句不被 SQLite 当作单条 INSERT/UPDATE/DELETE 接受；外键、JSON 列和少量不变量在提交前检查，违反就整批回滚并列出原因。可写的是媒体身份与资料（media_entities、media_bindings、media_overrides、media_snapshots……）、danmaku_bindings、ui_shelves、ui_presentations；任务引擎、后续、会话、各类历史与审计、缓存和投影队列只读。
- **记录与通知**：每次提交写入 db_commits（SQL、参数、改动计数、前后镜像、origin、invocationId、actor），并在 activity 里留一条；发出 `media.assets.changed`（kind 为 metadata、artwork、danmaku 或 identity），刷新读这些行的界面、片库索引和封面缓存。直接写入不往 Classic 投影，不产生专用原语的回执和领域历史，不自动递增 media_entities.revision。
- **撤回**：`db.undo {commitId}` 恢复那次提交的前镜像。每一行当前内容必须仍等于那次提交的后镜像，否则整个撤回被拒绝并列出冲突的行；`dryRun:true` 只看不改。撤回本身也是一次提交，可再撤回。''',
  'danmaku': danmakuFamilyDescription + r'''- **弹幕**：
  - **轨道**：一条弹幕轨道属于某个文件或某一集，有它的来源平台（弹弹play、优酷、B 站、本地文件……）和该平台上的视频；同一平台的同一个视频只保留一条，再次交入就是刷新。
  - **用在哪里**：剧集的热度线和主视觉上飘的弹幕，都来自 NipaPlay 记下的轨道。用 `danmaku.*` 修改，用 `state.query` 的 `danmaku.bindings`、`danmaku.tracks` 读取。
  - **同名弹幕文件**：NipaPlay 索引本地视频时，在后台发现并读取旁边最匹配的 XML/JSON，记录路径、平台、视频号、条数与读取时间；内容留在原文件。文件变化会重读，消失或不可读会记为不可用。热度线、主视觉弹幕、`ui_facts` 每集覆盖和轨道查询读取同一份记录，Next 播放器加载这条轨道。Next 播放时自动取得的弹弹play 弹幕也会保存为轨道，下一次仍可读取和播放。
  - **其他平台的弹幕**：你取回来的文件只是中间产物。用 `danmaku.import` 交给 NipaPlay 时，弹幕内容会保存成 NipaPlay 数据目录 `next/danmaku/` 里的文件，数据库记录引用、条数、时间范围和来源，绑在那一集或那个文件上；交完以后，原文件就不再需要。导入内容不会按缓存空间回收；刷新或撤销轨道后，不再被引用的旧文件会清掉。要刷新，就重新取一次、再交一次。中间文件放在这个仓库的 `records/`（不进 git），不需要写进视频所在的目录，那里可能是只读的。
- **弹幕可以同时来自多个平台**：Next 内置的来源是经过 NipaPlay 网关的弹弹play；本地弹幕文件可以用 `danmaku.import` 交入（来源记为本地文件）；交入的弹幕可来自任意平台。同一平台的同一个视频只保留一条轨道，再次交入就是刷新。Next 没有内置优酷、B 站来源或应用内平台登录；已有的平台绑定、轨道与缓存仍可读取和播放。''',
  'subtitle':
      r'''Per-file subtitle facts persist independently from playback. Imports copy content into managed storage and batch errors retain index and recovery information. update edits imported language/title/source with expectedRevision; remove releases an imported association and retains its copy. reset_selection restores automatic selection; select null explicitly disables. Current internal playback and persistent selection use the same facts. copy_delete alone deletes unreferenced managed copies and returns NeedsDecision with an exact fingerprint. cues reads active external timed text with delay-aware current/context lines; embedded or bitmap limitations are explicit.
- **字幕**：按视频文件记录内嵌轨与匹配的外挂字幕，包含语言、标题、格式、来源、可用性和默认选择。内嵌语言来自容器声明，外挂语言来自文件名，未知记为 `und`；文件名语言不是内容核验，记录没有识别烧录在画面中的字幕。资源标题里的“内嵌”通常是压进画面的硬字幕，不会出现在轨道里；“内封”才是可选的字幕轨。单视频目录的 `Subs/`、`Subtitles/` 下语言字幕也会记录。`media.metadata.ui_facts` 给出每集的字幕语言、内嵌或外挂轨道及覆盖。`subtitle.tracks` 读取记录；`subtitle.import` 批量交入字幕文件及语言、来源，内容复制进 NipaPlay 数据目录，交完原文件不再需要，视频目录可以只读。Next 播放时按记录恢复字幕：显式选择和已有 Classic 选择优先，之后按应用语言设置决定简中或繁中优先，再选中文、英文；文本外挂先于内嵌轨。默认选择及依据也在记录中，`subtitle.select` 可记录选择或关闭字幕。`playback.load_subtitle` 仍可为当前播放临时加载。
- 无界面宿主支持字幕事实、同名外挂索引、导入和显式默认选择；配置 ffprobe 时记录内嵌轨道，未配置时内嵌状态为 unavailable。它不播放字幕、不读取 Classic 字幕偏好或观看历史；默认字幕由调用者显式选择。''',
  'download': 'preview 接受 magnet、本地 .torrent/file URI 和 HTTP(S) 种子地址；复用 add 的有界元数据获取、hash 校验和缓存，不创建任务或下载媒体字节。GUI delete 返回文件清单 NeedsDecision；delete.request 创建持久 disk_deletion 任务，等待当地用户确认并重检清单；用户同意、拒绝、关闭窗口或取消后，结果（状态、是否已删、deletedFiles）作为后续回到发起它的会话，忙时排队，你已登记 `followup.register when {jobId}` 的不再重复送。delete 加 fileIndices（仅限单个 jobId）只删下载里的这几个文件：清单和确认窗口只列它们；用户同意后先把它们从引擎的选择里去掉再删数据，其余文件继续下载或做种；回读里这些文件 included 为 false、actualSize 为 null，deletedFiles 列出已删的；确认前文件或选择变了就拒绝；只能是输出目录内的本地文件，不删目录。remove 保留文件。\n' +
      r'''- **下载器**：内置 BT 引擎支持 magnet、种子文件和 HTTP(S) 种子链接，使用 Classic 的下载目录设置；新任务可以指定目录和是否建立任务文件夹，重复添加同一哈希不会搬动已有文件。由你发起的下载，视频文件通过校验并登记入库时、任务完成或失败时，以及连续五分钟没有新字节时（`download.stalled`，带当时的已下字节和连接、已发现、失效 peer 数；每段停滞送一次，有了新字节才算过去），事实都会自动作为后续回到发起它的会话；取消的任务不再回报。会话忙时排队，回合结束后才送达。第一份文件事实和停滞立即入队，其余文件按十分钟合并，任务结束立即送回剩余事实；你已登记的同事件后续不会再多送一份。`download.read` 给出实际落盘路径、逐文件已校验字节、完整与可播状态、连接/已发现/待连接 peer、最近采样间的进展和所在盘可用字节。初始化时逐文件进度可能未知；公开引擎接口不提供做种数或来源持有的片段分布，返回 null。可以在添加时指定文件索引，也可以用 `download.select_files` 改变任务要下载的文件；不删除已下的数据（要删数据用 `download.delete` 的 fileIndices）。引擎没有普通文件优先级接口。
- **单个下载文件完成时**：引擎确认全部片段通过校验、NipaPlay 核对路径和大小后，本地视频就登记入库，无需等整个任务结束。开启自动扫描时，Classic 扫描器识别该文件；识别不了仍登记文件，不虚构作品。`download.file_completed` 事件的对象是 `任务号:文件索引`，包含文件校验事实和文件当时的 `media`（`fileId`、`workIds`、`episodes`；每个剧集带 `identitySources`，说明这条文件—剧集关联来自哪里：Classic 自动识别 `classic_match`、写入时带 `boundBy` 和 `origin` 的显式绑定，或 `local_catalog`；没有关联时 `episodes` 为空，`download.read` 里已登记文件的 `media` 是读取时的当前状态），可以触发同名 hook 或登记的后续。完整文件的持久校验记录允许访问该文件，不把下载目录或未完成的邻居当作片库根目录。整个任务完成仍有原来的回执和 `download.completed` 事件；回执保留 `fileIds` 和当时已有的 `workIds`，后来绑定的作品通过文件当前的剧集对应找到。扩展已完成的文件选择会返回新的观察任务，旧回执保留。
- **其他下载器**：qBittorrent、Aria2、seedbox 这类下载器，NipaPlay 不内置，也不代管。你用它们自己的命令行或接口驱动，可以在本机，也可以在别的设备上运行程序。文件落进 NipaPlay 能读到的位置之后，扫描、识别、入库、播放和本机下载的文件一样。从别的机器取回文件，用文件通道或用户已有的同步方式。''',
  'mesh':
      r'''`mesh.devices` 返回同账号设备、连通状态、各设备实际开放的能力和经过双向 TLS 认证的设备自我描述。自我描述包含平台、宿主角色、片库根目录、下载目录，以及宿主配置的存储路径与 Nipa 所在设备；路径属于描述它的那台设备。无界面节点提供片库、下载、任务、hooks 和定时程序，那里没有对话宿主。网络加入、签发者、监听策略和 Nipa 所在设备由宿主配置，Action 不能开放这些权限。`./nipa --device NAME list`、`describe ACTION`、`call ACTION ...` 和 `watch JOB_ID` 使用该设备的实时目录；名称也可换成设备 ID，重名不会任选一个。

从 Mac 对话通过组网发起的下载，在发起时固定返回设备与线程。每个已校验、已入库的视频文件和任务终态，由下载设备的持久后续队列交回那个会话；会话忙时排队。返回事实含来源设备，文件路径、`local` 和 `playable` 是来源设备上的事实。断线后保留待交付记录，重复交付使用同一回执。工作站 hooks 或定时程序调用 `agent.wake` 时，宿主配置的 Nipa 设备接收唤醒；不指定线程时回到那里持久主会话。工作站的 `followup.list` 中 `deliveryState: forwarded` 及 `remoteReceipt` 表示目标已经持久接收，实际对话状态保存在目标设备。
- 远程写与本机遵循同一契约；实时目录仅列目标宿主已注册能力，包括设置、账号、窗口、应用、诊断、备份、插件、对话、记忆与 Mesh 转发。app.capabilities 给出可用前置和远程范围。组网信任、签发者、监听策略、程序授权和秘密登记归目标宿主管理；删除和覆盖保留 NeedsDecision。没有播放器或 Classic 历史的宿主不会注册这些能力。
- **媒体库跨设备是一份合并库**：`library.merged` 包含本机和同账号设备上的全部作品。一部作品的剧集可能分散在几台设备上；重复文件优先本机。视频留在原设备，播放时直接读取原处，不复制整部文件。
- **设备离线时**：上次看到的作品、元数据和已缓存图片仍显示；设备 online=false，只在离线设备上的剧集 playable=false。恢复连接后目录和进度继续更新。
- **读取别的设备上的文件**：`media.library.readable` 批量解析剧集；`media.mesh_files.readable` 批量解析绝对 path 和 deviceId，不限已入库文件。远端文件返回当前调用节点的 127.0.0.1 HTTP Range 地址，可给播放器、ffprobe、ffmpeg；回环需绕开 HTTP_PROXY。设备之间的字节经过同账号双向 TLS，协调服务不转发视频。
- **写入别的设备上的文件**：`media.mesh_files.begin/chunk/finish` 提供文件暂存、分段写入和完成校验，cancel 丢弃未完成传输；省略 deviceId 操作本机。文件权限是目标节点进程的实际权限，父目录须存在。传输 ID 目前不跨节点进程重启。
- **删除和覆盖先问用户**：`media.mesh_files.delete` 批量预览，finish 遇到已有目标返回 NeedsDecision；这个 NeedsDecision 由调用者自己用 confirm 解决，NipaPlay 不会向用户显示任何确认，所以用户同意之前不要调 confirm；删除下载里的文件用 `download.delete`，它会在 NipaPlay 里问用户。目标自预览后变化会拒绝。加入 Mesh 是宿主同意同账号设备访问，没有额外共享开关。''',
  'program':
      r'''- `program.run` 是目标设备的后台命令或脚本任务，按普通用户权限在那台设备的 harness 工作目录运行。每台设备独立授权，默认关闭；只能由那台设备宿主在 `program.json` 打开并重启，Agent 的设置能力不能打开它。已认证的设备描述包含开关事实和工作目录。Windows 默认用 cmd，也支持 PowerShell；WSL、Linux、macOS 用 POSIX sh。
- 程序任务有标题、经脱敏的输出末尾、退出码和耗时，有超时，`task.cancel` 停止它的进程树。命令不在重启后自动重放。由会话发起的程序，终态回执会作为后续回到原设备、原仓库、原线程；忙时排队，`followup:false` 不自动回传。每次执行都进入目标设备的 activity，记录来源、设备和命令。输出文件属于目标设备，不自动复制回来。
- `nipa sync-repository` 把调用者选定的已提交 Git 引用及其可达历史作为 bundle 分块送到目标 harness 的 `records/mesh-bundles/`，校验 SHA-256，不自动 checkout、合并或覆盖目标仓库。未提交文件、Git 配置、连接凭据和进程环境不随 bundle 传输。仓库与历史里的秘密不属于可同步内容；Mac 模型配置与凭据留在 Mac。收到的 bundle 可由目标程序使用当地 Git 读取，仓库工具因而可在目标设备运行。''',
  'followup': r'''- 关闭对话不会中断 NipaPlay 里的任务。定时脚本只在 NipaPlay 运行且 Next 开启时执行。
- **hooks 和定时程序**：由 NipaPlay 在事件发生时或到点时运行，同样通过 `nipa` 工作。需要你判断时，用 `agent.wake` 叫醒你；只是记下发现，用 `activity.report`。
- 通过 Mesh 在会话中登记的 `followup.register` 也固定回到发起设备、仓库和线程，沿用持久票据与去重交付；显式线程与发起线程不一致会被拒绝。程序自动回传和同一事件的手动订阅共享事实去重。
- **耗时操作是 NipaPlay 的后台任务**：Agent 可以登记后续，让自己在任务结束时被唤醒。''',
  'agent':
      r'''- **子代理是后台的帮手**：Codex 原生子代理在同一个 harness 的独立线程里工作；用户在 NipaPlay 里看得到，能用 `task.cancel` 停止。你的回合结束后它才完成的，结果作为持久后续回到这个会话，忙时排队；你已用 `wait` 取到的结果不会重复交回。
- **宿主派发**：`agent.dispatch` 接收标题、说明及可选的返回线程，脚本或 hooks 在没有父 Agent 回合时也能启动独立回合，默认返回主会话。宿主派发最多同时运行两个，更多的排队；`agent.dispatch.report` 是宿主派发回合的一句话进度接口。原生子代理的并发由 Codex 管理。''',
  'settings':
      r'''- **设置的每次修改都记录来源**：谁改的、何时、为什么。用户说"以后都这样"时，就是一条持久偏好，修改时写明理由。''',
  'history': r'''观看进度由播放器写入；mark_watched_batch 可以标记看过。state.query history.entries 提供稳定 entryId、fileId、canonical workId/libraryEpisodeId 和本机缓存 poster/still；旧 episodeId 仍是 Classic 数字编号。无绑定/无缓存返回 null，不联网取图。历史按 lastWatchedAt 降序及 entryId 排序，游标存排序值，删掉已读条目或最后锚点仍能继续；这是实时观测，条目的观看时间变化仍可能重排。remove 支持 entryIds/paths/animeIds 的并集，包括 locator=null 的条目，只删除记录，保留视频。''',
  'task': 'UiTask.type 带 executor 类型，例如 download、media.scan_classic；kind 仍区分 background/helper。任务关联的作品不存在时仍呈现任务，不假造作品或图片。\n' +
      r'''后台任务共用持久快照、来源和回执。control 批量暂停/恢复/取消，逐项给支持与受理事实；paused 可能仍在排空当前文件。get/wait 核对完成。resources 读取实际容量；tasks.*Concurrency 设置只改变新工作派发。不能安全重放的执行器拒绝暂停。终态回执不改写，取消不删除文件。
- `describe ACTION` 给出输入与输出契约，`call task.list` 可筛选任务，`call task.get '{"jobId":"..."}'` 给出单个任务详情。查询默认每页 50 行，可用 `limit`、`select` 与返回的 `nextCursor` 控制读取范围。
- 返回任务只代表已受理。只有状态为 `succeeded`、并且回执经过验证，才算完成。`watch` 是有界的等待，不是后台守护。''',
  'state':
      r'''只读视图读已有索引，不重新探测视频。查询默认每页 50 行，支持 limit、select 和 nextCursor。用 ./nipa call state.describe '{"view":"视图名"}' 读取字段、单位、关系与查询约束；不指定 view 列出全部视图。''',
  'app':
      appFamilyDescription + r'''update.check 立即复用 Classic 发布检查；失败时 hasUpdate/latestVersion 为 null，错误与检查时间保留。update.status 读取上次检查；update.open 打开已核对公开发布页。没有应用内更新安装、自动重启或下载能力。instance 读取当前进程事实。
这台机器上可能装着多个 NipaPlay（正式版、开发构建、实验副本）；按应用名或 bundle id 打开的未必是 `nipa` 连接的那个实例。`nipa status` 的实例事实和 `ui.*` 的界面操作、截图来自当前连接的实例。
- `./nipa status` 的 `harnessSeed` 给出种子 `path`、当前 `head` 和已抓取的 `trackingHead`。`trackingBehindSeed=true` 表示应抓取更新；`missing_remote` 表示尚未配置远端，`not_fetched` 表示尚未抓取，`different_remote` 表示远端指向另一处，未知状态不等于已同步。此检查只读，不执行 fetch 或合并；`current` 只说明远端跟踪引用最新，不表示你已合并。''',
  'accounts':
      r'''- **需要登录的平台**：用户的浏览器里通常已经登录，直接使用这个登录状态；浏览器也没登录时，打开该平台的登录页，请用户自己登录，然后继续。
- 由你发起、要用户在 NipaPlay 窗口里登录的 `accounts.login`，结束时（登录成功、失败、关窗或取消）作为后续回到发起它的会话，忙时排队；事实只有平台、方式、状态和是否已登录，没有账号名和密码。你已对该 jobId 登记 `followup.register` 的不再重复送。用户在对话里给出秘密、由你直接传入的登录不回报。''',
  'playback':
      r'''open/pause/seek/navigation accept commands; snapshots observe asynchronously. State reports sessionId, readiness, buffering, buffered position, error/recovery and actual supported controls. External unknown position/duration/pause/rate remain null. wait is bounded and detects a changed session; retry explicitly reloads the source through Classic and may preserve position. chapters exposes container markers and detected skip segments; navigate uses chapter, frame or active skip semantics. Backward frame stepping may be approximate. playlist reports the actual detail source list, without authenticated stream URLs.
播放器共用 Classic 和 Next；播放本地或媒体服务器上的文件，叠加字幕和弹幕。临时加载字幕用 playback.load_subtitle；持久事实用 subtitle。''',
  'discover': r'''弹弹play 每日放送与推荐。''',
  'plugins': r'''应用插件。''',
  'media.sources': r'''SMB、WebDAV、Jellyfin、Emby 等远程来源。
- search 结果的 poster 是已有本机缓存路径；没有缓存为 null，不逐项取图。workTitle 给已绑定作品名。artwork(sourceId,itemId) 懒加载服务器海报，复用 X48 图片供应者，只返回本机路径，不返回鉴权 URL。
- `media.sources.search {query,sourceIds?,limit?}` 是只读搜索：Jellyfin/Emby 用服务器 SearchTerm 和有界分页，SMB/WebDAV 只查已有文件索引，不枚举目录、不登记新文件、不写发现记录。省略 sourceIds 搜所有支持的已配置来源；limit 限制每个来源（默认 12）。返回 sources[]，每个来源单独给出 entries、total 或 error。离线或登录失败如实返回，其他来源保留结果；索引来源的 unverified 是未知连通状态，不能当成在线。
- 结果有 sourceId、itemId、标题、可播放事实；已绑定条目带 Next workId/episodeId，服务器原样条目另有 sourceWorkId/sourceEpisodeId。作品 ID 用 ui.open，来源条目用 media.sources.play {sourceId,itemId}。来源分组在界面上可逐个 sourceIds 请求，分别显示结果与错误。
- browse/sync 是发现与写索引入口；不要用它们实现每次输入的搜索。
- WebDAV、SMB 各有内网和公网两个地址，至少一个非空，空表示未配置。WebDAV 是 url（内网）和 wanUrl（公网）；SMB 是 host/port 和 wanHost/wanPort（同时以 smb:// 的 url、wanUrl 给出）。两个都有时 Classic 优先内网，address 是当前正在使用的那个，可能无需编辑就在内网与公网间变化；Jellyfin、Emby、NipaPlay、Dandanplay 只有 url，address 与它相同。
- put/update 接受这些字段；省略的字段（包括另一套地址）保持不变，空字符串清除该地址，但至少保留一个。地址规则不变：WebDAV 只允许 HTTP(S)，不带凭据、query、fragment；SMB 主机不带凭据或路径。
- 已保存的密码属于保存时的那组地址：删除某个地址或在内网与公网间切换仍可使用，新增或更换为不同的地址、或换账号，需要重新 login。''',
  'media.library': r'''`media.library.search_merged {query,limit?,episodeLimit?}` 只读搜索 X48 本机与认证 Mesh 合并目录的标题、原名、已有别名、年份及剧集标题；空白分词为 AND，忽略大小写，按字面子串匹配。返回 works[]、episodes[{work,episode}]、workTotal/episodeTotal，默认每组最多 12。返回 workId/episodeId 可以直接用于 Next 作品页和 ui.open；海报是本机路径，设备与 playable 是目录最近观察。索引每 5 秒随目录更新，media.library.refresh 可立即刷新；首次搜索建立索引，其后不逐次读全库。离线 Mesh 保留事实并标为不可播放。
原 media.library.search 保留 Classic 观看记录语义与 animeId。不要将这个 animeId 当成合并 workId。''',
  'media.metadata': r'''`media.metadata.search/search_batch` 读取在线候选，每个结果另带 workId。它是本机与认证 Mesh 合并片库已接受 exact/contains 作品或发行身份的 Next workId；没有对应身份就是 null，不按同名推断。首次读取可能准备可重建的目录与图片缓存，不接受候选或写绑定。资料、身份与图片能力的其余约定见 nipa describe media。''',
  'media.mesh_files':
      r'''`mesh.devices` 返回同账号设备、连通状态、各设备实际开放的能力和经过双向 TLS 认证的设备自我描述。自我描述包含平台、宿主角色、片库根目录、下载目录，以及宿主配置的存储路径与 Nipa 所在设备；路径属于描述它的那台设备。无界面节点提供片库、下载、任务、hooks 和定时程序，那里没有对话宿主。网络加入、签发者、监听策略和 Nipa 所在设备由宿主配置，Action 不能开放这些权限。`./nipa --device NAME list`、`describe ACTION`、`call ACTION ...` 和 `watch JOB_ID` 使用该设备的实时目录；名称也可换成设备 ID，重名不会任选一个。

从 Mac 对话通过组网发起的下载，在发起时固定返回设备与线程。每个已校验、已入库的视频文件和任务终态，由下载设备的持久后续队列交回那个会话；会话忙时排队。返回事实含来源设备，文件路径、`local` 和 `playable` 是来源设备上的事实。断线后保留待交付记录，重复交付使用同一回执。工作站 hooks 或定时程序调用 `agent.wake` 时，宿主配置的 Nipa 设备接收唤醒；不指定线程时回到那里持久主会话。工作站的 `followup.list` 中 `deliveryState: forwarded` 及 `remoteReceipt` 表示目标已经持久接收，实际对话状态保存在目标设备。
- 远程写与本机遵循同一契约；实时目录仅列目标宿主已注册能力，包括设置、账号、窗口、应用、诊断、备份、插件、对话、记忆与 Mesh 转发。app.capabilities 给出可用前置和远程范围。组网信任、签发者、监听策略、程序授权和秘密登记归目标宿主管理；删除和覆盖保留 NeedsDecision。没有播放器或 Classic 历史的宿主不会注册这些能力。
- **媒体库跨设备是一份合并库**：`library.merged` 包含本机和同账号设备上的全部作品。一部作品的剧集可能分散在几台设备上；重复文件优先本机。视频留在原设备，播放时直接读取原处，不复制整部文件。
- **设备离线时**：上次看到的作品、元数据和已缓存图片仍显示；设备 online=false，只在离线设备上的剧集 playable=false。恢复连接后目录和进度继续更新。
- **读取别的设备上的文件**：`media.library.readable` 批量解析剧集；`media.mesh_files.readable` 批量解析绝对 path 和 deviceId，不限已入库文件。远端文件返回当前调用节点的 127.0.0.1 HTTP Range 地址，可给播放器、ffprobe、ffmpeg；回环需绕开 HTTP_PROXY。设备之间的字节经过同账号双向 TLS，协调服务不转发视频。
- **写入别的设备上的文件**：`media.mesh_files.begin/chunk/finish` 提供文件暂存、分段写入和完成校验，cancel 丢弃未完成传输；省略 deviceId 操作本机。文件权限是目标节点进程的实际权限，父目录须存在。传输 ID 目前不跨节点进程重启。
- **删除和覆盖先问用户**：`media.mesh_files.delete` 批量预览，finish 遇到已有目标返回 NeedsDecision；这个 NeedsDecision 由调用者自己用 confirm 解决，NipaPlay 不会向用户显示任何确认，所以用户同意之前不要调 confirm；删除下载里的文件用 `download.delete`，它会在 NipaPlay 里问用户。目标自预览后变化会拒绝。加入 Mesh 是宿主同意同账号设备访问，没有额外共享开关。''',
};
