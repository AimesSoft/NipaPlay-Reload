# X61：按需安装 Codex 与自定义 Responses 端点

2026-10-15，worktree `~/Desktop/nipaplay-next-wt/x61-runtime`，
分支 `next/x61-runtime`。没有 commit、push、pub get、依赖变更或
`lib/next/ui/` 改动。用户 2026-10-15 的新决定覆盖 X59 原先的“随应用打包、
官方端点优先”设计：现在固定运行包按需下载，模型由用户填写地址、key 和模型名。

## 1. 完成了什么

### 固定运行包

- `lib/next/runtime/codex_manifest.dart` 固定 **0.144.1**，含 macOS、Windows、
  Linux 各 ARM64/x64 六个官方 GitHub Release 资产的 URL、字节数、SHA-256
  和原生入口相对路径。下载完整 `codex-npm-<platform>-<arch>-0.144.1.tgz`，
  不下载 npm JS 启动器，不查询 latest，不要求 Node/npm。
- 正式桌面 Next 的启动快照默认解析自管运行包；还没有可用包时自动安装。
  `ChatHost` 最终以绝对路径执行 `codex app-server`。保留整个
  `package/vendor/<target>/` 布局、执行权限、code-mode-host、rg、zsh 和
  Windows 辅助程序。解压调用系统 tar；Windows 为受支持 Windows 10/11 的
  `tar.exe`，Linux 发行环境需具备 tar/gzip。
- 数据在 `<next-data>/codex-runtime/`：下载保存在 `.part`，HTTP Range 续传；
  服务返回 200 时截断重下，错误的 206 范围被拒绝。取消保留部分下载；
  断网保留已落盘部分，重试重新校验。长度和 SHA-256 必须匹配清单；
  hash 不匹配即删除文件并返回失败状态。临时解压目录不作为就绪包发布，
  全部安装步骤完成后才原子重命名。
- 镜像设置只接受不含凭据、查询参数或片段的 HTTPS 目录。镜像目录按清单
  文件名提供运行包和许可文本，校验值不随镜像改变。使用现有
  `SystemProxyService` / `AppHttpProxy`，回环地址直接连接。
- 同目录集中保存固定版本 Codex LICENSE、NOTICE，ripgrep 15.1.0 的
  COPYING / LICENSE-MIT / UNLICENSE，以及固定 zsh commit 的 LICENCE；
  也收集运行包内原有许可文件。第三方文本只下载到数据目录，不进仓库。
  文件来源、hash 和字节数锁在 `codex_licenses.dart`。
- 主程序在 macOS 安装时须通过 `codesign --verify --strict -R=notarized`。
  安装器不重签上游程序、不移除 quarantine、不修改 Gatekeeper。
- 高级选项 `managed / path / specified` 单独持久化；只有明确选 path 或
  specified 时才采用外部 Codex。运行包选择与模型配置来源是两项独立设置。
  移除在 chat 进程运行时拒绝；关闭 Nipa、关闭 chat 或退出应用会取消下载。
  更新清单才更新目标版本，既有其他版本目录不在启动时自动清扫。
  下载完成后才读取最新模型快照，下载期间保存的地址/key/模型会在首次启动生效。
- LabProfile 默认保持原有 PATH/CODEX_HOME 行为。实验可显式设置
  `NIPAPLAY_CODEX_EXECUTABLE` 使用下载程序；未设置时行为不变。移动端不创建
  桌面安装器，Next 关闭时不启动下载。

### 自定义端点

- 新的正式桌面配置以空白 NipaPlay 模型选择开始，没有默认官方地址。
  提供方只是可选显示名称，未填时为“自定义”；地址、key、模型名才是核心。
  `wire_api="responses"`，key 继续走保险库和环境变量，不进入参数或 TOML。
- DeepSeek 模板为 `https://api.deepseek.com/` + `deepseek-flash`；智谱模板为
  `https://open.bigmodel.cn/api/v1` + `glm-5.3-flash`；自定义可任意填写。
  保留原有 OpenAI/OpenRouter 候选以兼容已有接线，所有候选都只是可编辑模板。
- 传输时规范化尾部 `/responses`，保留路径前缀，避免重复拼接。
  不改写已保存 URL，X52 原有的来源、提供方、模型和按原地址绑定的密钥引用
  都继续读取。新测试确认 launch 不改写 `model.json`，密钥仍能取出。
- 自有端点 `checkModel` 发一个最多 256 输出 token 的 Responses 请求，强制
  调用无副作用的 `nipaplay_connection_check` 函数；不会执行真实工具。
  区分连接失败、认证失败、模型不存在、Responses 不支持和工具能力失败，
  仅返回固定中文句子，不回显上游正文。认证请求不跟随重定向，正文读取有界。
  成功只证明该函数调用，不等于所有 Codex 工具、流式和 reasoning 均受支持。
  已保存的用户 Codex 配置来源仍用既有独立 probe thread 检查。

## 2. 决策与界面契约

1. 完整官方平台 npm 资产就是 native 运行目录的载体；从 Release 下载它，
   保留全部原布局，直接运行其中的 native binary，不运行 npm 安装脚本。
2. 新增 `NextHostRuntimeSettings` 宿主端口，通过
   `runtime.hostSettings.runtimeSettings` 访问，沿用 deviceSettings 的兼容方式，
   避免迫使现有 UI/fake adapter 增加方法。`PendingHostSettings` 代理新端口，
   现有 `hostSettings.changes` 同时通知下载进度和状态变化。
3. 安装和模型检查结果通过公开状态返回；自动启动发现安装失败会停止并显示
   原因，不回落到 PATH 或另一家模型。安装完成后可让尚未启动的宿主重试。
4. 镜像与程序来源只在宿主进程接口提供，没有注册 Action、SettingsRegistry
   或 mesh 方法。沿用 X52 的权限边界；普通用户权限下的任意 shell/文件写入
   仍受既有授权约束，此接口不宣称提供 OS 文件权限隔离。
5. `/responses` 规范化只作用于检查和启动，保留 X52 的 vault identity。
   不自动替换旧 DeepSeek 模型或地址，不为自定义模型虚构 catalog 容量。

主控设置页接线：

| 接口／字段 | 用途 |
|---|---|
| `hostSettings.runtimeSettings.codexRuntime()` | 当前运行包快照 |
| `status` | 自管包安装状态：`notInstalled / downloading / verifying / ready / failed`；高级来源另看 source |
| `receivedBytes / totalBytes` | 运行包下载字节进度；订阅 `hostSettings.changes` |
| `version` | 自管包固定版本；外部程序为 null，不能把固定版本冒充其版本 |
| `problem` | 简短失败原因，校验失败明确说明已删除文件 |
| `source / executable / mirror` | 自管包或明确选择的高级程序来源、宿主镜像 |
| `licensesDirectory` | 本地许可目录，供“开源许可”读取 |
| `installCodex()` | 安装或续传；Future 在操作结束时完成，检查最终 status |
| `cancelCodexInstall()` | 取消并保留部分下载 |
| `removeCodex()` | 删除当前版本和运行包部分下载；活动进程存在时拒绝 |
| `setCodexRuntime(UiCodexRuntimeChoice)` | 保存完整来源/程序路径/镜像选择 |

模型页面继续使用原 `model/setModel/checkModel` 字段。模板应在用户主动选择时
填入地址和模型名，仍可修改。LabProfile 没有自管安装器，新端口在 Lab 默认
抛出“不支持／沿用外部 Codex”，主控可隐藏 Lab 的自管运行包区块。

## 3. 实验与验证

### 真实下载、续传、校验与 macOS

证据：[download.json](evidence/x61/download.json)、
[macOS 签名](evidence/x61/macos-signatures.json)、
[下载实验输出](evidence/x61/download-test.txt)。

使用官方 Release `rust-v0.144.1` 的 macOS ARM64 完整平台包，
**120,299,266 字节**，固定 SHA-256：

```text
365a5685170f66bad58dd1dabb0462dfb824f82a870bcc8d9af2eb0a41cf2e18
```

- 初始库存核对下载保存在 `/tmp/nipa-next/x61/inspect.tgz`；随后真实安装器
  独立下载，在 **4,198,567 字节**处取消，保留 `.part`，再次安装续传到
  `ready`。完成下载、校验、解压与许可收集共 **138,186 ms**。
- 库存包只改一个字节，交给同一安装器；观察到 `failed`，消息为
  **“SHA-256 校验失败，已删除下载文件”**，部分文件确实不存在。
- 四个 native binary 的原签名完整性检查均为 exit 0。
  Codex 和 code-mode-host 的 notarized requirement 为 exit 0，签发者是
  OpenAI OpCo, LLC；rg、zsh 是上游 ad hoc 签名，notarized requirement 为 exit 3。
  保留这个区别，不把它们宣称为已独立公证。
- `spctl --assess --type execute` 对裸 CLI 返回“code is valid but does not
  seem to be an app”，未把它解释为失效签名。另对实际下载的主程序**写入并保留**
  `com.apple.quarantine`（0083），直接执行仍 exit 0，输出
  **`codex-cli 0.144.1`**。后续实验也用这份保留属性的程序运行 app-server。
  没有关闭系统保护或清除属性。

下载脚本为 `scripts/next/x61_download_experiment.dart`，需先将上面的固定
资产下载到 `inspect.tgz`，作为单字节破坏实验的原始材料。网络通过现有系统
代理服务；实验和普通测试启动时均去掉代理环境变量，回环直连。

### 本 worktree 的真实隔离实例

脚本：[x61_experiment.py](../../scripts/next/x61_experiment.py)，
结果：[lab.json](evidence/x61/lab.json)。

只由脚本在内存读用户 `~/.codex/config.toml` 的 cpa 地址、当前模型和凭据。
使用本 worktree Debug 构建、临时 NIPAPLAY_PROFILE、默认安静模式，经 VM
扩展操作，没有窗口激活或像素点击。通过自有进程树的 `ps comm` 确认真正
运行的 executable 是刚下载的绝对路径，未读取带环境值或凭据的进程参数。

| 观察 | 结果 |
|---|---|
| 自定义端点真实回合 | `completed`，**3252 ms** |
| 实际模型／提供方 | `gpt-6.1-sol / nipaplay`，取本轮用户 cpa 配置；未假装它是推荐模型 |
| 真实错误 key 检查 | `ok=false`，“密钥无效或没有权限”，**731 ms** |
| 本机 Chat-only 服务检查 | `ok=false`，“端点不支持 Responses 接口”，**1 ms** |
| 用户配置前后 hash | 相同 |
| 秘密扫描 | **277 文件，匹配 0** |
| 清理 | 实例、其自有子进程退出；profile 和下载 runtime 目录删除；记录 PID 均不存在 |

没有读取登录钥匙串，没有修改用户 Codex 配置或 harness，没有操作其他
NipaPlay 实例。没有将端点、key、原始模型输出、VM URL 或第三方文件放入证据。

### 约束测试、构建与失败记录

- Windows/Linux 单元测试只使用本机临时 `.tgz` 夹具，没有下载或执行这些平台
  的官方程序。验证 Windows `.exe` 入口、Linux native 入口、全部 helper 布局、
  原有许可收集、取消／续传、Range 被忽略后的重下、破坏后的删除和显式 PATH
  选择。**4 项通过**（含 manifest 和 Responses 分类）；见
  [相关测试](evidence/x61/runtime-tests.txt)。这不替代两平台真机安装。
- 宿主相关测试 **7 项通过**，覆盖原 vault identity、不丢已保存配置、
  无秘密投影、路径前缀、代理、来源切换后的原线程恢复；见
  [宿主测试](evidence/x61/host-tests.txt)。
- 报告前唯一一次完整 Next + Classic 相关回归：**646 项通过、7 项既有条件跳过**，
  用时 **2 分 11 秒**，没有失败；见 [完整回归](evidence/x61/full-tests.txt)。
  之后首次安装模型快照的读取移至下载完成后，只重跑受影响的宿主测试，
  没有再跑全量，也没有重复已通过的模型请求。
- 最终 Debug 构建成功；按本项目 DebugProfile entitlement ad hoc 签名，
  deep/strict 验证通过。构建产生的 Podfile.lock 变更已恢复，无依赖修改。
  [构建输出](evidence/x61/build.txt)、[签名验证](evidence/x61/sign.txt)。
- 静态检查没有 error/warning；保留 `next_runtime.dart:271` 既有的花括号
  风格 info，未为此改无关代码；见 [静态检查](evidence/x61/analyze.txt)。
- 首次新测试的 `HttpRequest.transform(utf8.decoder)` 类型不匹配导致编译失败，
  同批另一个测试被编译器退出连带标成 loading failure；改为显式
  `cast<List<int>>()` 后相关测试通过。这是 fixture 编译错误，不是网络环境故障。
  其余宿主测试当次已通过，修复后只重跑受影响部分。
- 只对本轮新建的 Dart 文件运行 formatter；现有文件没有整文件格式化。
  [最终审计](evidence/x61/final-audit.json)记录证据秘密扫描、进程／目录清理和源码 hash。

## 4. 还缺什么与主控决定

- UI 接入运行包区块、模板选择和“开源许可”目录展示，由主控完成。
- 镜像服务器的部署与固定版本文件同步属于发行环境，本轮提供可配置入口。
- Windows/Linux 真机安装、Windows Authenticode/SmartScreen、干净 macOS
  分发环境中全部配套 helper 的行为仍需发行验收；本轮按任务仅实测本机
  macOS ARM64。rg/zsh 未独立公证的事实已单列。
- 未使用 DeepSeek 或智谱官方 key，不把自定义 cpa 回合当成两家官方模板
  全工具兼容性的证明，也不声称完成 Rust 所有传递依赖的完整许可审计。

需要主控决定的问题：**没有**。
