# X49：harness 记忆与会话延续

2026-10-13，worktree `x49-memory`，分支 `next/x49-memory`，基线 `edc3adc0`。未 commit、push、pub get 或改依赖；`pubspec.yaml` 只新增种子资产声明。未改种子 AGENTS.md、界面代码、用户 Codex 配置或用户 harness。全部构建在本 worktree。真实观察使用 `deepseek-v4.1-flash`、独立 CODEX_HOME、临时安静 profile 和本 worktree 直接可执行文件；没有启动安装版、激活窗口、像素点击、访问登录钥匙串、真实应用数据或其他实验实例。

## 1. 完成了什么

- 重写前一会话的 JSON 记忆草稿，使用 harness 的普通 Markdown：`memory/preferences.md` 常驻偏好，`memory/MEMORY.md` 常驻索引，其他主题文件按需读取。记忆继续由 harness Git 管理，无额外数据库、抽取模型、向量库或会话切段。
- 种子新增 `.codex/hooks.json` 和 `hooks/session_start.py`，匹配 SessionStart 的 startup/resume/clear/compact。每次从磁盘现读偏好与索引，并取得实时设置及现有数据的“刚才”。种子 `.codex/config.toml` 明确 `features.memories=false`。
- `SettingsRegistry.preferences()` 提供用户或 Agent 改过的用户级设置当前值、最后修改时间、来源与理由；默认值、迁移、application 来源和运行时值不作为偏好复制。秘密经既有脱敏层处理。
- `NextCore.memory` 的 `MemoryData` 与 `memory.list/read/edit/delete/context` Actions 已接入。设置页“Nipa 记得的事”可列出、读取、删除整个文件，或带 revision 提交剩余文本删除其中一条偏好。接口、调用方与限制写在 [chat README](../../lib/next/chat/README.md)。本任务没有 GUI。
- GUI 删改以 `NipaPlay User <user@localhost>` 提交目标文件，记录动态与 commit；Agent Action 保留真实调用来源，并以 Nipa 署名。不带走无关暂存内容；目标已有暂存修改或读取后已变化时拒绝覆盖。未跟踪文件的删除也有独立 Git 记录。
- 每个线程保存已经见过的文件 revision，下一回合开头追加简短变化说明，请重读更新文件、停止使用删除或修改前的偏好。不改已有消息；切回同一个 app-server 中已加载的线程时保留未送达变化。
- `memory.context {threadId?}` 是只读的上下文接口，含常驻文件、设置、最近会话 ID、原文摘录、截断标记和省略项。数据来自 Codex 历史、未结束任务、后续及 activity，未生成交接，也未保存第二份聊天记录。Debug lab VM 扩展补了 hooks/compact 和模拟 GUI 删改入口，生产不注册。

主要实现：[记忆服务](../../lib/next/memory/service.dart)、[Actions](../../lib/next/memory/capability.dart)、[最近事实](../../lib/next/memory/recent.dart)、[SessionStart 脚本](../../assets/next/harness/hooks/session_start.py)。

## 2. 决策

1. **文件是事实源。** Agent 可直接写文件并提交；宿主不推断对话中的偏好、不自动整理主题或重新生成索引。编辑 API 用 SHA-256 revision 避免覆盖用户或 Agent 的后续改动，路径支持中文文件名，禁止越界和符号链接。
2. **偏好上限以 UTF-8 字节计。** API 修改 preferences.md 和 MEMORY.md 的硬上限各为 8192 字节。Agent 直接写出的超限文件不被改写；注入在完整 UTF-8 字符边界截断，并准确注明被省略的字节数。实时设置也有 8192 字节注入预算，超出可通过 settings.get/history 读取。
3. **“刚才”只投影已有字段。** 按 updated_at 查最近会话，扫描最多 30 个，跳过空会话与已知宿主帮手。最近六条用户/助手原话、未结束任务及后续、最近五条动态分别有字符预算，连同截断提示不超过 3000 Unicode 字符。消息从尾部保留最新内容；任务、后续和动态保留前部，注明省略哪一侧、多少字符。activity 的省略条数基于完整既有视图，不把查询窗口误写成总数。JSON 被截到中间时明确标为原文片段。
4. **中途变化只追加。** 变化说明放进新 turn 的文本开头，没有 thread/inject_items 改写、每轮重建 developer instructions 或隐藏模型回合。每个前台/帮手线程独立收到一次变化；没有变化就不追加。
5. **删除是停止使用当前记忆。** Git 仍保留旧版本，Codex 历史也保留。服务不按自然语言猜测其他主题笔记是否重复同一偏好；索引仍由用户/Agent 维护。实验发现重复偏好会遗留在主题笔记中，因此给 X50 的事实明确偏好以 preferences.md 和实时设置为准。
6. **秘密在写入和输出边界处理。** API 拒写可识别的密码、cookie、令牌、认证链接和私钥，读取/注入脱敏。Agent 的直接文件写入没有被接管；无法靠模式识别覆盖任意自然语言中的秘密，仍需要种子中的“秘密不进记忆”。合成秘密的真实观察见下表。

## 3. 实验与真实观察

驱动：[x49_experiment.py](../../scripts/next/x49_experiment.py)，补测：[x49_supplement.py](../../scripts/next/x49_supplement.py)、[x49_restart.py](../../scripts/next/x49_restart.py)。只读汇总：[x49_analyze_evidence.py](../../scripts/next/x49_analyze_evidence.py)。主实验使用三个独立临时 profile，每项各三次；共 62 次真实模型请求。回环 relay 转发到已有 CPA，保留原模型、认证与请求协议，只保存脱敏后的模型输入和实际 usage；未保存认证头、配置、凭据或原始推理。完整原文与计算见 [summary.json](evidence/x49/summary.json)、[模型输入](evidence/x49/provider-inputs.json.gz)、[时间线](evidence/x49/timeline.json) 和 [实验日志](evidence/x49/experiment.log)。

### 六项主要实验

用户首句完全相同，没有要求“写记忆”或指定文件：

> 我今晚只想轻松点，推荐时别选恐怖片；我更喜欢温暖的结局。每次先给我两部就好。我刚才在挑周五电影夜的片单，先别推荐，待会儿继续。

| 项目 | 第 1 次 | 第 2 次 | 第 3 次 |
|---|---|---|---|
| 顺口偏好入库 | preferences.md 468 字节，两条；第一条合并了轻松/恐怖/温暖三项 | 484 字节，三条 | 三条，并创建作品笔记 |
| 真压缩后推荐 | 《帕丁顿熊2》《海蒂和爷爷》 | 《帕丁顿熊2》《海蒂和爷爷》 | 《帕丁顿熊2》《小森林 夏秋篇》 |
| 新会话续上 | 知道偏好，接着上一组推荐《白日梦想家》《天使爱美丽》 | 明说周五电影夜与偏好，推荐《时空恋旅人》《小森林·夏秋篇》 | 明说周五电影夜与偏好，新增《绿皮书》《海蒂和爷爷》，另列四部已有总片单 |
| 中途删除后 | 不再排除《惊声尖叫》，说明当前只剩数量偏好 | 不再因类型禁忌排除；按仍在的轻松/温暖偏好判断 | 不再因类型禁忌排除；按仍在的温暖偏好判断 |
| 压缩摘要字符数 | 2501 | 1419 | 2687 |
| 合成秘密不在记忆 | true，2 个文件 | true，3 个文件 | true，3 个文件 |

三次都由 Agent 自己写了带日期和用户出处的偏好。删除使用 GUI 调用同一个 MemoryData.edit，不发送“请忘掉”的用户消息；宿主下一轮自动追加变化说明。第 1 次删除的是包含恐怖偏好的整条 Markdown 条目，因此同时移除了该条里合并的轻松/温暖偏好，另一条数量偏好保持原文。这和第 2、3 次仅删除恐怖条目不同，结果按各自实际剩余内容判读。

实际删除后回复摘录：

> 第 1 次：没有类型禁忌了——所以《惊声尖叫》不再被排除，我不会因为“记得的禁忌”把它拿掉。
>
> 第 2 次：不会再因为“类型禁忌”排除它。那条已经删除，我不从旧对话里把它捡回来。
>
> 第 3 次：那条禁忌已经被你删掉了，我不会从旧对话或旧笔记里把它捞回来。

第 2、3 次 Agent 发现主题笔记/索引仍有旧偏好，却询问是否顺手清理，没有自行完成清理。这是实际留下的缺口，不能把“下一回合不再依据它”扩大成“所有重复记录都已清掉”。第 1 次 Agent 自行更新了索引。原始三份文件保存在时间线 `memory-files-*`，未替它修饰结果。

秘密只用随机生成的合成 cookie；值始终只在临时实验中使用，relay 在存证之前移除它，报告仅保存是否入库的布尔结果。三次均未在 memory/ 文件中找到该值。没有使用真实密码、PT passkey、账号或令牌做实验。

### 压缩实际保留了什么

通过 app-server 的 thread/compact/start 执行真实本地模型压缩，再检查下一次发给 CPA 的 input，而非只看 UI 或 thread/read：

- 三次都保留了首句偏好用户原文，以及包含探针命令的用户消息原文；后者还带上了宿主追加的真实变化说明。
- 三次都有 `Another language model started to solve this problem…` 开头的 Codex 压缩摘要，分别为 2501 / 1419 / 2687 Unicode 字符。
- 三次在压缩后首个请求里，旧 assistant 条目为 0，旧 function_call_output 为 0。旧工具输出没有作为工具条目保留；探针标记可出现在用户命令、摘要或 hook 的助手原话摘录中，不能把这些当成旧工具输出仍在。
- 下一回合的 SessionStart(compact) 重新加入 developer 记忆块，分别为 1721 / 1872 / 1788 字符；AGENTS.md/环境也重新出现。这些是重新注入的事实，而非压缩保留的旧 assistant/工具项。
- app-server 的原会话历史仍可读，宿主 turn-process 仍能恢复命令事实。这不意味着它们还在模型的压缩上下文里。

摘要全文与 hook 原文均在 summary.json。没有写自定义交接或 compact_prompt。

### 缓存对照

每个 profile 再开两条线程，同一三轮短提示，依次启用 hook、禁用 hook。通过 CPA 的真实 `usage.input_tokens_details.cached_tokens / usage.input_tokens` 计算。模型输入直接确认启用组有记忆块，禁用组没有。表中依次列三轮百分比：

| 重复 | 有注入 | 无注入 |
|---|---|---|
| 1 | 98.927 / 99.863 / 99.843 | 99.777 / 99.757 / 99.858 |
| 2 | 98.888 / 99.824 / 99.804 | 99.777 / 99.757 / 99.858 |
| 3 | 98.845 / 99.780 / 99.760 | 99.777 / 99.757 / 99.858 |

全部九轮加权：有注入 99.504%，无注入 99.797%。只看同一线程后两轮：99.812% 对 99.807%。有注入多约 1K 输入 token；实际总输入为约 106K–107K token。两组已有大段共用前缀且固定先跑启用组，首轮受预热与新记忆块影响；三次短对照不能外推到长主会话的总成本或证明统计差异。

中途删除另有更直接的缓存事实：下一次请求完整保留此前请求 input 的全部前缀条目，三次分别为 4/6/6 项，均完全相等；变化说明只出现在新的用户输入项。见 summary.json 的 deletionPrefixes。

### app-server hook 与信任

Codex 版本 `0.144.1`。只登记 `[projects."<harness>"] trust_level="trusted"` 时，hooks/list 可发现项目 hook，但 `trustStatus=untrusted`：[探针](evidence/x49/hook-trust-probe.json)。实验再从 hooks/list 的 key/currentHash 登记临时 CODEX_HOME 的 `[hooks.state."<key>"] trusted_hash="<currentHash>"`，才正常执行。没有 bypass_hook_trust，也未修改用户配置。

主实验共 12 次 hook/completed，全部 completed，实测耗时 105–249 ms；压缩后的 hook 在下一回合启动时出现。同一个 app-server 切回已加载线程的三次 thread/resume，没有重新执行 SessionStart，只有已有前缀仍在：[补测](evidence/x49/supplement/timeline.json)。因此宿主不能在选线程时重置它已经见过的记忆 revision。

真正关闭并重启 app-server、恢复同一条持久主线程三次，SessionStart(resume) 三次均 completed；每次停机时改变磁盘数量偏好为 1/2/3 部，模型分别答“先给 1 部”“先给 2 部”“先给 3 部”，threadId 始终相同：[重启时间线](evidence/x49/restart/timeline.json)、[事件](evidence/x49/restart/chat-5.jsonl.gz)。没有新建或分段替代主会话。

**给 X50 的接入事实：项目信任与 hook 哈希信任都需要登记；项目 trusted 本身不会运行项目 hook。哈希随声明变化，应读取 hooks/list 的实际 key/currentHash。** hook 脚本代码自身变化不改变这份声明哈希。当前 hook 注册的字面命令是 `python3 hooks/session_start.py`，timeout=15，matcher=`startup|resume|clear|compact`。

### 失败、边界与最终检查

首次把压缩阈值设为 18K，低于该实验实际基础输入，导致工具调用后重复压缩；本次失败有 13 次真实请求。结束自己的 PID 后保留 [失败证据](evidence/x49/threshold-failure/timeline.json) 与 [清理](evidence/x49/threshold-failure/cleanup.json)。改为实验配置 300K，并通过 thread/compact/start 明确触发真实压缩，之后才完成三组观察。未改生产阈值，也没有据此选择生产阈值。

最终补测三次验证：按 updated_at 选到最近实际说过话的线程；设置弹幕透明度 .60/.65/.70 的现值与理由进入上下文；等待播放的真实 followup 与 activity 原文进入“刚才”；preferences.md/MEMORY.md 各 9000 字节时准确提示省略 810 字节；最近事实各为 868 字符，并准确报告动态截断与省略条数：[补测](evidence/x49/supplement/timeline.json)。这些是控制输入的接口验证，不冒充 Agent 自主创建了任务或设置。

- Flutter 3.44.6、所有命令 --no-pub，Erika 使用指定缓存。[最终 Debug 构建](evidence/x49/build-last.log)成功，[签名验证及 allow-jit/无 app-sandbox 检查](evidence/x49/signature-last.log)通过；新增四个记忆/hook 文件确实进了 Flutter bundle：[资产检查](evidence/x49/bundled-assets.json)。CocoaPods 改写的 Podfile.lock 已恢复，GeneratedPluginRegistrant 保留既有生成变化。
- 最终 analyze 无 error/warning，保留 chat_host/helpers 中三条既有花括号风格 info：[日志](evidence/x49/analyze-delivery.log)。最终记忆模块与约束测试单独 analyze 无问题：[日志](evidence/x49/analyze-memory-final.log)。只对本次完整新写的四个 Dart 文件格式化，未格式化已有整文件。
- 相关初测 19 项通过；全量 `test/next` 加桌面退出测试只跑一次：504 通过、7 跳过，新增设置偏好测试因漏写 required decodeStorage 而加载失败。修正后仅跑 X49 文件，8 项通过；后续修正只补测涉及切换通知、未跟踪文件署名和中文路径的条目。有效去重结果为 **512 通过、7 跳过**，未重复全量：[全量](evidence/x49/full-next.log)、[X49 八项](evidence/x49/constraints-git-final.log)、[切换/署名](evidence/x49/constraints-resume-author.log)、[中文路径](evidence/x49/constraints-unicode.log)。
- 所有实验按自己的 PID 退出，临时目录全部删除。主三组、补测、三次重启以及首次阈值失败都有独立清理记录：[主实验](evidence/x49/cleanup.json)、[补测](evidence/x49/supplement/cleanup.json)、[重启](evidence/x49/restart/cleanup.json)。[最终审计](evidence/x49/final-audit.json)确认九个自己的 App PID 均已退出、所有 profile 已删除、证据不含合成秘密值。没有触碰 ui-demo 或主控实例。
- `git diff --check` 通过。实现 worktree 没有提交；实验中的 Git 提交仅属于已删除的临时 harness。

## 4. 给 X50 合并进 AGENTS.md 的种子事实

下面一段共 565 UTF-8 字节；未写入种子 AGENTS.md。

> 记忆在 memory/，由 git 管理。preferences.md 是常驻偏好，最多 8192 UTF-8 字节，每条写日期与出处，变化在原处修改；能落成设置的偏好改设置并写理由，不重复。偏好以该文件和实时设置为准，不从主题笔记恢复。MEMORY.md 是一行一条的常驻索引，其余按需读。SessionStart 从磁盘现读，注入偏好、设置理由、索引及最近对话、任务、后续和动态原文；压缩仍由 Codex 管理。用户删改后下回合追加通知，旧记忆不恢复。秘密不进记忆。

## 5. 还缺什么与问题

还缺设置页 UI（由主控安排）以及 X50 的项目与 hook 哈希信任登记；既有 harness 的种子合并继续用已有升级机制，不在这里覆盖用户文件。Windows/clear 事件没有真实平台实验。主题笔记中的重复偏好未自动清理；短对照也未决定长主会话的生产压缩阈值。

需要主控决定的问题：**没有**。
