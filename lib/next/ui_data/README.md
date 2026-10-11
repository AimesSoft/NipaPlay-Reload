# Next 的界面数据

界面在 `await core.ready` 后使用 `core.uiData`（实现 `NextUiData`）。接口文件 `ui_data.dart` 保持原样。订阅 `changes` 后重新读取首页、作品、剧集和卡片；`tasks()` 每个订阅先收到完整任务列表，随后在任务修改时收到新列表。界面退出时取消订阅，NextCore 负责关闭服务。

`workId / episodeId / taskId` 和书架 `id` 用于点击、定位和调用能力，不是显示文字。其余文字为作品元数据、简短的观看提示或 Agent 的短句。任务标题由任务类型与关联作品生成，不显示底层任务标题、路径、日志、来源链或回执。

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

## 图片与热度

图片从作品/剧集已接受的身份取得，沿用现有作品/发行的 contains 关系与单集的 exact 关系。TMDB 复用原 MetadataTransport、正常凭据解析和应用的系统代理；支持保险库的 API key 与 Bearer 读取令牌。没有 TMDB 身份时沿用已有来源的 imageUrl；没有身份或 TMDB 凭据则图片为 null。

TMDB 的图片 URL、语言选择、评分、类型、集数、制作公司和单集时长追加到原 `media_snapshots`，保留对象身份、来源、抓取时间和收到时间；本地图片是可删除的投影。背景优先语言为 null 的图；Logo 为中文、日文、英文、中性图。文件按 URL 哈希存到 Next 数据目录的 artwork，解码验证后原子发布。tint 将背景缩到 64 像素宽，对 RGB 色箱计数，并取最多色箱的平均色，包含 ARGB alpha。

每集热度汇总当前有效绑定的所有缓存，包含剧集轨道及关联文件轨道，不因播放时关闭轨道而遗漏已有弹幕。相同缓存/时间范围/偏移只计一次；每个来源内部沿用原缓存读取的去重。文件轨道按剧集范围裁剪，偏移后映射到剧集时间轴；没有范围的多集文件不猜测。60 个等宽桶按最高桶归一化，无弹幕为 null；无时长时用最后一条弹幕的时间作为跨度。绑定、修订、偏移、范围、时长、缓存内容/收到时间进入缓存指纹，变化后重算。

SQLite v11 只追加 `ui_presentations / ui_shelves / ui_cache`。任务提交后即时通知 changes；其余数据库和 Classic 内存历史每 250ms 观察一次（同连接 total_changes、其他连接 data_version、现有历史供应者），变动后通知。通知可能合并同一观察窗口或因缓存落盘多一次，不承诺每条领域事件一条通知。后台任务变化与轻量缓存投影无网络请求；首次作品/剧集读取可能等待图片下载。

Debug 且临时 profile 才注册 `ext.nipaplay.uiData`，供实验读同一界面接口、采样流、模拟会话边界、触发真实 hook 和通过正常保险库写入固定测试文件。该入口不在 Agent 能力目录，不在生产启用。
