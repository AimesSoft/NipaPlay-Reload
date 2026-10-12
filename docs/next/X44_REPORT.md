# X44：下载事实自动回到发起会话

2026-10-13，worktree `x44-download-notify`，分支 `next/x44-download-notify`。未 commit、未 push。

## 1. 完成了什么

- `download.add` 在新任务提交时根据 invocation 固定 `returnTo`：聊天 CLI 回到当时选中的线程；宿主帮手及 `codex_native` 来源回到帮手任务记录的父线程。仓库、线程、调用来源及 invocation ID 随任务持久保存。脚本、hooks、GUI 或无法解析到会话的来源不建立自动返回目标。重复添加已有哈希不改变原发起者。
- 后续服务读取 X40 的 `checkpoint.completedFiles`，只交回已校验、已登记入库的视频文件。事实包含任务号、文件索引与路径、字节、校验、fileId、已知作品/剧集关联及完成时的 `playable`；未知身份保持未知。下载入库适配器补充已有剧集 ID 与属性，不创建身份。
- 每个文件对象只覆盖一次；整个任务的 succeeded / failed / cancelled 另覆盖一次。排队、窗口时间及覆盖的对象均保存于既有 followup snapshots；重启恢复及扩选携带的旧文件对象不重发。没有迁移、改写旧任务或旧回执。
- 派发前先解析 Agent 登记的后续。同仓库、同线程的匹配文件事件、任务终态或成功的 `download.completed` 后续优先，自动批次去掉对应事实；广义一次性订阅只覆盖它实际接到的那个对象。保留 Agent 的原说明。取消或尚未覆盖事实的失败登记不抑制新自动通知。
- 复用现有后续派发：会话忙时排队，不中断活动回合，不切换用户当前会话；已经开始但确认丢失时仍按既有 marker 查历史，不重开回合。自动输入仅交付事实，不安排播放、绑定、继续等待等动作。
- 下载种子事实已写明自动返回、排队、批量及显式后续去重。入口是既有 `download.add` Action，无新增 GUI 功能。

核心实现：[download_returns.dart](../../lib/next/followups/download_returns.dart)、[download_service.dart](../../lib/next/downloads/download_service.dart)。契约见 [followups/README.md](../../lib/next/followups/README.md) 和 [downloads/README.md](../../lib/next/downloads/README.md)。未修改 `lib/next/ui/`、X41/X43 部分或 Classic 下载实现；保留 GeneratedPluginRegistrant 的既有生成改动，构建生成的 Podfile.lock 变化已恢复。

## 2. 决策

**第一批立即，其余一分钟合并，终态立即冲刷。** 第一份可播视频关系到用户能否开始看，立即进入后续队列。其后的所有文件事实累积到一个 pending batch，下一次普通派发最早是上次派发之后一分钟；会话忙或宿主不可用时继续合并，不积累几十份独立唤醒。任务结束不等窗口，连同剩余文件事实交回。保留每个文件事实比“只送首尾”更适合用户随后核对集数；一分钟窗口限制回合密度，同时避免中间完成情况长时间没有反馈。最后一个普通批次已派发时，紧接的终态仍可以单独送回一次。

**返回目标在发起时固定，事件覆盖在后续记录中固定。** 不在完成时猜当前会话，不接管已有下载，不为历史无来源任务补目标。取消自动后续属于取消这份交付，不重新生成它。扩选产生的新观察任务继承原目标及原文件事件对象，新终态仍属于新任务。

**完成事实是时间点快照。** `playable:true` 表示 X40 当时已验证规范路径、完整大小和本地视频，并完成登记；随后文件被删除或绑定发生变化，Agent 通过当前状态查询核对。媒体身份取已有绑定；`identificationPending` 表示身份未确定，并不保证有识别任务正在执行。

**帮手来源复用 X38 的归属证据。** 只使用记录的 parentThreadId；原生子代理 shell 若继承父 `NIPAPLAY_CHAT`，仍按实际 CLI 来源归属，不猜是谁执行了命令。未修改帮手协议或来源契约。

## 3. 实验与真实输出

### 隔离与材料

四个实例均直接运行本 worktree 已构建、ad-hoc runtime 签名的 Debug 可执行文件。使用独立临时 profile、下载目录、数据库、harness、CODEX_HOME 和公共 CA 副本；真实模型配置为 `deepseek-v4.1-flash` / `cpa`，NO_PROXY 包含回环和配置中的 provider host。没有修改用户的 `~/.codex`。未启动安装版、访问登录钥匙串或真实 NipaPlay 数据目录、使用 `/Volumes/Media`、激活窗口或像素点击；没有操作 ui-demo 或主控实例。

材料沿用 X40 的 FFmpeg `lavfi testsrc2` 制法，自制三集测试图案，明确 CC0-1.0 并允许分发。大小分别为 702,145、780,978、865,025 字节，共 2,348,148 字节。回环 tracker / BT peer 分阶段宣布可供应的片段；应用实际经 librqbit 下载和校验。实验控制片段供应，不是身体安排下载顺序；没有验证公网 BT 或商业动画识别。

脚本：[experiment.py](evidence/x44/experiment.py)、[local_seed.py](evidence/x44/local_seed.py)。证据目录：[evidence/x44](evidence/x44/)。本轮验收后端事实与对话，没有截图或播放器解码验收。

### 身体：排队、窗口、去重

身体使用真实应用及 Codex app-server，回环模型仅保持首回合忙、随后立即结束各后续回合，不能当成真实 DeepSeek 输出。任务 `job-0135b0bed5bae0e6201731617af19a6f`，目标线程 `01a1311e-864d-70e1-b2f9-029183a7ad4e`。

以下时间均为 2026-10-12 UTC，本地为 2026-10-13（UTC+8）。原始状态：[body/timeline.json](evidence/x44/body/timeline.json.gz)，最终补采：[body/final-supplement.json](evidence/x44/body/final-supplement.json)。

| UTC | 实际观察 |
| --- | --- |
| 17:17:33.539 | 第一集持久完成，702,145 字节、verified、imported、playable 均成立；其他集未完成，父任务 running。 |
| 17:17:34.062 | 原回合仍 inProgress，第一份后续 ready，reason 为等待活动回合结束，目标线程保持原线程。 |
| 17:17:34.109 | 放行忙回合后，第一份后续实际派发，随后 completed。 |
| 17:17:43.572 | 第二集完成；新批次 ready，deliverAfter 为 17:18:34.109，没有立即开回合。 |
| 17:18:34.809 | 第二批实际派发，距第一批 **60.700 秒**。 |
| 17:20:08.769 / .830 | 第三集的普通窗口已过，文件事实先派发；紧随的任务终态另派发一次。四个后续最终均 completed。 |
| 17:21:32 补采 | 三个文件事件对象各一次、终态一次；重复 add 返回原 jobId，后续数量仍为四；片库有三个文件。 |

身体驱动原先误写了“最后必然合成一个批次、总共三轮”的断言，等待条件未成立。实际第三集完成较晚，普通窗口已经过去，允许文件与终态分两轮。已在同一实例补采最终四份事实和 duplicate-add 读回，再中断驱动触发其 finally 清理；保留 `body-driver.txt` 的 KeyboardInterrupt，不重跑身体实验。脚本当前接受末尾批次的这两种合法时序。

### 真实 DeepSeek：原回合结束后自动叫醒并告知

成功阶段：[deepseek-end-at-submit/timeline.json](evidence/x44/deepseek-end-at-submit/timeline.json.gz)、[chat-events.jsonl.gz](evidence/x44/deepseek-end-at-submit/chat-events.jsonl.gz)。真实线程 `01a13127-dad8-7b60-b2d0-4c14641902ce`，任务 `job-ec3b9cfc5b5741d59c7d24a42fe14784`。原始目标仍为：

> 把这套合集下下来，第一集好了就告诉我。

仅附种子 / CC0 许可证位置和隔离边界，没有给下载、后续登记或通知步骤。种子先供应第一集的部分片段，最后一个校验片段受控。**为固定“回合结束在先、文件完成在后”的实验顺序，本阶段在下载提交后由驱动中断原回合；不是模型自行结束的证据。** 保留同一应用、线程、任务及模型，没有新增用户提示或代写通知。

| UTC | 实际观察 |
| --- | --- |
| 17:27:40.062 | 原始自然语言回合开始，header 为 deepseek-v4.1-flash / cpa。 |
| 17:27:59.886 | 她核对许可证及 manifest 后调用 `download.add`，三集全部选中。 |
| 17:27:59.897 | 驱动中断原回合，turn/completed 为 interrupted；当时第一集只有 229,376 字节、complete:false，followup.list 为空。 |
| 17:27:59.917 | 原回合已结束，实验者释放第一集最后片段。 |
| 17:28:04.478 | 第一集通过校验、登记入库；自动后续含文件索引 0、fileId、verified / imported / playable:true，作品及剧集关联为空。 |
| 17:28:04.511 | 后续在原线程开启新回合 `01a13128-42b2-7b01-8eed-6f1c56a8c597`。没有 `followup.register`。 |
| 17:28:09.159 | 她在新回合实际说：“第一集已校验完成，我确认一下当前状态和其余文件进度。”随后自行查当前下载。 |
| 17:28:14.810 | 她完成第一份回复：“第一集已下好”，逐项说明 702,145 字节完整、已校验、已入库、可播放；其余两集在后台继续。回合于 .907 完成。 |
| 17:28:14.510–.598 | 其余两集完成并入库，父任务 succeeded；索引 1、2 与 terminal 合成一份批次，冲刷原来应等到 17:29:04.511 的窗口。 |
| 17:28:14.926 | 第一份回合结束后，终态批次实际派发。两次派发间隔 10.415 秒，属于终态立即冲刷。 |
| 17:28:59.081 | 她实际给出三集各自字节、校验、入库、可播和 verified 成功回执；如实说无作品身份。回合于 .169 完成。 |
| 17:29:00.195 | 两份自动后续均 completed，三个文件对象各一次、任务终态一次。关闭宿主、按自身 PID 退出应用、删除 profile。 |

第一份最终回复还说“作品识别还在进行中”。身体事实只有 identificationPending:true，且本实验关闭自动扫描，没有证据表明有识别任务在执行；不把这句话当成识别进度。末轮她确认了作品未绑定，也没有虚构身份。

### 两个未成立的前置观察

- [deepseek/](evidence/x44/deepseek/) 初始片段供应全部受控。她提交下载后持续排查空 bitfield、tracker、peer，并未自然结束；300 秒观察期限到后驱动清理。没有第一集完成或后续唤醒证据。她在诊断中查询了系统进程 / 监听端口（含按名称过滤）；未启动或控制其他实例。保留真实轨迹，不把这段描述为满足全部实验隔离约束的成功观察。
- [deepseek-partial/](evidence/x44/deepseek-partial/) 改为先供应部分第一集，仍留最后片段。等待期间宿主于本地 01:25:50.543 报 `FormatException: Unexpected extension byte (at offset 0)`，app-server stderr 随后为 stdout broken pipe；90 秒后中断 RPC 报 `Chat server is not running`，驱动清理。错误出现在文件完成前，尚未产生自动后续，未确定协议字节错误的根因，也未在本任务修改聊天传输实现。

成功阶段只补“原回合结束后的文件交付与真实模型通知”，改为提交后立即中断以控制时序，身体实验没有重跑。仍未验证**同一句话下，模型自行结束原回合而不持续轮询**；受控原回合结束后的自动唤醒与用户通知已经成立。

### 验证与收尾

- 数据约束：重开保存覆盖与回执、手工后续说明优先、late broad one-shot 的实际对象归属、帮手来源固定父线程、无来源不通知、失败回执不冒充成功、非视频 / 未登记文件不提前交回。最终相关文件 **15 passed**：[constraints-final.txt](evidence/x44/verification/constraints-final.txt)。首轮包含 X40 的相关约束也通过。
- 完整 `test/next` 加四份 Classic 下载 service / 扫描 / 控制 / session storage 测试仅运行一次，**482 passed / 4 skipped**，1 分 48 秒：[full-next.txt](evidence/x44/verification/full-next.txt)。
- 最终相关 analyze 无问题：[analyze-final.txt](evidence/x44/verification/analyze-final.txt)。本 worktree 最终 Debug `--no-pub` 构建、runtime ad-hoc 签名、strict verify、allow-jit / 无 app-sandbox 验证通过：[build-final.txt](evidence/x44/verification/build-final.txt)、[signature-final.txt](evidence/x44/verification/signature-final.txt)。成功真实对话使用此最终构建；身体阶段之后的订阅排序修正由约束测试守住，没有重跑其已成立实验。
- 四个应用 PID **12636、12645、21194、33458** 均已退出，各自 profile 已删除。未停止其他实例。[cleanup-secret-check.json](evidence/x44/verification/cleanup-secret-check.json) 保存收尾核验。每次归档前在内存替换当前认证副本、端点令牌和敏感环境值；最后检查 32 个证据文件（含解压日志）对 5 个已知认证值零匹配。没有记录或提交秘密。

## 4. 问题

需要主控决定的问题：**没有**。

剩余实验限制：模型自行结束原回合未成立；一次 app-server 协议 UTF-8 错误根因未定位；没有实际播放器解码或公网 BT 验收。文件/终态返回、排队、密度、去重及受控结束后的真实 DeepSeek 通知已观察到。
