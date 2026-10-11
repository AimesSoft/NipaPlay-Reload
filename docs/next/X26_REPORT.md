# X26：Next 界面数据与 Agent 摆放

2026-10-11，证据时间均为 UTC。worktree `~/Desktop/nipaplay-next-wt/ui-data`，分支 `next/ui-data`。

已读 TEAM、RESEARCH、X22、X23、X25。本 worktree 没有视觉提案目录，因此只读主仓库的 INTERACTION，并通过回环只读 HTTP 服务在浏览器打开 concept.html。没有在主仓库构建，没有启动安装的 NipaPlay，没有访问登录钥匙串或正常应用数据，没有 commit、push、pub get 或依赖变更。

## 1. 完成了什么

- `core.uiData` 实现 `NextUiData`；原 `ui_data.dart` 完全未改。界面直接读取 home/work/episodes/cards，订阅 changes/tasks，不解析 Action envelope。
- 首页包含自动或 Agent 主视觉、现有历史的继续观看、Agent 书架、最近添加；集号和剩余时间生成自然短句。
- TMDB 背景、海报、片名 Logo、剧集截图下载为本地文件，解码后原子发布；背景主色为 ARGB tint。图片 URL 和扩充元数据追加到现有来源快照，保险库与 MetadataTransport 复用原基础设施。支持 API key 和 Bearer 读取令牌。没有对应身份或 TMDB 凭据时图片缺省为 null；非 TMDB 使用已有来源的 imageUrl。
- 每集已有弹幕按全部有效来源缓存合计，生成 60 桶的 0..1 热度，绑定、内容、偏移、时长或剧集范围改变后失效重算。
- `ui.present` 把五种接口卡片追加到 NIPAPLAY_CHAT 对应的当前回合；整批验证对象引用，存引用和短句，读取时解析实时任务/后续状态。不存在的引用返回写法明确的错误。
- `ui.shelves.put` 摆放 hero/书架，空列表移除；`ui.shelves.remove` 与 `core.uiData.removeShelf` 支持移除一项或整处摆放。用户移除记入 activity，保留自然标题、用户来源及实际移除的作品；不会删除作品、任务或历史。
- 种子 AGENTS.md 只补了一条关于 ui.present/ui.shelves.put 及观众文字的事实。
- SQLite v11 只追加 presentations、shelves、cache 三张表；v0–v10 升级与旧数据保留纳入约束检查。

界面接入、输入示例及状态映射见 [ui_data/README.md](../../lib/next/ui_data/README.md)。

## 2. 决策

**图片属于来源快照，本地文件属于可删除的投影。** 作品/发行身份沿用原来的 contains，单集沿用 exact，不创造身份。TMDB 优先选语言为空的背景；Logo 按中文、日文、英文、中性图选择。没有 TMDB 身份才使用已有来源的图片；不根据标题猜测另一个 TMDB 对象。缓存按 URL 哈希命名，并检查当前身份与快照指纹、文件存在性。tint 将背景缩到 64 像素宽，取最多 RGB 色箱的平均色。首次作品/剧集读取可能等待下载，没有额外刷新期限或下载编排规则。

**元数据与显示文案分开。** 作品资料保留已收到的来源值和用户编辑；任务标题由任务类型和关联作品生成，不转发原始任务标题、路径、错误、日志或回执。Agent 文字要求一行、最多 160 字符，并拒绝明显的 ID、路径、URL 和调试信息；种子和 schema 明确它是给观众看的短句。标识只放在引用字段。没有可靠的剩余时间估计时 UiTask.remaining 为 null。

**卡片不复制状态。** taskId 使用真正的 jobId；preparation 的每一步恰好绑定 taskId、entityId 或 followupId。实体步骤表示作品/剧集已经找到；任务和后续实时决定进度与状态。当前接口没有 cancelled，因此取消映射为 failed；等待决定/中断映射为 paused，等待重试为 queued。后续 completed 只表示该回合结束，沿用 X25 的语义。ui.present 根据现有 journal 的最新会话回合边界定位，不另存对话正文；无活动回合报错。

**首页采用已有事实。** Agent hero 最优先。自动 hero 先取最近成功任务关联的可播放作品，再取最近本机可播放入库（无任务历史时的准备事实），之后是继续观看作品的可播放新集，最后是继续观看首部；自动 hero 没有 note。继续观看直接用 history.continue_watching，历史供应者未接入时不制造记录。最近添加取首次入库顺序倒序，最多二十部。书架项的 note 优先作为 caption，否则生成集号/剩余时间。摆放和单项移除经现有媒体 mutation 串行，移除保留其他项。

**热度统计保留各来源的数量。** 当前有效绑定的缓存都计入，播放时关掉的轨道也属于“已有弹幕”。同一缓存、时间范围、偏移只计一次，各来源内部沿用原缓存去重；不同来源不做文本相似度合并。文件弹幕按明确的剧集范围裁剪；多集文件没有时间范围就不猜。无弹幕为 null；无时长时以最后弹幕时间作为统计跨度。缓存保存归一化值和指纹，不复制弹幕正文。

**推送是重新读取的通知。** 任务提交/状态/进度/回执变化即时发 changes，再发完整 UiTask 列表；没有 tasks 订阅者时不做这份投影。其他数据库和 Classic 内存历史每 250ms 观察一次：同连接 total_changes、其他连接 data_version、已有历史供应者。书架和卡片成功落盘立即通知。一次窗口内的变化可能合并，缓存落盘或随后观察可能多通知一次，不把它当成逐事件总账。领域事实继续归 activity。

## 3. 实验与真实输出

### 实例与证据

直接执行本 worktree 的 Debug 可执行文件，最终 profile 为 `x26-ui-18837`。VM getVM.pid 与 subprocess PID 都为 **18838**。回环请求绕开代理；TMDB API 与图片通过应用原有系统代理机制，启动环境使用 Clash `http://127.0.0.1:7897`。

实验 Debug 扩展只在临时 profile 注册，不在 Agent 能力目录：读取同一个进程内 UI 接口、记录两个流、模拟会话边界、触发真实 hook、写入实验观看历史。测试令牌从规定的 0600 文件读入内存，通过 `core.credentialVault.write` 写入实验文件保险库，结果只返回 `configured:true`。没有把令牌传进命令参数、写入报告或提交；最后在内存比较其原文，日志/证据中不存在。

完整逐次 `nipa` stdout、UI 返回、采样时间见 [operations.json](evidence/x26/operations.json) 与 [experiment.log](evidence/x26/experiment.log)。[UI_OUTPUT.md](evidence/x26/UI_OUTPUT.md) **完整贴出了 home/work/episodes/cards/heat/changes 返回的 JSON**，没有隐藏 null 或删掉引用字段；后面的 JSON 是其中选定字段的摘录。[实验脚本](evidence/x26/experiment.py) 可在同样的临时配置中复现。

### 两部真实作品与图片

先用 nipa 搜索，再使用实际返回的身份：TMDB TV **209867《葬送的芙莉莲》**与 **119100《孤独摇滚！》**。取得真实第一季目录，绑定各自前两集；没有用显示集号代替外部 episode ID。work() 的全作品集数分别返回 **38、12**，评分 **TMDB 8.8、8.4**，制作公司 **Madhouse、CloverWorks**。芙莉莲当前来源返回 38，未把视觉提案的 28 写成事实；本次仅绑定两集，不宣称已经导入全目录。

两个 work 的 backdrop/poster/logo 都是临时数据目录中实际存在的本地路径，四个 episode 的 still 也一样。图片已逐张打开：背景没有覆盖片名，两张海报与中文 Logo 对应正确；芙莉莲两集截图为石桥和花丛，孤独摇滚两集截图为后藤独及乐队成员。白色透明的孤独摇滚 Logo 另在浏览器中核对文字。[图片原样副本]（图片为 TMDB 资料，未入库）在删 profile 前复制，仅作为实验来源证据。

实际 tint：

```json
{"葬送的芙莉莲":4292327304,"孤独摇滚！":4294703862}
```

对应 `0xffd7b788`、`0xfffbfaf6`。media.metadata.snapshots 的实际输出包含这些对象的 artworkUrls、类型、集数、制作公司和评分，并保留 source=provider_snapshot、origin=application、抓取/收到时间；URL 经 nipa 原有脱敏显示，凭据未进入快照。

### 首页与观看进度

实验另外生成了 **26 分钟的蓝色静态视频**，通过正常 scan 与 bind_batch 关联第一集，用来观察时间轴，**它不是番剧视频，不把这个绑定说成内容识别正确**。通过 WatchHistoryProvider 的正常写入方法记录位置 17 分钟，再刷新原历史供应者。

home() 没有 Agent hero 时返回芙莉莲，note=null；继续观看书架返回真实 caption **“第 1 集 · 剩 9 分钟”**，episode.progress 为 **0.6538461538461539**，playable=true。其后最近添加顺序是孤独摇滚、芙莉莲。Agent 放 hero 后，note 变为 **“今晚一起走进芙莉莲的旅途。”**；书架“适合今晚”的孤独摇滚 caption 为 **“听一场热闹的演出。”**。完整结果在上述 UI_OUTPUT。

### 弹幕合计与失效

给芙莉莲第一集先交入 4 条 bilibili 测试弹幕，再交入 3 条 youku 测试弹幕，最后以 5 条刷新原 bilibili 轨道。所有导入都经 `nipa call danmaku.import`，不手写绑定或缓存。

三次 heat 的前 3 桶实际为：

```json
{"首次":[1.0,0.5,0.5],"合计两个来源":[1.0,0.3333333333333333,1.0],"刷新原来源后":[1.0,0.0,0.6]}
```

每次都返回完整 **60 桶**，其余桶为 0.0，范围为 0..1；完整数组已贴在 UI_OUTPUT。刷新后 bilibili 条数从 4 变 5，youku 的 3 条仍在，热度重算；没有将原 4 条继续累加成旧内容。

### 当前回合卡片与实时任务

经 nipa 调用 ui.shelves.put，再模拟 `x26-session / x26-thread / x26-turn` 的已有回合边界，设置 NIPAPLAY_CHAT 调用 ui.present。实际返回：

```json
{"status":"completed","result":{"presentationId":1,"threadId":"x26-thread","turnId":"x26-turn","count":5}}
```

五张分别是作品、剧集、候选、准备、任务。候选理由为“想听音乐的时候看。”。后台引用的是应用实际运行的 `hooks/playback.started`：程序读取输入，等待 12 秒，正常退出并产生 verified 回执；**只模拟会话号，没有模拟任务终态**。

cards() 两次读取的同一准备步骤摘录：

```json
{"label":"整理好了","state":"running","detail":null,"progress":null}
{"label":"整理好了","state":"done","detail":null,"progress":1.0}
```

同一 task 卡片从 `state:running,progress:null` 变为 `state:finished,progress:1.0`，标题是“处理后续”，没有显示 Hook 原始任务标题或任务号。没有再次调用 ui.present；变化来自任务事实。无效作品与任务的实际错误分别指导使用 library.works 的本地 id、task.list/task.get 的 jobId。

### 推送与移除

最终采样：

| 操作阶段 | changes 条数 | tasks 快照数 | 首次→末次 UTC |
|---|---:|---:|---|
| 绑定、扫描、观看历史、图片、弹幕 | 24 | 7 | 16:33:57.151391 → 16:34:18.400516 |
| 书架、卡片、hook 运行至完成 | 12 | 5 | 16:34:18.650184 → 16:34:31.400170 |
| GUI 移除和 hero 清空 | 3 | 0 | 16:34:31.519744 → 16:34:31.743567 |

完整流包含每次 UTC 时间及 tasks 全列表，已贴在 UI_OUTPUT。任务进入终态时两条流都有输出；GUI 移除落盘时间为 `16:34:31.518900Z`，首次通知为 `16:34:31.519744Z`。轮询通知与立即通知会重复，不用通知数量当领域事件数量。

GUI 移除后，书架消失；随后仅查询 activity，实际记录：

```json
{"type":"ui.shelf_removed","title":"已从首页移除","actor":"user","origin":"gui","subjectId":"tonight"}
```

原始记录保留 before、after=null、实际移除作品的 entityIds，warnings=[]。书架移除没有删除作品/剧集。另有数据约束测试守住“从两项书架只移除一项时，另一项与移除动态仍正确”。

### 意外、修复与范围

1. 初次预填孤独摇滚的 ID 不正确，真实搜索返回 119100，脚本停止并清理；改用真实返回重跑。[attempt1](evidence/x26/attempt1-operations.json)。
2. 图片缓存清理回调返回了自身 Future，形成自等待，使 home/cards 不结束；改为 void 清理。约束检查中的持久卡片读取和真实实例均观察到修正后的正常返回。[attempt2](evidence/x26/attempt2.log)、[attempt3](evidence/x26/attempt3.log)。中止第三次时，VM 连接重置曾提前打断 finally；随后按已记录 PID 核实它已退出，并删除那一个 profile，[补充清理](evidence/x26/attempt3-cleanup.json)。最终脚本同时处理连接重置。
3. 首次图片实验只得到了剧集截图：我把作品 contains 关系误当成没有身份。按原模型接入后，背景、海报、Logo、tint 和作品扩充元数据全部取得。[原输出](evidence/x26/attempt4-operations.json)。
4. 补充历史实验最初走 WatchHistoryManager 的旧 JSON 写入分支，Provider 读取中没有该进度；改为原 WatchHistoryProvider 的正常写入方法，最终得到继续观看和剩 9 分钟。没有改 Classic 的历史行为。[原输出](evidence/x26/attempt5-operations.json)。
5. 一轮同时启动两个 Flutter test 进程出现测试宿主回环连接提前关闭，结果不算通过；最终去掉测试启动环境代理，串行重跑全量 Next 与 Classic 回归，均通过。

启动日志仍有原来的 audioplayers/universal_gamepad MissingPluginException，未在本任务修改插件或隐去日志。本次实测为 macOS，卡片会话关联采用允许的模拟边界；未把它说成真实 Agent 对话或新界面交互验证。Bangumi 等 fallback 沿用已有来源字段，本轮未增加其线上图片实验。

### 检查与清理

初次构建缺 package_graph 和 Flutter 派生 Swift Package/.packages，只读复制同 lock 的 sibling worktree 生成输入并重定位；没有解析依赖。Flutter 使用固定 3.44.6、全部带 --no-pub，构建设置 ERIKA_PREBUILT_CACHE_DIR。CocoaPods 自动改写 Erika lock 后已还原，最终无依赖文件差异。

```text
flutter build macos --debug --no-pub
✓ Built build/macos/Build/Products/Debug/NipaPlay.app

flutter test --no-pub test/next --reporter expanded
01:33 +399 ~4: All tests passed!

flutter test --no-pub <相关 Classic 元数据、代理、退出测试> --reporter expanded
00:00 +14: All tests passed!
```

[build](evidence/x26/build.log)、[完整 Next 测试](evidence/x26/all-next.log)、[Classic 回归](evidence/x26/classic.log)、[analyze](evidence/x26/analyze.log)。analyze 无 error/warning，保留两条花括号风格 info。约束检查覆盖整批引用失败不写入、不接受伪造状态、书架移除不丢其他项、卡片重开不丢来源引用或任务回执，以及旧版本迁移；功能成立依据以上真实实例输出。

所有七个实验 App PID 均不存在、profile 均删除：[cleanup.json](evidence/x26/cleanup.json)。最终 PID 18838 退出码 -15，profileRemoved=true。实验保险库、合成视频、历史、数据库、harness 和协议日志随 profile 删除。只保留脱敏证据、下载图片的证据副本和本 worktree 构建产物；只读提案服务与图片预览服务及浏览器也已退出。git diff --check 通过，原接口无差异，未 commit/push。

## 4. 问题

需要主控决定的问题：没有。
