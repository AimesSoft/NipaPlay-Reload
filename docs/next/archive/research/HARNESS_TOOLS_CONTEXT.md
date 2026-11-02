# Harness 的工具、上下文与提示词：前沿调研与对照

> 2026-10-13，研究员调研，不改代码。
> 对照对象是 `assets/next/harness/`（种子 AGENTS.md、`nipa`、`hooks/`、`tools/`）和能力层（`packages/nipa_harness`、`lib/next`）。
> 运行时：Codex app-server 0.144.1，模型 deepseek-v4.1-flash（经 CPA）。

---

## 0. 结论先行

1. **工具形态和前沿一致，`nipa` 不用改成 MCP。**
   - `nipa list → describe → call` 就是 MCP 官方 2026-07 推荐的"目录 → 查看 → 执行"三层渐进发现。
   - Codex 在 DeepSeek 这类非 OpenAI 模型上不启用工具搜索。约 100 个能力如果做成函数定义，会全量塞进前缀；走命令行正好避开这个问题。
2. **最紧迫的问题是种子体积。**
   - 种子 AGENTS.md 三天里从 5,018 字节涨到 25,621 字节（36 次提交）。Codex 对项目说明有 32 KiB 硬上限，超出部分按字节静默截掉，模型看不到任何提示。
   - 被截掉的是文件末尾，也就是「授权」「hooks」「维护」这三节。再增长约 9 KB，授权规则就开始从 Nipa 的视野里消失。
3. **`nipa` 的大输出已经被 Codex 从中间截断。**
   - 本地会话记录里，超过 10,000 token 的输出共 14 次被截，只保留头尾。涉及 `status`、`list`、`state.describe`、`describe media.library.works`、`media.sources.query`。
   - `nipa` 自己没有输出预算，也不会把大结果落到文件里。
4. **缓存命中已经很好。**
   - 实验配置里 143 次请求的命中率是 96.5%，EXPERIMENTS.md 记录的是 99% 以上。
   - DeepSeek flash 的命中价只有未命中价的 1/50，命中率是成本的决定因素。
   - 要守住的是：前缀里不放会变的东西，比如即将做的记忆功能（X49）。
5. **2026 年的主流共识**：系统提示和说明文件变短；流程放进按需加载的技能；工具用法只写在工具定义里；harness 的每个组件都看作"对模型短板的假设"，要随模型重测。
   - 我们"写事实不写步骤、给工具不教流程"的原则和这些共识一致。
   - 但种子的大部分篇幅是每次都注入的能力语义说明。按 2026 年的做法，这些内容应该放进 `describe` 或按需读取的文档。
6. **研究证据要小心对待。**
   - 2026 年多篇论文发现，说明文件对成功率的影响常常不显著，可测的收益主要在效率。
   - 说明文件里点名的工具会被几乎逐字采用（2.5 次对 0.05 次）。
   - agent 自己写的技能平均没有收益，还有自我投毒风险。所以经验笔记"写明何时、怎样确认"这条要坚持。
7. **子代理、后续、唤醒的设计都和前沿同构。**
   - Codex 的子代理结果只入队、不开回合，app-server 也没有服务端主动开回合的机制。我们的"后续"机制正好补上了这一环。
   - 可以改进的是唤醒消息里的来源与权限标注。

---

## 1. 可信度标注与方法

| 标注 | 含义 |
|---|---|
| 【一手】 | 调研时打开过原文、官方文档或源码核对 |
| 【摘要】 | 只来自搜索摘要或二手转述，没能打开原文 |
| 【实测】 | 在本机测量（分词器、Codex 会话记录、git 历史） |
| 【推测】 | 我的推断，需要实验验证 |
| 【基线·2025】 | 早于 2026 年的资料，后面附现状判断：**仍成立 / 已修正 / 被推翻** |

- **方法**：7 路并行检索，覆盖 Anthropic、Manus/Cognition/LangChain/12-factor、工具与 MCP、系统提示与 AGENTS.md、子代理与唤醒、2026 年的新 harness 与厂商、2026 年的研究与评测。再加本地测量：
  - DeepSeek V3 分词器（V4 分词器未测，推测相近）；
  - `~/.codex/sessions` 和 `LabProfiles/*/codex-home/sessions` 里 Nipa 的会话；
  - 种子的 git 历史。
- **注意**：网页抓取经过小模型转述，引号里的原文接近原话但没有逐字核对。对外引用数字前，建议回原文再看一眼。

---

## 2. 2026 年的新变化（和 2025 年主流说法相比）

| 2025 年的说法 | 2026 年的状态 | 依据 |
|---|---|---|
| 主语是"上下文工程（context engineering）" | **换了主语**：变成"harness 工程（harness engineering）"，上下文工程被看作 harness 的交付内容 | Hashimoto 02-05、OpenAI 02-11、LangChain 02-17 / 03-10、martinfowler.com 04-02【一手】 |
| 系统提示要详尽，放一组典型示例 | **已修正**：大幅删减。Claude Code 删掉 80% 以上的系统提示，编码评测没有可测损失；示例换成"接口设计"（枚举、schema 自带用法） | Anthropic 07-24【一手】、Deep Agents v0.7 07-29：基础 token 从约 6000 降到约 2000【一手】、Codex 提示按模型下发并删掉了 AGENTS.md 段【一手 源码】 |
| 用 /init 自动生成详细的 AGENTS.md 有益 | **被推翻**：LLM 生成的说明文件让成功率略降、成本增加 20–23%；仓库概览没有帮助 | ETH arXiv 2602.11988（v3 09-29）【一手】 |
| 说明文件能提高正确率 | **已修正**：正确率多半不显著；收益在效率（运行时间 −28.6%），以及让 agent 用上点名的工具 | 2601.20404、2607.27250、2602.11988【一手】 |
| 不要做多代理（Cognition） | **已修正**：原作者改口为"写入保持单线程，其他代理贡献智力而不是动作"；子代理分"隔离"和"分叉（继承全部上下文、复用缓存）"两种模式 | Cognition 04-22【一手】、LangChain 09-08【一手】、Claude Code fork【一手】 |
| 不要在迭代中增删工具（Manus：遮蔽而非删除） | **部分被改写**：函数层仍保持固定；新的 API 可以在不破坏缓存的前提下中途追加工具；主流改为延迟加载加工具搜索 | Anthropic inline tools 09-22【一手】、DeepSeek Harness v0.1.7-rc.2 09-24【一手】、Kimi K3 文档【一手】 |
| 工具多了会乱，要动态加载 | **仍成立，重要性下调**：延迟加载成为默认（Claude Code 01 月、Codex 0.142.2 06-25）；对前沿模型主要是成本和延迟问题 | Claude Code changelog【一手】、Codex release【一手】、2605.24660【一手】 |
| 代码模式（code mode）是实验 | **成为主流之一**：MCP 官方客户端最佳实践推荐；OpenAI 新模型在 Codex 里只暴露代码模式入口；pi 1.0 用 Codemode 接 MCP | MCP 07-28【一手】、Codex models.json【一手 源码】、Ronacher 10-06【一手】 |
| bash 就够了 / 不需要 MCP | **变成分层**：本地、认证已配好、命令常见时用 CLI；远程、OAuth、需审计时用 MCP；结构化数据上专用查询工具明显胜过 bash | Arize 05 月、Braintrust/Vercel 01-22、Simon Willison 07-31【一手】 |
| 长上下文会解决问题 | **被否定**：HumanLayer 退回 200K 窗口的模型；长上下文的退化强烈依赖模型；出现"过早放弃"现象 | HumanLayer 03-23【一手】、Boolean 09-15【一手】、2606.29718【一手 摘要页】 |
| 压缩就是做摘要 | **已修正**：只截断旧工具结果、不改写，效果更好；压缩移到服务端 API | 2608.26218、2609.26779【一手 摘要页】、Anthropic 压缩 API、OpenAI 02-10【一手】 |
| 用 todo 复述目标（Manus） | **被削弱**：评测显示关掉 todo 略好且更便宜，Deep Agents 默认关闭 | LangChain 07-29【一手】 |
| 缓存命中率最重要、上下文只追加 | **仍成立，并有了数据**：成本省 41–80%；激进压缩可能少用 token 却多花钱 | 2601.06007、2609.00749【一手】 |
| agent 能自我进化、自己写技能 | **大幅修正**：没有外部验证和留出集时收益不可靠；自写技能平均没有收益；有自我投毒风险 | SkillsBench 2602.12670、EVOMAL 2608.25776、2607.12227【一手 摘要页】 |
| 安全靠模型层的规则 | **已修正**：先在环境层隔离；被钓鱼的指令 25 次里有 24 次成功外泄；说明文件需要信任门 | Anthropic 05-25【一手】、Codex #39837 08-21【一手 源码】 |
| harness 组件一次设计、长期有效 | **被推翻**：组件编码的是对模型短板的假设，换模型就过时（如上下文重置变成"死重"）；改系统提示必须过评测 | Anthropic 03-24、04-08、04-23 复盘【一手】 |

---

## 3. 上下文工程

### 3.1 2025 年基线和现状判断

- **Anthropic《Effective context engineering for AI agents》**，2025-09-29【一手·基线】
  - 要点：
    - 上下文是有限的"注意力预算"。系统提示要在"合适的高度"：既不硬编码脆弱的 if-else，也不空泛。
    - 原则是"smallest possible set of high-signal tokens"。
    - 只保留轻量标识（路径、查询、链接），运行时再取。
    - 用压缩、结构化笔记、子代理三种手段，子代理只回传 1,000–2,000 token 的摘要。
  - **主体仍成立**。"在系统提示里放典型示例"一条已被 2026-07 的"接口设计"取代。
- **Manus《Context Engineering for AI Agents》**，季逸超，2025-07-18【一手·基线】
  - 六条原则：
    1. 围绕 KV 缓存设计：输入输出比约 100:1，缓存价差 10 倍；前缀稳定，开头不放精确到秒的时间戳，只追加，JSON 键顺序确定。
    2. 遮蔽而非删除工具，工具名前缀统一。
    3. 文件系统当外部记忆，压缩要可恢复。
    4. 用 todo.md 复述目标。
    5. 保留错误。
    6. 避免被少量示例带偏。
  - 现状：1、3、5、6 **仍成立**；2 **部分被改写**（见第 2 节）；4 **被削弱**。
  - 后续资料（Lance Martin 2025-10-15 的研讨会笔记【一手】）：
    - 少于 20 个原子函数，其余能力下沉到沙箱里的 CLI；MCP 工具也经 CLI 调用。
    - 旧工具结果换成只留路径的紧凑版本。
  - Manus 2.0（2026-09-28）的新 harness 叫 Cascade，原话是"按需引入能力"。厂商自测数字：token −23%、成本 −32%【一手】。
- **Cognition《Don't Build Multi-Agents》**，2025-06-12【一手·基线】
  - 主张共享完整轨迹，并指出"动作隐含决定"。
  - **已修正**：2026-04-22《Multi-Agents: What's Actually Working》【一手】改为"writes stay single-threaded and the additional agents contribute intelligence rather than actions"。用干净上下文的评审代理，每个 PR 平均抓到 2 个 bug。
- **LangChain 写入/选取/压缩/隔离四分法**，2025-06/07【一手·基线】
  - 框架**仍被广泛引用**。
  - 2026 年 LangChain 的说法变成"harness 是上下文工程的交付机制"（03-10）。
- **12-factor agents**，HumanLayer，2025-04 起【一手·基线】
  - 自己掌控上下文和控制流、错误压缩进上下文（连续 3 次失败就升级）、小而专注的 agent、从任何地方触发、预取上下文（第 13 条）这几条原则**仍成立**。
  - HumanLayer 自己 2026-03 承认 RPI 工作流的部分建议是错的【摘要】。
- **Anthropic《Effective harnesses for long-running agents》**，2025-11-26【一手·基线】
  - 做法：进度文件、JSON 功能清单、git、每次会话只做一项。
  - **仍成立**，2026 年已被收进 memory tool 文档。但同一作者团队 2026 年指出，这类脚手架要随模型升级重新验证。

### 3.2 2026 年的前沿做法

- **Anthropic《The new rules of context engineering for Claude 5 generation models》**，2026-07-24【一手】
  - 删掉 80% 以上的系统提示，编码评测没有可测损失。六条变化：
    1. 规则换成判断。
    2. 示例换成接口设计：Todo 工具约 9,100 字符的示例，换成状态枚举加一条规则。
    3. 预载换成渐进披露：验证、评审拆成按需技能，工具改为延迟加载。
    4. **不重复：工具用法只写在工具定义里。**
    5. 手写 CLAUDE.md 换成自动记忆。
    6. 简单规格换成更丰富的参考材料。
  - 对 CLAUDE.md 的建议是写得轻，把 token 花在"坑"上。
- **LangChain Deep Agents v0.7**，2026-07-29【一手】
  - todo 中间件默认关闭。
  - 删掉隐藏系统提示，工具描述砍掉 43%，基础输入从约 6000 降到约 2000 token。
  - 提出"interfaces beat examples"（接口胜过示例）。
- **LangChain《Improving Deep Agents with harness engineering》**，2026-02-17【一手】
  - 只改 harness，Terminal-Bench 2.0 从 52.8% 提到 66.5%。
  - 改动包括：退出前自检清单、启动时注入目录和可用工具、循环检测、时间预算提醒。没有逐项消融。
- **Anthropic《Scaling Managed Agents》**，2026-04-08【一手】
  - 会话是只追加的日志，harness 是大脑，沙箱是手，凭据永远进不了沙箱。
  - Sonnet 4.5 需要的上下文重置，到 Opus 4.5 变成"死重"。
- **Anthropic《Harness design for long-running application development》**，2026-03-24【一手】
  - 规划、生成、评估三代理；代理之间用文件通信。
  - 记录了"上下文焦虑"：接近上限时提前收工。
  - 原话："every component in a harness encodes an assumption about what the model can't do on its own"。
- **Anthropic 2026-04-23 质量复盘**【一手】
  - 系统提示里一条"≤25 词"的规则让两个模型都下降 3%。
  - 教训：每次改提示都要按模型跑评测、逐行消融、灰度发布。
- **OpenAI《Harness engineering》**，2026-02-11【一手 经代理抓取】
  - 一个大 AGENTS.md 失败了，原因："crowds out the task"、"When everything is 'important,' nothing is"。
  - 改成约 100 行的目录，指向 `docs/` 里的详细资料；不变量用 linter 和结构测试机械执行。
- **HumanLayer《Long-Context Isn't the Answer》**，2026-03-23【一手】
  - 从 1M 窗口的模型退回 200K 窗口的模型，原因是各种长度下指令遵循都下降。
  - 上下文告警改为固定 10 万 token。

### 3.3 缓存命中

- **DeepSeek 当前规则**（api-docs 页面，访问于 2026-10-13）【一手】
  - 硬盘缓存默认开启。缓存单元在"用户输入结尾"和"模型输出结尾"落盘，长输入按固定间隔落盘。
  - **只有完整匹配某个缓存前缀单元才命中**，部分重叠不算。
  - 尽力而为，不保证命中；不再使用后几小时到几天内清除。
  - 价格（谷时，每百万 token）：flash 命中 $0.003，未命中 $0.15，**比例 1/50**；pro 是 1/30。
  - 峰时价格翻倍：北京时间工作日 9–12 点、14–18 点。
  - 带工具的思考模式请求**必须回传此前全部轮次的 `reasoning_content`**，否则报 400。
  - 2026-09-10 起模型名改为 `deepseek-flash`，旧名只是临时路由。我们经 CPA 转发，实际映射未确认。
- **Anthropic 提示缓存文档**（当前版本）【一手】
  - 前缀顺序是工具 → 系统 → 消息，任何一层变化都会让这一层及之后的缓存失效。
  - 2026 年新增：中途增删工具不破坏缓存（07 月、09-22 两个 beta）；返回未命中原因（09-23 GA）。
- **Kimi K3 工具调用最佳实践**【一手】
  - 全局只放 `search_tools` 加少量核心工具，其余定义用追加的系统消息按需注入。
  - 改动早期声明会破坏命中；推理强度要在会话开始前定好。
- **DeepSeek Harness**（DeepSeek 官方开源，v0.1.7-rc.2，2026-09-24）【一手】："Dynamic tool additions without KV Cache invalidation"。
- **研究**
  - 《Don't Break the Cache》（2601.06007，2026-01）【一手 摘要页】：成本省 41–80%。只缓存系统提示、排除动态工具结果更稳定。
  - ContextPipe（2609.00749）【一手】：结构化重组上下文少用 30% token，但命中率从 95.3% 降到 86.2%。缓存价是原价 0.1 倍时，只追加反而便宜约 11%。只有缓存价超过原价 14.5% 时，压缩才划算。
  - **推论【推测】**：DeepSeek flash 的缓存价是 1/50，远低于 14.5%，所以对我们来说"只追加、晚压缩"几乎总是更省。
- **MCP 规范 2026-07-28**【一手】：`tools/list` 应按确定顺序返回，理由写的就是提升提示缓存命中。

### 3.4 压缩与上下文腐化

- **退化强烈依赖模型**
  - Boolean，2026-09-15【一手，博客，只有 20 题】：预填 25 万、50 万 token 后，有的模型从 31% 掉到 22%，有的基本不变；"相关"的旧内容伤害反而更大。
  - Chroma《Context Rot》，2025-07-14【一手·基线，仍是被引用最多的依据】。
- **"过早放弃"**：SII-GAIR 2606.29718【一手 摘要页】发现，模型远没用满窗口就放弃，而且随上下文变长加剧。
- **只截断、不改写**
  - Lewis 2608.26218【一手 摘要页】：上下文吃紧时机械截短旧工具结果，SWE-bench Verified 上 fail-to-pass 比例从 28% 提到 49%。
  - CliffCompaction 2609.26779【一手 摘要页】：只截断或丢弃，不改写，不二次压缩。成本最多降 50%。
- **各家的阈值**
  - Manus 约 128K–200K 开始压缩【摘要】；Phil Schmid 说 1M 窗口的模型通常在 256K 以内就开始退化【一手】。
  - Hermes 默认在窗口 50% 时压缩，保留开头 3 条和结尾 20%，并把超过 200 字符的旧工具输出换成占位文本【一手】。
  - Anthropic 服务端压缩默认 150K 触发【一手】。

### 3.5 记忆

- **Hermes Agent**（v0.21.7，2026-10）【一手】
  - MEMORY.md 2,200 字符，USER.md 1,375 字符。会话开始时冻结成快照注入，为的是保住前缀缓存；写满了报错，让 agent 自己合并。
  - 源码原话："Write entries as declarative facts, not instructions to yourself … imperative phrasing gets re-read as a directive in later sessions and can override the user's current request"。这是目前对"事实型"最明确的一手表述。
- **Claude Code 自动记忆**【一手】：MEMORY.md 索引只加载前 200 行或 25KB，主题文件按需读取。
- **Letta MemFS**【一手 文档】：用 git 支撑的记忆文件。改用文件的理由是通过 API 写记忆会重编译提示、破坏缓存【摘要】。
- **OpenClaw**（2026.10.2）【一手】：跑在 Codex app-server 上时，AGENTS.md 交给 Codex 原生加载；MEMORY.md 不每轮贴入，只放一条指向记忆工具的说明。
- **评测**：MERIT 2609.05441【一手 摘要页】：记忆实现不同，成功率最多差 60pp；结构化事实库处理"已更新的事实"明显好于嵌入检索。

---

## 4. 工具设计

### 4.1 数量与粒度

- **各家给出的"开局可见工具"上限**
  - OpenAI 函数调用指南："Aim for fewer than 20 functions available at the start of a turn"；每个命名空间少于 10 个【一手】。
  - Anthropic 工具搜索文档：超过 30–50 个工具后选择准确率下降；常用 3–5 个常驻【一手】。
  - MCP 客户端最佳实践（2026-07-28）：工具定义占上下文 1–5% 时就该考虑渐进发现【一手】。
  - Manus：少于 20 个原子函数【一手】。pi：只有 read/write/edit/bash 四个工具，系统提示加工具定义不到 1,000 token【一手】。
- **合并的方向**【一手·基线 2025-09，仍成立】：按意图合并，不要每个 API 端点对应一个工具；总是连着调用的合并成一个；用 search 代替 list；已知参数由宿主填好。
- **CLI 与 MCP 的有数据对照（2026）**
  - Vercel d0【一手·基线 2025-12-22】：十几个专用工具减到 2 个，耗时从 274.8s 降到 77.4s，token 降 37%。样本只有 5 题。
  - Braintrust/Vercel 反例，2026-01-22【一手】：结构化数据上，SQL agent 准确率 100%，bash agent 52.7%，token 多 7 倍。
  - Scalekit，2026-03-11【一手，作者在卖 MCP 网关】：简单任务 CLI 用 1,365 token，MCP 用 44,026 token。
  - Arize，2026-05【一手】：各方案正确率都约 0.83；MCP 在复杂任务上常常"退回 bash 去解析 JSON"，成本是技能方案的 6 倍以上。结论是本地、认证已配好用 CLI，远程、OAuth 用 MCP。
  - Simon Willison，2026-07-31【一手】：MCP 更容易审计和控制，敏感应用上会更多依赖 MCP。
- **代码模式**
  - Cloudflare，2026-02-20【一手】：`search()` 加 `execute()` 两个工具覆盖 2,500 多个端点，约 1,000 token。
  - Anthropic 程序化工具调用（2026-02-17 GA）【一手】：token −37%。
  - 《The Bitter Lesson of Tool Calling》2608.06370【一手】：14 个模型里有 11 个用代码调用不差于 JSON 调用。
  - Codex 源码【一手】：OpenAI 新模型的 `tool_mode` 都是 `code_mode_only`。
  - 代价：需要沙箱；单步任务反而更慢（goose 2025-12）【一手】。

### 4.2 MCP 工具过多：工具搜索、延迟加载

- **Claude Code**【一手】
  - v2.1.7（2026-01-14）起，工具描述超过上下文 10% 时延迟加载；2026-03 起所有工具默认延迟。
  - `alwaysLoad` 豁免（04-28）。
  - 经搜索加载的工具描述，截断上限提到 16,384 字符（10-08）。
- **Codex**【一手】
  - 0.142.2（2026-06-25）起 MCP 工具默认走工具搜索。
  - **只有模型元数据 `supports_search_tool=true` 时才延迟加载。未知模型走回退元数据，这个值是 false**，所以 Codex 跑 DeepSeek 时，MCP 工具会全量暴露。
  - 插件 MCP schema 有预算：单个 8,000 字节，总共 64,000 字节。
- **MCP 规范 2026-07-28**【一手】
  - 协议改为无状态；`tools/list` 按确定顺序返回；`list_changed` 改走订阅。
  - 渐进发现仍然没有进规范本体，只在 2026-08-22 的路线图里。
  - 技能扩展 SEP-2640 已定稿【一手，合并日期为摘要】。
- **Cursor**（2026-01-06）【一手】：工具描述同步到文件夹按需查阅，总 token 降 46.9%；长工具输出写进文件。
- **研究**【一手 摘要页】
  - 2605.24660：自适应短名单把展示的工具数从 50 降到 7，覆盖率不变。
  - MCPEvol-Bench 2607.14642：工具接口演化后，表现下降约 14%。所以接口稳定本身有价值。

### 4.3 返回值

- **Anthropic《Writing effective tools for agents》**，2025-09-11【一手·基线，仍成立】
  - 返回语义化名称而不是 UUID。
  - 用 `response_format` 区分简洁和详细两档，简洁版约为详细版的 1/3。
  - 分页、过滤、截断要有合理默认值，截断时告诉 agent 下一步怎么做。
  - 错误要给出具体可操作的修正，不要甩调用栈。
- **MCP 规范 2026-07-28**【一手】
  - 工具执行错误用 `isError: true` 放在结果里，原文是"contain actionable feedback that language models can use to self-correct"。输入校验错误也归为工具执行错误（2025-11 起）。
  - 返回结构化内容的工具，同时应该给一份序列化文本。路线图承认两者并存"让作者困惑"，结果形态还会重新设计。
- **12-factor 第 9 条**【一手·基线，仍成立】：错误压缩进上下文，连续约 3 次失败就升级给人。
- **截断策略**
  - Codex【一手 源码 + 实测】：超限时从**中间**截掉，头尾各留一半，前面加一行头"original token count / Total output lines"。
    - 本机 0.144.1 + deepseek-v4.1-flash 实测保留 10,000 token。
    - 调研员读的上游主干显示，回退模型按 10,000 **字节**截。如果升级后真是这样，可见输出会缩到约 3,300 个汉字【推测，需升级后实测】。
    - 可用 `tool_output_token_limit` 调整。
  - Claude Code【一手】：Bash 内联约 30,000 字符，超出就给文件路径加 2,000 字符预览；MCP 默认上限 25,000 token。
  - Carlini 的并行编译器实验（Anthropic 2026-02-05）【一手】：测试输出要精简，把错误原因和"ERROR"写在同一行方便 grep，并预先算好汇总。
- **格式**
  - ImprovingAgents（2025-09，GPT-4.1-nano）【一手·基线】：Markdown 键值格式的准确率高于 JSON，token 也更少。HN 上有人复测，100 行以内各种格式差别不大【摘要】。
  - 《Notation Matters》2605.29676【一手】：紧凑格式能省 18–27% token，但有的格式会降准确率、弄坏并行调用。
  - 结论：格式的影响小于"少返回"。

### 4.4 命名空间

- MCP 工具名（SEP-986，2025-11 起）【一手】：1–128 个字符，字符集为 `[A-Za-z0-9_.-]`；示例 `admin.tools.list` 说明点号可以做命名空间。聚合多个服务器时应加服务器前缀。
- Anthropic【一手】：前缀和后缀两种命名方式效果不同，要用评测决定。
- OpenAI【一手】：用 namespace 分组，每组少于 10 个函数。模型主要是在 namespace 或 MCP 服务器这两种分组上训练搜索的。

---

## 5. 系统提示与 AGENTS.md

### 5.1 各家怎么做（版本、日期均为访问于 2026-10-13）

| 系统 | 常驻文件 | 注入方式 | 上限或建议 | 按需加载 | 风格 |
|---|---|---|---|---|---|
| Codex 0.162.1 | AGENTS.md / override / 备用文件名 | 作为 user 消息；`thread/start` 也可以传 `developer_instructions`、`base_instructions` | **项目说明合计 32 KiB，按字节硬截，不提示模型** | 技能（只注入名字、描述、路径）、子目录 AGENTS.md | 偏事实和约束 |
| Claude Code 2.1.296 | CLAUDE.md、rules、MEMORY.md 索引 | 系统提示之后的 user 消息 | 每个文件少于 200 行；索引 200 行或 25KB | 技能、按路径生效的规则、子目录懒加载 | 事实优先 |
| OpenClaw 2026.10.2 | AGENTS / SOUL / IDENTITY / USER / MEMORY | 系统提示；跑在 Codex 上时走原生加载，人格走开发者说明 | 每个文件 2 万字符，合计 6 万；截断时提示模型去读原文件 | 技能列表、记忆搜索 | 指令型加人格 |
| Hermes v0.21.7 | 一个上下文文件，加 SOUL 和记忆 | 系统提示，冻结快照 | 至少 2 万字符或窗口的 6%，保留头 70%、尾 20%；记忆 2,200 + 1,375 字符 | 三级技能、会话检索 | **明确要求事实型** |
| OpenHands SDK 1.54 | AGENTS.md | 系统提示 | 记忆索引约 6,000 字符 | 渐进技能、关键词和路径触发 | 混合 |
| Goose 1.54 | AGENTS.md / .goosehints | 每次请求进系统提示 | 要求简短 | 文件引用按需读取 | 混合 |
| Cline 3.0.70 | .clinerules/ | 拼在系统提示末尾 | 文档提醒"规则消耗 token" | 按路径的条件规则 | 偏指令型 |
| pi 1.2.0 | AGENTS.md / CLAUDE.md | 系统提示底部 | 提示本身不到 1K token | 技能 | 极简 |

（来源：各家文档或源码【一手】，Goose 的工具管理细节为【摘要】。）

### 5.2 研究证据（2026）

| 研究 | 规模 | 发现 |
|---|---|---|
| Gloaguen 等（ETH），2602.11988，v3 09-29【一手】 | SWE-bench Lite 300 题 + 新基准 CTXbench 138 题 | LLM 生成的说明文件让成功率略降（不显著），成本 +20–23%；人写的有时有益，但不稳定。仓库概览没有帮助，而 95–100% 的生成文件都含概览。**文件里点名的工具每题使用 2.5 次，不点名时少于 0.05 次**。结论：人写，只写"额外要求" |
| Lulla 等，2601.20404【一手】 | 10 个仓库、124 个 PR | 有 AGENTS.md 时中位运行时间 −28.6%，输出 token −16.6%，完成度相当 |
| Khatri，2607.27250【一手】 | Claude Code 和 Codex，288 次运行 | 上下文策略对正确率没有可测影响；失败的原因是实现能力不足 |
| McMillan，2605.10039【一手 摘要页】 | 1,650 个会话 | 文件大小、位置、格式、自相矛盾都没有可检测的效应；会话越长，指令遵循越差 |
| Chakrabarti，2608.11095【一手 摘要页】 | 1,867 个仓库 | 说明文件在整个生命周期里增长 226%，几乎只增不减；给每条指令写明理由，才能事后删掉冗余 |
| 2606.20512【一手 摘要页】 | SWE-bench Verified | 用探测结果反复修订说明文件，解决率从 25.5% 升到 33.0%，增益来自定位到正确文件 |

### 5.3 共识：事实还是指令、多长、常驻还是按需

- **常驻文件只放"推不出来、每次都需要"的东西**：环境、语义、约束、非常规约定、坑。
  - Claude 文档原话："Keep it to facts Claude should hold in every session … If an entry is a multi-step procedure or only matters for one part of the codebase, move it to a skill or a path-scoped rule"。
  - Hermes 明确要求用事实陈述，不写对自己的命令。
- **长度**
  - OpenAI：约 100 行，当目录用。
  - Claude：每个文件少于 200 行，逐行问"删掉它 Claude 会出错吗？"。
  - Codex：短而准确的 AGENTS.md 胜过长篇模糊规则。
  - HumanLayer（2025-11·基线，原则仍成立）：少于 300 行，他们自己的根文件不到 60 行。但"系统提示约 50 条指令"这个数字已经过时，不要再引用。
- **按需加载**：流程放进技能，只和某个路径相关的内容放进子目录或路径规则，强制性的规则交给代码或 hook。
- **对"只写事实"的修正**：ETH 的研究表明，指令会被可靠执行，而"仓库概览、目录导览"这类事实对成功率没有帮助。所以"事实"应该理解为**语义和约束**，不是导览。
- **强调词要克制**：Claude 文档说"If you emphasize many lines, none of them stands out"。

### 5.4 Codex 的具体行为（对我们最要紧）

- **【一手 源码】项目说明的上限**：`project_doc_max_bytes` 默认 32,768 字节。
  - 超出时直接按字节截断，再做有损的 UTF-8 转换。中文可能截出乱码字符。
  - **模型看不到截断提示**，只在日志里留一条记录。
  - 全局 `~/.codex/AGENTS.md` 不占这 32 KiB。
- **【一手 源码】信任门**：2026-08-21 合入的 #39837 规定，**不受信任的项目完全不读 AGENTS.md**。
- **【一手 源码】说明中途变化时会重新注入**：重新注入的消息开头写"These AGENTS.md instructions replace all previously provided AGENTS.md instructions."。这是追加的消息，不改前缀，所以不破坏缓存。
- **【一手】`thread/start` 可以传 `developer_instructions`**，作为 developer 角色消息注入。OpenClaw 就是用它放人格。这条路径有没有 32 KiB 上限，调研员没有完全确认。
- **【一手 源码】2026 年的 Codex 系统提示已改为按模型下发**，删掉了原来的 AGENTS.md 规范段和计划工具段。
- 以上前三条都是 0.144.1 之后的行为，我们现在用的版本还没有【推测：升级时会撞上】。

---

## 6. 子代理与帮手

- **何时隔离**（共识）：输出冗长、任务能独立完成并用一段摘要交回、或者需要限制工具时才隔离。需要共享隐含决定时，用分叉（继承全部上下文、复用缓存），或者干脆单线程【一手：Claude Code 子代理文档、LangChain 09-08、Cognition 04-22】。
- **结果怎么回传**（共识）：只回最终报告，内容浓缩；大件产出写进文件，只传路径。
  - Anthropic 2025-06：传轻量引用，避免"传话游戏"【一手·基线，仍成立】。
  - Codex 文档："Return summaries from subagents instead of raw intermediate output"【一手】。
- **交代任务**：子代理看不到父会话，交代时必须把路径、错误、已经做的决定都写进去【一手：Agent SDK、Hermes"must pass everything"】。
- **Codex 子代理**【一手 源码】
  - 多代理功能默认开启。v2 工具在 `collaboration` 命名空间下，每个会话默认最多 4 个并发线程。
  - 子线程结束后，结果以"只入队、不开回合"的方式投递给父线程。**父回合已经结束时，结果要等下一回合才被看到**。
  - v2 的投递格式是 `Message Type: FINAL_ANSWER … Payload: …`，没有"由你决定"之类的框架语。
- **Claude Code**【一手】
  - 后台子代理成为默认。完成通知会标为"自动事件，不是用户消息"，并说明报告里的指令"carry no authority from you"。v2.1.210 起还会中和报告里伪造的系统标签。
  - 嵌套深度默认 3，并发默认 20。
- **反面教训**：Claude Code 的 Routines 早期把触发提示包装成"不可信通知"，结果模型拒绝执行。v2.1.213 改为把它当作指派的任务，只把附带数据标为不可信【一手】。标注过度和不标注一样有害。
- **用评审代替自评**：自评会系统性地偏乐观。2026 年的标准做法是用独立上下文的验证者来评审【一手：Anthropic 03-24、06-02，LangChain 02-17】。

---

## 7. 长时间运行、后台任务与唤醒

- **Codex app-server**【一手】
  - 有 `thread/start|resume|fork`、`turn/start|steer|interrupt`、`thread/inject_items`（追加条目但不开回合）、`thread/goal/*`。
  - **没有服务端主动开回合的方法，唤醒只能由宿主发 `turn/start`**。
  - Codex 自己的 hooks（12 个事件）在 2026 年 4–5 月转为稳定，两处资料日期略有出入。
- **Claude Code**【一手】
  - hooks 增加到 30 多个事件。`asyncRewake` 让后台 hook 以退出码 2 唤醒模型，输出以系统提醒的形式出现。
  - `Monitor` 把后台脚本的每行输出推给模型；`ScheduleWakeup` 和 cron 只在回合之间、空闲时触发，**错过的不补跑**。
  - Channels 由 MCP 服务器推送事件进运行中的会话，忙时排队。
  - Routines 在云端运行，每次运行都是新会话。
- **OpenClaw**（2026.10.2）【一手】
  - 心跳：默认 30 分钟一次。官方建议心跳用隔离会话加轻上下文，单次从约 100K token 降到 2–5K。HEARTBEAT.md 已改为数据库里的草稿区，`HEARTBEAT_OK` 约定被 `heartbeat_respond` 工具取代。
  - 定时任务改名 automations，有四种载荷，其中"系统事件"只入队、不调用模型。
  - 外部触发：`/hooks/wake` 入队一条系统事件；`/hooks/agent` 发起一个回合，外部内容默认做安全包裹。
  - 子代理完成时的注入文本：首行是"This context is runtime-generated, not user-authored"，结尾要求"对照用户要的结果，再判断任务是否完成"。
- **Hermes**【一手】
  - 定时任务在全新会话里运行。纯脚本任务输出 `{"wakeAgent": false}` 就跳过模型，原文称之为"cheap pre-run gates"（廉价的预检闸门）。
  - 回复只有 `[SILENT]` 时不投递。
- **共识**：事件在回合之间投递，忙时排队；要有静默出口；注入的内容要标明来源。
- **分歧**：唤醒落在主会话（OpenClaw main、Claude Code channels），还是新开隔离会话再回报（Routines、Hermes cron、OpenClaw isolated）？各家选择不同。

---

## 8. 对照我们的 harness

### 8.1 现状实测

| 项目 | 数值 | 出处 |
|---|---|---|
| 种子 AGENTS.md | 25,621 字节，244 行，约 6,263 token | 【实测】DeepSeek V3 分词器 |
| 其中「NipaPlay 的构成」一节 | 约 2,906 token，占 46% | 【实测】 |
| 种子增长 | 2026-10-11 是 5,018 字节，10-13 是 25,621 字节，共 36 次提交；最近一次（X47）+1,477 字节 | 【实测】git 历史 |
| 离 Codex 32 KiB 上限还剩 | 7,147 字节（约 2,400 个汉字） | 【实测】 |
| 文件末尾三节 | 「授权」从第 22,367 字节开始，「hooks」从 23,631 开始，「维护」从 24,194 开始 | 【实测】 |
| 被截掉的临界点 | 前面再增加 +7.1KB，「维护」开始被截；+9.1KB，「授权」开始被截；+10.4KB，「授权」整节消失 | 【实测】按截断规则推算 |
| 用户真实 harness 的 AGENTS.md | 19,635 字节 | 【实测】 |
| hooks/README、tools/README | 1,157 和 878 token，按需读取，不常驻 | 【实测】 |
| `nipa` 输出体积 | 10-11 共 716 次调用，p50 是 693 字节，p90 是 3,897 字节；10-12/13 共 99 次，p50 是 1,467 字节，p90 是 14,721 字节 | 【实测】会话记录 |
| 被 Codex 截断的 `nipa` 输出 | 14 次（10,000 token 处从中间截）：`status`、`list`（旧版）、`call state.describe`（37,127 token 截掉 27,127）、`call media.library.works`、`describe media.library.works`、`describe media.metadata.override`、`call media.sources.query`、`query library.files/works` | 【实测】 |
| 缩进 JSON 和紧凑 JSON 的 token 比 | 1.27（多 27%） | 【实测】280 万 token 的证据 JSON 样本 |
| 缓存命中 | 实验配置 143 次请求，输入 2,050 万 token，命中 96.5%，单次最大 201K；EXPERIMENTS 记录 99–99.9% | 【实测】 |
| Codex 版本 | 本机 0.144.1，上游最新 0.162.1（10-09） | 【实测】/【一手】 |
| 信任门 | 本机 `~/.codex/config.toml` 里手动把 harness 路径标成了 trusted；`lib/next` 里没有登记信任的代码 | 【实测】 |

### 8.2 已经符合前沿的

1. **能力入口的形态**
   - 函数层是 Codex 自带的一小套固定工具，约 100 个能力都在 `nipa` 后面，用 `list → describe → call` 三层发现。这和 MCP 2026-07 的客户端最佳实践、Cloudflare 的 search/execute、Manus"少于 20 个原子函数加 CLI"、pi、Kimi `search_tools` 是同一个模式。
   - 函数层不变，所以不会因为增删能力破坏缓存。
   - 我们本来就是本地运行、认证由 `nipa` 处理好、调用方式是常见的命令行，正是 Arize 结论里适合 CLI 的条件。
   - RESEARCH.md 的开放问题"命令行还是 MCP"，在我们这种运行时上已有相当清楚的外部证据：Codex 对 DeepSeek 不启用工具搜索【一手 源码】。
2. **种子以事实为主**：和 Claude 文档、Hermes 源码、OpenHands 的写法一致。"授权"写的是边界，不是步骤；"你的工作"写的是目标和优先级。
3. **种子点名了关键能力**，比如 `media.metadata.ui_facts`、`danmaku.import`、`bind_batch`。ETH 的研究显示，点名会让工具真正被用上。实验 11 到 12 的对比也说明，`ui_facts` 和种子里的事实让"补简介"从 9 分钟没完成变成 1 分半完成。
4. **返回值**
   - 信封统一为 completed / needs_decision / failed。错误带 code、retryable 和逐字段的 violations，对应 MCP 的"在结果里返回可操作错误"。
   - `NeedsDecision` 给出可以直接执行的调用，对应 12-factor 的"用工具调用联系人"。
   - 查询默认每页 50 行，支持 `select` 和 `nextCursor`，对应 Anthropic 的分页建议。
   - `ui_facts` 一次给出界面缺什么，对应"预取上下文"和"返回有意义的上下文"。
   - 公开链接不再脱敏；截图默认缩小到长边 1280。
5. **缓存**：前缀稳定，唤醒文本是追加进来的。实测命中 96.5–99.9%。
6. **"后续"机制**正好补上 Codex 的缺口：子代理结果只入队不开回合，app-server 也不会主动开回合。我们的后续由宿主发 `turn/start`，并且持久化、忙时排队、重复投递用同一回执。这和 Claude Code 的完成通知、OpenClaw 的完成事件同构。
7. **hooks 和定时程序是廉价的预检闸门**：脚本先检查，需要判断时才 `agent.wake`，只记发现时用 `activity.report`。这和 Hermes 的 `wakeAgent:false`、OpenClaw 只入队的系统事件一致。错过的运行不补跑，和 Claude Code cron 相同。
8. **隔离运行有了入口**：`agent.dispatch` 开独立回合，结果回到主会话，对应 OpenClaw 隔离的定时任务和 Hermes 的全新会话。
9. **环境层的硬边界**：删除硬盘文件必须在 NipaPlay 界面确认；本地端点不走代理；秘密会脱敏。这和 Anthropic 2026-05"先在环境层隔离"的结论一致。
10. **经验笔记要"写清何时、怎样确认"**：这正是 2026 年对自我改进的主要修正——没有验证的自写知识不可靠（SkillsBench、EVOMAL），也对应 Anthropic 的"assert it or drop it"。

### 8.3 冲突或落后的

| 问题 | 我们现在 | 前沿做法 | 证据强度 |
|---|---|---|---|
| 种子会被静默截断 | 25.6KB，三天涨了 5 倍，末尾是授权；Nipa 还被要求往里写环境和经验 | Codex 按 32 KiB 硬截且不提示；OpenAI 用约 100 行的目录；Claude 每个文件少于 200 行；说明文件只增不减（+226%） | 【一手 源码】+【实测】 |
| 能力语义写在常驻说明里 | 「构成」一节约 2,900 token，详细写了字幕、弹幕、下载的语义 | 工具用法只写在工具定义里，不重复（Claude 07-24）；我们的工具定义就是 `describe` | 【一手】；收益大小为【推测】 |
| 大输出被从中间截掉 | `nipa` 没有输出预算，`describe` 有的超过 10K token | Claude Code 和 Cursor 把大结果写进文件，只给路径和预览；截断时附下一步建议；Codex 自己给插件 schema 设了 8KB 预算 | 【实测】+【一手】 |
| JSON 带缩进 | `indent=2` | 少返回、紧凑返回 | 【实测】多 27% token |
| 错误不够可操作 | `Unknown action: X.` 不给相近的名字；参数错误只说"use --help"，丢掉了 argparse 的具体原因；HTTP 错误丢掉了响应体 | 错误要带可用值和修正方法 | 【一手】；我们的错误率数据没统计 |
| 信任门 | 新用户的 harness 没有登记信任；本机是手动登记的 | Codex 08-21 起不读不受信任项目的 AGENTS.md | 【一手 源码】；对新用户的影响是【推测】 |
| 唤醒消息的来源与权限标注 | 文本是"这是宿主派发的新回合……下一步由你决定"，没有说明它不是用户的话、facts 是数据 | Claude Code 和 OpenClaw 都标明"不是用户写的、不带用户授权"，同时避免标得过度导致拒绝执行 | 【一手】；风险程度是【推测】 |
| 压缩时机 | 单一主会话、1M 窗口，由 Codex 默认阈值压缩；实测单次请求已到 20 万 token | 多数资料在 128K–256K 之间就开始管理上下文；长上下文退化依赖模型 | 【一手】；对 DeepSeek 的影响是【推测】 |
| 实验方法 | 每个实验跑一次，主要看完成与否 | harness 差异常落在噪声里；要重复跑，看"每解出一题的成本"和失败分类；改提示要做消融 | 【一手】2607.22585、2609.17394、Anthropic 04-23 |

### 8.4 建议（按收益排序）

每条写明：做什么、为什么、怎样观察。都符合"给工具和基础设施、代码只保证不变量、写事实不写步骤"的原则。

**1. 给种子减重，并把截断变成可见的事实。收益最高，成本低。**
- **做什么**
  - 把「NipaPlay 的构成」里能力级的语义，挪到对应能力的 `describe` 说明里。例如字幕选择顺序放进 `subtitle.*`，弹幕轨道的去重与刷新放进 `danmaku.import`，下载回执放进 `download.*`。常驻文件只留跨能力的事实：数据归谁管、怎样才算"一部完整的作品"、界面读什么。
  - 剩余的参考资料可以放进 harness 里一个按需读取的文档，种子里留一行指向它。
  - 把「授权」挪到前部。
  - 让 `nipa status` 报告 AGENTS.md 的字节数和 Codex 的上限。这是事实，不是规则，Nipa 看到快满了自然会整理。
- **为什么**：Codex 按字节静默截断，被截的是末尾的授权（【一手 源码】+【实测】）。工具用法只写一处（Anthropic 07-24）。约 100 行的目录（OpenAI 02-11）。这也是我们自己的原则："需要说明才能用好的工具，就去修工具"。
- **怎样观察**：用实验 16 那句"整理一下"在同一份数据上跑，比较减重前后的回合数、token 和完成度；至少重复 3 次。
- **可信度**：截断风险是一手加实测；减重不降质量是【推测】，Anthropic 和 LangChain 在自家模型上测过，DeepSeek 上需要我们自己测。

**2. 给 `nipa` 设输出预算，大结果落盘。收益高，成本低。**
- **做什么**
  - 输出超过约 6–8K token（约 20KB）时，把完整 JSON 写进 `records/`，标准输出只给摘要：总数、前几条、`nextCursor`、文件路径。
  - 默认输出改为紧凑 JSON，`--pretty` 可选。
  - 给 `describe` 定一个体积目标，比如 8KB。`state.describe` 改成先列视图名、再按名取详情。
- **为什么**：Codex 已经在 10,000 token 处从中间截掉了 14 次（【实测】），截掉的是 JSON 中段，Nipa 看到的是一份残缺的数据。Claude Code、Cursor 都把大结果写进文件，只给路径和预览（【一手】）。紧凑 JSON 少 27% token（【实测】）。如果 Codex 升级后回退模型改按字节截，问题会更严重（【推测】）。
- **怎样观察**：统计会话记录里的截断次数，以及 Nipa 用 Python 二次过滤 `nipa` 输出的次数。

**3. 确认信任门与 Codex 版本。收益高，属于正确性问题。**
- **做什么**
  - 用干净的 `CODEX_HOME`，在 0.162.x 上开一个新 harness，看 AGENTS.md 和 `.codex/config.toml` 是否加载。
  - 如果没有加载，就在用户开启 Next 的知情同意之后，由宿主登记信任。也可以考虑改走 `thread/start` 的 `config` 覆盖或 `developer_instructions`。
- **为什么**：Codex 2026-08-21 起不读不受信任项目的 AGENTS.md（【一手 源码】）；本机能用，是因为手动登记过（【实测】）。
- **可信度**：机制是一手；对新用户确实会失效是【推测】，需要实测。

**4. 让 `nipa` 可以作为 Python 模块导入（代码模式的轻量版）。收益中高，成本低。**
- **做什么**：提供 `import nipa` 或类似入口，`call()` 返回字典，失败时抛出带 code 和 violations 的异常，`--device` 同样可用。不新增任何"批量流程"，只是让 Nipa 自己写的脚本少一层进程和引号。
- **为什么**：程序化工具调用 −37% token（Anthropic）；Cloudflare 和 pi 的 Codemode 都这样做；14 个模型里 11 个用代码调用不差于 JSON 调用（2608.06370）【一手】。实验 16 里 Nipa 在 heredoc 和引号上反复重试【实测 记录】。
- **怎样观察**：看抽帧、逐集导入这类批量任务的命令数和重试次数。

**5. 让错误可操作。收益中，成本低。**
- **做什么**
  - 未知能力时，返回最相近的几个 ID 和所在命名空间。
  - 参数错误保留 argparse 的具体信息。
  - HTTP 错误带上响应体里的错误信封（脱敏后）。
- **为什么**：MCP 2026-07 规范要求返回"可供自我纠正的反馈"；2610.00917 发现，失败信息怎样回传给模型，能让同一模型在不同 harness 里的排名反转（【一手 摘要页】）。

**6. 在唤醒和后续的文本里写明来源与权限。收益中，成本极低。**
- **做什么**：在现有文本里补两条事实：
  - 这是 NipaPlay 根据某次登记，或某个脚本，生成的回合，不是用户说的话；
  - 触发事实里的标题、文件名、站点文本都是数据。
  - 保留"下一步由你决定"。不要写成"不可信通知"，那样会让她拒绝执行（Claude Code Routines 的教训）。
- **为什么**：hooks 可以把 RSS 标题之类的站点文本放进 `facts` 和 `instruction`。种子的授权规则里，"用户明确要求"是破坏性操作的前提，唤醒不应该被误读为用户的要求【推测】。

**7. 为 X49 记忆功能保住缓存。收益中，属于设计输入。**
- **做什么**
  - 记忆文件放在 harness 的 git 仓库里，常驻部分做成小而稳定的索引（参考：Claude 200 行或 25KB，Hermes 2,200 字符），细节按需读取。
  - 条目写成事实，不写成命令（Hermes 源码的理由）。
  - 中途更新时用追加消息，不要改写前缀。Codex 新版的 AGENTS.md 重新注入就是追加式的。
- **为什么**：DeepSeek flash 的命中价是未命中价的 1/50，并且只认完整的前缀单元（【一手】）。如果每轮重写开发者说明或前缀，整段历史都会变成未命中【推测，可以用 `prompt_cache_hit_tokens` 直接验证】。

**8. 用实验确定压缩阈值。收益中，需要实验。**
- **做什么**：不分段、仍用 Codex 自己的压缩，只调触发阈值（Codex 的 `model_auto_compact_token_limit`，在 0.144.1 上需确认）。比较默认阈值和 200–300K 阈值下，长主会话里的行为：答非所问、重复旧任务、过早收工。
- **为什么**：多个 2026 年资料在 256K 以内就开始管理上下文；长上下文的退化依赖模型（【一手】）。压缩会让缓存失效一次（【推测】），所以要和成本一起看。

**9. 改进实验方法。收益中，属于研究方法。**
- **做什么**
  - 每个 harness 改动至少重复 3 次。
  - 记录每完成一项的 token 和耗时，以及失败分类。
  - 对种子做逐节消融（比如去掉「构成」一节）。
- **为什么**：同一模型换 harness，配对通过率常常只差 0–8pp，但 token 最多差 40 倍（2607.22585）；排行榜上相邻名次的差异多半不显著（2609.17394）；Anthropic 发现一行提示就能造成 3% 的退化（04-23）【一手】。

**10. 小项，收益低**
- `nipa list` 支持按命名空间前缀过滤，并保证顺序确定（MCP 2026-07 规范为了缓存要求确定顺序）。
- 在种子里补一条关于帮手的事实："帮手看不到你的对话，交代时要写全路径和已做的决定"（Agent SDK、Hermes 都这样要求）。
- DeepSeek 的峰谷价和模型改名可以作为环境事实，由 Nipa 写进「环境」。我们经 CPA 转发，实际价格和映射未确认。
- Codex hooks（SessionStart / PostCompact）可以在会话开始时预取一份 `nipa status` 摘要（12-factor 第 13 条、LangChain 的本地上下文中间件）。先做实验，不预设。

---

## 9. 一手确认与推测的清单

**一手确认（原文、官方文档或源码）**
- Codex 32 KiB 按字节硬截且不提示模型；信任门 #39837；`developer_instructions` 能在 `thread/start` 传入；子代理结果只入队不开回合；app-server 没有服务端主动开回合；未知模型不启用工具搜索。
- DeepSeek 缓存规则、1/50 的价格比、思考模式必须回传 `reasoning_content`、模型改名。
- Anthropic 2026 年各篇文章、提示缓存规则、工具搜索 GA；MCP 2026-07-28 规范与客户端最佳实践。
- ETH、Lulla、Khatri 等论文的数字（ETH 读了正文表格，其余为 arXiv 摘要页）。
- Claude Code、OpenClaw、Hermes 的文件上限与注入方式。

**本机实测**
- 种子体积与增长、各节位置、token 数；`nipa` 输出体积与 14 次截断；缩进 JSON 多 27% token；缓存命中 96.5%；Codex 版本与信任登记。

**推测（需要实验）**
- 减重后 Nipa 在 DeepSeek 上表现不变或更好。
- 新用户在新版 Codex 上读不到种子。
- Codex 升级后回退模型改按字节截断。
- 唤醒文本缺少来源标注会造成越权。
- 降低压缩阈值对长主会话有益。
- 记忆更新方式对缓存的影响。

**【摘要】级、引用前需复核**
- Manus 内部"约三分之一动作在维护 todo"。
- OpenClaw 子代理深度上限 5。
- 部分厂商发布日期（Gemini CLI 退役、A2A 1.0）。
- Codex hooks 的稳定日期（两处资料差约一个月）。

---

## 10. 来源

（日期为发布日期；文档页无日期时，写访问于 2026-10-13。）

**2024–2025 基线**
- Anthropic, Building effective agents, 2024-12-19: https://www.anthropic.com/engineering/building-effective-agents
- Anthropic, Effective context engineering for AI agents, 2025-09-29: https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents
- Anthropic, Writing effective tools for agents, 2025-09-11: https://www.anthropic.com/engineering/writing-tools-for-agents
- Anthropic, Equipping agents with Agent Skills, 2025-10-16（2025-12-18 成为开放标准）: https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills · https://agentskills.io
- Anthropic, Effective harnesses for long-running agents, 2025-11-26: https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents
- Anthropic, Introducing advanced tool use, 2025-11-24: https://www.anthropic.com/engineering/advanced-tool-use
- Anthropic, Code execution with MCP, 2025-11-04: https://www.anthropic.com/engineering/code-execution-with-mcp
- Anthropic, How we built our multi-agent research system, 2025-06-13: https://www.anthropic.com/engineering/multi-agent-research-system
- Manus, Context Engineering for AI Agents, 2025-07-18: https://manus.im/blog/Context-Engineering-for-AI-Agents-Lessons-from-Building-Manus
- Lance Martin, Context Engineering in Manus, 2025-10-15: https://rlancemartin.github.io/2025/10/15/manus/
- Cognition, Don't Build Multi-Agents, 2025-06-12: https://cognition.ai/blog/dont-build-multi-agents
- LangChain, Context Engineering for Agents, 2025-07-02: https://www.langchain.com/blog/context-engineering-for-agents
- HumanLayer, 12-Factor Agents, 2025-04 起: https://github.com/humanlayer/12-factor-agents
- HumanLayer, Writing a good CLAUDE.md, 2025-11-25（文章链接未在调研中记录）
- Chroma, Context Rot, 2025-07-14: https://www.trychroma.com/research/context-rot
- Cloudflare, Code Mode, 2025-09-26: https://blog.cloudflare.com/code-mode/
- Mario Zechner, What if you don't need MCP, 2025-11-02: https://mariozechner.at/posts/2025-11-02-what-if-you-dont-need-mcp/ ；pi coding agent, 2025-11-30: https://mariozechner.at/posts/2025-11-30-pi-coding-agent/
- Vercel, We removed 80% of our agent's tools, 2025-12-22: https://vercel.com/blog/we-removed-80-percent-of-our-agents-tools
- Armin Ronacher, Skills vs Dynamic MCP Loadouts, 2025-12-13: https://lucumr.pocoo.org/2025/12/13/skills-vs-mcp/

**2026：上下文与 harness**
- Mitchell Hashimoto, My AI Adoption Journey, 2026-02-05: https://mitchellh.com/writing/my-ai-adoption-journey
- OpenAI, Harness engineering, 2026-02-11: https://openai.com/index/harness-engineering/
- LangChain, Improving Deep Agents with harness engineering, 2026-02-17: https://www.langchain.com/blog/improving-deep-agents-with-harness-engineering
- Birgitta Böckeler, Harness engineering, 2026-04-02: https://martinfowler.com/articles/harness-engineering.html
- Anthropic, Building a C compiler with parallel Claudes, 2026-02-05: https://www.anthropic.com/engineering/building-c-compiler
- Anthropic, Harness design for long-running apps, 2026-03-24: https://www.anthropic.com/engineering/harness-design-long-running-apps
- Anthropic, Scaling Managed Agents, 2026-04-08: https://www.anthropic.com/engineering/managed-agents
- Anthropic, April 23 postmortem, 2026-04-23: https://www.anthropic.com/engineering/april-23-postmortem
- Anthropic, How we contain Claude, 2026-05-25: https://www.anthropic.com/engineering/how-we-contain-claude
- Anthropic, Dynamic workflows in Claude Code, 2026-06-02: https://claude.dev/blog/a-harness-for-every-task-dynamic-workflows-in-claude-code/
- Anthropic, The new rules of context engineering for Claude 5, 2026-07-24: https://claude.dev/blog/the-new-rules-of-context-engineering-for-claude-5-generation-models/
- Anthropic, Building effective agent automations, 2026-10-08: https://claude.dev/blog/building-effective-agent-automations/
- HumanLayer, Long-Context Isn't the Answer, 2026-03-23（链接未在调研中记录）
- Cognition, Multi-Agents: What's Actually Working, 2026-04-22: https://cognition.com/blog/multi-agents-working
- LangChain, Deep Agents v0.7, 2026-07-29；Organizing Context in a Multi-Agent Harness, 2026-09-08（LangChain 博客）
- Manus, Introducing Manus 2.0, 2026-09-28（manus.im 博客）
- Boolean, Context rot quantified, 2026-09-15: https://www.boolean.ai/blog/context-rot-quantified

**2026：工具与 MCP**
- MCP 规范 2026-07-28 Tools: https://modelcontextprotocol.io/specification/2026-07-28/server/tools
- MCP Client Best Practices: https://modelcontextprotocol.io/docs/2026-07-28/develop/clients/client-best-practices
- Cloudflare, Code Mode MCP, 2026-02-20: https://blog.cloudflare.com/code-mode-mcp/
- Cursor, Dynamic context discovery, 2026-01-06: https://cursor.com/blog/dynamic-context-discovery
- Vercel/Braintrust, Testing if bash is all you need, 2026-01-22: https://vercel.com/blog/testing-if-bash-is-all-you-need
- Scalekit, MCP vs CLI, 2026-03-11: https://www.scalekit.com/blog/mcp-vs-cli-use
- Arize, MCP vs CLI Skills, 2026-05: https://arize.com/blog/mcp-vs-cli-skills-for-agents-what-our-eval-found-and-which-you-should-use/
- Simon Willison, Stateless MCP, 2026-07-31: https://simonwillison.net/2026/Jul/31/stateless-mcp/
- Armin Ronacher, What is Codemode, 2026-10-06: https://lucumr.pocoo.org/2026/10/6/codemode/
- Anthropic 工具搜索文档: https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-search-tool ；程序化工具调用文档: https://platform.claude.com/docs/en/agents-and-tools/tool-use/programmatic-tool-calling ；提示缓存文档: https://platform.claude.com/docs/en/build-with-claude/prompt-caching ；更新日志: https://platform.claude.com/docs/en/release-notes/overview
- VS Code tools 文档（2026-10-07 更新）: https://code.visualstudio.com/docs/agents/run/tools

**2026：系统提示、说明文件与运行时**
- agents.md: https://agents.md
- Codex AGENTS.md 文档: https://learn.chatgpt.com/docs/agent-configuration/agents-md ；app-server: https://learn.chatgpt.com/docs/app-server ；hooks: https://learn.chatgpt.com/docs/hooks ；releases: https://github.com/openai/codex/releases
- Claude Code memory: https://code.claude.com/docs/en/memory ；best practices: https://code.claude.com/docs/en/best-practices ；sub-agents: https://code.claude.com/docs/en/sub-agents ；hooks: https://code.claude.com/docs/en/hooks
- OpenClaw: https://github.com/openclaw/openclaw ；工作区: https://docs.openclaw.ai/concepts/agent-workspace ；心跳: https://docs.openclaw.ai/gateway/heartbeat ；Codex harness: https://docs.openclaw.ai/plugins/codex-harness
- Hermes Agent: https://github.com/nousresearch/hermes-agent
- pi: https://github.com/earendil-works/pi ；Pi 1.0: https://earendil.com/posts/pi-1-0/
- DeepSeek KV 缓存: https://api-docs.deepseek.com/zh-cn/guides/kv_cache ；定价: https://api-docs.deepseek.com/quick_start/pricing ；思考模式: https://api-docs.deepseek.com/guides/thinking_mode ；Codex 集成: https://api-docs.deepseek.com/quick_start/agent_integrations/codex/ ；更新日志: https://api-docs.deepseek.com/updates/
- DeepSeek Harness: https://github.com/deepseek-ai/deepseek-harness
- Kimi K3 工具调用最佳实践: https://platform.kimi.ai/docs/guide/kimi-k3-tool-calling-best-practice

**2026：论文（arXiv）**
- 2602.11988 Evaluating AGENTS.md（ETH）· 2601.20404 AGENTS.md 效率 · 2607.27250 上下文策略与正确性 · 2605.10039 · 2608.11095 指令文件生命周期 · 2606.20512 迭代修订说明文件
- 2607.22585 harness 与 token 成本 · 2609.11987 原生与中立 harness · 2610.00917 失败信息回传与排名反转 · 2605.23950 · 2609.17394 SWE-bench 名次显著性
- 2608.26218 截短旧工具结果 · 2609.26779 CliffCompaction · 2606.29718 过早放弃 · 2601.06007 Don't Break the Cache · 2609.00749 ContextPipe
- 2605.24660 工具短名单 · 2607.14642 MCPEvol-Bench · 2608.06370 The Bitter Lesson of Tool Calling · 2605.29676 Notation Matters
- 2602.12670 SkillsBench · 2608.25776 EVOMAL · 2607.12227 自动演化 harness 的反证 · 2603.28052 Meta-Harness · 2604.25850 AHE · 2609.05441 MERIT
