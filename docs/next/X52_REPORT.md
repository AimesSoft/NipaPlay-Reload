# X52：宿主模型、组网与远程程序设置

工作目录：`x52-host`；分支：`next/x52-host`。没有 commit、push、依赖变更或 `lib/next/ui/` 改动。`ui_data/host_settings.dart` 的接口保持原样。

中断恢复核对（2026-10-13）：确认工作区改动、报告和已有实验记录一致；核对最终宿主测试、完整测试、真实切换与公开状态证据，`git diff --check` 通过。本次只补充交付记录，没有重复实验、测试或构建，也没有启动实例。

## 1. 完成了什么

- `NextRuntime.hostSettings` 提供完整的 `NextHostSettings` 接口。设置页可以在 Core 初始化前取得对象、订阅 `changes`；调用会等后端就绪。
- 模型选择保存为 `<next-data>/model.json`，内容只有来源、提供方名称、地址、模型和递增版本。用户 Codex 配置来源沿用现有启动行为；NipaPlay 来源生成 `<next-data>/codex-home/config.toml`。
- 密钥只交给 `CredentialVault`。引用按数据目录、提供方和地址分开，`apiKey:null` 保留对应提供方的密钥，空字符串删除。换地址或提供方不会把旧站点的密钥自动送到新站点。密钥不回读给 UI，不进入启动参数、公开环境诊断、活动或 journal。
- `checkModel` 检查保存的选择。NipaPlay 来源发送一个 `POST <baseUrl>/responses` 小请求，保留地址的路径前缀，使用 `AppHttpProxy` 和 `SystemProxyService`，符合已有 `flutter.player_http_proxy` 设置。拒绝携带认证信息的地址，并禁止认证请求跟随重定向。返回中文结果和延迟，不回显上游错误正文。Codex 来源使用独立 app-server 的 ephemeral 线程，保留主会话指针，不记检查回合的过程或 journal。
- `inUse` 来自活跃 `ChatHost.model`；保存的模型和实际使用的模型可以不同。`problem` 表达缺配置、缺密钥、服务未启动/断开、回合错误或已观察到的检查失败。进行中的旧回合不会因新选择的错误而被标成失败。
- 模型修改在下一回合开始时应用。等待宿主全部运行线程结束，重启同一个 `ChatHost` 的 transport，保持流订阅和 sessionId；用原 rollout 路径恢复线程，并覆盖恢复时的模型/提供方默认值。`harness_sessions` 的主线程 ID 不变，rollout 不复制、不改写为第二套历史。
- 自有来源的模型/提供方同时用无秘密的 `-c` 参数指定，优先于 harness 项目配置。用户配置没有写 `model` 时，从 Codex `model/list` 的实际默认项取模型，不硬编码版本默认值；没有写提供方时使用 Codex 默认的 `openai`。新建与恢复线程都使用这次启动的默认值，避免切回后沿用旧来源。
- `<next-data>/chat-rollouts.json` 只保存 ID → 原 rollout 路径。捕获直接创建/恢复和 `thread/started`，覆盖原生帮手的线程路径；并发写串行化。宿主重建后也能恢复主线程。
- `mesh()/setMesh()` 读写 `mesh.json`，保留其他已有字段，支持加入/退出、名称、协调地址、端口、回环、广播、IPv4/IPv6 地址和文件转换端口。旧配置未写 `enabled` 时继续沿用旧行为；显式 `false` 才退出。保存后重启 mesh，端口变化重置本机转换器，在下次取播放地址时绑定新端口。
- 设备列表取已知设备；在线节点刷新实际宿主描述。`mesh-host-facts.json` 只缓存角色和远程程序开关，离线时保留上次已观察到的值，不把离线改成拒绝。正式签发者为空且没有 Debug 开发签发者时，`available=false`，说明“此版本尚未配置组网签发者”。
- `remotePrograms()/setRemotePrograms()` 读写本机 `program.json`，立即更新 `ProgramRuntime.enabled`。关闭后拒绝新程序和 bundle 接收，也拒绝尚未开始的程序；已经运行的程序继续完成。没有新建程序权限 Action。
- 三类宿主修改使用现有 `body_changes` 记入活动，明确 `origin=gui / actor=user`。设置拒绝项保留，并增补模型/Codex/宿主设置前缀。宿主设置没有注册到 Harness、SettingsRegistry 或 mesh 分派器。

界面合并入口：`runtime.hostSettings`。提供方候选常量在 `lib/next/settings/model_presets.dart`，包含 OpenAI、DeepSeek、OpenRouter 和自定义 Responses 地址，附 `responses` 兼容性标记。

## 2. 决策与合并说明

### Codex 协议

本机实际版本为 **0.144.1**。用临时 `CODEX_HOME` 实测 `wire_api="chat"`：app-server 的 initialize 虽然成功，却发出配置无效警告，并回落到默认配置；不能以 initialize 成功判定提供方可用。`wire_api="responses"` 正常加载所选提供方。[协议证据](evidence/x52/protocol.json)。

因此自有配置统一生成 Responses API。DeepSeek 官方 Chat Completions 地址不能直接用于这个版本的 Codex；DeepSeek 候选标记 `responses:false`，需要改填兼容 Responses 的网关地址。没有静默改用 OpenAI，也没有新增 Chat Completions/Anthropic 协议适配器。预置项不保证某个账号、模型或网关的全部工具行为；`checkModel` 验证请求、认证和响应格式，小请求通过也不等价于所有工具能力通过。

配置说明同时核对了 OpenAI Codex 文档技能提供的当前 manual 中 custom model providers / Responses 约定；这里的版本判断以 0.144.1 实测为准。[官方配置说明](https://developers.openai.com/codex/config-advanced/#custom-model-providers)。

### 密钥与 shell snapshot

真正实验发现 Codex 默认开启的 shell snapshot 会保存登录 shell 的环境。仅设置 `shell_environment_policy.exclude` 不能阻止这份快照落盘。因此 Next 启动 app-server 时两种来源都增加：

```text
-c features.shell_snapshot=false
```

自有配置也写入 `[features] shell_snapshot=false`，并从工具环境排除 `NIPAPLAY_MODEL_API_KEY`。保险库读取时将值登记到现有内存 SecretRedactor，随后才启动进程。启动环境的公开诊断采用原有白名单，始终不包含模型密钥。

原有 LabFileVault 会写明文 `credential-vault.json`；真实凭据实验不能使用它。本轮模型设置在 Lab 下用实现同一 `CredentialVault` 接口的内存后端，Lab 重启后需要重新输入实验模型密钥。生产模式仍用 NipaPlay 现有的保险库。这没有改变其他 Lab 凭据的行为。

### 信任与 X50

NipaPlay 自有 `CODEX_HOME` 写入：

```toml
[projects."<当前 harness 的绝对路径>"]
trust_level = "trusted"
```

用户 Codex 来源没有写入或重写用户配置。X50 应继续用启动参数覆盖 `projects.<绝对路径>.trust_level="trusted"`；主控合并 `chat_host.dart` 启动区域时，需同时保留 X50 的信任覆盖、X52 的 `features.shell_snapshot=false`、自有来源的模型/提供方覆盖和 `NIPAPLAY_CHAT` 覆盖。自有配置的信任写入位于单独的 `HostSettingsService.launch().prepare`。

跨 `CODEX_HOME` 的同 ID 恢复使用 Codex 的实验性 `thread/resume.path`，所以带模型设置的宿主 initialize 开启 `experimentalApi`。需要继续按所用 Codex 版本验证这个字段；本轮 0.144.1 的真实切换与宿主重建均已通过。

### Lab 与无界面版

Codex 来源仍从 `<LabProfile.root>/codex-home` 读取预先准备的配置，仍重设 Lab 的临时目录；NipaPlay 来源另用 Lab 数据目录中的自有 home。两者没有覆盖彼此的 config，也没有触碰用户的 `~/.codex` 或 `~/nipaplay-harness`。

headless 仍读自己的 `mesh.json`、`program.json`，默认远程程序关闭；未接入 GUI 的宿主设置或模型启动。自有 `CODEX_HOME + vault + env_key` 的分离对将来在无界面节点运行帮手有意义，但不能直接复用 GUI 的 Lab 内存后端或把密钥放进 headless 配置文件；本轮没有实现那条启动路径。

## 3. 实验与验证

### 自动化约束与集成

`test/next/host_settings_test.dart` 使用随机 canary 密钥和内存保险库，扫描临时目录所有文件、RPC 事件、公开环境、活动和 `state.query` envelope；不打印匹配内容。覆盖密钥保留/地址隔离、代理和路径前缀、错误正文回显隔离、拒绝项、远程程序即时授权、mesh 未配置签发者、已知设备和离线权限缓存。

模型切换集成使用**真实 Codex 0.144.1**与本机 Responses 流服务：主线程、帮手同时运行时保存新来源，主线程完成后仍等待帮手，不提前关闭进程；随后切到自有 home，再切回未显式填写 model 的原 Lab home。主线程 ID 相同、三轮历史保留，关闭并重建宿主后仍恢复同一线程；原 config 字节不变，未生成 shell snapshot 文件，文件和公开结果扫描没有 canary 密钥。独立的 Codex 检查也确认不改变主指针、路径索引或 journal。[最终相关测试](evidence/x52/host-tests.txt)。

宿主与真实 TLS mesh 的相关检查通过 17 项，1 项既有 headless 条件跳过。[mesh 检查](evidence/x52/mesh-tests.txt)。最后一次完整 `test/next` 加 Lab/Classic 网络设置和远程控制回归检查：**513 项通过，7 项按既有条件跳过**；没有加载失败或失败测试。[完整检查](evidence/x52/full-next.txt)。完整检查之后，针对最终线程路径捕获、未填写默认模型、独立检查和设置投影复核，只重跑了相关宿主文件，没有第二次全量测试。

最后构建为本 worktree 的 macOS Debug 构建，使用指定 Flutter 3.44.6、`--no-pub` 和 Erika cache。[构建](evidence/x52/build.txt)。按 DebugProfile entitlement 重新 ad hoc 签名并通过 deep/strict 验证。[签名](evidence/x52/sign.txt)。静态检查没有 error/warning；`mesh/library.dart` 保留原有的花括号风格 info，没有整文件格式化。[静态检查](evidence/x52/analyze.txt)。

### 用户 cpa 凭据的隔离真实切换

只由 `scripts/next/x52_experiment.py` 在内存里读取用户 `~/.codex/config.toml` 的 cpa 地址、模型和凭据。原 Lab config 把凭据改为环境变量引用，自有模型来源的标签设为 DeepSeek。没有复制含密钥的 config 或 auth 文件，没有打印原配置或凭据。

脚本直接启动 worktree 构建的可执行文件，设置临时 `NIPAPLAY_PROFILE`，保持安静、不激活窗口，操作仅经 Lab VM WebSocket 扩展。设置参数中的密钥在 WebSocket RPC 帧传递，没有放进 URL 查询、进程参数或脚本文件。没有启动 `/Applications/NipaPlay.app`。

| 观察 | 真实结果 |
|---|---|
| 正确配置检查 | `ok=true`，可以使用，1806 ms |
| 错误密钥检查 | `ok=false`，密钥无效或没有权限，115 ms |
| NipaPlay 来源回合 | `completed`；实际模型 `deepseek-v4.1-flash`；实际 provider `nipaplay`；2665 ms |
| 切回原来源回合 | `completed`；实际模型 `deepseek-v4.1-flash`；实际 provider `cpa`；1828 ms |
| 线程与历史 | 两次 header 的 thread/mainThread ID 均未变，读取历史得到两轮 |
| 原 Lab 配置 | 字节不变 |
| 用户修改活动 | 3 条 `gui/user` 宿主设置修改 |
| 目录扫描 | 277 个文件，正确/当前错误密钥原文匹配 0；没有模型 vault 文件 |
| 清理 | 应用和 app-server 已退出，实验目录已删除 |

[真实切换结果](evidence/x52/experiment.json)、[经 VM URI 脱敏的实例日志](evidence/x52/lab.log)。正确检查复用 attempt-1 的已通过观察，错误检查复用 attempt-2 的已通过观察；修复快照后的重跑只执行受影响的切换和文件扫描，没有重复已通过的小请求检查。

另做只检查公开状态的独立 Lab 实验，没有重复模型请求：真实 `state.query(activity)` 返回 2 条宿主修改，均为 `actor=user / origin=gui`，公开结果中没有模型密钥；169 个实验文件扫描为 0。[状态结果](evidence/x52/state-experiment.json)、[实际 activity envelope](evidence/x52/activity-state.json)。这个实例也已退出并删除目录。

### 失败与修正

- 首轮 VM readiness 只检查宿主对象存在，主线程 ID 还没就绪，脚本的线程相同断言失败；改为等实际主线程 ID 非空。[attempt-1](evidence/x52/attempt-1.json)。
- 后续切换、检查都成功，但全目录扫描发现 3 个含原凭据的文件。只记录相对路径，确认是两种 home 下的 `shell_snapshots/*.sh`；没有保存文件内容。每次失败也立即退出并删除 Lab 目录。关闭快照后扫描为 0。[attempt-2](evidence/x52/attempt-2.json)、[定位记录](evidence/x52/attempt-3.json)。
- 单元 HTTP 测试最初被 Flutter 测试 binding 的默认 HTTP 拦截阻止；测试内恢复真实 IO client，代理回环实验随后通过。
- 并发帮手测试最初使用共享请求计数跨 `await`，重复完成了 fixture 的 Completer；改为按请求保存计数，最终通过。没有将这个测试 fixture 错误记成产品故障。
- 公开状态实验最初重复拼接了 endpoint 文件已有的 `/harness` 路径，得到 HTTPError；改为使用文件内的完整 URL，仅重跑状态部分。[状态首次记录](evidence/x52/state-attempt-1.json)。
- 构建的 CocoaPods 自动改动 `Podfile.lock` 已恢复；任务开头已有的 GeneratedPluginRegistrant 改动保留，没有处理它。

## 4. 还缺什么与主控决定

1. Y8 的真实界面接线由主控合并，本轮没有改界面。模型提供方候选需把 DeepSeek 的 Responses 网关要求展示给用户；mesh 文件转换端口改变会废弃旧的本机播放 URL，下次读取取得新 URL。
2. 正式 mesh 签发者仍为空，这是当前发行输入缺口；接口已经如实报告不可用，未用开发签发者冒充正式可用。
3. 本轮提供了模型配置和保险库入口，**没有下载或打包 Codex 可执行文件**。当前仍需启动环境能找到 `codex`（Windows 使用原有可执行文件选择）。因此完全没有 Codex binary 的新电脑，仅填写提供方还不能启动 Nipa。要让这类用户不用另装 Codex，需要主控决定发行时怎样随 NipaPlay 提供/安装相应版本的 Codex runtime；本轮受“不改依赖”约束没有新增这一发行组件。
4. 官方 DeepSeek 直连接口需要 Responses 网关或单独的协议适配工作；本轮没有做协议转换，已验证的 DeepSeek 实验来源是用户的 cpa Responses 地址。
5. 本轮的宿主权限边界是**接口边界**：没有 Action/mesh 分派可以调用这些 setter。现有 Codex 的 `danger-full-access`、已授权的任意程序以及 X46 的全文件原语仍有普通用户的文件权限，因而不能宣称它们无法直接改宿主配置文件。没有在此轮暗中改变这些既有授权。若“只有设备前的人能改”要求对任意 shell/文件写入也有强保证，需要主控决定受保护存储或进程隔离方案；接口拒绝项本身不能提供这个保证。

需要主控决定的问题：**Codex runtime 的发行/安装方式，以及宿主设置是否要求进程/文件权限层面的强隔离**。其余实现决策已按本报告落地；X50 的信任覆盖按上文合并即可。
