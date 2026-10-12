# Next 的界面数据

界面在 `await core.ready` 后使用 `core.uiData`（实现 `NextUiData`）。订阅 `changes` 后重新读取首页、作品、剧集和卡片；`tasks()` 每个订阅先收到完整任务列表，随后在任务修改时收到新列表。界面退出时取消订阅，NextCore 负责关闭服务。

`workId / episodeId / taskId` 和书架 `id` 用于点击、定位和调用能力，不是显示文字。其余文字为作品元数据、简短的观看提示或 Agent 的短句。普通任务标题由任务类型与关联作品生成；帮手使用 Agent 给的简短标题。

## 首页与移除

`ui.shelves.put` 替换一处摆放：

```json
{"placement":"hero","note":"今晚一起看。","items":[{"workId":"本地作品 ID"}]}
```

```json
{"placement":"shelf","id":"tonight","title":"适合今晚","items":[{"workId":"本地作品 ID","note":"听一场热闹的演出。"}]}
```

`items:[]` 移除。书架保留稳定的 Agent 自定 ID；`hero / continue / recent` 为保留 ID。书架项的 note 映射为 caption，缺省时按下一集及观看进度生成。继续观看读取现有 `history.continue_watching`；尚未接入历史供应者时不制造观看记录。最近添加以作品首次入库顺序倒序，最多二十部。

GUI 可用 `core.uiData.removeShelf(id, workId: ...)` 移除一项，省略 workId 移除整处摆放。能力入口为 `ui.shelves.remove`，保留调用者来源。用户移除写入 `body_changes`，activity 中有自然标题、用户来源及关联作品。

`airing` 是保留书架 ID。今天更新位于继续观看之后，空时省略。作品需要已接受的弹弹play作品身份，并出现在收藏日历中，或已有在看/继续观看历史。复用 X29 的 Classic 日历和详情缓存，以单集 `airDate` 的本地日期为准；只有星期没有剧集日期时不猜。缓存不足且已登录时，经原 BangumiService 取得日历/详情。一天多集展示目录中最后一集；有明确时间才显示“今天 23:30”。日历由运行时供应给 Core，Core 单独使用时没有 Flutter 设置服务依赖。

主视觉优先采用 Agent 的 hero。否则读取成功任务关联的可播放作品，再取本机最近可播放入库；这两项是“最近准备好”的事实。其后取继续观看作品的可播放新集，最后取继续观看首部。自动主视觉没有 note。

## 对话卡片

`ui.present` 输入 `cards` 数组，每次调用追加在当前回合。`NIPAPLAY_CHAT` 的来源字符串对应已有 journal 的最新回合边界；无活动回合报错，不猜测线程。省略 `cards()` 的 turnId 读取整个线程，提供 turnId 则只读指定回合。

| kind | 引用与短句 |
|---|---|
| work | workId |
| episode | episodeId，作品从父关系解析 |
| candidates | items: [{workId, reason?}] |
| task | taskId，使用任务的 jobId |
| preparation | title、可选 workId、steps: [{label, detail?, 三选一 taskId / entityId / followupId}] |

引用在整个批次写入前验证；缺失引用的错误说明应查询的视图及 ID 语义。步骤不可提交 state/progress，实时读取任务或后续；实体步骤表示已经找到该作品/剧集。没有额外的状态常量或第二份任务状态。接口的 failed 合并失败和取消，paused 合并暂停、等待决定及中断；等待重试映射为 queued。remaining 无可靠估计时为 null。

X37 的帮手同样使用 `ui.present`，其活动来源为 `harness_cli:helper:<jobId>`。
原卡片位于帮手线程的实际回合；帮手结果的后续派发时，引用也追加到发起线程的实际后续回合。
重复对账不会重复复制。卡片中的任务仍实时解析，不保存第二份任务状态。

## 后台任务契约（X37）

`UiTask` 原字段保持兼容；新增字段默认可省略。

| 字段 | 含义 |
|---|---|
| taskId | 持久任务号，可用于 `task.get/cancel`，不是显示文字 |
| title | 观众看到的短标题；帮手使用调用者提供的 title |
| state | queued/running/paused/finished/failed；容量等待是 queued，取消仍映射 failed |
| kind | `UiTaskKind.background`（默认）或 `helper`，区分普通任务与帮手 |
| startedAt | 实际开始处理的 UTC 时间；帮手进入线程时记录，尚未开始或没有该事实时 null |
| currentActivity | 一句现在在做什么；帮手可用 `agent.helper.report` 更新，否则显示宿主的简短状态；其他任务可为空 |
| summary | 结束回执里的结果摘要；尚未结束或没有摘要时 null；是帮手的报告，业务结果需查对应回执 |
| threadId | 帮手的 Codex 线程号，可打开其对话；排队尚未建线程或普通任务为 null |
| parentThreadId | 结果返回的发起会话线程号；普通任务为 null |
| cancelled | 是否确实取消，默认 false；可区分 failed 中的取消与错误 |
| source | 可选来源：`codexNative` 为原生子代理，`host` 为 `agent.dispatch` 的宿主派发；原任务兼容 null |
| artwork | 已缓存的关联作品图片，无关联或缓存时 null |
| progress | 可核实的 0–1 进度；未知为 null，帮手始终 null，包括完成后 |
| remaining | 有可靠估计时的剩余时长，否则 null |

没有进度也是正常后台任务。不得把 null 补成 0%、完成时补成 100% 或用思考/命令次数估算帮手进度。

X38 原生子代理复用上述字段：标题取 prompt 的短句，currentActivity 取最新助手短句或实际工具阶段，summary 保留最后完整回答；取消仍是 failed + cancelled=true。没有修改作品或图片投影。
两个帮手同时运行，更多的按创建顺序等待；这个上限不限制主会话。

## 图片与热度

`media.metadata.ui_facts {workId}` 直接读取同一个 `NextUiData.work/episodes`，返回所有作品资料和逐集标题/截图的 `available/value/path/source`、简介与标题语言、截图覆盖数量、优先主视觉图与 tint。没有假名证据时语言采用声明值，缺少声明就是 unknown；发现日文假名时 language=ja，保留 declaredLanguage 与 languageBasis，避免把中文请求参数误当简介的实际语言。生成的集数注明来自本地剧集目录。读取可能填充可删除的图片缓存。

`media.artwork.set` 输入 `entries:[{entityId,kind,url或file,source:{label,url?}}]`。backdrop/poster/logo 的 entityId 是作品，still 的 entityId 是单集；url 是无 userinfo 的 HTTP(S)，file 是本机绝对路径，两者恰好一个。整批图片解码、复制/缓存成功后，原子写入既有 `media_overrides/media_metadata_edits`，activity 的 metadata.edited 保留来源、调用者与 invocationId。四种图片独立覆盖；来源快照、身份与旧编辑全部保留。文件以内容哈希复制，原文件可删除；URL 沿用 X26 的 URL 哈希下载缓存。覆盖不需要平台身份或平台凭据，并在来源刷新后保留。

标题与简介仍用 `media.metadata.override`：field=title 是显示标题，field=overview 是简介，支持 language:"zh-CN"。语言与文字采用相同的 persistent/correction/clear 生命周期，替换文字时未声明语言就恢复 unknown，不继承旧语言。来源文字优先简体中文，显式用户/Agent 编辑仍优先。

没有图片覆盖时，从作品/剧集已接受的身份取得，沿用现有作品/发行的 contains 关系与单集的 exact 关系。TMDB 复用原 MetadataTransport、正常凭据解析和应用的系统代理；支持保险库的 API key 与 Bearer 读取令牌。没有 TMDB 身份时沿用已有来源的 imageUrl；没有 TMDB 凭据时仍能读取已保存的图片事实和独立覆盖。

TMDB 的图片 URL、语言选择、评分、类型、集数、制作公司和单集时长追加到原 `media_snapshots`，保留对象身份、来源、抓取时间和收到时间；本地图片是可删除的投影。背景优先语言为 null 的图；Logo 为中文、日文、英文、中性图。文件按 URL 哈希存到 Next 数据目录的 artwork，解码验证后原子发布。tint 将背景（缺少时使用海报）缩到 64 像素宽，对 RGB 色箱计数，并取最多色箱的平均色，包含 ARGB alpha。

普通公开 URL 包括非秘密查询参数会原样进入 Agent 输出；userinfo、令牌、签名查询/片段和已知秘密仍脱敏。服务端和种子 nipa 同时应用此约束。`ui.capture` 默认 PNG 长边至多 1280 像素，不放大小图；originalSize:true 返回原尺寸。输出同时包含 originalWidth/originalHeight，与 instance 一起确定截图来自当前连接实例。

每集热度汇总当前有效绑定的所有缓存，包含剧集轨道及关联文件轨道，不因播放时关闭轨道而遗漏已有弹幕。相同缓存/时间范围/偏移只计一次；每个来源内部沿用原缓存读取的去重。文件轨道按剧集范围裁剪，偏移后映射到剧集时间轴；没有范围的多集文件不猜测。60 个等宽桶按最高桶归一化，无弹幕为 null；无时长时用最后一条弹幕的时间作为跨度。绑定、修订、偏移、范围、时长、缓存内容/收到时间进入缓存指纹，变化后重算。

`UiWork.danmaku` 只读取上述有效缓存和剧集范围。先取目录第一集的前 180 秒，不足六句时依次扩到第二、第三集的开头；不会扩到单集后段。时间窗可用 `settings.set {key:"next.heroOpeningSeconds", value:180}` 调整（30–300 秒），GUI 可读取同一设置 schema。每句 2–18 个 Unicode 字符，合并空白、排除网址/域名、控制字符、四个以上连续重复字符及重复三次以上的短字符组；去标点和空白、转小写后跨剧集去重。按剧集、时间排序，同刻按原文排序，最多六句。保留真实原文，没有短语白名单，不做剧情语义判断；开头也可能含其他集的剧透。不会为这份投影发起网络请求。

`ui.open {entityId:作品}` 或 `{workId:作品}` 在 Next 外壳可见时打开 Next 详情，返回 `interface:"next"`；外壳未显示时沿用原 Classic 详情入口并返回 `interface:"classic"`。连接仅为 `WorkDetailBridge` 的挂载回调，界面调用已有 `openWork`。直接 animeId、页面、对话框、文件与剧集播放入口保持原语义。

## 本地观看状态与界面开关

界面和 Agent 都调用 `history.mark_watched_batch`：

```json
{"entries":[{"episodeId":"本地剧集 ID","watched":true},{"fileId":"本地文件 ID","watched":false}]}
```

每项恰好一个 episodeId/fileId。整批先解析并验证，Classic 观看历史事务只更新 progress、position 和 lastWatchTime；无历史、状态矛盾或多集文件会拒绝整批，保留匹配、时长、缩略图等字段。看过为进度 1、位置等于时长；没看过为进度和位置 0。成功后刷新原 WatchHistoryProvider，写入带调用者来源的 activity。Next 能力开启时，Classic 详情页的本地勾选走同一个 Action；原有账号观看状态同步保持原入口。

`labs_use_next_interface` 已注册到 `settings.describe/get/set/reset/history`。注册表读取原存储键，写入实际的 NextUiPreference；界面写入仍经 SettingsStorage/SettingsAccess，只有一个值，并保留两边调用来源。

SQLite v12 增加 `media_file_aliases`，事务合并历史的通用 remote 文件和唯一来源范围下的同 URL 文件；保留旧 ID、观察、回执与合并前的行存档。运行时登记也执行相同合并，重复执行不再改变结果。不同服务器范围继续独立。

SQLite v11 只追加 `ui_presentations / ui_shelves / ui_cache`。任务提交后即时通知 changes；其余数据库和 Classic 内存历史每 250ms 观察一次（同连接 total_changes、其他连接 data_version、现有历史供应者），变动后通知。通知可能合并同一观察窗口或因缓存落盘多一次，不承诺每条领域事件一条通知。后台任务变化与轻量缓存投影无网络请求；首次作品/剧集读取可能等待图片下载。

Debug 且临时 profile 才注册 `ext.nipaplay.uiData`，供实验读同一界面接口、采样流、模拟会话边界、触发真实 hook 和通过正常保险库写入固定测试文件。该入口不在 Agent 能力目录，不在生产启用。
