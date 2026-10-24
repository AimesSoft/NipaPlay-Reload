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
    'app.runtime reads the non-secret facts of remote access, the mesh, the model and the runtime; app.restart relaunches the application on macOS. '
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
  'diagnostics': r'''status 给健康、版本、资源、日志和迁移观察；file_logs 用受限 fileId 与行游标读取脱敏摘录。recover 只执行显式的日志重启、投影核对、索引器检查，不自动修改用户数据或登录。日志公开发布必须有明确目标与内容；本族不上传。
- status 的 player.details 与 playback.info 来自同一次内核查询：videoCodec、audioCodec、videoWidth/Height、fps、hwdec（正在用的硬解方式，软解为 no，未知为 null）、decoder、hardwareDecoding、droppedFrames、buffering。
- errors 读 Next 开启期间本进程的未捕获错误（Flutter 框架错误、未捕获的异步错误、isolate 错误），同一错误再次出现只累计次数；以及上一次开着 Next、却没有经过 NipaPlay 退出流程就结束的运行（unclean_exit），带那次最后记下的播放。原生崩溃没有 Dart 堆栈，只表现为 unclean_exit。
- player_log 读播放内核交给应用的最近若干行：Media Kit 是 mpv 日志消息（默认只有 error 级），MDK 是媒体事件与状态以及 MDK 自己的日志（全进程一份，不属于某个播放器），Erika 是播放错误、解码器切换、音频输出变化与视频参数，再加上 Erika 自己的日志环（全进程一份：source=engine 是 Erika 的运行诊断，source=ffmpeg 是 Erika 内 FFmpeg 的警告与错误，已由 Erika 脱敏），在读取时与 Erika 播放器关闭前抄进来。player_log_file 让 Media Kit 把 mpv 完整日志写进数据目录的文件，再用 player_log 的 file=true 分页读。
- MDK 的日志处理器全进程只有一个：Next 开启时接过来，每一行原样交给原来的处理器，Next 关闭时交还；设了 MDK_LOG 时 MDK 自己写 stderr，Next 不接，player_log 的 mdkLog 说明这一点。
- errors 另给 thisRun（本进程记下的不同错误数与出现次数）和 uncleanExits（总数、还没被 errors 返回过的条数、最近一次的时间）；返回过的异常退出算已读，跨重启保留；summaryOnly 只看计数，不改变已读。
- 这些记录只在 Next 开启时进行；原有的错误处理、日志级别与界面日志设置不变。''',
  'cache': r'''plan(kinds,maxBytes) 返回实际回收对象、估计字节和保留原因，prune(planId) 重新核对引用与变化并返回逐项结果。仅可重取缓存回收无 NeedsDecision。Next 弹幕池复用引用感知回收；正在获取时推迟。计划是当前进程的预览，不允许夹带任意路径。''',
  'storage': r'''status 给目录真实用量和卷可用空间。父目录包含子目录，不相加。watch 显式订阅空间阈值、unwatch 取消；仅当前进程有效，转换发 storage.space_changed。可重取缓存用 cache.plan/prune；字幕、导入弹幕、用户下载与无法证明可重取的图片保留。磁盘用户文件删除/覆盖沿用 media.mesh_files 的 NeedsDecision。 `state.query storage.volumes`、`storage.directories` 以行给出同样的事实，可过滤。''',
  'network': r'''status 给路由、代理、故障转移、媒体服务器连接 UA 及来源最近错误/上次成功。check 显式检查已登记来源或官方网关 healthz，不更换路由或登录。观测历史只覆盖当前进程，未观察值不宣称可达。第三方凭据去向仍由用户设置；秘密不进输出。 `state.query network.routes`、`network.observations` 以行给出同样的事实；来源逐地址的连通性在 `media.sources` 族的 `addresses[]` 与 `media.source_addresses` 视图。''',
  'events': r'''身体变化共用 hook 与 followup 的持久事实日志。describe 列出事件；wait(afterCursor) 有界等待和分页，游标跨重启；只重读事实，不重跑脚本。followup.register 订阅下一次事件；hook 名称就是事件名。播放位置不逐帧发事件；seek_requested 是受理意图，settlement 必须另核对。playback.failed 的 facts 是一条播放失败记录，与 playback.failures 的条目相同（stage、category、内核原文等）。''',
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
- **对话**：首页展开的对话页，和其他页面的侧栏，是同一个会话。你用 `ui.present` 摆的卡片出现在回复下方，状态实时更新，不必为更新状态再摆一次。一个回合的卡片都显示在该回合回答之后，按摆出的顺序；同一回合里与已摆出的卡片相同的（同类且指向同一对象，或内容完全相同）只显示一次，结果里的 `cards[].alreadyShown` 会说明。从后台帮手调用时，卡片进入帮手自己的对话（结果里 `conversation` 为 `subagent`）；帮手的结果交回主对话时，它在那之前摆出的卡片随结果一起复制到主对话，交回之后再摆的只留在帮手自己的对话里，打开它才看得到。卡片有：作品（workId 或 ref）、剧集（episodeId）、候选作品（items，每项 workId 或 ref）、任务（taskId）、准备进度（title 与 steps，每步引用任务、实体或后续）、选项（`choices`：可选的 question，2–6 个 options，每项 label、可选 detail 和 recommended）。用户点选项卡片中的一项，等于在对话里说出它的 label。
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
- **身份**：作品与弹弹play、Bangumi、TMDB 或其他 HTTPS 来源的绑定。本地作品也可用 media.entities.put_batch 建立，不要求外部身份。用 `bind_batch` 和 `unbind_batch` 修改。文件可以同时有 Classic 自动识别的剧集关联（`source=classic_match`，`boundBy` 为 null）和显式绑定的关联，两者指向不同的集时都保留，`identity.get.conflicts` 列出差异。`unbind_batch` 省略 `bindingIds` 只撤销显式绑定；`classic_match` 绑定可以点名撤销，文件上的和它所建的剧集、版本、作品上的都可以（文件的绑定 ID 在下载事件和 `download.read` 的 `identitySources` 里，其余在 `identity.get` 里）。撤销只改 Next，Classic 的观看记录（进度、animeId/episodeId）和界面不变，不向 Classic 写任何东西。撤销文件上的：只由它支撑的文件—剧集关联移除，那次 Classic 观察改记为 `classic_match_revoked`，之后的同步不会再挂回，Classic 对该文件记下不同的识别才导入新的；结果的 `remainingClassicBindings` 列出失去该文件的剧集及其版本、作品上仍已接受的 `classic_match` 绑定。撤销哪一层，影响片库里哪一层的显示：片库不显示既无已接受绑定、其下也无文件的作品，所以只撤销文件时作品仍在，点名作品的 `classic_match` 绑定后作品才离开片库。`restore_classic_batch` 按点名恢复；文件的绑定只在它仍是 Classic 的当前观察时恢复。没有点名时，`classic_match` 仍跟随 Classic 的匹配记录：Classic 里该路径的观看记录被删除（`history.remove`，观看进度随记录一起删除）或匹配改变后，下一次同步撤销它的文件绑定，并移除不再有绑定支撑的文件—剧集关联；显式绑定及其关联不受影响。
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
- **一次交一部作品的资料**：`media.metadata.put` 一次提交一部片库作品的标题、原名、简介、年份、类型、海报、背景、Logo，以及按 `episodeId` 或（`season`，`number`）指定的各集标题、简介、播出日期、时长、截图；同时给出 `episodeId` 与 `season`/`number` 时，写入的就是该集的季号、集号（只改 Next 目录里的属性，不碰 Classic），回执 `numbering` 列出 before/after，同一 release 下季号加集号不能相同，否则整批拒绝；字段都可省略，省略的不动。图片先取到并能解码才提交，任何一项失败则整批不写。不存在的集按本地目录规则建出来（可以没有文件）。资料来源 `source` 与 actor、origin、invocationId 一并记录；写入的是和 `override`、`artwork.set` 同一份持久覆盖，刷新来源快照后仍在，并优先于所有来源快照。同一 `requestId` 重放结果不变。
- **剧集列表**：作品下各季的集，只包含绑定过的集。
- **Classic 同步**：保留识别标题与已有的详情缓存，包括标题语言、简介、海报、背景、类型和集数。未缓存的资料不会自动补抓；没有声明语言的识别标题仍是 `und`。Next 的显式覆盖优先，不修改 Classic 的详情缓存。
- **新进片库的文件**：文件进入片库，不论是你下载的、用户添加的文件夹、Classic 扫描到的，还是媒体来源同步进来的，NipaPlay 都会把这批文件的事实（路径、`fileId`、怎么进来的、剧集关联与 `identitySources`、作品有没有 TMDB 身份）送给你，见 `followup` 族。TMDB 身份和资料由你补，用户不必开口。
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
- **专用原语之外，也可以直接读写库**：`db.describe` 列出 next.db 的表、含义、可写范围和跨表规则（classic_match 如何随同步重新导入、覆盖优先于快照、图片覆盖存在哪）；`db.query` 用 SQL 只读查询；`db.write` 先预演再提交，`db.undo` 撤回。专用原语仍是便捷入口，已有身份、资料、绑定的契约不变；直接写入不往 Classic 投影。
- **从视频取画面**：`media.frames`：从视频文件的指定时间取画面，每张写成本机临时的 JPEG（默认）或 PNG 文件，并返回路径、宽高和画面实际所在的时间。用途举例：看某一集几个时间点的样子，把两集同一段落的画面放在一起比对，给用户看他说的那一刻。媒体用 path（本机绝对路径、file:// 或 media.library.readable / media.mesh_files.readable 给出的 http(s) 地址）或已记录剧集的 animeId + episodeId 指定。时间用 atMs（毫秒数组）或 range {startMs,endMs,everyMs}（含 endMs，everyMs 不小于 100），二者给一个。单位全是毫秒。每次最多 60 张，超出整个调用被拒绝，一张也不取。尺寸用 width 或 maxEdge（最长边，默认 640，最大 3840），保持比例，不放大到超过视频本身。timeoutMs 限制整次调用（默认 60 秒，最大 300 秒）。取不到的帧在 frames 里带 error.code（beyond_duration、decode_failed、timeout、skipped_after_timeout）而不影响其他帧；durationMs 与视频尺寸是文件的事实，未知时为 null。画面来自独立的解码器，不暂停、不跳转、不重开正在播放的视频，调用结束前释放：有 Erika 时用 Erika 自己的单帧导出（独立的解复用与软解，PNG 由 Erika 直接编码），不能用时退回 MDK；engine 写实际用的引擎，退回时 engineFallback 给出 Erika 没用上的原因。文件是临时的，一天后清理。这个能力只给画面，画面里是什么由你判断。要自己看画面，用 `read_image` 读这些文件；换了模型或地址后第一次启动你的运行器时，NipaPlay 会给模型看一张纯红小图并问颜色，答得出才声明它收图，结果记在 Next 数据目录的 `dsh/model-input.json`，之后沿用；那次没得到回答就下次启动再问，答不出时 `read_image` 会报模型不收图，这时可以换能看图的模型，或者用别的办法。''',
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
- **字幕**：按视频文件记录内嵌轨与匹配的外挂字幕，包含语言、标题、格式、来源、可用性和默认选择。内嵌语言来自容器声明，外挂语言来自文件名，未知记为 `und`；文件名语言不是内容核验，记录没有识别烧录在画面中的字幕。资源标题里的“内嵌”通常是压进画面的硬字幕，不会出现在轨道里；“内封”才是可选的字幕轨。单视频目录的 `Subs/`、`Subtitles/` 下语言字幕也会记录。`media.metadata.ui_facts` 给出每集的字幕语言、内嵌或外挂轨道及覆盖。`subtitle.tracks` 读取记录；`subtitle.import` 批量交入字幕文件及语言、来源，内容复制进 NipaPlay 数据目录，交完原文件不再需要，视频目录可以只读。Next 播放时按记录恢复字幕：显式选择和已有 Classic 选择优先，之后按应用语言设置决定简中或繁中优先，再选中文、英文；文本外挂先于内嵌轨。默认选择及依据也在记录中，`subtitle.select` 可记录选择或关闭字幕。`playback.select_track` 和 `playback.load_subtitle` 带 `remember`（布尔，默认 false）：false 只对当前播放生效，不写字幕记录，也不写 Classic 共用的外挂字幕列表；true 把这次选择写进字幕记录（外挂文件同时进入共用的外挂字幕列表），下次打开同一视频照用；返回值的 `remembered` 是这次是否写入了记录。用户在播放器界面上选的字幕总是记住。`playback.tracks` 的 `subtitles.selected` 是当前正在用的，`subtitles.remembered` 是字幕记录里为这个视频保存的（null 表示没有保存），`rememberedIsSelected` 说明两者是否一致；每条字幕轨道另有 `remembered` 标记。
- 无界面宿主支持字幕事实、同名外挂索引、导入和显式默认选择；配置 ffprobe 时记录内嵌轨道，未配置时内嵌状态为 unavailable。它不播放字幕、不读取 Classic 字幕偏好或观看历史；默认字幕由调用者显式选择。''',
  'download': 'preview 接受 magnet、本地 .torrent/file URI 和 HTTP(S) 种子地址；复用 add 的有界元数据获取、hash 校验和缓存，不创建任务或下载媒体字节。GUI delete 返回文件清单 NeedsDecision；delete.request 创建持久 disk_deletion 任务，等待当地用户确认并重检清单；用户同意、拒绝、关闭窗口或取消后，结果（状态、是否已删、deletedFiles）作为后续回到发起它的会话，忙时排队，你已登记 `followup.register when {jobId}` 的不再重复送。delete 加 fileIndices（仅限单个 jobId）只删下载里的这几个文件：清单和确认窗口只列它们；用户同意后先把它们从引擎的选择里去掉再删数据，其余文件继续下载或做种；回读里这些文件 included 为 false、actualSize 为 null，deletedFiles 列出已删的；确认前文件或选择变了就拒绝；只能是输出目录内的本地文件，不删目录。remove 保留文件。\n' +
      r'''- **下载器**：内置 BT 引擎支持 magnet、种子文件和 HTTP(S) 种子链接，使用 Classic 的下载目录设置；新任务可以指定目录和是否建立任务文件夹，重复添加同一哈希不会搬动已有文件。由你发起的下载，视频文件通过校验并登记入库时、任务完成或失败时，以及连续五分钟没有新字节时（`download.stalled`，带当时的已下字节和连接、已发现、失效 peer 数；拿不到元数据也算，那时带 `metadata: false` 和最近一次错误，已下字节为 0，未知的总字节与 peer 数为 null，拿到元数据这段就过去；每段停滞送一次，有了新字节才算过去），事实都会自动作为后续回到发起它的会话；取消的任务不再回报。会话忙时排队，回合结束后才送达。第一份文件事实和停滞立即入队，其余文件按十分钟合并，任务结束立即送回剩余事实；你已登记的同事件后续不会再多送一份。停滞也是公开事件（对象是 `stalled:任务号:序号`），不论下载由谁发起，都可以写 `hooks/download.stalled` 或用 `followup.register` 的 `when: {event: 'download.stalled', objectId: 任务号}` 等它的下一次停滞（省略 objectId 等任意下载）。`download.read` 给出实际落盘路径、逐文件已校验字节、完整与可播状态、连接/已发现/待连接 peer、最近采样间的进展和所在盘可用字节。初始化时逐文件进度可能未知；公开引擎接口不提供做种数或来源持有的片段分布，返回 null。可以在添加时指定文件索引，也可以用 `download.select_files` 改变任务要下载的文件；不删除已下的数据（要删数据用 `download.delete` 的 fileIndices）。引擎没有普通文件优先级接口。
- **单个下载文件完成时**：引擎确认全部片段通过校验、NipaPlay 核对路径和大小后，本地视频就登记入库，无需等整个任务结束。开启自动扫描时，Classic 扫描器识别该文件；识别不了仍登记文件，不虚构作品。`download.file_completed` 事件的对象是 `任务号:文件索引`，包含文件校验事实和文件当时的 `media`（`fileId`、`workIds`、`episodes`；每个剧集带 `identitySources`，说明这条文件—剧集关联来自哪里：Classic 自动识别 `classic_match`、写入时带 `boundBy` 和 `origin` 的显式绑定，或 `local_catalog`；没有关联时 `episodes` 为空，`download.read` 里已登记文件的 `media` 是读取时的当前状态），可以触发同名 hook 或登记的后续。完整文件的持久校验记录允许访问该文件，不把下载目录或未完成的邻居当作片库根目录。整个任务完成仍有原来的回执和 `download.completed` 事件；回执保留 `fileIds` 和当时已有的 `workIds`，后来绑定的作品通过文件当前的剧集对应找到。扩展已完成的文件选择会返回新的观察任务，旧回执保留。
- **HTTP 下载**：`download.add` 带 `backend: {kind: "http"}` 时，source 是一个 http:// 或 https:// 文件地址（其他协议拒绝），NipaPlay 用自己的 HTTP 下载器把它当普通文件下载，走同样的任务、停滞（`download.stalled`）、`download.file_completed` 和入库流程；不解压、不从文件名猜内容，zip 之类非视频文件照实报告 `not_video`。文件放在 downloadDirectory 或下载目录设置里（createFolderForTask 为 true 才建以文件名命名的文件夹），文件名是服务器给的（Content-Disposition 的 filename，否则最终地址路径的最后一段），已有同名文件不覆盖，新文件加 " (1)"、" (2)"；数据先写 `文件名.nipaplay-part`，完整且校验通过才改名，片库不会看到半个文件。暂停、继续、取消和重启后用 Range 续传，服务器不支持时从头下；可选 `connections`（整数 1–8，默认 1）把文件分成这么多段、用各自的连接并行下载到同一个 `.nipaplay-part`，只在服务器给了 `Accept-Ranges: bytes` 和 Content-Length 时生效，否则退回单连接；`health.http.connections` 如实记 `{requested, used, reason}`（used 等于 requested 时 reason 为 null，否则是 `no_range`、`unknown_length`、`too_small` 或 `range_ignored`），多连接时另有每段的 start、end、completedBytes。已下字节是各段之和，所有段都没有新字节才算停滞，某一段出错只重试那一段，续传时每段从自己已有的字节继续；`health.http.resume` 记 `confirmed`、`ignored`、`rejected` 或 `untested`。连接失败和 5xx/408/429 会重试且不算进展，所以照常触发五分钟停滞；其他 4xx 直接令任务失败。可选 `checksum: {algorithm: md5|sha1|sha256, value}` 在最后一个字节后核对，不符则任务失败，失败和回执里都有期望值与实际值，数据留在 `.nipaplay-part`；不给 checksum 时回执的 `checksum` 记录算出的 sha256，`matched` 为 null（没有核对）。没有 peer，`health` 里的 peer 计数为 null。任务的 `infoHash` 是 `http-` 加规范化地址（去掉 # 片段）的 SHA-1，与种子 infoHash 不会相同。`download.preview` 带同样的 backend 时只发 HEAD（被拒绝才发 `Range: bytes=0-0` 的 GET 并在响应头后关闭），返回最终地址、状态码、Content-Length、Content-Type、是否支持 Range、服务器给的文件名、Last-Modified 和 ETag，不下载内容，不创建任务。
- **下载引擎汇总**：`state.query downloads.engine` 每个后端（builtin、http）一行：是否启用（`download.enabled`）、运行/排队/暂停/等待/已结束的任务数、后端报告的总下载与上传速率、会话限速读回值（0 为不限；读不到为 null）。下载关闭时不询问后端，速率为 null；后端出错时带 `error` 码。http 后端没有限速控制（`limitsSupported` 为 false）。
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
- **hooks 和定时程序**：由 NipaPlay 在事件发生时或到点时运行，同样通过 `nipa` 工作。需要你判断时，用 `agent.wake` 叫醒你；只是记下发现，用 `activity.report`。`state.query harness.hooks` 给每个事件对应的程序（ready；存在但没有执行位因而被忽略的是 not_executable；没有是 absent；`hooks/` 里不对应任何事件的文件是 unrecognized）和最近一次运行的时间、状态、退出码、耗时。`harness.schedules` 给 `schedules.json` 的每一项：是否有效及原因、程序是否可执行、下次到点时间、最近一次运行，以及没有启动的次数——`skippedLate` 是时钟晚了两秒以上被丢弃（不补发）的次数，`skippedWhileRunning` 是上一次还没结束而没启动的次数。任何一项无效，文件里的定时程序都不运行。下次到点时间与跳过次数只覆盖本进程；运行记录只覆盖任务列表仍保留的部分。
- 通过 Mesh 在会话中登记的 `followup.register` 也固定回到发起设备、仓库和线程，沿用持久票据与去重交付；显式线程与发起线程不一致会被拒绝。程序自动回传和同一事件的手动订阅共享事实去重。
- **耗时操作是 NipaPlay 的后台任务**：Agent 可以登记后续，让自己在任务结束时被唤醒。
- **新进片库的文件**：文件进入片库时，NipaPlay 把事实合成一批送来，不按内容挑选，也不丢文件。开关是设置 `library.notifyNipaEnabled`（默认开；关闭后不再发送，关闭期间进来的文件之后不补发）。
  - 不是你的操作带进来的（用户添加的文件夹、Classic 扫描、媒体来源同步）：每一批开一个宿主派发的后台回合（同 `agent.dispatch`，但不返回任何会话），说明里是这批文件的事实；不进主会话，结束记入动态。同时只有一个这样的回合；它还在运行时进来的文件排进下一批。
  - 你的调用带进来的（`media.library.roots.*`、导入、扫描等，任务沿用发起它的来源）：这一批作为后续回到发起的会话，忙时排队，不另开回合。
  - 下载导入的文件由下载回报送出，同一个 fileId 不在这里重复送。重启后已送过的文件不会再送。
  - 一批在文件停止进来 30 秒后送出，从第一个文件起最迟 5 分钟，扫描结束时立即送出，一批最多 100 个文件，多出的进下一批。
  - 每个文件的事实：`path`、`fileId`、`via`（怎么进来的：`local_scan` 本地文件夹扫描、`classic_history` Classic 扫描或观看记录、`media_source` 媒体来源同步、`download_import` 下载导入、`metadata_put`、`path` 某个操作点名了这个路径）、`enteredAt`、`source`（位置来源；媒体来源条目另有 `mediaSource` 的 `sourceId`、`type`、`itemId`、`name`）、`workIds`、`works[].identities.tmdb`（作品有没有 TMDB 身份，与 `media.metadata.ui_facts` 相同的判断）、`episodes[]`（`episodeId`、`workId`、`facts`、`identitySources`）。没有剧集关联时 `episodes` 为空。''',
  'agent':
      r'''- **子代理（subagent）**：运行你的 agent 程序原生的子代理，在同一个 harness 的独立会话里工作；用户在 NipaPlay 里看到它是一项后台任务，能用 `task.cancel` 停止。它结束时的回复回到派它的会话：你还在回合里就作为下一步的输入，回合已结束就开一个新回合；同一个结果不会交回两次。
- **宿主派发**：`agent.dispatch` 接收标题、说明及可选的返回线程，脚本或 hooks 在没有父 Agent 回合时也能启动独立回合，默认返回主会话。NipaPlay 自己也用宿主派发处理新进片库的文件，那样的回合不返回任何会话，结束只记入动态。宿主派发最多同时运行两个，更多的排队；`agent.dispatch.report` 是宿主派发回合的一句话进度接口。原生子代理的并发由运行它的 agent 程序管理。''',
  'settings':
      r'''- **设置的每次修改都记录来源**：谁改的、何时、为什么。用户说"以后都这样"时，就是一条持久偏好，修改时写明理由。
- **存储值与生效值**：`settings.get`、`settings.set` 和 `settings.describe` 的每一项并列返回 `value`（存储值）和 `effective`（运行中实际在用的值），以及 `effectiveState`、`effectiveSource`、`effectiveReason`、`effectiveDetail`。`effectiveState` 为 `same`（两者相同）、`differs`（不同，原因在 `effectiveReason`：`restart_required` 需重启、`reload_required` 下次打开媒体才用（播放器内核、HTTP 代理、macOS 原生视频、Erika Android 输出模式：没有打开的媒体时 settings.set 之后播放器立刻按存储值重建；正在看的媒体不受打扰，下一个媒体打开后在按存储值新建的播放器上重开一次，重建后恢复为 `same`）、`runtime_adjusted` 播放器按当前状态调整了值、`speed_boost_active` 长按加速中）、`inactive`（存储值没有在用，`effective` 为 null；`overridden` 被另一项设置覆盖、`inactive_dependency` 依赖的设置关着、`kernel_unsupported` 当前内核不支持，`effectiveDetail` 点名那一项）、`unknown`（取不到运行值，`effective` 为 null；`applies_at_next_open`、`loaded_when_page_created`、`player_not_attached`、`no_runtime_probe`、`probe_failed`）。`effectiveSource` 为 `live`（读自运行中的组件）、`startup`（应用启动时读入的存储值，只在启动时读取的设置）或 `storage`（没有可单独观察的运行值，保存它的 setter 就是运行组件使用的那个）。
- **会把密钥或流量送往别处的设置要用户同意**：`danmaku.spoilerAiApiUrl`（防剧透 AI 的密钥和弹幕）、`network.httpProxy`、`plugins.githubProxyUrl`、`network.bangumiServerUrl`（Bangumi 令牌和请求）、`network.allowInvalidCertificates`（全局信任自签名证书）。你用 `settings.set` 把它们设为非空（开关设为开）时返回 NeedsDecision，什么都不改；同一次调用里的其他修改也一并等待，同一次调用里这几项的无效值会让整个调用被拒绝。选项 `settings.set.request` 创建 `setting_consent` 任务并在 NipaPlay 里问用户：只有用户点“更改”才按原调用（原 reason、expectedRevision）写入；用户拒绝则任务失败，信息是“用户没有同意修改设置”，设置不变。用户回答后（更改、取消或关窗）结果作为后续回到发起它的会话，忙时排队，你已对该 jobId 登记 `followup.register` 的不再重复送。设为空串或关闭、`settings.reset`、值没有变化，以及用户自己在设置页改，都不需要问。
- 以下设置读写 Classic 界面里的同一份偏好：`network.bangumiServerUrl`（空串为官方服务器，`effective` 是请求实际使用的完整地址）、`network.mediaServerDeviceId`（空串为自动生成，`effective` 是 Jellyfin/Emby 请求实际带的 DeviceId）、`appearance.largeScreenLayout`、`appearance.classicLocalLibrarySort`、`appearance.collectionSort.<local|webdav|smb>`、`appearance.unwatchedOnly.<jellyfin|emby|shared>`、`playback.<jellyfin|emby>DefaultQuality` 与 `playback.<jellyfin|emby>Transcoding`。后几类视图偏好在页面创建时读取（`apply` 为 restart_app，`effectiveReason` 为 loaded_when_page_created）。
- **没有设置认领的偏好**：`settings.prefs.list` 列出应用偏好（SharedPreferences）里的所有键，标出类别、类型和大小，不含值。`class` 为 `claimed`（某个注册表设置存放它，`claimedBy` 点名；用 `settings.set`）、`credential`（按名字或策略是秘密）、`boundary`（授权边界：远程访问、遥控、Agent、模型、组网）、`routing`（按名字是地址、代理、服务器或证书信任而没有设置认领）、`open`。`settings.prefs.get` 读值：看起来像秘密的文本被遮蔽，超过 4000 字符的被截断；`credential` 和 `boundary` 的值任何动作都不返回（边界的非秘密事实见 `app.runtime`）。`settings.prefs.set` 是兜底，只能写 `open` 的键：先预览（改前改后和 `previewId`，只有发起者可用一次），再带 `previewId` 写入；预览之后偏好变了、或值像凭据，就拒绝；已有的键保持类型；除类型外不校验值。每次写入记录 `commitId`（`prefs-N`）、来源、reason、改前改后，`settings.prefs.history` 列出，`settings.prefs.undo` 撤销（该偏好仍是那次写入留下的值才行，撤销本身也是一次可撤销的记录）。已被设置认领的键、凭据、授权边界和 routing 键不能这样写，只有用户能改，或经校验它的设置。''',
  'history': r'''观看进度由播放器写入；mark_watched_batch 可以标记看过。state.query history.entries 提供稳定 entryId、fileId、canonical workId/libraryEpisodeId 和本机缓存 poster/still；旧 episodeId 仍是 Classic 数字编号。无绑定/无缓存返回 null，不联网取图。历史按 lastWatchedAt 降序及 entryId 排序，游标存排序值，删掉已读条目或最后锚点仍能继续；这是实时观测，条目的观看时间变化仍可能重排。remove 支持 entryIds/paths/animeIds 的并集，包括 locator=null 的条目，只删除记录，保留视频。''',
  'task': 'UiTask.type 带 executor 类型，例如 download、media.scan_classic；kind 仍区分 background/helper。任务关联的作品不存在时仍呈现任务，不假造作品或图片。\n' +
      r'''后台任务共用持久快照、来源和回执。control 批量暂停/恢复/取消，逐项给支持与受理事实；paused 可能仍在排空当前文件。get/wait 核对完成。resources 读取实际容量；tasks.*Concurrency 设置只改变新工作派发。不能安全重放的执行器拒绝暂停。终态回执不改写，取消不删除文件。
- `describe ACTION` 给出输入与输出契约，`call task.list` 可筛选任务（默认最新的在前、每页 50 个，`total` 是匹配总数；用 `limit`、`offset` 翻页，`nextOffset` 给出下一页的起点，没有时已是最后一页；需要正序时传 `order:"oldest"`），`call task.get '{"jobId":"..."}'` 给出单个任务详情。查询默认每页 50 行，可用 `limit`、`select` 与返回的 `nextCursor` 控制读取范围。
- 任务快照的 `origin` 记录提交时的真实调用来源，只在提交时记下：`kind` 为 `user`（NipaPlay 界面上的用户操作）、`conversation`（某个对话里的 `./nipa` 调用，带 `sessionId`，已知时带 `threadId`）、`subagent`（子代理的调用，带 `helperJobId` 或 `threadId`）、`script`（hooks 或 schedules 程序的调用，带 `hookJobId`，已知时带 `event`、`scheduleId`）、`host`（宿主自己提交，如事件触发的 hook 运行、恢复、后台派发）、`device`（另一台设备经 mesh 提交，带 `deviceId`）、`cli`（不在对话里的 `./nipa`）、`mcp`、`other`。没有记录的旧任务不带 `origin`。
- 返回任务只代表已受理。只有状态为 `succeeded`、并且回执经过验证，才算完成。`watch` 是有界的等待，不是后台守护。''',
  'state':
      r'''只读视图读已有索引，不重新探测视频。查询默认每页 50 行，支持 limit、select 和 nextCursor。用 ./nipa call state.describe '{"view":"视图名"}' 读取字段、单位、关系与查询约束；不指定 view 列出全部视图。
- 系统状态视图，只陈述观察到的事实，每个时间都是那次观察发生的时刻，没有观察过就是 null：`media.sources`、`media.source_addresses`（来源及其每个地址）、`accounts`、`network.routes`、`network.observations`、`storage.volumes`、`storage.directories`、`library.scan`、`app.update`、`harness.hooks`、`harness.schedules`、`downloads.engine`。字段含义用 `state.describe` 读。这些视图读现有状态，不联系服务器、不启动下载器。''',
  'app':
      appFamilyDescription + r'''update.check 立即复用 Classic 发布检查；失败时 hasUpdate/latestVersion 为 null，错误与检查时间保留。update.status 读取上次检查；update.open 打开已核对公开发布页。没有应用内更新安装或下载能力。instance 读取当前进程事实。
- `app.runtime` 读取这台设备上只有用户能改的设置的非秘密事实：`remoteAccess`（服务是否在运行、端口、自启动、IPv6、接收端是否开启、受信任设备数量，没有设备身份和令牌）、`mesh`（是否加入、状态、设备名、协调服务地址（不含凭据）、端口、仅本机、局域网发现、手动地址、文件代理端口、是否允许远程运行程序）、`agent`（Agent 端点开关）、`runtime`（`selected` 按环境和实验配置选中的是 codex 还是 dsh；`running` 当前对话宿主的运行时、模型、提供方，没有宿主时为 null；`codex` 的来源、版本与是否已安装）、`model`（NipaPlay 里设置的提供方、不含凭据的地址、模型名和 `keyConfigured`，或沿用的 Codex 配置里写的模型）。密钥不返回；这些设置不能通过 Action 修改。
- `app.restart`（仅 macOS）：先启动一个脱离的辅助进程，一秒后与 `app.quit` 一样正常退出；辅助进程最多等 60 秒让本进程退出，然后用同一个可执行文件、同样的启动参数和环境（实验配置的环境变量原样带回）再启动一次，本进程没有退出就什么都不启动。结束的是连接着你的这个实例及其端点，新进程有新的进程号并自行启动端点，重连后用 `app.instance` 确认。回执只表示已安排，不证明新进程已启动。`apply` 为 `restart_app` 的设置在新进程里生效。其他平台返回 unavailable，读不到启动参数或启动不了辅助进程时也返回 unavailable，并且什么都不重启。
这台机器上可能装着多个 NipaPlay（正式版、开发构建、实验副本）；按应用名或 bundle id 打开的未必是 `nipa` 连接的那个实例。`nipa status` 的实例事实和 `ui.*` 的界面操作、截图来自当前连接的实例。
- `./nipa status` 的 `body.playback` 给当前播放的事实：`state`（播放器状态，没有视频也没有错误时为 `idle`）、`positionMs`、`durationMs`、`path`；当前有错误时带 `error`（`stage`、`category`、`failureId`）；本进程有过播放失败时带 `lastFailure`（最近一条的 `failureId`、`at`、`category`、`stage`、`kernel`、`path`）；资料库认得该文件时再有 `workId`、`work`、`episodeId`、`episode`（如“第 3 集 标题”，电影不带集号）。不认得就只有播放器自己的事实，不猜作品。`body.diagnostics` 给本进程未捕获错误的种数与次数（`uncaughtErrors`、`uncaughtOccurrences`）、是否有还没被 `diagnostics.errors` 返回过的异常退出（`uncleanExitUnread`、`uncleanExitsUnread`、`latestUncleanExitAt`）和是否在记录（`recording`）。
- `./nipa status` 的 `body` 对各部分各给一个简短摘要，细节在 `body.views` 指向的视图里：`sources`（数量、已连接、失败、不可达地址、凭据被拒绝/缺失、同步失败/进行中）、`downloads`（默认目录、是否启用、进行/排队/暂停任务数、总上下行速率）、`space`（首个卷的可用与总量，`volumes` 是所有卷）、`scan`（是否在扫描、目录数、识别失败文件数）、`network`（本进程观察到的来源数与失败数）、`updates`（是否检查过，检查过则带时间、最新版本、是否有更新、错误码）、`hooks`（可运行、因无执行位被忽略、不认识的文件数，以及 `schedules` 的文件状态、条目数、无效数、跳过次数）、`mesh`（设备数与在线数）。读取失败的部分是 `{unavailable, reason}`，`reason` 带错误码与信息，不影响其他部分。
- `./nipa status` 的 `harnessSeed` 给出种子 `path`、当前 `head` 和已抓取的 `trackingHead`。`trackingBehindSeed=true` 表示应抓取更新；`missing_remote` 表示尚未配置远端，`not_fetched` 表示尚未抓取，`different_remote` 表示远端指向另一处，未知状态不等于已同步。此检查只读，不执行 fetch 或合并；`current` 只说明远端跟踪引用最新，不表示你已合并。''',
  'accounts':
      r'''- **需要登录的平台**：用户的浏览器里通常已经登录，直接使用这个登录状态；浏览器也没登录时，打开该平台的登录页，请用户自己登录，然后继续。
- 由你发起、要用户在 NipaPlay 窗口里登录的 `accounts.login`，结束时（登录成功、失败、关窗或取消）作为后续回到发起它的会话，忙时排队；事实只有平台、方式、状态和是否已登录，没有账号名和密码。你已对该 jobId 登记 `followup.register` 的不再重复送。用户在对话里给出秘密、由你直接传入的登录不回报。''',
  'playback':
      r'''open/pause/seek/navigation accept commands; snapshots observe asynchronously. State reports sessionId, readiness, buffering, buffered position, error/recovery and actual supported controls. External unknown position/duration/pause/rate remain null. wait is bounded and detects a changed session; retry explicitly reloads the source through Classic and may preserve position. chapters exposes container markers and detected skip segments; navigate uses chapter, frame or active skip semantics. Backward frame stepping may be approximate. playlist reports the actual detail source list, without authenticated stream URLs.
播放器共用 Classic 和 Next；播放本地或媒体服务器上的文件，叠加字幕和弹幕。加载外挂字幕用 playback.load_subtitle，选字幕轨用 playback.select_track；两者的 `remember` 决定这次选择是否写入字幕记录（默认 false，只对当前播放生效）；字幕记录本身用 subtitle 读写。
- state 另给内部播放器此刻的事实：rate 是选定的倍速，effectiveRate 是此刻实际使用的倍速（按住长按加速时为 speedBoost.rate），kernelRate 是最后交给内核的倍速；kernel 是实际在播放的内核（info 里另有 configured，即内核设置）；danmakuRenderer 是实际画弹幕的那一层（内核自己画时为 player_native）；autoNext 是结束时的动作与下一集倒计时（countingDown、remainingSeconds、next），cancel_auto_next 取消正在进行的倒计时。
- info 在调用时向内核查询：容器、视频编码与分辨率、声明帧率与实测帧率、码率、解码器与是否硬解、丢帧等计数、音频编码与声道、输出与缓存。内核不提供的项为 null；kernelDetails 保留内核原样的报告。
- 打开失败或播放出错时，state.error 带 stage（NipaPlay 哪一步报的错）、category（依次由本地文件状态、内核原文、播放器原文、步骤映射，映射不了为 unknown）、kernelRetryable（内核自己的重试判断）和原始 messages。每次失败记入 failures，同时发出 playback.failed 事件，事件跨重启保留。内核日志与未捕获错误见 diagnostics。
- kernel 在调用时读当前内核：身份与版本（Media Kit 给 mpv 与 ffmpeg，MDK 给 mdk，拿不到为 null）、controls（这个内核能改什么、这台设备能换到哪些内核）、一组固定属性此刻的值（snapshot）和点名读取的属性（properties，带内核自己的错误）。MDK 只报告在这个播放器上设过的属性。Erika 给最近一次解码器事件里的后端（hardware、fellBack 由它读出；FFmpeg 打开硬解后初始化失败、实际改用软解时，Erika 会报这次回退）、帧/音频/HDR 计数、输出状态、资源、超分、轨道与调试 HUD；计数从会话开始累计，window 是与上一次读取（同一播放器、同一媒体）或 sampleMs 间隔之间的变化与帧率；diagnostics 是 Erika 自己的诊断快照，原样给出（解码器、帧计数、呈现耗时、输出与 HDR、资源、音频、缓冲与队列深度，timing 里有迟到丢帧与迟到程度、呈现节奏与抖动、音画时钟漂移与校正、各项时序参数）；notReported 列出 Erika 仍没有暴露的项（网络吞吐与重试、缓冲原因、解码警告（在 player_log 里）、音频设备与延迟、字幕渲染、弹幕丢弃、HDR 元数据与杜比视界、解码器选择）。
- set_kernel_properties 改的是正在播放的这一个内核实例（每次播放新建实例）：Media Kit 收任意 mpv 属性（通过 mpv 当下生效，不变成之后文件的选项），MDK 收任意属性和视频/音频解码器顺序（MDK 多在打开流或解码器时读取），Erika 收 upscaler 与 debugHud（Erika 的轨道、字幕、弹幕偏移与其他内核一样经 playback.select_track、playback.load_subtitle、subtitle.*、danmaku.* 控制）。每项报告 before、requested、after（从内核读回）和内核的错误，记下来源与时间。改动只属于这个实例：换媒体（新会话新实例）或 reopen_with_kernel（新内核实例）就结束，记为 ended，下一个媒体按设置打开。restore_kernel_properties 在播放中按名称或全部恢复，内核没报告过原值的（restorable=false）恢复不了。
- 能把流量或凭据送到别处的设置（代理、UA、请求头、Cookie、Referer、TLS 信任、stream-lavf-o 这类选项文本里设的上述几项，或值里带地址）要用户在 NipaPlay 里允许；拒绝就什么都不改。
- 透传：kernel_command 在 Media Kit 上把 mpv 命令（字符串数组）原样交给 mpv，返回 mpv 的结果数据或它自己的错误文本，之后播放器报错时一并返回；任何命令都能执行，包括 vf/af 滤镜、change-list glsl-shaders 着色器、run 与 subprocess；load-script 只收 harness 仓库里的脚本。改属性的命令（set、add、cycle、cycle-values、multiply、change-list、vf、af）报告属性前后值，并像 set_kernel_properties 一样只属于这个内核实例、可撤销。命令参数里带地址或代理、请求头、Cookie、UA、Referer 的要用户允许，run 与 subprocess 不需要。kernel_invoke 在 Erika 上把方法名与参数原样交给 Erika 的 JSON 方法表；listMethods 返回整张表（每个方法的作用范围、说明、参数名/类型/是否必填、返回什么），Erika 以后加的方法会出现在表里，不用改 NipaPlay 就能调；没有这个方法时 supported=false，失败时带 Erika 自己的错误。watch_kernel_properties 在 Media Kit 与 MDK 上按间隔读若干属性，返回限定时长内的每次变化，调用结束即停止。每次直接调用都记入 changes（谁、何时、内核、命令或属性、原值、结果、错误）。
- reopen_with_kernel 把当前播放换到另一个内核的新实例，在当前位置重开当前媒体，会话和观看记录不变，不改内核设置；是否在播、位置、倍速、音量、音轨与字幕选择（按语言、标题、编码匹配，否则按序号）和已选的外挂字幕文件带过去，换的过程中发来的暂停或跳转落在新实例上；结果报告请求的与实际运行的内核、是否打开、错误和各项前后值。旧实例上的改动随它结束。下一个媒体回到内核设置。
- 这些改动不跨内核实例：关闭 Next 界面时会话关闭，实例随之销毁。长期生效的改动用 settings.set；播放中保存内核相关设置不影响正在播放的实例，下一次打开按新值，settings.get 的 effective 报告正在播放的实例是按什么值建的。''',
  'discover': r'''弹弹play 每日放送与推荐。''',
  'plugins': r'''应用插件。''',
  'media.sources': r'''SMB、WebDAV、Jellyfin、Emby 等远程来源。
- search 结果的 poster 是已有本机缓存路径；没有缓存为 null，不逐项取图。workTitle 给已绑定作品名。artwork(sourceId,itemId) 懒加载服务器海报，复用 X48 图片供应者，只返回本机路径，不返回鉴权 URL。
- `media.sources.search {query,sourceIds?,limit?}` 是只读搜索：Jellyfin/Emby 用服务器 SearchTerm 和有界分页，SMB/WebDAV 只查已有文件索引，不枚举目录、不登记新文件、不写发现记录。省略 sourceIds 搜所有支持的已配置来源；limit 限制每个来源（默认 12）。返回 sources[]，每个来源单独给出 entries、total 或 error。离线或登录失败如实返回，其他来源保留结果；索引来源的 unverified 是未知连通状态，不能当成在线。
- 结果有 sourceId、itemId、标题、可播放事实；已绑定条目带 Next workId/episodeId，服务器原样条目另有 sourceWorkId/sourceEpisodeId。作品 ID 用 ui.open，来源条目用 media.sources.play {sourceId,itemId}。来源分组在界面上可逐个 sourceIds 请求，分别显示结果与错误。
- browse/sync 是发现与写索引入口；不要用它们实现每次输入的搜索。
- 每个来源还带重启后仍在的观察事实，列表不联系服务器；同样的事实在 `state.query` 的 `media.sources` 与 `media.source_addresses` 里可过滤。`addresses[]` 给每个已配置地址最近一次尝试：`reachability`（reachable、unreachable，没有尝试过是 unknown，不等于离线）、`lastAttemptAt`、`lastSuccessAt`、`lastFailureAt`、稳定的 `errorCode`（如 timeout、connection_refused、dns_failed、network_unreachable、tls_failed、auth_failed、credential_missing、http_状态码、connection_failed）和 `latencyMs`。SMB/WebDAV 地址在启动检测和测试连接时探测，Jellyfin/Emby 的各地址在连接时尝试，只有一个地址的来源在 `media.sources.check` 时记录。`lastCheck` 是最近一次检查，`sync` 是最近一次同步（result 为 running、succeeded、failed、cancelled，进程结束时仍在跑的记为 interrupted；`lastSuccessAt`、`indexed`、`errorCode`、`jobId`），`lastError` 带 `code`、`at`。`credential.state`：none（不需要登录）、saved（已有保存的登录，不读保险库，保险库里的条目没了会在使用时以 credential_missing 出现）、missing（需要登录而没有保存）、rejected（来源在最近一次接受之后拒绝了保存的登录），另有 `lastRejectedAt`、`lastVerifiedAt`；从不含凭据。改了地址或账号后，旧的探测与凭据观察清除。
- browse/sync 把条目登记为文件时，首次登记的条目发出 `library.file_added`（`via` 为 `media_source`，`path` 是来源条目的位置，`fileId` 为登记的文件），并计入新进片库的事实，见 `followup` 族。
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
