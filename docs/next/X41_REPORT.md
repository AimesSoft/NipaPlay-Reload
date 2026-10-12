# X41：字幕成为 NipaPlay 的文件事实

2026-10-13。实现、构建和实验均在 `next/x41-subtitles` worktree。没有 commit、push、新依赖、下载管理改动或 `lib/next/ui/` 改动。实验脚本：[x41_experiment.py](../../scripts/next/x41_experiment.py)。

## 1. 完成了什么

- 数据库从 v14 升到 v15，只新增 `file_subtitles` 表；每个视频文件保存字幕轨、发现状态、默认选择及依据。内嵌轨包含容器声明的语言、标题、格式和轨道索引；语言码归一化，原声明保留。外挂包含路径、格式、文件名语言、匹配依据、大小与修改时间。未知语言是 `und`，不把文件名推断当作内容核验。
- 扫描的既有 MDK 时长探测同时带回内嵌轨，没有第二次视频探测。文件注册、下载入库、Classic 同步和既有索引的启动核对共用文件事件；缺少探测的旧索引才另行探测。单队列后台发现外挂，每 30 秒核对新增、变化和缺失；原文件不可用时保留上一份轨道事实并标记不可用。
- 新能力 `subtitle.tracks` 批量读取文件事实；`subtitle.import` 批量交入绝对路径的字幕文件、语言和来源，内容复制到 `next/subtitles/`，原文件可删除；`subtitle.select` 持久记录默认轨或显式关闭。批量导入逐项返回 `saved` 和错误，某项失败不掩盖已保存的项。文本导入拒绝无可解析时间轴的文件，VobSub 要求配对，文件大小上限为每份 32 MiB。
- Next 开启时，播放器从这份记录登记候选并加载默认轨。GUI 和 `playback.select_track` 的手动选择、字幕挂载/移除会记录选择；`subtitle.select` 在下次播放生效。Next 关闭、运行时销毁时撤掉字幕回调，Classic 原来的自动加载路径保持原行为。
- `media.metadata.ui_facts` 新增 `episodes.subtitles` 覆盖数和每集 `subtitles.available / languages / tracks / files`。文件项带探测状态、检查时间和选择，避免把“尚未探测”误报为“没有字幕”。
- 种子只补充字幕相关事实：“你的工作”说明身体自己发现字幕；“一部完整的作品”说明记录、交入和加载，以及烧录字幕尚未被识别；去掉“字幕只在 Classic 那边”的过期陈述。

## 2. 决策

### 探测、发现和保存

优先复用扫描已有的 MDK 探测，字幕不成为额外读取整部视频的理由。旧索引或仅登记了路径的文件按需补探测。内嵌探测的超时/失败记为不可用，不声称没有轨道。每 30 秒核对仍有目录和 stat 的 SMB 成本；本轮没有测数千文件规模。

相邻字幕直接复用 Classic 的 `subtitleMatchesVideo`、`computeLocalSubtitleMatchScore`、VobSub 配对与规范路径函数，不维护第二份模糊匹配规则。Classic 的扩展名集合没有改变；Next 另支持 WebVTT。

真实目录带来了一个有明确归属的额外规则：**视频所在目录只有一个视频时**，其 `Subs/` 或 `Subtitles/` 中按语言命名的字幕归属于它。Big Short 的五份字幕正是这种结构。记录的 `matchBasis=single_video_subdirectory` 与 `classic_filename_match` 分开；目录有多个视频时不做这种归属。没有改变 Classic 的发现行为。

发现的外挂继续引用原文件；Agent 交入的字幕保存内容快照和声明的来源、语言、操作者、调用 ID、时间。内容哈希相同的交入复用一份内容；再次交入更新该轨的来源事实。WebVTT 原字节照存，同时在自己的数据目录生成 SRT 播放副本，支持有/无小时的时间码、cue ID 和 cue settings；播放副本保留文字和时间，未保留 WebVTT 的区域布局、定位和样式。

### 默认选择和 Classic 边界

显式选择（包括关闭）优先，然后读取已有 Classic 的主字幕映射与最后激活索引。其余按应用语言设置决定简中/繁中优先，再选中文、英文；`auto` 使用系统 locale。文本外挂先于内嵌，外挂匹配分数及稳定排序用于同语言候选取舍。选择记录含 `basis`、实际 `preferredLanguages`、`languageMode` 和文本外挂优先事实；不是交给 Agent 的操作说明书。

索引读取 Classic 偏好使用新增的只读入口，不调用会清理缺失文件、改写列表的 Classic 加载方法。Next 实际播放仍复用既有字幕菜单、叠层和内核加载接口，没有改界面。Classic 的多外挂叠加渲染仍在；Next 持久默认只记一条主轨，不承诺恢复整个多字幕堆栈。

语言未知时继续未知。Doctor-X FINAL 的外挂文件名没有语言声明，记作 `und`，没有因为父目录名含 `JPN_SUB` 就声明它是日文。长安第 1 集的容器语言是 `und / eng / und`，记录为 `und / en / und`，没有猜测两条未知轨的语言。

## 3. 实验与证据

### 身体：只读发现、每集覆盖、实际加载与重启

来源只读，没有向共享写文件、改名、删文件或复制视频。Big Short 与 Doctor-X FINAL 各扫描一个视频；长安只登记第 1 集来补探测，没有扫描或复制全剧。发现记录见 [discovered.json](evidence/x41/body/discovered.json)，全过程见 [body operations](evidence/x41/body/operations.json)。

| 文件 | 内嵌 | 外挂 | 语言事实 |
|---|---:|---:|---|
| The Big Short (2015) | 0 | 5 | 英文两份、法文、葡萄牙文、西班牙文 |
| Doctor-X FINAL | 0 | 1 | und |
| 长安十二时辰第 1 集 | 3 | 0 | und、en、und |

Big Short 扫描任务用时 2.098 秒，Doctor-X FINAL 用时 1.517 秒；是这两个单视频扫描回执的墙钟时间，不是完整目录规模基准。

先实际打开 Big Short，`playback.tracks` 返回 `English.srt`、`origin=external`、`selected=true`。见 [播放截图](evidence/x41/body/movie-sidecar.jpg)：截图位于开头黑场，不能以此证明屏幕上已经出现英文台词；加载证据来自播放器轨道状态。

随后交入实验者自己创作的一条中文 SRT，以 `subtitle.select` 选为默认，删除原文件，确认 NipaPlay 的内容副本仍存在。按 PID 退出实例并重启同一临时配置，**下次播放选中数据目录里的副本，画面实际显示实验中文字幕**，见 [imported-replay.jpg](evidence/x41/body/imported-replay.jpg)。没有从网上下载字幕或其他媒体。

每集投影检查用同一临时配置中的三个明确标记的本地 work/release/episode 夹具，把这三份真实文件事实接到集上；夹具在实例退出后离线写入，仅供身体观察，没有虚构或声明外部平台身份，也没有交给 Nipa 指示。三份 `ui_facts` 均为 `episodes.subtitles=1`，包含上述轨道、语言、来源和默认选择：

- [Big Short ui_facts](evidence/x41/body/ui-facts-0.json)：包括五条发现轨与一条交入的简中轨；
- [Doctor-X ui_facts](evidence/x41/body/ui-facts-1.json)；
- [长安 ui_facts](evidence/x41/body/ui-facts-2.json)。

长安实际播放返回三条内嵌字幕轨，其中一条选中，见 [embedded-playback.jpg](evidence/x41/body/embedded-playback.jpg)。这是轨道已激活的证据，截图开头没有台词，未用它宣称已验证特定语言的字幕内容。

观察中发现：空的 Classic 字幕映射被拿来和内嵌轨缺少路径的空值比较，误把内嵌第 0 轨标成 `classic_choice`。已修正为必须存在字符串路径才比较；相关约束测试确认未知语言和英文轨并存时按偏好选择英文，不能凭空生成 Classic 选择。**保存的身体原始证据保留修正前的依据，没有篡改或重复整套实验。** 之后只读偏好入口、WebVTT 播放副本和应用语言设置的补充，经相关测试与最终构建验证，未追加一次相同的真机实验。

身体实例两个进程 PID 75702、76554 均按 PID 退出，临时配置 `x41-body-75698` 已删除。

### 真实 DeepSeek：已有硬字幕，空轨道不等于看不到中文字幕

独立临时配置先扫描只读的 `/Volumes/Media/无职转生 第二季`。25 个 MP4 的扫描回执为 49.299 秒；身体记录 **25 个文件，探测全部 ready，字幕轨全部为空**。没有替 Agent 做身份整理或填实验步骤。

只对 Nipa 说：

> 《无职转生》第二季有中文字幕吗？没有的话帮我配上。

实际头部为 `deepseek-v4.1-flash / cpa`，回合完成用时 **208.316 秒**，无最终服务端错误。完整结果见 [agent operations](evidence/x41/agent/operations.json)、[commands](evidence/x41/agent/commands.json)、[messages](evidence/x41/agent/messages.json)、[chat events](evidence/x41/agent/chat-events.jsonl.gz)。

她执行了 34 次终端命令，并有 3 次查看图片的完成事件：

1. 读取实例、片库与根目录。没有作品/剧集身份，初始 `library.episodes` 和作品搜索为空；她转到文件与真实目录。
2. 尝试列能力和查询视图，再读取 `subtitle.tracks`。用上了身体的“25 个文件，ready，空字幕轨”事实。她没有使用 `ui_facts`，因为没有 workId；不能把身体夹具的覆盖实验当成她使用过的事实。
3. 用 ffprobe 抽查编号 00、01、12、24：每个文件只有 H.264 视频和 AAC 音频。用文件枚举确认目录没有外挂字幕。
4. 从第 01 集抽取多个时间点并查看拼图，随后抽查编号 00、06、12、18、24 的画面拼图；事件日志保留 `nz01.png / sheet.png / eps.png` 的 `imageView` 完成记录。她据此判断画面里已有烧录的简中/日文双语字幕。
5. 最终告诉用户“有中文字幕，但它是烧录在画面里的，不是可切换字幕轨”，没有下载、没有交入字幕，没有下载视频。她清理了自己的临时帧，所以本次交付保留查看图片的事件轨迹，没有保留抽帧图本身。[result.jpg](evidence/x41/agent/result.jpg) 经打开核对，是实验实例没有作品的首页；回合由实验 VM 入口发起，没有展开对话界面，不能把这张图当作回复截图，实际回复以 messages 和线程记录为证据。

卡点和范围：

- `nipa list` 默认输出被截断，她多次列能力、猜查询入口；能最终发现字幕入口，但路径不短。
- 她对已索引目录再次调用 `media.files.list`，它会重新探测视频；这次命令被中断（退出 130），没有继续等待。随后改用文件事实和外部工具。
- 实验禁止在外部 `/tmp` 写入；她第一次抽帧失败后改写 harness。两次 zsh 无匹配 glob、一次 `echo ===` 的 shell 解析错误和 Pillow 未安装，也被她改用已有 ffmpeg 解决。没有安装依赖。
- 她说“25 集整季一致”的措辞比抽查证据强：直接抽查了五个编号和第 01 集多个时间点，没有逐集视觉核验。报告保留这个实际范围。
- 字幕轨事实尚不能表达烧录字幕。她用画面观察补上这个判断，**没有把空轨道误当成没有中文字幕**；这个结论不能扩展成身体已具备自动硬字幕识别能力。

Agent 实例 PID 78776 已退出，临时配置 `x41-agent-78772` 已删除。实验使用隔离 CODEX_HOME、认证副本、公共 CA 副本与 NO_PROXY；没有修改用户 `~/.codex`、访问钥匙串、激活窗口或触碰其他实例。证据中的端点令牌和 VM 认证链接已脱敏。

### 验证

完整 `test/next` 加相关 Classic 字幕测试**只跑了一次**：[full-tests.log](evidence/x41/full-tests.log)，结果 465 通过、4 跳过、2 失败。两个失败来自新增后台探测在测试宿主尝试加载不存在的 MDK 动态库；一次相关重跑进一步暴露纯单元测试没有初始化 SharedPreferences binding。已提供字幕探测注入并补全测试夹具；没有通过吞异常处理。

修正后仅重跑受影响的核心、元数据、字幕持久化、v0–v14 迁移与 Classic 字幕测试：[delivery-related-tests.log](evidence/x41/delivery-related-tests.log)，**48 通过**。语言设置补充后的最后字幕约束检查：[final-subtitle-tests.log](evidence/x41/final-subtitle-tests.log)，**6 通过**。覆盖副本独立性、无效导入不覆盖既有数据、明确关闭、缺失文件可用性、单视频 Subs 的归属限制、空映射不生成选择、Classic 偏好不被改写和 WebVTT 原文/播放副本的持久性。没有第二次全量测试；不把局部修正后的结果写成全量再次通过。

最终 Debug 构建：[build-final-verification.log](evidence/x41/build-final-verification.log)。签名：[signature-delivery.log](evidence/x41/signature-delivery.log)，adhoc、allow-jit、无 app-sandbox，deep/strict 验证通过。分析：[analyze-final-verification.log](evidence/x41/analyze-final-verification.log)，无 error/warning，保留既有文件的风格/弃用 info。CocoaPods 生成的 Podfile.lock 变化已恢复；GeneratedPluginRegistrant 的已有生成变化按任务约定保留。

## 4. 还缺什么与问题

没有做 OCR 或自动烧录字幕识别；现有字幕表的“没有轨”不能推出画面没有文字。外挂语言来自声明/文件名，不是内容语言检测。没有真机验证所有内核、所有字幕格式或多字幕堆栈恢复；本轮实际验证了外部 SRT、内嵌轨和交入 SRT 重启恢复。字幕删除能力和自动垃圾回收未新增；来源快照和 WebVTT 播放副本保留在自己的数据中。

需要主控决定的问题：**没有**。硬字幕作为可持久事实的入口、能力发现截断和大目录读取成本，是本轮记录的后续观察，未越界改成新目标。
