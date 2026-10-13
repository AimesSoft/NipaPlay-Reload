# X45 / X46 主控三机运行说明

## X47c 后的媒体库验收

本节是 X45 之后的能力增量，须先重编译并替换三端自己的构建；X45 已留存二进制
没有 X47 文件协议。实现者不启动工作站节点，以下跨设备验收仍由主控运行监督。
主控先前账号 Pointer 和端口拓扑的观察已用于修正下文，不要重复旧实验。

下载回传的路径仍属于下载节点，但现在 Mac 的 library()/library.merged 会周期读取
节点目录，按已接受身份合并显示；来源标出设备，离线保留上次事实。未知作品身份仍
需使用现有工具登记/绑定，下载的独立文件不自动猜作品。另一设备上的剧集通过
ui.open {entityId:合并剧集ID} 使用现有 Classic 播放器，视频直接从源处读取。

可观察 Mac 的 `library.merged`、`media.metadata.ui_facts`、`media.library.readable`；
播放应能定位进度并保留同名/导入弹幕、字幕和绑定。图像在 Mac 变为缓存文件路径。
HTTP 转换口只有 Mac 127.0.0.1，默认随机端口，对外不开放明文 HTTP；设备间使用已有
TLS 1.3 双向认证和 SSH 候选，视频不经协调服务。
如需固定端口，宿主在 Mac mesh.json 写 fileProxyPort（1024–65535，修改后重启）；
占用时回退随机，state.query mesh.file_proxy 报告实际端口。发放的 URL 带安全随机
令牌，关闭/重启失效，不打印完整地址到验收证据；未发放令牌的请求应为 404。

文件通道与进程权限相同，可用 media.mesh_files.readable 读取任意节点可读路径，
begin/chunk/finish 写入字幕或传输文件；覆盖和批量删除返回 NeedsDecision，先问
用户再执行确认。没有 shareLibrary 开关，加入 Mesh 就是宿主同意。`/Volumes/Media`
仍遵守本实验的只读约束；写入验收只使用各端 nipaplay-next 工作目录里的测试文件。
离线状态和进度回退可从同一视图观察，设备恢复后同步；具体策略见 X47_REPORT。

本说明供主控亲自运行和监督联网验收。实现者只做了本机回环自动检查与工作站编译，
未启动工作站节点、下载或真实模型对话。证据边界见 [X45_REPORT.md](X45_REPORT.md)。
全部命令使用本 worktree 构建、独立实验目录；不启动安装版，不激活窗口，不操作
`ui-demo` 或主控已有实例，不读取登录钥匙串。模型配置只留在 Mac。

## 1. 程序与端口

| 身体 | 程序 | 数据目录示例 | Mesh 端口 |
|---|---|---|---|
| Mac | 本 worktree 的 `build/macos/Build/Products/Debug/NipaPlay.app/Contents/MacOS/NipaPlay` | `~/Library/Application Support/NipaPlay/LabProfiles/x46-controller/data/next` | 47821 |
| Windows | `D:\nipaplay-next\x46-headless\build\headless\nipaplay-headless.exe` | `D:\nipaplay-next\x46-lab-data` | 监听 47832，候选 47822 |
| WSL | `/home/labuser/nipaplay-next/x46-headless/build/headless/nipaplay-headless` | `/home/labuser/nipaplay-next/x46-lab-data` | 47823 |

Windows 同目录已有 `nipaplay_headless_native.dll`，WSL 已有
`libnipaplay_headless_native.so`；二者同时包含 Mesh 与 librqbit。源码和离线 Cargo
缓存已准备。X46 AOT 已在上述新目录编译，原生库复用 X45；准备脚本
`tool/next/x46_workstation_compile.py` 只解包与编译，不启动节点。第一次准备要求新目录，
再次更新须先保留旧源码与构建，显式选择更新目录。
Mac 的 GUI 仍使用现有 FRB Rust framework；无界面使用独立 C ABI，二者复用 Rust 实现。
远程程序授权、仓库同步和观察项见 [X46_RUNBOOK.md](X46_RUNBOOK.md)；先确认各节点
用的是 X46 程序，X45 二进制不含 `program.run`。

所有 MCP 和 Mesh 节点监听回环。协调服务监听 Mac `127.0.0.1:18082`。
这些是示例固定端口；若已被其他实验使用，整套配置和转发一起换端口，不结束其他进程。
BT 引擎保持正常行为，自己的 TCP/UDP 网络由 librqbit 管理；不能把 Mesh 回环监听
误解为普通下载也只访问回环。

## 2. Mac 协调服务与开发 CA

在本 worktree，使用现有依赖离线构建，临时 CA 私钥仅留在 Mac：

```sh
cd ~/Desktop/nipaplay-next-wt/x46-remote-run
cargo build --offline --locked --manifest-path server/nipaplay-mesh-coordinator/Cargo.toml
mkdir -m 700 /tmp/nipa-next/x46-controller-ca
server/nipaplay-mesh-coordinator/target/debug/nipaplay-mesh-coordinator \
  --generate-dev-ca /tmp/nipa-next/x46-controller-ca/ca.pem \
  /tmp/nipa-next/x46-controller-ca/ca.key
```

另一个终端以前台方式运行，记录自己的 PID；不要把密钥内容写入日志：

```sh
env -u DANDANPLAY_APP_SECRET -u DANDANPLAY_APP_SECRET_URLS \
  -u DANDANPLAY_UPSTREAM_BASE -u DANDANPLAY_APP_ID \
  MESH_CA_CERT_FILE=/tmp/nipa-next/x46-controller-ca/ca.pem \
  MESH_CA_KEY_FILE=/tmp/nipa-next/x46-controller-ca/ca.key \
  MESH_DATABASE_PATH=/tmp/nipa-next/x46-controller-ca/mesh.db \
  MESH_LISTEN_ADDR=127.0.0.1:18082 \
  DANDANPLAY_GATEWAY_BASE=https://nipaplay.aimes-soft.com/dandanplay \
  MESH_ACCOUNT_CLAIM_POINTER=/UserId \
  HTTP_PROXY=http://127.0.0.1:7897 HTTPS_PROXY=http://127.0.0.1:7897 \
  NO_PROXY=127.0.0.1,localhost \
  server/nipaplay-mesh-coordinator/target/debug/nipaplay-mesh-coordinator \
  > /tmp/nipa-next/x46-controller-ca/coordinator.log 2>&1
```

网关访问走 Clash 系统代理，回环直连。X45 主控已确认弹弹play 测试令牌字段是
`/UserId`（大小写敏感）；X46 已把协调服务默认值改为它。可用 [Mesh README 的声明名诊断](../../lib/next/mesh/README.md#主控本机端到端验收)
重启自己的 Mac profile，只输出名称和类型；或协调程序
`--inspect-account-claim-names` 从私有流程的 stdin 取 token，先验证再输出名称。
不要在终端复制令牌、解码打印 payload。没有稳定 ID 声明时停止，交主控裁定；不改限流或账号约束。

健康查询只有回环：`curl --noproxy '*' http://127.0.0.1:18082/healthz`。
将**公开** `ca.pem` 用 `scp ... workstation-wsl:D:/nipaplay-next/x46-headless/ca.pem`
复制，WSL 再从 `/mnt/d/nipaplay-next/x46-headless/ca.pem` 复制到自己的源码目录。
不要复制 `ca.key`、协调数据库或 Mac 模型配置。

## 3. 用户自有 SSH 转发

所有 SSH 由 Mac 发起，只连 `workstation-wsl`，`BatchMode=yes`、无循环重连；认证失败
最多再尝试两次。工作站登录 shell 是 Windows cmd，WSL 命令显式用 `wsl.exe --`。
不改服务、计划任务、网络模式、防火墙或系统 PATH。

Mac 开一个前台终端：

```sh
ssh -N -o BatchMode=yes -o ConnectTimeout=15 -o ExitOnForwardFailure=yes \
  -L 127.0.0.1:47822:127.0.0.1:47832 \
  -L 127.0.0.1:47823:127.0.0.1:47823 \
  -R 127.0.0.1:18082:127.0.0.1:18082 \
  -R 127.0.0.1:47821:127.0.0.1:47821 \
  workstation-wsl
```

Windows→WSL 的 47823 使用 WSL 默认 localhost 转发。
**Windows 节点监听 47832，对外报 47822。** WSL 的 stdio relay 监听 47822 会自动
映射到 Windows 本机 47822；Windows 节点不能再占用它，Mac 的 `-L 47822` 也不能
指向 Windows 47822，否则会绕回 WSL→Mac。47832 是 Windows 节点的终点，不是
转发监听端口。每条转发的终点必须是节点，逐段核对所有 localhost 自动映射；仅凭
`ExitOnForwardFailure` 不能发现成功绑定后的自环。不要同时使用旧拓扑。WSL 默认 NAT 不能假定
`127.0.0.1` 能连接 Windows 的反向 SSH listener，因此另准备了仅转发字节的
[ssh_stdio_forward.py](../../tool/next/ssh_stdio_forward.py)。Mac 分别开三个前台终端：

```sh
python3 tool/next/ssh_stdio_forward.py --listen-port 18082 --target-port 18082
python3 tool/next/ssh_stdio_forward.py --listen-port 47821 --target-port 47821
python3 tool/next/ssh_stdio_forward.py --listen-port 47822 --target-port 47822
```

每条命令通过一个 Mac 发起的 SSH stdio channel，使 WSL 回环 listener 转到 Mac
回环对应端口；47822 再经上面的 `-L` 到 Windows。远端脚本已在
`/home/labuser/nipaplay-next/x45-headless/ssh_stdio_forward.py`。不依赖 WSL 网络改造，
不做地址探测。mTLS 在节点之间结束，转发者不解密 Mesh 内容。
X45 主控已用此修正拓扑完成三机互见；X46 没有再启动工作站节点。
端口绑定失败时停止该实验并检查上述固定路径，不扫描其他地址。

WSL 的 47822 listener 会映射到 Windows 回环 47822，Windows 节点不能也监听 47822；
原说明的同端口配置曾形成转发环。现在 Mac 的 -L 47822 指向 Windows 47832。
三机于是都可使用候选 `127.0.0.1:47821/47822/47823`；协调服务也都在各自回环 18082。

## 4. 隔离配置与登录

Mac 使用新且唯一的 profile（下文 `x46-controller`）。先创建该 profile 的
`data/next`、`harness`、`codex-home`、`temp`，不要覆盖已经存在的实例目录。
`preferences.json` 只在这个 profile 写入：

```json
{
  "flutter.labs_enable_agent_endpoint": true,
  "flutter.labs_use_next_interface": true,
  "flutter.next_harness_path": "<MAC-PROFILE-ABSOLUTE>/harness",
  "flutter.remote_control_receiver_enabled": true,
  "flutter.dandanplay_server_mode": "hongkong",
  "flutter.player_http_proxy": "http://127.0.0.1:7897",
  "flutter.auto_check_updates_in_background": false,
  "flutter.auto_sync_enabled": false
}
```

`data/next/mesh.json`：

```json
{"coordinator":"http://127.0.0.1:18082","name":"Mac Nipa","port":47821,
 "loopbackOnly":true,"broadcastDiscovery":false,"roles":["agent"],
 "storage":[],"addresses":[{"kind":"relay","host":"127.0.0.1","port":47821,"priority":100}]}
```

在 Windows 与 WSL 分别建立上表独立数据目录，初始化 `headless.json`：
`{"format":1,"host":"nipaplay-headless","mediaRoots":[],"port":0}`。
**仅写标记不会启动节点。** 再写各自 `mesh.json`（Windows 把名称、port、候选 port
改为 `Windows workstation`，监听 `port:47832`，addresses 候选仍为 `port:47822`；WSL 如下）：

```json
{"coordinator":"http://127.0.0.1:18082","name":"WSL workstation","port":47823,
 "broadcastDiscovery":false,"roles":["download","library"],
 "agentDeviceId":"<MAC-MESH-DEVICE-ID>",
 "storage":[{"path":"/mnt/d","role":"workstation shared media"}],
 "addresses":[{"kind":"relay","host":"127.0.0.1","port":47823,"priority":100}]}
```

Windows storage 标签用 Windows 路径，如 `D:\\`。storage 是宿主自我描述标签，不授予
文件权限；实际 mediaRoots 与 downloadDirectory、availableBytes 来自宿主实时读取。
Mac ID 在 Mac 加入后从 `data/next/mesh-identity.json` 的 `deviceId` 读取；不要复制身份文件。
组网身份与任务的 ownerDeviceId 是不同命名空间。

测试账号只由脚本读取 `/tmp/nipa-next/testservers.json`（0600）。Mac 启动后运行：

```sh
python3 tool/next/x45_enroll_test_account.py --profile x46-controller \
  --worktree ~/Desktop/nipaplay-next-wt/x45-mesh-three
```

该辅助程序使用 Mac 的 `accounts.login`（原网关 router/client），在内存中取已登录
测试 token，再经 SSH stdin 调用两端 `--enroll-token-stdin`。只往独立 vault 登记
测试账号，不启动节点，不把模型密钥或用户账号带到工作站。不要打印登录回执、vault
或 endpoint.json。本轮没有执行这份联网辅助程序，主控使用时监督其固定端点。

Mac 首次登录后的组网检查最长等待 30 秒；失败加入至少隔 15 分钟重试，不能通过
循环重启绕过协调限流。需要校验声明时使用上节名称诊断。

## 5. 启动三个节点

Mac 临时模型配置按 [X23](X23_REPORT.md) 的隔离方式：仅复制本机已授权的
config/auth 到该 profile 的 `codex-home`，保留 auth 权限并将 config 设为 0600；
只在副本把 model 设为 `deepseek-v4.1-flash`，保留 provider 设置。
复制 `/etc/ssl/cert.pem` 为 profile 的 `system-ca.pem`。不改 `~/.codex`。
`NO_PROXY` 加回环和配置中 provider 的 host，网关仍走 Clash。配置内容及带认证链接不进证据。

```sh
ERIKA_PREBUILT_CACHE_DIR=/tmp/nipa-next/x2-erika-cache \
  ~/development/flutter-3.44.6/bin/flutter build macos --debug --no-pub
codesign --force --deep --sign - --options runtime \
  --entitlements macos/Runner/DebugProfile.entitlements \
  build/macos/Build/Products/Debug/NipaPlay.app
```

然后直接运行**本 worktree 可执行文件**（替换绝对 profile 路径与 provider host）：

```sh
env NIPAPLAY_PROFILE=x46-controller \
  NIPAPLAY_MESH_DEV_CA=/tmp/nipa-next/x46-controller-ca/ca.pem \
  CODEX_HOME='<MAC-PROFILE-ABSOLUTE>/codex-home' \
  CODEX_CA_CERTIFICATE='<MAC-PROFILE-ABSOLUTE>/system-ca.pem' \
  SSL_CERT_FILE='<MAC-PROFILE-ABSOLUTE>/system-ca.pem' \
  HTTP_PROXY=http://127.0.0.1:7897 HTTPS_PROXY=http://127.0.0.1:7897 \
  NO_PROXY='127.0.0.1,localhost,<PROVIDER-HOST>' \
  build/macos/Build/Products/Debug/NipaPlay.app/Contents/MacOS/NipaPlay \
  > /tmp/nipa-next/x46-controller-ca/mac.log 2>&1
```

保留默认安静行为，不设 `NIPAPLAY_LAB_QUIET=0`，不激活或像素点击。用该实例自己的
Debug VM extension 连接对话，接口见 [chat README](../../lib/next/chat/README.md)
及 `scripts/next/x23_vm.py`；连接文件明确指向该 profile。

Windows cmd（可由 Mac 的单次 SSH 前台会话执行，以下是远端命令）：

```bat
cd /d D:\nipaplay-next\x46-headless
set NIPAPLAY_MESH_DEV_CA=D:\nipaplay-next\x46-headless\ca.pem
build\headless\nipaplay-headless.exe --data D:\nipaplay-next\x46-lab-data
```

WSL（Mac SSH 命令前面加 `wsl.exe --`，或 WSL 前台终端）：

```sh
cd /home/labuser/nipaplay-next/x46-headless
NIPAPLAY_MESH_DEV_CA="$PWD/ca.pem" ./build/headless/nipaplay-headless \
  --data /home/labuser/nipaplay-next/x46-lab-data
```

默认 seed 从当前目录读取；其他目录启动要传 `--seed <源码>/assets/next/harness`。
原生库默认从可执行文件旁加载，也可用 `--native-library` 显式指定。
初次启动日志有本实例 PID、endpoint 路径和 URL，没有令牌；把 stdout/stderr 保存到
各自工作目录的实验日志，记下 PID。

Mac 接收跨设备回传仍服从 Classic receiver 开关和设备信任。由主控允许这两个已核对
的 Mesh ID；安静实验可停止自己的 Mac profile，在其 preferences 副本预置
`flutter.remote_control_trusted_devices`（值是 JSON **字符串**）后重启：
每项包含 `clientKey:"id:<MESH-ID>"`、`clientId:"<MESH-ID>"`、`clientName`、
`platform`、`remoteIp:"127.0.0.1"`、ISO `trustedAt`。不修改真实用户偏好，不让 Agent
给自己授权，不绕过 Classic receiver 开关。仅同一私钥的本机自调用无需设备审批。

## 6. 配置、事实与状态

`mesh.json` 是宿主配置；`broadcastDiscovery` **默认 true**，本说明实验设 false。
无界面 Mesh 强制回环，Mac 用 `loopbackOnly:true`。加入、心跳、候选和证书续期不依赖广播。
host roles/storage、coordinator、Agent 设备 ID、签发者和监听启用不作为 Agent 的设置项。
`mesh.addressCandidates` 仍可由已有 settings Action 修改，心跳按原服务间隔上报。

无界面 `<data>/download.json` 可省略；默认正常支持 DHT、tracker、本地发现、PEX
及公网 peers，private torrent 的限制遵循 librqbit。可配置
`{"dht":false,"localDiscovery":false,"trackers":true,"peers":["127.0.0.1:PORT"]}`
进行受控回环夹具检查；这些只是宿主开关，没有改成私有种子专用实现。
PEX 由 librqbit 协议实现管理，没有新增独立 PEX 开关。配置在下载引擎首次初始化时读取，
修改后停止再重启；普通空任务启动不会初始化 BT，引擎恢复未完成下载时会初始化。
下载默认目录 `<data>/downloads`，自选绝对目录不得与只读媒体根相交；符号链接祖先也检查。

每个节点自己的 `running.json`、`journal.jsonl`、`download-audit.jsonl`、`next.db`
以及启动终端日志用于观察。不要把私有 vault、endpoint、身份私钥或整套用户配置复制到证据。
Mac 明确选实验端点：

```sh
export NIPAPLAY_ENDPOINT_FILE='<MAC-PROFILE-ABSOLUTE>/endpoint.json'
python3 '<MAC-PROFILE-ABSOLUTE>/harness/nipa' call mesh.devices '{}'
python3 '<MAC-PROFILE-ABSOLUTE>/harness/nipa' --device 'WSL workstation' list
python3 '<MAC-PROFILE-ABSOLUTE>/harness/nipa' --device 'Windows workstation' describe download.add
python3 '<MAC-PROFILE-ABSOLUTE>/harness/nipa' --device 'WSL workstation' call task.list '{}'
```

`--device` 可用完整 ID 或唯一设备名，支持 list/describe/call/watch。
`mesh.devices` 的 online 表示本次经过认证的调用可达；description 包含角色、宿主类型、
mediaRoots、downloadDirectory 和 headless storageFacts，路径属于被调用设备。
任务的 read/watch 必须也选执行设备。下载事实中的 playable/local 是源设备事实，
不会自动成为 Mac 文件或本地播放器可访问路径。

无界面动态注册只读片库根的 Action 是 `media.library.roots.add/list/remove`；注册不
扫描或改媒体。WSL 可使用 X43 已记录路径 `/mnt/d/Anime/躲在超市后门抽烟的两人`，
主控先确认实际存在；若从 Samba 配置读路径，仅读取已知共享的 path 项，不读认证。
本轮只读过 path 项但未从 Samba 核实这条 Anime 路径。不要重挂载 `/Volumes/Media`。
随后片库扫描、资料读取、身份批量绑定用节点实时目录中的 Action。

自动回传保留提交时原 thread/repository，即使 Mac 切换会话也不改变。源节点
`deliveryState:forwarded` 仅表示目的端已持久接收，目的端 followups 的 turnId/turnStatus
才表示对话执行情况。未指定 threadId 的脚本 `agent.wake` 到 Agent 设备主会话，忙时排队。
下载后续无需脚本手填远端会话；控制面/SSH 中断会等待并按持久批次重试，不能重复提交下载。
手动订阅文件事件可在 Mac 使用已有 `followup.register`；远端 jobId 不能当 Mac 本地任务 ID。

## 7. 主控的真实观察

先保存三端互见的 `mesh.devices`、Mac 对两端片库/下载/任务读调用的脱敏输出。
再给 Nipa 三条用户原话，不给操作步骤：

1. “工作站上都有些什么剧？”
2. “把工作站上的《躲在超市后门抽烟的两人》整理好”
3. “在工作站上把这个合集下下来，第一集好了告诉我”

下载实验由主控选择合法公有领域/CC0 合集或自制小视频；输出目录只在工作站工作目录。
真实网络行为由主控监督，不扩大校园网流量。记录发现设备和工具的轨迹、卡点、逐文件
登记和事件、首文件完成时父任务状态，以及原会话后续 turn 的真实 threadId、turnId。
再由工作站事件或定时脚本调用当地 `agent.wake`，核对 Mac 收到来源设备与触发事实。
下载节点不创建对话。只看到 ready/forwarded 不能宣称真实 DeepSeek 已回复。

## 8. 停止与清理

先停止各自 headless，等待启动终端 `stopped`：

```bat
D:\nipaplay-next\x46-headless\build\headless\nipaplay-headless.exe --stop --data D:\nipaplay-next\x46-lab-data
```

```sh
/home/labuser/nipaplay-next/x46-headless/build/headless/nipaplay-headless \
  --stop --data /home/labuser/nipaplay-next/x46-lab-data
```

Mac 先通过自己的 Debug 宿主 close 入口关闭 app-server，再结束启动时记下并核对过的
Mac PID；不要按应用名找进程。协调服务、三个 stdio relay、主 SSH 转发各自 Ctrl+C
或按各自 PID 退出；relay 会结束自己的 SSH child，远端 stdio EOF 关闭 WSL listener。
确认自己所有进程退出后，只删除两个 `x46-lab-data`、自己的 Mac profile、临时 CA
目录和其下载测试数据/日志。保留 `x46-headless` 源码、构建、离线工具；公开 CA 副本
可以随实验清除。不操作任何系统服务、计划任务、用户媒体、download-harness 或用户 Codex。
