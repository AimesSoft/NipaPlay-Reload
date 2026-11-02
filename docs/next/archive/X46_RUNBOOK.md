# X46：三机远程能力与程序运行

本说明由主控亲自执行和监督。实现者只运行了 Mac 本机合成账号/mTLS 回环检查，
工作站只编译，不启动节点、不跑网络实验或真实对话。基础配置、登录、Mac 临时
DeepSeek 配置、启动与按 PID 清理沿用已修正的 [三机运行说明](X45_RUNBOOK.md)。
不要触碰主控已有实验、ui-demo、安装版、真实登录钥匙串或用户数据。

## 当前程序与转发终点

| 节点 | X46 程序 | 监听 | 广告/各节点使用的候选 |
|---|---|---|---|
| Mac GUI | 本 worktree `build/macos/Build/Products/Debug/NipaPlay.app/Contents/MacOS/NipaPlay` | 127.0.0.1:47821 | 127.0.0.1:47821 |
| Windows | `D:\nipaplay-next\x46-headless\build\headless\nipaplay-headless.exe` | 127.0.0.1:47832 | 127.0.0.1:47822 |
| WSL | `~/nipaplay-next/x46-headless/build/headless/nipaplay-headless` | 127.0.0.1:47823 | 127.0.0.1:47823 |

两端 AOT 已编译，原生库没有变更，复用 X45 的 `.dll/.so`；可继续使用既有离线工具。
Mac 只直接运行本 worktree 可执行文件，带独立 `NIPAPLAY_PROFILE=x46-controller`，
保留默认安静行为。不要启动 `/Applications/NipaPlay.app`，不要通过应用名定位进程。

Mac SSH 的 `-L 127.0.0.1:47822:127.0.0.1:47832` 最终到 Windows 节点；WSL 47822
stdio listener 经 WSL 自动 localhost 映射也占据 Windows 47822，因此它不能同时
是 Windows 节点端口或 Mac `-L` 的目标。WSL→Mac47822→Windows47832 才有终点。
保留原先 47821、47823、18082 的转发。开始前逐条确认终点是节点/协调服务，
不是另一个指回上游的转发器；绑定成功不代表无环。不要同时运行旧 47822→47822 拓扑。

协调服务默认账号声明已改为 **`/UserId`**，大小写敏感。这是 X45 主控观察的弹弹play
令牌字段；环境显式指定旧 `/userId` 会覆盖正确默认值，须移除或改正。
只输出声明名和类型的诊断仍可用于不同发行方，不输出 token 或 payload。

## 由目标设备宿主授权

每台节点独立，默认关闭。在自己的实验数据目录创建 `program.json`：

```json
{"enabled": true}
```

| 宿主 | 示例配置路径 | 程序工作目录 |
|---|---|---|
| Windows | `D:\nipaplay-next\x46-lab-data\program.json` | `D:\nipaplay-next\x46-lab-data\harness` |
| WSL | `~/nipaplay-next/x46-lab-data/program.json` | `~/nipaplay-next/x46-lab-data/harness` |
| Mac profile | `<profile>/data/next/program.json` | 该 profile 的 `next_harness_path` |

Windows cmd 的宿主写法（目录必须是自己已初始化的 headless 数据目录）：

```bat
echo {"enabled":true}>D:\nipaplay-next\x46-lab-data\program.json
```

WSL 宿主写法：

```sh
printf '%s\n' '{"enabled":true}' > "$HOME/nipaplay-next/x46-lab-data/program.json"
```

Mac 可以用文本编辑器在上述隔离 profile 的 `data/next` 写同一 JSON；本轮不修改界面。
开关在宿主启动时读取，修改后由宿主按该实例 PID 正常停机并重启。设 `false` 或在
停机后删除自己创建的文件即可关闭。不要让 Nipa 写这些宿主配置或替自己授权；
`settings` 注册表拒绝 `program.*`/对应旧名，远端没有设置修改或宿主登录入口。
无需把 Mac 的开关打开才能指挥已授权的工作站。

开启的含义是让 Nipa 像这个用户一样运行任意程序，能访问该用户可访问的文件和
当地凭据；工作目录不是 OS 沙箱。默认不继承模型认证、Codex 配置、代理或调用者
环境，只带目标 OS 的基础环境和目标 endpoint 文件路径。凭据应通过目标本地文件
引用，不放在命令正文；会进入 journal 的命令输入遮蔽，任务/activity 中记录脱敏事实。
删除、覆盖和对只读实验媒体的约束仍然有效。`/Volumes/Media` 与工作站媒体只读；
不要让测试程序写媒体目录，产物放在本节点 harness 的 `records/`。

## 仓库与运行能力

Mac 明确选择自己的 endpoint，用 seed 中新版 `nipa` 检查实时设备描述：

```sh
python3 '<MAC-HARNESS>/nipa' call mesh.devices '{}'
python3 '<MAC-HARNESS>/nipa' --device 'Windows workstation' describe program.run
python3 '<MAC-HARNESS>/nipa' --device 'WSL workstation' describe subtitle.import
```

设备描述中的 `programExecution.enabled/workingDirectory/defaultShell` 给出真实开关、
工作目录和平台。核对 Mac 的工作目录是 `next_harness_path`，不是公共 `harness-seed`；
X45 记录中出现过后者，本轮不改主控的 profile。已有用户 harness 不自动覆盖 seed，
需要主控或 Nipa按现有 Git seed 合并契约取得新版 `nipa` 与事实。

同步接口为 `nipa --device ... sync-repository --repository <本地仓库> --ref HEAD`。
它只传选定已提交引用及可达历史，不传 `.git/config`、未提交文件、私有 endpoint、
环境变量或模型目录；仓库及历史不能包含秘密。每片最多 384 KiB，总计最多 64 MiB，
经过已有认证 Mesh 传输，最终核对 SHA-256，重复片不覆盖不同内容。
结果包含执行设备上的 `bundle.path`、提交 revision。目标仍是原 harness，bundle 存在
`records/mesh-bundles/<来源摘要>/<内容摘要>.bundle`，不会自动 checkout 或合并。

目标 `program.run` 可以用当地 Git 从 bundle 新建独立目录，或 fetch 到当地 harness；
怎样选择、合并、解决冲突由 Nipa 决定。要覆盖已有内容先取得用户授权。
工具在目标 harness 下可直接调用，无需搬运整部视频。Windows Git/Python/ffmpeg 若
不在当地环境里，由宿主在工作目录准备或使用绝对程序路径，不做全局安装或改 PATH。

`program.run` 输入为标题、`command`，可选 `shell`、`timeoutSeconds`、`followup`。
Windows 默认 `cmd`，可显式 `powershell`（无 profile、非交互、UTF-16 编码命令）；
WSL/Linux/macOS 为 `sh`。脚本也通过该平台命令解释器调用，不假设 Windows 有 sh。
默认超时 900 秒，可设 1–3600 秒；后台立即返回 jobId，任务 get/wait/watch、取消都
选择执行设备。回执验证的是程序结束及退出码，不宣称输出内容正确；任务 details
与回执包含 stdout/stderr 末尾（各最多 8192 字符）、退出码、耗时及超时/停止事实。
运行中的输出每秒发布。中断任务重启时记失败，不自动重放命令。

会话发起且未设 `followup:false` 时，终态事实绑定原设备/仓库/线程，采用 X45 已签发
回传票据、持久去重和丢 ACK 重试。脚本发起且无会话来源时不猜返回线程；可显式
登记目标节点后续或按宿主 Agent 目的设备 wake。源端 `forwarded` 只代表目的端
持久接收，实际模型 turn 的运行状态在目的端。远端 `followup.register` 固定返回发起会话，保留登记的 instruction；显式 threadId
必须与发起线程相同。自动回传与相同事件的手动订阅去重。不要用远端 jobId 订阅 Mac 本地任务。

## 主控验收与清理

先在一台自己控制的工作站节点开关，再由主控让 Nipa自然完成一个小任务，例如
“在工作站上用你仓库里的工具，从这个视频截一张图，做好告诉我”。不要给 Nipa
编排识别、同步或调用流程。素材只读，输出在工作目录，检查 actual cwd、所选平台、
目标 activity 的来源/设备/命令、退出码、输出脱敏、取消/超时，以及原线程真实 turn。
没有 ffmpeg 时如实记录缺少程序，准备工具由主控决定。

字幕事实和导入/默认选择可在两端直接远程调用；内嵌轨道需要宿主 `--ffprobe` 或
持久 headless 配置中的 ffprobe，未配置返回 unavailable。无界面仍没有播放器、
Classic 历史和完整账号管理，不能把这些能力的缺席解释为用户没有观看记录。

停止顺序与 [X45_RUNBOOK](X45_RUNBOOK.md#8-停止与清理) 一致，节点关闭会取消
自己的程序任务并等待退出。取消/超时终止普通进程树；显式脱离父进程的 daemon
不属于可跟踪子树，不把 `task.cancel` 当 OS 沙箱。记录自己启动的 PID，结束后确认
没有编译或节点子进程残留；只删除自己的实验数据/profile/CA与中间输出，保留两端
`x46-headless` 程序、X43工具和 X45 公共原生库。不操作用户 Codex 或 download-harness。
