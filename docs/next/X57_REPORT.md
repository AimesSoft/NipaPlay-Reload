# X57：X49 / X50 / X52 与 Y8 集成验证

2026-10-13，worktree `~/Desktop/nipaplay-next-wt/x57-verify`，分支
`next/x57-verify`，基线 `3dcac1524afd275efd947793d1307271583cf91c`。
未 commit、push、pub get 或改依赖。构建全部在本 worktree，Flutter 3.44.6、
`--no-pub`、指定 Erika cache；GeneratedPluginRegistrant 的既有生成变化保留，
构建产生的 Podfile.lock 变化已恢复。没有改 Classic 生产代码。

## 1. 完成了什么

- 默认实验 CODEX_HOME、NipaPlay 设置的提供方、切回默认来源，三个主回合均
  `completed`，实际提供方依次 `cpa → nipaplay → cpa`，主线程和三轮历史保持。
- 三次启动的 `config/read` 均确认当前 harness `trust_level=trusted`，
  `features.shell_snapshot=false`。三次原始 X49 SessionStart hook 均完成，当前
  偏好和“刚才”原文进入上下文；模型不调用工具即可答出种子代号和更新后的偏好。
- 正确和错误密钥的真实 `runtime.hostSettings.checkModel()` 已验证。
- Y8 设置页通过真实服务和 VM 调试扩展打开，保留本实例窗口的 JPG：模型来源、
  正在使用的模型、真实组网不可用状态、远程程序的关和开都核对过。
- Windows 启动只作代码审阅，参数与环境覆盖正确。
- 九个隔离实验目录逐个扫描并删除，所有模型密钥匹配为 0；最终没有残留的
  已记录 PID 或 cwd 属于这些 profile 的进程。

证据总入口：[最终三轮结果](evidence/x57/final/summary.json)、
[信任与注入核对](evidence/x57/final/trust-and-context.json)、
[最终审计](evidence/x57/final-audit.json)。

## 2. 修复与决策

### 来源切换恢复时必须重新登记 hook 信任

首个完整诊断实例：切到 `nipaplay` 后回合完成、线程不变，但没有
`hook/completed`，模型也没有读到刚修改的偏好。
[原始失败](evidence/x57/diagnose/managed-turn.json)。

原因是 X52 重启 app-server 的 `_applyModel()` 直接调用 `thread/resume`，没有
X50 在 `_select()` 中添加的项目 hook 哈希信任。新进程没有旧线程的内存覆盖。

在 [chat_host.dart](../../lib/next/chat/chat_host.dart) 的三个直接恢复入口补入
`_projectHookConfig()`：模型切换的前台恢复、切换后的帮手恢复、读取跨 home
rollout 的按需恢复。保留帮手的 `NIPAPLAY_CHAT` 来源覆盖，不写持久 hook state，
也不批准用户或全局 hook。

回归测试另暴露出路径别名：macOS 测试仓库使用 `/var/...`，规范路径为
`/private/var/...`。此前以规范 cwd 取 hooks/list 的 key，再以原 cwd 开线程，
两个 key 不相同。现在 hooks/list 使用与线程相同的 cwd；来源文件规范化后
检查是否仍在当前 harness 的 `.codex/` 内，实际 key/hash 原样登记。

### 跨 home 索引为空时，“刚才”仍读取已有主线程

信任修复后 hook 能读到新偏好，但新 CODEX_HOME 的 `thread/list` 没有原 home
的会话索引，因此“刚才”误报最近会话无。
[观察](evidence/x57/hook-fixed/failure-events.json)。原主线程 rollout 实际可读。

[recent.dart](../../lib/next/memory/recent.dart) 在原有按 updated_at 排序的候选
后补入未列出的持久主线程；只有前面的候选没有可用对话时才用它。仍最多检查
30 个候选，仍跳过帮手，不创建摘要或第二份聊天记录。这个修复保证本轮来源
切换后的已有主会话能进入“刚才”；没有宣称合并所有 home 的完整会话目录。

### 组网签发者缺失时也显示程序权限

真实设备页只有“此版本尚未配置组网签发者”，隐藏了远程程序开关；当实验
宿主文件中 `program.enabled=true` 时，页面也看不到当前授权。
[修复前窗口](evidence/x57/before-ui-fix/devices.jpg)、
[同时读取的真实值](evidence/x57/before-ui-fix/summary.json)。

[section_host.dart](../../lib/next/ui/settings/section_host.dart) 仅移除程序权限卡
外层的 `m.available` 条件。组网开关保持不可用，程序授权直接显示和修改
`runtime.hostSettings` 的值。这样用户在不能加入组网的版本也能看到、撤销
已有授权；没有扩大程序权限，也没有更改默认值。

## 3. 实验与真实输出

驱动：[x57_experiment.py](../../scripts/next/x57_experiment.py)，复用 X52 的
WebSocket VM 客户端和脚本内凭据读取。窗口号由
[x57_window.swift](../../scripts/next/x57_window.swift) 根据本次 Popen PID 查询，
只调用 `screencapture -x -o -t jpg -l<窗口号>`。审计驱动：
[x57_audit.py](../../scripts/next/x57_audit.py)。

所有实例直接运行本 worktree 构建的可执行文件，独立临时 `NIPAPLAY_PROFILE`，
默认安静。未启动安装版、按应用名查找、激活窗口、移动鼠标或像素点击。
没有读写登录钥匙串、用户真实应用目录、用户 harness、ui-demo 或主控实例。
用户 `~/.codex/config.toml` 只在脚本中读取 cpa 的配置，未修改它；没有复制
认证文件。API key 经进程环境和 VM WebSocket 帧传递，不进入 argv、查询 URL、
模型配置文件或证据。LabModelVault 将自有来源的密钥留在内存。

### 三轮主会话与信任

默认 home 新建、没有任何持久 projects 或 hook 信任记录，provider 使用用户
cpa 的 Responses 地址与凭据，配置仅引用 `NIPAPLAY_MODEL_API_KEY`。实验种子
只附加随机代号及隔离范围，原始 `.codex/hooks.json` 和 `session_start.py`
字节保持不变。先以一条真实普通会话建立“刚才”的用户和助手原话，再回到
原主线程做三轮。每次切换前仅在临时 preferences.md 更换随机偏好代号，以
区分新注入和旧上下文。

最终三轮主线程均为 `01a13559-188d-7aa2-8131-dda4f6878cc7`，模型均为
`deepseek-v4.1-flash`：

| 来源 | 回合 | 回合耗时 | SessionStart | hook 耗时 | 种子 / 当前偏好 |
|---|---|---:|---|---:|---|
| 默认 Lab CODEX_HOME / cpa | completed | 2469 ms | completed | 128 ms | 无工具读到 |
| runtime.hostSettings / nipaplay | completed | 2648 ms | completed | 120 ms | 无工具读到 |
| 切回默认 home / cpa | completed | 5074 ms | completed | 159 ms | 无工具读到 |

默认回合原话：

> 实验种子代号：X57_SEED_2076d7834e
> 当前偏好验证代号：X57_PREF_bf0ceb9f5d
> 刚才对话里的代号：X57_RECENT_962e61fa71
> 推荐数量：2 部

切换后分别准确答出 `X57_PREF_7c7529660f`、`X57_PREF_0c947c7e88`。三轮
hook context 都有相应当前偏好及“刚才”的原文代号，命令执行数均为 0；
三次读取到的 Codex 配置都确认项目信任和关闭 shell snapshot。
[逐项核对](evidence/x57/final/trust-and-context.json)、
[完整主历史](evidence/x57/final/main-history.json)、
[事件](evidence/x57/final/events.json)。默认 home 的 config 字节未改。

模型对“刚才”的使用有实际局限：managed/returned 回合虽然已收到含该代号
的 hook 原文，答复仍说“无”或认为属于更早的会话。中间两次复测也有类似
否认或选择了其他代号的行为。初版驱动把模型准确复述“刚才”也当成切换通过
条件，因而中断；最后改为按任务验证 hook 注入，并要求无工具读到种子和
当前偏好。没有删去失败回复、改 seed/hook 提示词或追加请求挑选更好的回复。
证据证明注入发生，不能扩大成模型一定正确使用每条最近事实。

### 正确和错误密钥

| 检查 | 真实结果 | 延迟 |
|---|---|---:|
| 正确密钥 | ok=true，可以使用 | 1162 ms |
| 随机错误密钥 | ok=false，密钥无效或没有权限 | 233 ms |

正确检查来自 [initial](evidence/x57/initial/summary.json)，诊断轮又成功执行
过一次（3261 ms）；之后所有修复轮均复用首次正确检查，不重复它。
错误检查只执行一次，见 [final](evidence/x57/final/summary.json)。错误检查后
直接切回默认来源，没有向错误密钥发起主回合。真实 activity 的修改来源为
用户 GUI，证据见 [activity](evidence/x57/final/activity.json)。

### Y8 真实设置页

没有设置 `NIPAPLAY_NEXT_UI_FAKE*`，`CoreSettingsData` 接的是
`runtime.hostSettings`。以下 JPG 均只包含本实例窗口：

- [默认来源](evidence/x57/final/nipa-default.jpg)：Codex，正在用 deepseek-v4.1-flash。
- [NipaPlay 来源](evidence/x57/final/nipa-managed.jpg)：DeepSeek，正在用同一模型，
  密钥栏仅“已保存”，没有密钥值。
- [切回来源](evidence/x57/final/nipa-returned.jpg)：回到 Codex，实际模型不变。
- [设备，程序权限关](evidence/x57/final/devices.jpg)：组网不可用，程序开关关，
  与真实 `mesh.devices.status=disabled`、`remotePrograms.enabled=false` 一致。
- [交付构建设备，程序权限开](evidence/x57/delivery-last/devices.jpg)：在启动前
  只给临时宿主 `program.json` 写入 enabled=true，真实接口读回 true，页面
  显示开。没有登录或加入任何 mesh，没有运行远程程序。
- [交付构建 Nipa](evidence/x57/delivery-last/nipa-default.jpg)：实际默认模型。

delivery-ui / delivery-last 是无模型请求的界面复核；最后一轮
[sourceHashes 与真实状态](evidence/x57/delivery-last/summary.json) 对应最终
生产源码。已通过的来源切换未在界面复核中重复。

### Windows、构建与测试

[Windows 审阅](evidence/x57/windows-review.md)：Windows 直接 argv，无七个
shell 位置参数；模型、提供方、信任和会话覆盖均正确。macOS 的 `$0` 是
`nipaplay-chat`，`$1`–`$7` 与任务给定顺序完全对应，真实三轮已覆盖。

- [最后构建](evidence/x57/build-last.log)成功；
  [最后签名](evidence/x57/signature-last.log) deep/strict 验证通过，allow-jit
  保留，无 app-sandbox。末次构建后直接启动并截取自己的窗口。
- [相关宿主 / 记忆测试](evidence/x57/host-memory-delivery.log)：13 通过。
  修改现有真实 Codex + 回环 Responses 测试，断言每次恢复后的 hook 完成、
  最新偏好原文、主指针和三轮历史保持，以及新 home 中“刚才”可读。
- [设置页测试](evidence/x57/ui-tests.log)：10 通过。新增没有签发者时仍显示
  当前 true 权限并能撤销为 false 的回归约束。
- [一次全量 test/next + Classic/Lab](evidence/x57/full-next-classic.log)：
  **568 通过，7 跳过，无失败**。另加 lab_profile、Classic 网络契约、远程
  控制设置与访问守卫。全量后只补足“刚才”候选仍限制 30 个的边界，相关
  13 项再次通过，没有第二次全量。
- [最终 analyze](evidence/x57/analyze-delivery.log)无问题；git diff --check
  通过。没有对已有文件做整文件 dart format。

测试首轮 hook 断言失败；补齐 fixture 的 Git 与项目 config 后仍失败，最终
通过 hooks/list 定位到实际 cwd 和规范 cwd 的 key 不同，见
[诊断日志](evidence/x57/host-hook-details.log)。修复后通过。初次真实实验在
正确检查后 VM 操作失败，未取得完整切换事件，保留
[初始结果](evidence/x57/initial/summary.json)，没有把它算成通过。

### 秘密扫描与清理

九个 profile 的扫描都在停止进程后、删除目录前进行，检查正确和该轮错误
模型密钥的原文字节；日志、Codex rollout、journal 都在扫描范围内。
最终三轮实例扫描 5676 个文件，0 命中，0 shell snapshot 文件；对应 journal
为 `data/next/journal.jsonl`，两份真实 rollout 都已扫描。连接运行所需的
endpoint/VM token 没有当作模型泄漏；它们随 profile 删除，保留的 VM URI 和
endpoint token 脱敏。

所有失败轮也立即按自己的 PID 退出并删除目录，各目录均有 cleanup.json。
末两次界面复核还记录了自己 PID 的进程后代，关闭后无剩余 PID。
[最终审计](evidence/x57/final-audit.json)只按已记录 PID 与这九个 profile
的 cwd 核验，没有按应用名查找或清理其他实例。保留证据再检查真实模型 key、
私钥块、认证 URL 和长 Bearer 值，均为 0 命中。

## 4. 还缺什么与主控决定

本轮五项验证没有待办。Windows 按任务只审阅，没有真实 Windows 运行证据；
当前构建没有 mesh 签发者，只验证了真实不可用状态，没有声称加入组网成功。
模型能读取当前偏好，但有时否认已注入的“刚才”，上述原始答复保留，未把
注入成功等同于模型使用可靠。

需要主控决定的问题：**没有**。
