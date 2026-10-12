# X35：新媒体到完整作品的身体断点

2026-10-12，worktree `~/Desktop/nipaplay-next-wt/x35-pipeline`，分支 `next/x35-pipeline`。证据时间为 UTC。阅读了 TEAM、RESEARCH、实验 11、X34 报告、种子「NipaPlay 的构成」和主控的系统清单。

## 1. 完成了什么

- Next 可以访问成功下载回执验证过的单个本地文件，即使下载目录不是片库根目录；文件绑定到剧集后可以出现在 Next 播放入口。下载目录仍不自动加入扫描根目录。
- 下载入库回读返回 Next `fileId/workIds`，完成回执汇总 `fileIds/workIds`。任务的界面关联读取作品 ID，也可以通过文件的当前剧集对应找到后来绑定的作品；回执仍是当时的快照。
- 已有 `imageUrl` 不再因存在 TMDB 身份而隐藏；TMDB 取图缺少某个角色时，也保留已保存的角色图片。显式图片覆盖仍优先。没有凭据不会自动请求 TMDB。
- Classic 同步保留已有详情缓存中的标题语言、简介、海报、背景、类型和集数，记录 `classic_cache` 来源；缓存改变不撤销匹配、不覆盖 Next 的显式编辑、不重复保存同一缓存快照。
- Next 索引与文件枚举支持指向授权根目录内视频文件的符号链接；不递归跟随目录链接。
- 真实下载后的绑定暴露了 Classic 投影标题读取断点，一并修复：读取两种快照结构；新文件可使用已有的识别/缓存标题，有 Classic 观察的文件仍保留原有名称保护。
- 种子仅修改「NipaPlay 的构成」中的对应事实；没有编排识别、翻译、选图或弹幕流程。没有修改 `lib/next/ui/`、聊天模块、UiTask 契约或 X36 的工具。

## 2. 决策及理由

**下载的授权属于经过验证的文件，不属于整个目录。** 原来的 Classic 完成扫描特意不把共享下载目录设为根目录，避免把其他未完成的下载纳入扫描。这条事实保留。Next 根据持久成功回执、完成状态、选中标记、大小验证和规范路径开放单个文件；回执没有验证的邻居、未选中的文件和目录不随之开放。文件不存在时仍不可访问。没有新增数据库版本或重写历史任务。

**身份和文件关联是独立事实。** 已下载的本地视频可以先登记为文件，识别待定不阻塞下载成功。已有 Classic 对应继续同步；没有身份就不虚构作品。下载回执列出当时已有的作品，界面通过回执中的文件 ID 跟随后来的绑定。这是数据连接，不是自动识别流水线。

**已有图片应当可见，但图片角色不能靠猜。** `imageUrl` 没有横版背景或透明 Logo 的语义，因此仍在作品上作为海报、在集上作为截图。保存的 `artworkUrls` 则按各自角色读取；不用自动裁剪、放大或把海报改称背景。缺背景时继续使用 X34 的海报替补和海报主色。翻译、选图和补齐其他角色留给 Agent。

**Classic 已有缓存应保留，缺失资料仍是缺失事实。** 同步只读现有内存/设置缓存，不调用详情抓取，不回写 Classic 缓存。未缓存的作品仍只有识别标题，语言为 `und`；这条限制如实写进种子。缓存快照使用内容身份去重，资料变化与匹配观察分开。Next 关闭时不运行这些 Next 适配器，Classic 原有下载、扫描和缓存代码没有改动。

**新文件的标题来自它明确绑定的已有剧集。** 两种快照结构都必须能读。对还没有 Classic 观察的新文件，已经绑定的作品/剧集标题可以用于投影；已有 Classic 观察时仍不拿 Classic 快照重新解释其名称。这个修复让已有事实能够交付，不增加检索或判断步骤。

## 3. 实验与真实输出

### 隔离、材料与证据

只运行本 worktree 的 Debug 可执行文件，使用临时 `NIPAPLAY_PROFILE`，签名通过 `codesign --verify --deep --strict`。配置中的 `CODEX_HOME`、认证副本、公共 CA 副本和 `NO_PROXY` 按 X23 设置；模型为 `deepseek-v4.1-flash`。保持默认安静，没有激活窗口、像素点击、按应用名查找或启动安装的应用，没有访问登录钥匙串或真实应用数据。

Classic 对照是一段实验者生成并以 CC0 提供的两秒蓝色色卡，2,962 字节，配合明确标注为合成的 Classic 历史和详情缓存。海报使用公开图片作为缓存读取的测试输入，不声称它是色卡的真实海报或 TMDB 匹配。临时 HTTP tracker 与 BT peer 只监听回环地址；下载由应用真实的 librqbit 执行。该实验验证内置下载、验证、回执与入库连接，不验证公网种子的可用性。

新媒体材料为只读挂载 `/Volumes/Media/长安十二时辰`。把它和临时 `data/incoming` 加为实验根目录，在 incoming 先放第 1 集的符号链接，隔三秒加入第 2、3 集；没有向卷写入或复制这些视频。没有另建 SMB 容器：本轮断点在本地索引、回执和元数据投影，未声明测试 NipaPlay 的 SMB 客户端。

原始输出按阶段保存在 [evidence/x35](evidence/x35/)：`before/operations.json`、`after/operations.json`、`done/operations.json` 与 `agent/operations.json.gz` 是主要证据；其他目录保留失败与中断。脚本为 [experiment.py](evidence/x35/experiment.py)、[local_seed.py](evidence/x35/local_seed.py) 和 [resume.py](evidence/x35/resume.py)。

### 1：下载目录外的已知文件，修复前确实不可播放

`before` 实例里，色卡文件实际存在，Classic 已识别并同步了文件与剧集；没有片库根目录。真实输出摘录：

```json
{"source":"local","available":true,"locator":null}
```

同进程 `NextUiData.work`：

```json
{"number":1,"title":"第1集","runtimeMs":2000,"playable":false}
```

修复后，`done` 中真实下载 `delivered-cc0.mp4`，回执验证大小相等、完成、被选中，未设下载目录为根目录；通过正常 `bind_batch` 绑定到已有剧集后：

```json
{"next":{"number":1,"title":"第1集","playable":true}}
```

这是界面同源数据的播放可用性验证，没有在用户桌面实际开启播放器。实际解码/音视频播放不在本轮声明内。

### 2：下载回执现在能关联作品，也能保留识别待定文件

修复前的回执缺少 Next 关联由原 `_receipt` 和 Classic `lookup` 的实际代码结构确认；没有再启动旧构建重复一次 BT 传输。修复后的真实内置 BT 传输输出，见 `done/download-completed`：

```json
{"downloadComplete":true,"files":[{"expectedSize":2962,"actualSize":2962,"local":true,"included":true,"imported":true,"identificationPending":true,"reason":"not_identified"}],"fileIds":["file-42718880-fc94-4d96-82ce-c5ec89fce31f"],"workIds":[]}
```

没有身份时，空 `workIds` 是事实；同一个文件随后绑定成功，`download-ui-home` 已通过回执文件找到作品并作为可播放的首页 hero。

另一个任务对合成 Classic 已识别的同内容文件执行原生 torrent 完成校验。它的文件事先已在输出目录，因此这一项是现有文件校验/关联实验，不是第二次网络传输。真实回执见 `agent/known-work-download-completed`：

```json
{"downloadComplete":true,"fileIds":["file-77505f50-cfbb-4359-a93b-d18290be846b"],"workIds":["work-5d25b666fd92ec1fa35aa869a5f0f805c4ed45df5c9f1fd4ebc4668d49e2c61e"]}
```

[下载准备好后的截图](evidence/x35/agent/download-ready.jpg) 已显示缓存简介、海报替补背景、最近添加卡片与“播放第 1 集”。人工打开并核对了这张 JPG。

### 3：TMDB 身份不能隐藏已有来源图片

同一合成作品先只有弹弹play 身份，再显式加入 TMDB 身份，没有配置 TMDB 凭据；向已绑定的来源交入公开 `imageUrl`。`before` 的第二次 `ui_facts`：

```json
{"poster":{"available":false,"path":null},"heroImage":null,"tint":null}
```

`after` 的相同角色对照：

```json
{"poster":{"available":true},"backdrop":{"available":false},"heroImage":"poster","tint":4294901502}
```

保留已有海报，未虚构背景。角色化 `artworkUrls` 和显式覆盖本来已受 X34 支持，因此“有 TMDB 身份而没有凭据时一张图都没有”并不适用于所有保存方式；本轮确认并修复的是 `imageUrl` 被 TMDB 身份阻断的路径。

### 4：Classic 已缓存资料同步时不再丢失

`before` 的详情缓存明明有中文标题、简介和图，而 `ui_facts` 返回：

```json
{"title":{"language":"und"},"overview":{"available":false,"value":null},"poster":{"available":false}}
```

`after` 无需资料刷新便返回：

```json
{"title":{"language":"zh-CN"},"overview":{"available":true,"value":"实验者生成并以 CC0 提供的两秒蓝色色卡。","language":"zh-CN"},"poster":{"available":true}}
```

来源为 `classic_cache`；同一缓存再次同步不增加快照，缓存更新不撤销绑定，显式简介覆盖仍保留，约束测试已验证。没有自动抓取未缓存资料。

### 新挂上的片库与陆续出现的文件

`agent` 中两个真实扫描回执依次为：

```json
{"verification":"verified","details":{"indexed":1,"fileIds":["file-3f6d2faa-38e2-4129-9cf4-bee86c46d5e3"]}}
```

```json
{"verification":"verified","details":{"indexed":3,"fileIds":["file-263b876f-c35b-4142-bddf-45c5f170da5c","file-3f6d2faa-38e2-4129-9cf4-bee86c46d5e3","file-f6bf8f92-ecf4-473a-a412-fb0b479d57b2"]}}
```

`state.query library.files` 给出规范的 `/Volumes/Media/...S01E01/02/03...mp4` 位置，`available:true`，但三行的 `episodeId/workId` 均为 null。此时只完成文件索引；作品身份、剧集对应、资料、图片、弹幕仍缺，界面不会因此虚构《长安十二时辰》卡片。

### 真实 DeepSeek 回合

首次自然语言输入为“《长安十二时辰》放进来了，帮我整理一下，弄好看点。”，附隔离边界，没有提供整理步骤。它读取状态、能力目录和文件相关事实；原回合在 113 秒观察点仍有内容输出。主执行工具随后随上游满载中断，应用进程也结束，临时配置及原 Codex 线程保留。

按用户“不要重复已经有证据的实验”的要求，续接脚本只启动同一配置、恢复同一线程，发送“继续刚才的整理。”，不重新下载或扫描。

续接使用同一 profile、同一线程、模型 `deepseek-v4.1-flash`。观察从 **2026-10-12 07:20:08 UTC** 到 **07:30:08 UTC**，600.17 秒后由实验 watchdog 中止；未收到 Agent 的完成答复。原回合与续接回合分别留有 20、48 条命令记录。原回合的 113 秒只是一次观察点，不能把它当作原回合完整耗时或与续接相加冒充连续完成时间。

她使用了这些事实：片库根目录已授权、目录有 48 集视频和 48 个 XML、文件名包含 S01E01–48、弹弹play 未登录、TMDB 凭据不可用、Bangumi 公开条目 `285493` 为这部三次元作品且有 48 集分集资料、本地 XML 声明 `chatserver=youku` 与逐集 `chatid`。她自行调用整根目录扫描，随后取得 Bangumi 资料并批量绑定作品、季、集和文件。操作者没有替她填写《长安十二时辰》的身份或元数据。

最终 `state.query library.files` 有 49 行：合成下载文件 1 行，归于《长安十二时辰》且 `available:true` 的文件 **48 行**。最终 `media.metadata.ui_facts` 的摘要如下，逐字段来源与全部剧集在 `agent/operations.json.gz`，便于复核的计数在 [summary.json](evidence/x35/agent/summary.json)：

```json
{"title":"长安十二时辰","titleLanguage":"zh-CN","overview":true,"year":true,"episodeCount":48,"episodeTitles":48,"episodeStills":0,"poster":true,"backdrop":false,"logo":false,"genres":false,"studio":false,"ratings":false,"heroImage":"poster","tint":4278452756}
```

首页数据的 `hero.next.playable:true`，下一集标题为“狼卫入城长安暗流汹涌”。`hero.work.danmaku` 仍为空，轨迹没有成功导入弹幕的调用。48 个文件的对应关系和可用位置已成立；本实验没有实际打开播放器逐集播放，不能把数据层可播放等同于逐集解码验收。

最终截图通过 **07:30:12 UTC 的 `ui.capture`** 获取并转 JPG：[当前整理结果](evidence/x35/agent/result.jpg)。已打开核对：主视觉显示《长安十二时辰》、2019、48 集、中文简介、“播放第 1 集”，最近添加卡片显示海报。主视觉使用海报替补；Agent 的最后一句仍是“写一个可复用的截图抽取脚本。”，没有冒充任务完成。

卡点按任务要求分开判读：

- **身体断点**：本轮已修复下载文件授权、任务到作品关联、已有图片隐藏、Classic 缓存丢失和标题投影错误。真实整理到批量绑定时未再出现这些错误。整根目录 `media.files.list` 两次各约 65 秒返回泛化的连接错误；第三次约 19.73 秒取得 48 行。轨迹只能证明工具调用超时/连接错误与重试，不能证明应用真的重启。根目录枚举/扫描会探测媒体，读取 SMB 挂载有成本；这里没有据泛化错误另改 X36 的工具或聊天代码。
- **事实不清**：Agent 把 `media.files.list` 当作取得完整清单的入口，在扫描后再次探测全目录。种子补充“扫描和按根目录枚举会计算头部哈希、探测时长；`state.query` 读已有索引”的事实。此补充来自本轮观察，加入于回合之后，没有重跑实验来声称它已改善 Agent 行为。
- **Agent 判断与执行**：她整批遍历 XML 读取来源/条数耗时 **117.62 秒**；多次尝试受实验写入边界限制的 `/tmp`/heredoc，再改在 harness 内用 `python -c`。截图脚本首次受引号嵌套影响报语法错，之后用 `printf` 写成并通过语法检查。中止时正在并发抽帧，没有截图导入完成证据。她先研究优酷 ID 解码、再准备截图和额外资料，尚未导入已有 XML；这属于本轮的取舍与执行结果，未用代码替她规定处理顺序。

截至上限，作品身份、48 集对应、中文资料、年份、海报与首页入口已成立；类型、制作公司、评分、横版背景、Logo、48 集截图、弹幕及字幕没有完成。Bangumi 的原始响应已有部分额外资料，但没有交入界面事实，仍显示缺失。结果是“能看到并进入播放”的阶段成果，**不是完整作品全部补齐的成功回合**。

实验脚本按进程号关闭 PID `96060`，`cleanup` 回执为 `profileRemoved:true`。收尾检查没有 X35 profile 目录或携带这些 profile 路径的存活进程。没有触碰 ui-demo 或主控实例。

### 验证与失败

- 相关下载、身份与界面约束测试：58 项通过；新增下载边界与缓存约束：2 项通过；最终缓存/投影相关组合：3 项通过。
- 按 TEAM 排队、去除代理的完整 `flutter test --no-pub test/next` 只运行一次，**440 项通过、4 项跳过**，耗时 1 分 51 秒。Classic 投影相关检查和 Classic 详情缓存不变检查也在该套件中通过。
- 最终 Debug 构建（包含最后的种子事实补充）成功，签名验证通过；最终构建后没有重跑媒体或对话实验。构建、签名、analyze 和完整测试末段输出保存在 [verification](evidence/x35/verification/)。analyze 的已有 `ui_data/service.dart` 单行 for 花括号提示与本轮无关；没有依赖修改。构建自动重写的 Podfile.lock 已恢复；保留用户允许忽略的 GeneratedPluginRegistrant 改动。
- 实验脚本曾遗漏 `reason/requestId`、误读 task.get 的包裹层、使用 21 字节 peer ID、把返回的 server tuple 当 list。这些是实验脚本错误，失败输出保留；修正后只继续受影响的阶段。下载后的绑定则暴露了真实标题投影断点，修复后真实绑定与界面关联成功。
- 上游满载中断不作为身体能力失败；续接因观察上限中止单独记录。已完成的下载和扫描证据保留，未重跑。原始对话过程记录只属于这些临时配置。最终证据检查对照 4 个当前配置的秘密值并检查令牌/私钥/带认证 URL 模式，匹配数为 0；检查输出只保存计数。

## 4. 问题

需要主控决定的问题：没有。

未把作品自动补齐做成流水线；无身份的文件、未缓存资料、翻译、来源检索、背景/Logo/每集截图、弹幕和字幕仍各自有缺失事实与工具入口。本轮真实整理回合在观察上限前只完成了部分组合，缺失项与最终界面结果已在上文逐项记录。
