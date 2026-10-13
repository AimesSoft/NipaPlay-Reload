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

const familyFacts = <String, String>{
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
- **对话**：首页展开的对话页，和其他页面的侧栏，是同一个会话。你用 `ui.present` 摆的卡片出现在回复下方，状态实时更新。
- **右上角的进度环**：NipaPlay 的后台任务。
- **播放器**：播放能播放的集（本地文件或媒体服务器上的文件），叠加弹幕和字幕。
- **界面刷新**：界面随时读取最新数据，交给 NipaPlay 的东西马上可见。
- **普通公开链接**会原样返回；带登录凭据、令牌、签名或访问密钥的链接会被脱敏。`ui.capture` 默认返回长边不超过 1280 像素的截图，传 `originalSize:true` 返回原尺寸。
- **想让用户在 NipaPlay 里看到的，可以用 `ui.present` 和 `ui.shelves.put` 摆给他**：这些文字是给观众看的，用自然的短句，不写 ID，也不写过程。''',
  'media':
      r'''NipaPlay 自己会做一部分：作品有 TMDB 身份时取图，同步 Classic 识别的结果，把下载完成的文件登记入库，发现并记录视频旁的同名 XML/JSON 弹幕、内嵌字幕轨和匹配的外挂字幕。`media.metadata.ui_facts` 告诉你一部作品现在还差什么。你的工作是：
`media.metadata.ui_facts` 读的是和界面同一份数据，按作品给出下面每一项有没有、来自哪里；不必截图去猜。

- **文件与剧集的对应**：一个文件对应到某一集，那一集才能播放。本地文件在片库根目录（`media.library.roots.*`）内，或是 NipaPlay 已验证完成下载的文件，才在 Next 中可访问；文件仍须实际存在。对应关系由 `media.identity.bind_batch` 写入；Classic 识别成功的文件会自动同步过来。
- **身份**：作品与弹弹play、Bangumi、TMDB 或其他 HTTPS 来源的绑定。没有身份就没有作品，界面上也不会出现。用 `bind_batch` 和 `unbind_batch` 修改。
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

  有 TMDB 身份并配置了 TMDB 凭据时，NipaPlay 会自己取图。已经保存的 `artworkUrls` 各角色图片、其他来源的 `imageUrl` 和显式图片覆盖，不因缺少 TMDB 凭据而隐藏。`imageUrl` 在作品上是海报，在集上是截图；它没有横版或透明 Logo 的语义。`media.artwork.set` 可以把链接或本地文件，连同来源，设为任意一种图片。
- **剧集列表**：作品下各季的集，只包含绑定过的集。
- **Classic 同步**：保留识别标题与已有的详情缓存，包括标题语言、简介、海报、背景、类型和集数。未缓存的资料不会自动补抓；没有声明语言的识别标题仍是 `und`。Next 的显式覆盖优先，不修改 Classic 的详情缓存。
- **扫描**：`media.library.scan` 只建立索引，不做识别；支持指向授权根目录内视频文件的符号链接，不递归跟随目录链接。新增文件在下一次扫描时进入索引；身份、资料、图片、弹幕是独立的事实。
- **本地文件读取**：扫描和按根目录调用 `media.files.list` 会逐个读取视频、计算头部哈希并探测时长，并非只枚举文件名。`state.query` 的文件视图读取已有索引与对应关系，不重新探测视频。
- **你的工具**：这个仓库里的脚本，或别人的开源工具，负责在外面找东西：RSS、站点、API、文件。找到的结果交给 NipaPlay，才算进入了这个系统：
  - 下载：`download.add`；
  - 身份：`bind_batch`；
  - 资料：`import_batch` 或 `override`；
  - 图片：`artwork.set`；
  - 弹幕：`danmaku.import`。
- **媒体身份可以来自多个来源**：弹弹play、Bangumi、TMDB 等。弹弹play 没有收录，不等于无法识别；电视剧、电影常常只有 TMDB 身份。内容哈希匹配只能给出弹弹play 的 ID。文件名需要你自己理解，NipaPlay 不会替你解析。
- **你取得的结果都可以交给 NipaPlay 保存**（弹幕、元数据、身份），它会记录来源并检查一致性。缺少入口时，如实告诉用户。''',
  'danmaku': r'''- **弹幕**：
  - **轨道**：一条弹幕轨道属于某个文件或某一集，有它的来源平台（弹弹play、优酷、B 站、本地文件……）和该平台上的视频；同一平台的同一个视频只保留一条，再次交入就是刷新。
  - **用在哪里**：剧集的热度线和主视觉上飘的弹幕，都来自 NipaPlay 记下的轨道。用 `danmaku.*` 修改，用 `state.query` 的 `danmaku.bindings`、`danmaku.tracks` 读取。
  - **同名弹幕文件**：NipaPlay 索引本地视频时，在后台发现并读取旁边最匹配的 XML/JSON，记录路径、平台、视频号、条数与读取时间；内容留在原文件。文件变化会重读，消失或不可读会记为不可用。热度线、主视觉弹幕、`ui_facts` 每集覆盖和轨道查询读取同一份记录，Next 播放器加载这条轨道。Next 播放时自动取得的弹弹play 弹幕也会保存为轨道，下一次仍可读取和播放。
  - **其他平台的弹幕**：你取回来的文件只是中间产物。用 `danmaku.import` 交给 NipaPlay 时，弹幕内容会保存成 NipaPlay 数据目录 `next/danmaku/` 里的文件，数据库记录引用、条数、时间范围和来源，绑在那一集或那个文件上；交完以后，原文件就不再需要。导入内容不会按缓存空间回收；刷新或撤销轨道后，不再被引用的旧文件会清掉。要刷新，就重新取一次、再交一次。中间文件放在这个仓库的 `records/`（不进 git），不需要写进视频所在的目录，那里可能是只读的。
- **弹幕可以同时来自多个平台**：Next 内置的来源是经过 NipaPlay 网关的弹弹play；本地弹幕文件可以用 `danmaku.import` 交入（来源记为本地文件）；交入的弹幕可来自任意平台。同一平台的同一个视频只保留一条轨道，再次交入就是刷新。Next 没有内置优酷、B 站来源或应用内平台登录；已有的平台绑定、轨道与缓存仍可读取和播放。''',
  'subtitle':
      r'''- **字幕**：按视频文件记录内嵌轨与匹配的外挂字幕，包含语言、标题、格式、来源、可用性和默认选择。内嵌语言来自容器声明，外挂语言来自文件名，未知记为 `und`；文件名语言不是内容核验，记录没有识别烧录在画面中的字幕。单视频目录的 `Subs/`、`Subtitles/` 下语言字幕也会记录。`media.metadata.ui_facts` 给出每集的字幕语言、内嵌或外挂轨道及覆盖。`subtitle.tracks` 读取记录；`subtitle.import` 批量交入字幕文件及语言、来源，内容复制进 NipaPlay 数据目录，交完原文件不再需要，视频目录可以只读。Next 播放时按记录恢复字幕：显式选择和已有 Classic 选择优先，之后按应用语言设置决定简中或繁中优先，再选中文、英文；文本外挂先于内嵌轨。默认选择及依据也在记录中，`subtitle.select` 可记录选择或关闭字幕。`playback.load_subtitle` 仍可为当前播放临时加载。
- 无界面宿主支持字幕事实、同名外挂索引、导入和显式默认选择；配置 ffprobe 时记录内嵌轨道，未配置时内嵌状态为 unavailable。它不播放字幕、不读取 Classic 字幕偏好或观看历史；默认字幕由调用者显式选择。''',
  'download':
      r'''- **下载器**：内置 BT 引擎支持 magnet、种子文件和 HTTP(S) 种子链接，使用 Classic 的下载目录设置；新任务可以指定目录和是否建立任务文件夹，重复添加同一哈希不会搬动已有文件。由你发起的下载，视频文件通过校验并登记入库时、任务完成或失败（含取消）时，事实都会自动作为后续回到发起它的会话；会话忙时排队。第一份文件事实立即入队，其余按一分钟合并，任务结束立即送回剩余事实；你已登记的同事件后续不会再多送一份。`download.read` 给出实际落盘路径、逐文件已校验字节、完整与可播状态、连接/已发现/待连接 peer、最近采样间的进展和所在盘可用字节。初始化时逐文件进度可能未知；公开引擎接口不提供做种数或来源持有的片段分布，返回 null。可以在添加时指定文件索引，也可以用 `download.select_files` 改变任务要下载的文件；不删除已下的数据。引擎没有普通文件优先级接口。
- **单个下载文件完成时**：引擎确认全部片段通过校验、NipaPlay 核对路径和大小后，本地视频就登记入库，无需等整个任务结束。开启自动扫描时，Classic 扫描器识别该文件；识别不了仍登记文件，不虚构作品。`download.file_completed` 事件的对象是 `任务号:文件索引`，包含文件校验事实和当前文件/作品关联，可以触发同名 hook 或登记的后续。完整文件的持久校验记录允许访问该文件，不把下载目录或未完成的邻居当作片库根目录。整个任务完成仍有原来的回执和 `download.completed` 事件；回执保留 `fileIds` 和当时已有的 `workIds`，后来绑定的作品通过文件当前的剧集对应找到。扩展已完成的文件选择会返回新的观察任务，旧回执保留。
- **其他下载器**：qBittorrent、Aria2、seedbox 这类下载器，NipaPlay 不内置，也不代管。你用它们自己的命令行或接口驱动，可以在本机，也可以在别的设备上运行程序。文件落进 NipaPlay 能读到的位置之后，扫描、识别、入库、播放和本机下载的文件一样。从别的机器取回文件，用文件通道或用户已有的同步方式。''',
  'mesh':
      r'''`mesh.devices` 返回同账号设备、连通状态、各设备实际开放的能力和经过双向 TLS 认证的设备自我描述。自我描述包含平台、宿主角色、片库根目录、下载目录，以及宿主配置的存储路径与 Nipa 所在设备；路径属于描述它的那台设备。无界面节点提供片库、下载、任务、hooks 和定时程序，那里没有对话宿主。网络加入、签发者、监听策略和 Nipa 所在设备由宿主配置，Action 不能开放这些权限。`./nipa --device NAME list`、`describe ACTION`、`call ACTION ...` 和 `watch JOB_ID` 使用该设备的实时目录；名称也可换成设备 ID，重名不会任选一个。

从 Mac 对话通过组网发起的下载，在发起时固定返回设备与线程。每个已校验、已入库的视频文件和任务终态，由下载设备的持久后续队列交回那个会话；会话忙时排队。返回事实含来源设备，文件路径、`local` 和 `playable` 是来源设备上的事实。断线后保留待交付记录，重复交付使用同一回执。工作站 hooks 或定时程序调用 `agent.wake` 时，宿主配置的 Nipa 设备接收唤醒；不指定线程时回到那里持久主会话。工作站的 `followup.list` 中 `deliveryState: forwarded` 及 `remoteReceipt` 表示目标已经持久接收，实际对话状态保存在目标设备。
- Mesh 可调用目标设备实际注册的 `task.*`、`download.*`、`media.*`、`danmaku.*`、`playback.*`、`subtitle.*`、`history.*`、`followup.*`、`program.*`、`discover.*`、`sync.*`、`ui.*`，以及 `state.query`、`activity.report`、`agent.wake`、`app.instance`。设置可远程读取 `settings.get/describe/history`；账号可读状态、读写收藏和剧集观看状态、执行 Bangumi 同步及读取同步状态。宿主登录与退出、组网管理、信任、签发者、开关和设置修改没有远程入口。实时远端目录给出具体可用项；没有播放器或 Classic 历史的宿主不会注册这些能力。
- **媒体库跨设备是一份合并库**：`library.merged` 包含本机和同账号设备上的全部作品。一部作品的剧集可能分散在几台设备上；重复文件优先本机。视频留在原设备，播放时直接读取原处，不复制整部文件。
- **设备离线时**：上次看到的作品、元数据和已缓存图片仍显示；设备 online=false，只在离线设备上的剧集 playable=false。恢复连接后目录和进度继续更新。
- **读取别的设备上的文件**：`media.library.readable` 批量解析剧集；`media.mesh_files.readable` 批量解析绝对 path 和 deviceId，不限已入库文件。远端文件返回当前调用节点的 127.0.0.1 HTTP Range 地址，可给播放器、ffprobe、ffmpeg；回环需绕开 HTTP_PROXY。设备之间的字节经过同账号双向 TLS，协调服务不转发视频。
- **写入别的设备上的文件**：`media.mesh_files.begin/chunk/finish` 提供文件暂存、分段写入和完成校验，cancel 丢弃未完成传输；省略 deviceId 操作本机。文件权限是目标节点进程的实际权限，父目录须存在。传输 ID 目前不跨节点进程重启。
- **删除和覆盖先问用户**：`media.mesh_files.delete` 批量预览，finish 遇到已有目标返回 NeedsDecision；用户决定后才执行 confirm 的 destructive ActionCall。目标自预览后变化会拒绝。加入 Mesh 是宿主同意同账号设备访问，没有额外共享开关。''',
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
  'history': r'''- **观看进度**：由播放器写入；`history.mark_watched_batch` 可以标记看过。''',
  'task':
      r'''- `describe ACTION` 给出输入与输出契约，`call task.list` 可筛选任务，`call task.get '{"jobId":"..."}'` 给出单个任务详情。查询默认每页 50 行，可用 `limit`、`select` 与返回的 `nextCursor` 控制读取范围。
- 返回任务只代表已受理。只有状态为 `succeeded`、并且回执经过验证，才算完成。`watch` 是有界的等待，不是后台守护。''',
  'state':
      r'''只读视图读已有索引，不重新探测视频。查询默认每页 50 行，支持 limit、select 和 nextCursor。用 ./nipa call state.describe '{"view":"视图名"}' 读取字段、单位、关系与查询约束；不指定 view 列出全部视图。''',
  'app':
      r'''这台机器上可能装着多个 NipaPlay（正式版、开发构建、实验副本）；按应用名或 bundle id 打开的未必是 `nipa` 连接的那个实例。`nipa status` 的实例事实和 `ui.*` 的界面操作、截图来自当前连接的实例。
- `./nipa status` 的 `harnessSeed` 给出种子 `path`、当前 `head` 和已抓取的 `trackingHead`。`trackingBehindSeed=true` 表示应抓取更新；`missing_remote` 表示尚未配置远端，`not_fetched` 表示尚未抓取，`different_remote` 表示远端指向另一处，未知状态不等于已同步。此检查只读，不执行 fetch 或合并；`current` 只说明远端跟踪引用最新，不表示你已合并。''',
  'accounts':
      r'''- **需要登录的平台**：用户的浏览器里通常已经登录，直接使用这个登录状态；浏览器也没登录时，打开该平台的登录页，请用户自己登录，然后继续。''',
  'playback':
      r'''播放器共用 Classic 和 Next；播放本地或媒体服务器上的文件，叠加字幕和弹幕。临时加载字幕用 playback.load_subtitle；持久事实用 subtitle。''',
  'discover': r'''弹弹play 每日放送与推荐。''',
  'sync': r'''远程来源与多端同步。''',
  'plugins': r'''应用插件。''',
  'media.sources': r'''SMB、WebDAV、Jellyfin、Emby 等远程来源。''',
  'media.mesh_files':
      r'''`mesh.devices` 返回同账号设备、连通状态、各设备实际开放的能力和经过双向 TLS 认证的设备自我描述。自我描述包含平台、宿主角色、片库根目录、下载目录，以及宿主配置的存储路径与 Nipa 所在设备；路径属于描述它的那台设备。无界面节点提供片库、下载、任务、hooks 和定时程序，那里没有对话宿主。网络加入、签发者、监听策略和 Nipa 所在设备由宿主配置，Action 不能开放这些权限。`./nipa --device NAME list`、`describe ACTION`、`call ACTION ...` 和 `watch JOB_ID` 使用该设备的实时目录；名称也可换成设备 ID，重名不会任选一个。

从 Mac 对话通过组网发起的下载，在发起时固定返回设备与线程。每个已校验、已入库的视频文件和任务终态，由下载设备的持久后续队列交回那个会话；会话忙时排队。返回事实含来源设备，文件路径、`local` 和 `playable` 是来源设备上的事实。断线后保留待交付记录，重复交付使用同一回执。工作站 hooks 或定时程序调用 `agent.wake` 时，宿主配置的 Nipa 设备接收唤醒；不指定线程时回到那里持久主会话。工作站的 `followup.list` 中 `deliveryState: forwarded` 及 `remoteReceipt` 表示目标已经持久接收，实际对话状态保存在目标设备。
- Mesh 可调用目标设备实际注册的 `task.*`、`download.*`、`media.*`、`danmaku.*`、`playback.*`、`subtitle.*`、`history.*`、`followup.*`、`program.*`、`discover.*`、`sync.*`、`ui.*`，以及 `state.query`、`activity.report`、`agent.wake`、`app.instance`。设置可远程读取 `settings.get/describe/history`；账号可读状态、读写收藏和剧集观看状态、执行 Bangumi 同步及读取同步状态。宿主登录与退出、组网管理、信任、签发者、开关和设置修改没有远程入口。实时远端目录给出具体可用项；没有播放器或 Classic 历史的宿主不会注册这些能力。
- **媒体库跨设备是一份合并库**：`library.merged` 包含本机和同账号设备上的全部作品。一部作品的剧集可能分散在几台设备上；重复文件优先本机。视频留在原设备，播放时直接读取原处，不复制整部文件。
- **设备离线时**：上次看到的作品、元数据和已缓存图片仍显示；设备 online=false，只在离线设备上的剧集 playable=false。恢复连接后目录和进度继续更新。
- **读取别的设备上的文件**：`media.library.readable` 批量解析剧集；`media.mesh_files.readable` 批量解析绝对 path 和 deviceId，不限已入库文件。远端文件返回当前调用节点的 127.0.0.1 HTTP Range 地址，可给播放器、ffprobe、ffmpeg；回环需绕开 HTTP_PROXY。设备之间的字节经过同账号双向 TLS，协调服务不转发视频。
- **写入别的设备上的文件**：`media.mesh_files.begin/chunk/finish` 提供文件暂存、分段写入和完成校验，cancel 丢弃未完成传输；省略 deviceId 操作本机。文件权限是目标节点进程的实际权限，父目录须存在。传输 ID 目前不跨节点进程重启。
- **删除和覆盖先问用户**：`media.mesh_files.delete` 批量预览，finish 遇到已有目标返回 NeedsDecision；用户决定后才执行 confirm 的 destructive ActionCall。目标自预览后变化会拒绝。加入 Mesh 是宿主同意同账号设备访问，没有额外共享开关。''',
};
