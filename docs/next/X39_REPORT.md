# X39：同名弹幕成为身体的文件事实

2026-10-12。实现与构建位于 `next/x39-sidecar-danmaku` worktree；没有 commit、push、新依赖或 `lib/next/ui/` 改动。本文对应实验 14 的后续实现与对比观察。实验脚本为 [x39_experiment.py](../../scripts/next/x39_experiment.py)；X35 的实际参考脚本是 `docs/next/evidence/x35/experiment.py`，任务书所列 `scripts/next/x35_experiment.py` 在本 worktree 不存在。

## 1. 完成了什么

本地视频进入身份索引时，身体会异步发现相邻 XML/JSON，将最先可解析的候选记为这个文件的一条弹幕轨道。记录包含本地来源、声明的平台与原视频号、路径、文件大小和修改时间、弹幕条数、读取时间及读取耗时。自动轨道引用原文件，不向弹幕内容缓存复制文本；文件变化会重读，缺失或不可解析时保留上次事实并标记不可用。

扫描、下载入库、文件新增共用文件注册事件；已有索引在启动时及后台周期检查时也会被核对。数据库版本由 13 升至 14，只添加可空的 `danmaku_bindings.local_file` 字段，已有绑定和缓存保持原语义。

热度、主视觉评论、`danmaku.bindings`、`danmaku.tracks`、播放器和 `media.metadata.ui_facts` 使用这份绑定。`ui_facts` 新增每集 `danmaku.available / tracks / count` 与作品总覆盖 `episodes.danmaku`。每条轨道包含平台、原视频号、条数及本地文件事实；`playback.tracks` 可以看到已管理的弹幕轨道及对应 `bindingId`。

Classic 的文件名候选规则已提取共用。Next 接入播放器时替换本地自动加载入口，加载身体已记录的轨道，避免 Classic 再独立加载同一文件；脱离 Next 时清除回调。Next 关闭时仍按原来的设置、排序和候选解析流程工作。

播放时 Classic 自动匹配到的远程弹幕也纳入本批：复用已经取到的 Classic 原始缓存，作为 `automatic / playback` 写回 Next，保留条目实际声明的来源、原视频号，并复用当前播放器轨道。没有增加远程请求或第二套弹弹play 客户端。下一次播放与其他读取者因此能见到缓存记录。

种子只修改了要求的两处弹幕事实：「你的工作」说明身体自动记录同名弹幕；「一部完整的作品」说明同名与播放时自动取得的弹幕成为记录，缺失仍以事实呈现。新增行为也写入 [danmaku README](../../lib/next/danmaku/README.md)。

## 2. 决策

- **文件引用与统计分开。** 自动发现保存引用与时间分布计数，热度无需再次开 XML；主视觉和播放按需读原文件，进程内最多缓存四个文件的解析条目。原文件不存在时不冒充仍有可播放弹幕。已有 `danmaku.import` 继续保存用户明确交入的快照；同一路径的显式导入替换自动引用，后台不再叠加第二条池。
- **后台单读取者。** 文件注册只入队，扫描不等待弹幕内容。解析放在 Isolate；同一文件正在读时共享 Future。启动核对与每 30 秒核对覆盖外部改动；大小、修改时间及实体版本相同则跳过内容读取。读取前后 stat 不一致时不提交混合版本。此轮未测数千文件规模；周期目录核对仍有 SMB 元数据 I/O，单队列限制的是内容读取并发。
- **保持 Classic 的精确选择规则。** 同名 100 分、前缀 80、包含 60；弹幕关键词加 20，XML 加 3，最多尝试 8 个，分数相同按原文件名排序。包括“不相干 XML 也可能因加 3 分进入候选”的既有语义。本轮没有为了更严格的同名定义改变 Classic。
- **不解码或猜测平台身份。** 优酷 `chatserver/chatid`、B 站声明及 JSON 条目来源按现有解析器处理，原视频号原样记录；没有用猜测把 unknown 变成某个平台。
- **远程播放回写属于同一份真相。** 用户设置已经授权 Classic 自动取得弹幕，记录实际取得的池是身体记事实。回写复用播放器轨道，不重新安装同一池；没有实际来源字段时继续保留 unknown。
- **不编排整理步骤。** 自动发现是文件事实；作品检索、身份绑定、资料与视觉取舍仍由 Nipa 自己完成。没有新增整理流水线或指导性提示。

## 3. 实验

### 身体：48 条轨道、覆盖、热度和实际播放

只读来源为 `/Volumes/Media/长安十二时辰` 下的真实 48 集视频及各自相邻优酷 XML。完整轨道记录见 [48-tracks.json](evidence/x39/body/48-tracks.json)，便于逐行核对的路径、绑定 ID、来源、条数及读取时间见 [48-tracks.tsv](evidence/x39/body/48-tracks.tsv)。这组来自独立播放观察配置的索引快照；原扫描配置记录也保存在 [body/operations.json](evidence/x39/body/operations.json.gz)。两组都为 **48 条可用本地轨道、平台 youku，共 699,214 条弹幕**。它们属于不同临时配置，文件实体 ID 不要求相同。

读取与扫描分阶段记录，不能把中间调试间隔当成正常扫描耗时：

| 阶段 | 真实输出 | 含义 |
|---|---:|---|
| 初次完整视频扫描 | 100.176345 秒 | 48 个视频的扫描回执；后台弹幕不是扫描的等待条件 |
| 修复队列后重启续读至 48 条可用 | 14.428823 秒 | 复用已扫描配置，没有重扫视频 |
| 该配置记录的读取耗时总和 | 13,755 毫秒 | 每个文件实际解析计时相加，非整轮墙钟时间 |
| 独立播放观察配置识别已存在的 48 条 | 0.112653 秒 | 复用另一个本轮实验实例的只读索引快照；不是重新读取 48 个 XML 的速度 |
| 观察配置中既有读取耗时总和 | 17,141 毫秒 | 来自被复制索引的原读取记录 |
| 观察配置的 48 集身份绑定 | 187.458114 秒 | 另外的身份验证/绑定成本，不属于弹幕读取 |

初次脚本误以为视频直接位于根目录，设置阶段失败，尚未扫描。之后完整扫描成功，但 `_reads.whenComplete` 的表达式返回了刚移除的自身 Future，形成自等待，队列停在第一条。修正为不返回该 Future 的语句块，保留原扫描成果、只续读缺失轨道。再往后，身体观察脚本的目录检索没有找到电视剧：现有 Bangumi 搜索带动画 `type=2` 限制。失败、重启与清理回执均保留，没有将失败抹去。

为避免重复扫描及再次读取 48 个 XML，播放观察配置从本轮尚在运行的 `x39-agent-41072` 实验实例取得 SQLite 的只读 backup 与设备身份，在副本里移除活动任务及 incoming 位置；没有修改对话实例。该快照已具有 48 条同名弹幕事实。观察者仅在独立配置中使用 X35 已验证的 Bangumi subject `285493`，补齐身体观察所需的身份关联；没有给 Nipa 提示或替她执行任何整理步骤。详情见 [body-projection/operations.json](evidence/x39/body-projection/operations.json.gz)。

[作品 ui_facts](evidence/x39/body/ui-facts.json) 的集覆盖输出：

```json
{"episodes":{"total":48,"titles":48,"stills":0,"danmaku":48}}
```

这是播放观察时的快照，截图尚未完成；对话最终结果的 48 张截图另见后文。每集的轨道、平台、条数均在该 JSON 的 `episodes.items[].danmaku` 中。第 1 集的事实摘要：

```json
{"source":"local","platform":"youku","platformVideoId":"XNDI0NDYyNjk1Mg==","count":16203,"available":true,"readAt":"2026-10-12T14:37:36.229097Z","readMs":460}
```

通过 `playback.open` 在安静、音量为 0 的观察实例实际播放第 1 集，再查询 [playback.tracks](evidence/x39/body/playback-tracks.json)：1 个音轨、3 个内嵌字幕轨、**恰好 1 个弹幕轨**。弹幕轨的 ID 为 `next:danmaku-sidecar-c203d21624bf4f7148b4e70e4d476879e6a489afc434f06e9928b60b68d51c47`，`bindingId` 与 ui_facts 同条记录一致，`origin=sidecar`，条数 16,203。没有独立 Classic 本地池。

[播放截图](evidence/x39/body-projection/playing.jpg) 已打开核对：真实视频画面、播放状态、`00:00 / 47:02`，实例未抢前台。标题附近有既有 Debug 布局溢出标记，本轮未改界面代码。

热度使用同一组文件身份和绑定，由本轮实例的只读 `uiData episodes` 查询取证，见 [heat.json](evidence/x39/body/heat.json)：**48 集均有非空的 60 段热度**。第 1 集前 11 段为 `[0.861333, 0.544, 0.664, 0.744, 0.845333, 0.522667, 0.88, 0.634667, 0.672, 0.621333, 1.0]`。该投影的 `runtimeMs` 为 null，因此现有热度规则使用末条弹幕时间作为分段时长；这不是已经取得真实集时长的证据。

主视觉也来自记录中的弹幕：[hero-comments.json](evidence/x39/body/hero-comments.json) 取到了“2019年06月29日打卡~”“2019年07月03日举手~”“2019年07月04日打卡~”“周末举手~”“四川人民发来贺电”“坐标东北打卡”。这些文本是输出取证，不是向持久内容缓存复制了整份 XML。

### 附：48 集轨道条数

所有行均为 `source=local / platform=youku / available=true`；完整路径、原视频号、绑定 ID 和读取时间在上述 JSON/TSV。

| 集 | 条数 | 集 | 条数 | 集 | 条数 |
|---|---:|---|---:|---|---:|
| 01 | 16,203 | 17 | 17,366 | 33 | 13,200 |
| 02 | 17,089 | 18 | 14,091 | 34 | 14,011 |
| 03 | 13,371 | 19 | 15,043 | 35 | 14,243 |
| 04 | 14,043 | 20 | 16,925 | 36 | 13,810 |
| 05 | 12,458 | 21 | 13,604 | 37 | 15,103 |
| 06 | 15,652 | 22 | 14,525 | 38 | 16,577 |
| 07 | 12,936 | 23 | 16,236 | 39 | 14,681 |
| 08 | 14,323 | 24 | 12,146 | 40 | 14,348 |
| 09 | 14,605 | 25 | 14,858 | 41 | 15,367 |
| 10 | 15,149 | 26 | 13,341 | 42 | 15,513 |
| 11 | 14,339 | 27 | 14,777 | 43 | 17,198 |
| 12 | 14,957 | 28 | 13,957 | 44 | 14,170 |
| 13 | 15,893 | 29 | 13,347 | 45 | 14,984 |
| 14 | 11,953 | 30 | 13,156 | 46 | 14,596 |
| 15 | 13,372 | 31 | 12,573 | 47 | 14,427 |
| 16 | 17,661 | 32 | 14,042 | 48 | 12,995 |

### 对比：同一句话、DeepSeek、15 分钟

新临时配置 `x39-agent-41072`，模型 **deepseek-v4.1-flash**。原样发送：

> 《长安十二时辰》放进来了，帮我整理一下，弄好看点。

没有步骤、作品 ID 或动作顺序提示。隔离环境仅追加了用户要求的只读、安静、写入范围与秘密约束。参考 X35 放入三集 incoming 视频符号链接，并添加真实 48 集根目录；未引入 X35 的另一个合成下载 fixture。隔离 `CODEX_HOME`、公共 CA 副本与 `NO_PROXY` 沿用 X23 方法；没有改用户配置或访问登录钥匙串。

开始时间为 **2026-10-12 14:37:40.737689 UTC（当地 22:37:40）**，观察 **900.891693 秒** 后由 15 分钟 watchdog 中止，不是自然完成。完整动作、对话与截图保存在 [agent 证据目录](evidence/x39/agent/)，提炼结果见 [summary.json](evidence/x39/agent/summary.json)。

- **不再逐个读 XML。** 她枚举视频名称、查询已有索引与弹幕事实；没有解析 48 个 XML 或解优酷 chatid。唯一提到 XML/youku 的命令是把已有弹幕事实写入工具说明/笔记，不是源文件解析。
- **没有交给帮手。** `task.list(type=agent.helper)` 返回空，轨迹没有 native collaboration 调用。她自己写了 ThreadPoolExecutor/ffmpeg 并发抽帧；这是脚本并发，不能算派了 Agent 帮手。
- 完成 131 次命令执行、25 条 Agent 消息、81 个 reasoning item、19 次 imageView。命令 105 次 exit 0、26 次 exit 1，错误多见于 CLI 用法、heredoc 与引号拼接，不能把这些都归为身体能力失败。
- 最终 [ui-facts.json](evidence/x39/agent/ui-facts.json) 的 title、originalTitle、overview、year、genres、episodeCount、studio、ratings、backdrop、poster、logo 全部 `available=true`；`episodes={total:48,titles:48,stills:48,danmaku:48}`。**该 schema 检查的字段已没有缺项**，但这不证明所有截图质量、字幕与真实时长都已完成。

时间主要落在索引查询、作品绑定、资料提交和抽帧/视觉调整。下表为从用户消息起的近似墙钟位置，依据 [commands.json](evidence/x39/agent/commands.json)，不是将工具耗时强行分摊成整轮时间：

| 时间位置 | 观察 |
|---|---|
| 约 81 秒 | 提交真实 48 集扫描 |
| 约 197 秒 | 查询已有弹幕轨道事实 |
| 约 215 秒 | 创建作品/集身份结构 |
| 约 223–288 秒 | `library.files` 已有索引查询单次约 65.16 秒 |
| 约 304–322 秒 | 批量文件绑定，调用约 17.16 秒 |
| 约 335 秒 | 首次查询作品 ui_facts |
| 约 409–610 秒 | 写抽帧脚本、处理 heredoc/引号及后台会话问题，含显式 sleep；最终前台抽帧约 16.80 秒 |
| 约 654–678 秒 | 导入背景、Logo、每集截图，核对覆盖并固定主视觉 |
| 约 740 秒以后 | 保存可复用工具与笔记；继续检查偏暗截图并补抽 |

较长的单条命令还包括显式 sleep 30 秒、nohup 加 sleep 20 秒、补抽 17.47 秒、公共图片下载 14.56 秒和另一轮补抽 11.64 秒。余下墙钟包括模型思考与脚本重试，不能只用上述命令之和解释整轮。65 秒查询只能证明这一调用慢，不能据此断言应用重启或某个特定锁是原因。

截止前最后的消息仍在修图：当地 22:51:05 “几集截图偏暗（E34/E23/E46/E26/E01/E19），换时间点重抽。”；22:51:17 准备挑较亮帧；22:52:06 指出 E34 落在片头字幕，准备避开片头。没有最终完成消息。

[ui.capture 最终截图](evidence/x39/agent/result.jpg) 已打开核对：横版背景、中文标题 Logo、评分 7.2、2019、48 集、制作公司及每集截图、热度线进入页面。下面比较的是两轮观察结果，X39 的截图质量仍处于调整中。

| 项目 | 实验 14 / X35（10 分钟上限） | X39（15 分钟上限） |
|---|---|---|
| 相邻 XML | Agent 逐个解析，117.62 秒，并研究优酷 ID | 身体自动记录；Agent 没有解析 XML/解码 chatid |
| 弹幕覆盖 | 未成功导入，主视觉弹幕为空 | 48/48，699,214 条；覆盖、热度、主视觉和播放读同一绑定 |
| 帮手 | 没有委派 | 仍没有委派；有脚本并发抽帧 |
| 主要耗时 | 重复整目录枚举、XML/ID、编写抽帧脚本 | 索引查询、身份/元数据、脚本重试、视觉素材与补抽 |
| 作品资料 | 身份、中文简介、年份、48 集标题、海报 | schema 内作品字段全部可用，48 集标题与截图齐 |
| 截止时缺少的 ui_facts | 类型、制作公司、评分、背景、Logo、截图、弹幕 | schema 检查字段无缺项；截图质量仍在调整 |
| 回合状态 | 上限中止，未完成 | 上限中止，未自然完成 |

观察窗不同，SMB 缓存也经历过前面的身体实验，且配置 fixture 有上述差异。能确认的是 XML 读取工作从 Agent 轨迹中消失、弹幕无需显式导入即可被身体使用；**不能据此声称整轮整理速度提高了某个倍数**。

### 验证、失败与收尾

相关测试覆盖引用不复制内容、修改/删除后状态、轨道控制保留、显式导入与自动引用不叠加、候选规则、热度事实、自动远程回写与当前轨道复用、播放器接入/脱离。早期测试还暴露了自动发现对手工导入 fixture 的干扰，以及 local external object ID 编码不一致造成的外键失败；已隔离手工导入 fixture，并统一为现有 `ExternalRef.toJson()` 的稳定身份算法。修复后对应 12 项测试通过。

按 TEAM 排队、去代理的完整 `flutter test --no-pub test/next` **只运行一次**：449 通过、4 跳过、1 失败，1 分 38 秒。唯一失败为 runtime binding 测试替身缺少新增 `nextLocalDanmakuLoader` setter；补齐替身，并检查替换播放器时清除旧 hook。随后只跑该相关测试及 Classic 自动策略、XML 解析、轨道时间测试，**16 项全部通过**。没有为得到全绿日志重跑完整套件。日志见 [full-next.txt](evidence/x39/verification/full-next.txt)、[final-related-classic.txt](evidence/x39/verification/final-related-classic.txt)、[import-sidecar-fixed.txt](evidence/x39/verification/import-sidecar-fixed.txt)。

最终 analyze 无 error；包含 Classic 文件的检查仍报告既有 5 条 warning、17 条 info，未做无关清理。最终 Flutter 3.44.6 Debug `--no-pub` 构建成功，使用 Erika 预编译缓存，adhoc 签名与 `codesign --verify --deep --strict` 通过，见 [build-final.txt](evidence/x39/verification/build-final.txt)、[signature-final.txt](evidence/x39/verification/signature-final.txt)、[analyze-final.txt](evidence/x39/verification/analyze-final.txt)。最终构建包含手工导入身份修正、旧播放器 hook 清理及远程轨道 origin 标记；这些修正经相关测试检查，没有重复已成立的媒体/对话实验。构建生成的 Podfile.lock 已恢复，保留允许忽略的 GeneratedPluginRegistrant 变动。

远程播放写回使用合成 Classic 缓存测试验证：3 条原始评论、实际 B 站来源与视频号保留、无声明 ID 的条目不猜号；第一次复用当前轨道，第二次刷新不增加轨道或重复记录。本次真实播放设置走本地弹幕，**未另做真实远程匹配验收**。

所有实例从本 worktree 可执行文件直接运行，保持安静，未启动安装版应用，未触碰 ui-demo 或主控实例。关闭均按实验 PID；[cleanup.json](evidence/x39/verification/cleanup.json) 确认所有记录中的 x39 profile 目录不存在、匹配进程数为 0。只读 SMB 未写入、改名或重新挂载，没有复制视频整部。截图均为 JPG。对当前凭据值、私钥块与带用户名密码 URL 的证据检查匹配数均为 0，检查只保存计数，见 [evidence-audit.json](evidence/x39/verification/evidence-audit.json)。

## 4. 问题

需要主控决定的问题：**没有**。

后续观察缺口：真实远程自动匹配回写尚未真机验收；大量 SMB 文件下周期元数据核对的成本尚未量化；Bangumi 动画搜索限制、一次慢索引查询、缺失的集时长投影、部分截图质量及播放器 Debug 溢出仍在本轮范围外。Nipa 仍未主动使用帮手。它们不影响本轮已证实的同名轨道发现、48 集覆盖和单次加载结论，也不应被写成已经解决。
