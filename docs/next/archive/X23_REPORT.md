# X23：内嵌 Codex 对话宿主

2026-10-11，worktree `chat-host`，分支 `next/chat-host`。没有 commit、push、pub get 或依赖变更。开发与构建均在本 worktree；没有启动正式应用、操作登录钥匙串、访问真实 NipaPlay 数据或触碰 lab10 / exp10。

## 1. 完成了什么

- `lib/next/chat/chat_host.dart` 实现常驻 stdio app-server；`NextRuntime.chat` 在 Next 端点启用后创建，切换 harness、禁用 Next、退出桌面应用时关闭。启动失败另存为 `chatError`，不阻止 NipaPlay 的端点工作。
- 经用户的 POSIX 登录 shell 启动，cwd 为活动 harness，继承终端 PATH、代理和 CODEX_HOME。线程 start/resume 都传 `danger-full-access`、`approvalPolicy: never`，不传 model/modelProvider。头部使用服务器实际返回的 model/provider。
- 提供线程 start/resume/list（cwd、cursor）、turn start/interrupt/steer，以及 requestUserInput 问题流和回答入口；其他服务端请求返回 -32601。没有添加 dynamicTools、Action 或聊天界面。
- `events` 提供脱敏协议流，`display` 提供支持的 item、合并思考和每秒活性快照；未知 item 不进入显示流。思考增量按 item/类型/内容索引在 100 ms 窗口内合并。
- 活性给出回合开始/结束时间、已用时间、最后事件/内容时间与间隔、事件/内容/思考增量计数、最近 error。没有超时中断、自动重发或上游状态判定。
- `NIPAPLAY_CHAT` 进入 app-server 及其工具子命令。种子 `nipa` 用 `X-NipaPlay-Chat` 转交，来源记为 `harness_cli:chat:<sessionId>`，流入现有调用日志及各领域事实的来源。日志增加不含正文的 `chat.turn_boundary`，记录 session 来源、threadId、turnId、phase、status、时间；未来界面可按这些记录关联每轮调用。没有解析命令来推断改动。
- 当前端点令牌出现在输入、stdout 或 stderr 时，先同步撤销旧值，再写新的 0600 连接文件；MCP 和 `/harness` 同时换令牌。检测与脱敏也覆盖拆成多条 delta 的令牌。轮换事件写入调用日志，不含凭据值。
- 没有界面也能实验：Debug **且** lab profile 才注册 `ext.nipaplay.chat` VM service 扩展。实验脚本为 `scripts/next/x23_vm.py`、`x23_provider.py`、`x23_replay.dart`。扩展不在 Agent 的能力目录里；生产不注册，不记录第二份聊天历史。

接口及来源契约见 `lib/next/chat/README.md`。本轮已实测 macOS；启动实现面向 POSIX 登录 shell，Windows 明确返回宿主启动错误，其端点仍可工作。没有在未验证的平台声称对话可用。

## 2. 决策

1. **宿主与界面分开。** 实际协议事件先更新活性，再做显示限频；界面不需要接收每条思考 delta。内容指非思考文本：助手回复、命令/文件输出；思考单独计数。计数是事件条数，不是字符数。`hasContent=false` 表示这轮尚无内容，间隔从回合开始算。
2. **不覆盖用户选择。** 生产保留用户配置；实验在 profile 中复制配置，仅把实验模型改为 `deepseek-v4.1-flash`。凭据文件 `auth.json` 用保留权限的复制，配置副本设为 0600，skills 链接到原目录，由 lab 内核规则保证外部只读。宿主只要求配置副本事先存在，不去改用户的 `~/.codex`。
3. **登录 shell 与实验路径。** 先从同一登录 shell 获取环境，在内存清除携带当前端点令牌的变量，再通过登录 shell exec Codex；两次 shell 都从同一份原始继承环境开始，避免把第一次登录配置加工后的 PATH 再加工一次。启动脚本在 shell 配置加载后重新设置会话号和 lab 的 CODEX_HOME/TMPDIR。CLI 的 `shell_environment_policy.set.NIPAPLAY_CHAT` 保证会话号进入工具环境，不调整模型或代理策略。
4. **来源复用既有记录。** `origin` 使用上述字符串，不新增来源数据库。调用 journal 也记录 read 调用，使 `./nipa status` 的实际调用能留下会话来源；设置等持久事实仍使用自身已有的 `origin` / `changed_by`。回合边界只保存关联元数据，不保存对话。X22 可读这些真实来源及边界；本任务不实现 activity 视图。
5. **秘密处理在发布之前。** 保留令牌前缀跨 delta 拼接，完整命中后轮换并脱敏，再发布；这样逐条安全的片段也不会在日志中拼回一个有效令牌。旧令牌继续参与脱敏。测试只用临时端点生成的值，报告不含任何令牌。
6. **公共 CA 是实验启动配置。** lab 禁止钥匙串访问，Codex 默认 TLS 路径失败。实验复制 `/etc/ssl/cert.pem` 到 profile 的 `system-ca.pem`，用 `CODEX_CA_CERTIFICATE`、`SSL_CERT_FILE` 指向它。不读取钥匙串，不禁用 TLS 校验，不放松 X11 限制，也不把这项实验环境覆盖带进生产。

退出前提示、密码提醒、问题渲染和对话头部的视觉样式留给尚在设计的界面；本任务提供关闭入口及证据，不新增 GUI。

## 3. 实验与真实输出

### 构建和约束检查

worktree 最初缺少 `.dart_tool/package_graph.json` 和 Flutter 的派生 Swift Package。只读复制既有派生输入到本 worktree，并把本地插件路径改成 worktree 路径，没有重新解析依赖。Flutter 的 pod install 把锁文件里的 Erika 版本随既有解析结果改写，构建后已恢复锁文件，最终 diff 不含依赖文件。

```text
$ ERIKA_PREBUILT_CACHE_DIR=/tmp/nipa-next/x2-erika-cache \
    ~/development/flutter-3.44.6/bin/flutter build macos --debug --no-pub
✓ Built build/macos/Build/Products/Debug/NipaPlay.app

$ ~/development/flutter-3.44.6/bin/flutter analyze --no-pub \
    lib/next/chat lib/next/agent_endpoint.dart \
    test/next/agent_endpoint_test.dart packages/nipa_harness/lib/src/mcp/endpoint.dart
Analyzing 4 items...
No issues found! (ran in 1.2s)

$ ~/development/flutter-3.44.6/bin/flutter test --no-pub \
    test/next/agent_endpoint_test.dart --reporter expanded
00:00 +4: All tests passed!

$ ~/development/flutter-3.44.6/bin/flutter test --no-pub \
    test/desktop_exit_handler_test.dart test/next/harness_repository_test.dart \
    --reporter expanded
00:00 +5: All tests passed!

$ git diff --check
# 无输出，退出码 0
```

包括 runtime 和退出处理文件的扩大 analyze 使用 `--no-fatal-infos`，没有 error/warning，保留 5 条原有 info（一个花括号风格、四个 withOpacity）。约束测试守住原仓库文件、私有连接文件权限、两条端点的旧令牌撤销、跨 delta 脱敏与真实来源传递；没有用单元测试替代对话实验。

### 实验 0：真实实例、真实 CPA

直接运行本 worktree Debug 可执行文件，profile 为 `x23chat`。CODEX_HOME 是 `<root>/codex-home`，TMPDIR 是 `<root>/temp`。共享用户的 Codex 0.144.1，但实验配置独立。服务端实际返回的头部字段：

```json
{"model":"deepseek-v4.1-flash","modelProvider":"cpa","approvalPolicy":"never","sandbox":{"type":"dangerFullAccess"},"cwd":"~/Library/Application Support/NipaPlay/LabProfiles/x23chat/harness"}
```

最初继承登录 shell 的代理直接对话失败，25.413 秒结束，无内容：

```text
Reconnecting... 1/5
Reconnecting... 2/5
Reconnecting... 3/5
Reconnecting... 4/5
Reconnecting... 5/5
stream disconnected before completion: error sending request for url ([redacted URL]
```

给实验启动环境添加 CPA、127.0.0.1、localhost 的 `NO_PROXY` 例外，保留 HTTP_PROXY/HTTPS_PROXY，第二次仍失败（27.768 秒）。随后增加公共 CA 副本及上述两个 CA 环境变量，同一线程完成最小动作，回合 23.162 秒，最近 error 为 null。

这组对照支持公共 CA 配置解决了所观察到的 TLS 请求失败；没有用它推断代理自身坏了。原始登录环境的 HTTP_PROXY、HTTPS_PROXY 都是回环代理 127.0.0.1:7897，没有 ALL_PROXY / 小写代理变量；参考 as_driver 去除这些变量而直连。宿主默认保留它们，成功实验另加 NO_PROXY，这是相对默认环境的实际差异。公共 CA 加入后没有单独再测代理路径。

Agent 经宿主执行 `./nipa status`，输出摘录（省略 harnessSeed 详情）：

```json
{"status":"running","profile":{"name":"x23chat","root":"~/Library/Application Support/NipaPlay/LabProfiles/x23chat","externalFiles":"readOnly"},"version":"1.11.10","actions":122,"tasks":{"total":0,"byState":{},"activeTotal":0,"active":[]}}
```

实际命令 stdout：

```text
NIPAPLAY_CHAT = nipa-1791722106499060-5ba4477d
HTTP_PROXY_present = True
HTTPS_PROXY_present = True
endpoint_token_found = True
token_in_environment = False
path = /tmp/nipa-next/x23-denied.txt
errno = 1
error = [Errno 1] Operation not permitted: '/tmp/nipa-next/x23-denied.txt'

[main e8a4c62] X23 lab probe
 1 file changed, 1 insertion(+)
 create mode 100644 x23-probe.txt
e8a4c62 X23 lab probe
```

第一次命令使用 here-document；zsh 另报：

```text
zsh:1: can't create temp file for here document: operation not permitted
zsh:32: can't create temp file for here document: operation not permitted
```

Agent 随后用 `python3 -c` 取得上面的内存令牌比较及明确的被拒绝路径。这里没有输出令牌值，也没有把提交做在实现 worktree；提交只属于可删除的实验 harness。

包含脱敏及回合边界记录的构建再续接同一线程，补一个仅打印环境路径的探针，直接取得 stdout：

```text
{"NIPAPLAY_CHAT": "nipa-1791722691483515-353f1ee1", "CODEX_HOME": "~/Library/Application Support/NipaPlay/LabProfiles/x23chat/codex-home", "TMPDIR": "~/Library/Application Support/NipaPlay/LabProfiles/x23chat/temp"}
TMPPREFIX=/tmp/zsh
```

所以 TMPDIR 设置正确仍不能保证 zsh 的 here-document 不访问 `/tmp/zsh*`；没有放行这个外部路径。Agent 先前的文字总结声称取得了这些值，但当轮命令 stdout 未包含它们，因此这里使用最终探针的真实输出，未把总结当作证据。

真实调用 journal 中的 status 来源：

```json
{"invocationId":"inv-1791722130804534-3","actionId":"task.list","origin":"harness_cli:chat:nipa-1791722106499060-5ba4477d","effect":"read","input":{},"status":"completed","startedAt":"2026-10-11T12:35:30.804986Z","elapsedMs":1}
```

另经 Agent 修改临时实例 `seek.stepSeconds`，`next.db` 的 `settings_changes` 只读查询输出：

```json
{"sequence":1,"key":"seek.stepSeconds","previous_value":"10.0","value":"11.0","changed_at":"2026-10-11T12:36:20.482838Z","changed_by":"harness_cli:chat:nipa-1791722106499060-5ba4477d","origin":"harness_cli:chat:nipa-1791722106499060-5ba4477d","reason":"X23 source probe","invocation_id":"inv-1791722180432849-4","revision":1}
```

最终构建的回合边界也实际写入 journal：

```json
{"event":"chat.turn_boundary","origin":"harness_cli:chat:nipa-1791722691483515-353f1ee1","threadId":"01a12af1-a9cf-7d72-b190-7c4ae45ba69e","turnId":"01a12afe-e020-7d50-9548-14b6e9f52b07","phase":"started","status":"inProgress","startedAt":"2026-10-11T12:45:09.029887Z"}
{"event":"chat.turn_boundary","origin":"harness_cli:chat:nipa-1791722691483515-353f1ee1","threadId":"01a12af1-a9cf-7d72-b190-7c4ae45ba69e","turnId":"01a12afe-e020-7d50-9548-14b6e9f52b07","phase":"completed","status":"completed","startedAt":"2026-10-11T12:45:21.016582Z"}
```

`thread/list` 返回一个线程，cwd 正好为实验 harness；`thread/resume` 返回实际 `deepseek-v4.1-flash / cpa`，当时有 4 个回合。这里只验证 app-server 的续接，没有启动交互终端 `codex resume` 来增加另一轮实验。

### 实验 1：原时间轴离线回放

执行：

```sh
~/development/flutter-3.44.6/bin/dart --packages=.dart_tool/package_config.json \
  scripts/next/x23_replay.dart /tmp/nipa-next/as/exp9/events.jsonl
```

回放直接向宿主使用的 `ChatLiveness` 喂日志中的时间；处理可加速，时间差仍来自原日志的一秒精度。真实输出关键字段：

```json
{"events":65630,"maxEventGapSeconds":9,"eventPausesAtLeast180s":0,"longReasoningItems":[{"from":"2026-10-11T17:56:58.000","to":"2026-10-11T18:11:40.000","seconds":882},{"from":"2026-10-11T18:12:22.000","to":"2026-10-11T18:26:53.000","seconds":871}]}
```

每段超过 3 分钟的无非思考内容区间：

| 区间（日志本地时间） | 无内容时长 | 宿主证据 | 对照事后判读 |
|---|---:|---|---|
| 17:56:53 → 18:12:16 | 923 秒 | 下一条内容前 lastEventAgo=0 秒；思考 delta 累计 20,580；最近 error 为 `Reconnecting... 1/5` | 包含一个 882 秒的思考 item。持续有事件，不能只因没有回复就中断。 |
| 18:12:17 → 18:27:25 | 908 秒 | 下一条内容前 lastEventAgo=0 秒；思考 delta 累计 43,558；同一最近 error | 包含另一个 871 秒的思考 item，仍有连续事件。 |
| 18:30:43 → 日志结束 18:43:28 | 765 秒 | lastEventAgo=0；lastContentAgo=765 秒；思考 delta 累计 65,180；同一最近 error | 日志没有 turn/completed，宿主保留实际收到的 inProgress，不补造结束状态。 |

日志结束时实际证据：

```json
{"status":"inProgress","elapsedMs":2795000,"lastEventAgoMs":0,"lastContentAgoMs":765000,"hasContent":true,"eventCount":65618,"contentCount":346,"reasoningDeltaCount":65180,"latestError":"Reconnecting... 1/5"}
```

额外让时钟在日志结束后走 3 分钟，不增加事件，输出变为 `lastEventAgoMs=180000`、`lastContentAgoMs=945000`，status 仍为收到的 inProgress；没有中断或重发。这是额外静默探针，不是声称原日志有 3 分钟事件空窗。

与 `EXPERIMENTS.md` 的事后判读一致：实验 9 第二轮的任务已完成、续接含糊，Agent 用大量思考和只读核对确认进度；该轮作废。这是报告中的事后对照，宿主没有根据事件推断这个原因。

### 实验 1：不回应的 provider、中断和同线程重发

`x23stall` 真实 Debug 实例使用无凭据的回环模拟 provider；配置的模型名仍为 `deepseek-v4.1-flash`。模拟器只复现 Responses 传输行为，不宣称调用了真实 DeepSeek。首个 POST 不返回任何响应，后续 POST 返回一个最小 SSE 回复。

真实输出：

```text
mock provider listening on loopback
{"request": 1, "path": "/v1/responses", "model": "deepseek-v4.1-flash", "responds": false}
```

用户动作前，宿主从真实进程取得的证据：

```json
{"turnId":"01a12af5-df37-7810-b901-490646e2b329","status":"inProgress","elapsedMs":196270,"lastEventAgoMs":196184,"lastContentAgoMs":196270,"hasContent":false,"eventCount":6,"contentCount":0,"reasoningDeltaCount":0,"latestError":null}
```

仍然没有自动中断。之后实验驱动手动操作，实际 RPC 结果：

```text
steer {'turnId': '01a12af5-df37-7810-b901-490646e2b329'}
interrupt {}
after interrupt status=interrupted elapsedMs=196286
resend turnId=01a12af8-ddf8-70f0-8f70-1fdbe09fa1d5
{"request": 2, "path": "/v1/responses", "model": "deepseek-v4.1-flash", "responds": true}
mock reply 同一线程中断后重发成功。
```

重发后的 threadId 仍为 `01a12af5-de6b-7160-9fd3-7188d16cb247`；状态 completed，elapsedMs=18，eventCount=13，contentCount=2。包含脱敏、边界记录与关闭改动的构建再续接该线程并回复，completed，elapsedMs=23。

### 清理、意外及验证范围

最后通过 Debug close 入口关闭宿主，随后按每个实例自身 VM service 提供的 PID 结束实例：

```text
x23chat host close {'closed': True}
x23chat child PIDs [74723, 74745, 74916] remaining after close []
x23chat terminated verified app PID 74634
x23stall host close {'closed': True}
x23stall child PIDs [74726, 74744] remaining after close []
x23stall terminated verified app PID 74649
removed only .../LabProfiles/x23chat absent= True
removed only .../LabProfiles/x23stall absent= True
outside write probe exists= False
```

模拟 provider 同样已按自己的进程会话结束；复制的配置、auth、公共 CA、skills 链接、临时数据库、harness 提交均随两个 profile 删除。只保留脱敏的实验输出于 `/tmp/nipa-next/x23/`。内存检查显示当前 endpoint token 在三个应用日志和事件日志里均不存在，没有打印或记录凭据。

最终检查修正了启动环境的重复加工：实际登录 shell 使用原始继承环境，而非环境探针加工后的副本。两个从同一继承环境启动的登录 shell，一个原样、一个设置会话号后 exec，实测比较结果如下；随后再次完成 macOS 构建。这次环境参数修正后没有再增加 CPA 对话轮次。

```text
two login-shell launches from identical inherited environment: {'PATH': True, 'HTTP_PROXY': True, 'HTTPS_PROXY': True, 'ALL_PROXY': True, 'http_proxy': True, 'https_proxy': True, 'all_proxy': True}
chat session set= True
```

其他意外：最初后台 Popen 随工具会话退出，改为在可持续的 exec 会话中直接运行；首次清理曾把本任务的 x23stall 进程误认为 x23chat 而结束，随后改为从实例自己的 VM service 读取 PID，并从头重跑了上述完整 196 秒停顿实验。没有结束其他实验的进程。构建实例还报告 audioplayers / universal_gamepad 的 MissingPluginException，聊天宿主和端点继续工作；没有在本任务改插件或把这些日志隐去。

真实轮换只由临时端点约束测试触发，未故意向 CPA 泄露真实端点令牌。requestUserInput 的接口已实现，本轮对话没有产生该服务端请求；也没有声称已验证其未来 UI。退出清理经宿主 close 实测，退出前的新增提示仍属于未来界面。

## 4. 问题

需要主控决定的问题：没有。公共 CA 与 NO_PROXY 是已记录的实验启动配置；Windows 和界面交付不包含在本轮 macOS 宿主实验的验证声明中。
