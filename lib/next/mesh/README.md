# 阶段 M：客户端 Mesh

NextCore 创建 MeshRuntime、三个 Mesh Action 和 mesh.addressCandidates 设置项，
并管理 transport 生命周期。NextRuntime 将包含播放能力和 journal 的同一个 Harness
交回 Core；回环 MCP 和 Mesh 复用 nipa_harness/mcp.dart 的 JSON-RPC 分派器。
Mesh 不依赖 Labs 端点开关。可远程调用范围为 task.*、download.*、media.*、
danmaku.*、playback.*、subtitle.*、history.*、followup.*、program.*、discover.*、
sync.*、ui.*、state.query、agent.wake、activity.report、app.instance；另有设置读取
settings.get/describe/history，以及 accounts.status、collections.get/update、
episodes.get/update、bangumi.sync/sync_status。具体以目标宿主已注册目录为准。
没有远程 settings.set/reset、accounts.login/logout、credentials 或 Mesh 管理入口。
逐族理由与缺口见 [X46_REPORT](../../../docs/next/X46_REPORT.md)。

`program.run` 由目标宿主 `<next-data>/program.json` 的 `enabled:true` 独立授权，
默认 false、重启生效；不注册为 Agent 设置。普通用户进程在目标 harness 执行，
不继承发起设备环境。`program.repository.receive` 同一开关控制；`nipa sync-repository`
通过 Mesh 分块送 Git bundle 到目标 harness，不携带 Git 配置/未提交文件或自动合并。
运行事实、回执与原会话后续复用任务/activity/X45 交付基础设施。

## 身份、信任与调用

首次加入生成 Ed25519 PKCS#8 密钥；私钥只写 CredentialVault，公钥和不透明引用写
mesh-identity.json。保险库 key 由安装数据目录摘要区分，两个空白隔离目录生成不同设备身份。
Mesh deviceId 为 base64url(SHA-256(32 字节公钥))。
已有 TaskEngine 的本地持久 ownerDeviceId 保持原值，不改写旧任务归属；
Mesh 的设备、证书与 Invocation.origin 使用公钥派生的 Mesh deviceId。

Rust nipaplay-mesh 使用 ring、rustls / WebPKI 和 tokio-rustls。两端只允许 TLS 1.3；
标准验证器校验证书链、EKU、有效期，并要求客户端证书。
目标 DNS SAN 只用于绑定设备，不用于 DNS 寻址。
DNS 标签使用公钥 SHA-256 摘要的十六进制，格式为 d-前32字符.后32字符.mesh.nipaplay.invalid；
身份 URI 和协议 deviceId 仍使用既定 base64url 摘要。握手后再检查标准身份 URI 中的账号、
设备公钥摘要和最新设备快照的允许集合。证书到期或允许集合变更会关闭相关会话。
私有证书扩展 OID 不参与身份验证。

每个 TLS 连接传输一个 JSON-RPC 请求和响应：4 字节网络字节序长度，随后 UTF-8 JSON，
上限 1 MiB。文件读取响应另有下述二进制格式。initialize、ping、tools/list、tools/call 与回环 MCP 使用相同分派逻辑。
Mesh 帧增加 mesh: {invocationId, nonce, deadline}；deadline 使用 Unix 毫秒，必须在
当前时间到 1 小时内。ID/nonce 均至少 22 个 base64url 字符。按来源设备分别去重，
先持久化无秘密的去重记录，再进入 Harness；重启不会重置仍有效的窗口。
没有 TLS 0-RTT。并发会话/待分派队列均有上限。

## 跨设备媒体库与文件（X47c）

加入 Mesh 表示宿主同意同账号设备访问。目录、文件读写使用现有 TLS 1.3 双向证书、
设备公钥身份、有效期和吊销快照；没有 `shareLibrary` 开关，也没有库内路径白名单。
节点进程能读写的文件，同账号已认证设备就能读写。文件原语与目录协议不经过 Classic
receiver/trusted-devices 的第二次审批；tools/list 可由已认证设备读取；其他既有工具调用和回传的审批行为保留，X46 合并时
核对这一小处分派。协调服务只处理身份和地址，视频、字幕、弹幕、写入字节直接在设备
之间传输，沿用 LAN、overlay、用户自有 SSH 转发候选。

`mesh/library/snapshot` 提供版本化目录页（目标约 256 KiB，单页最大 512 KiB），
包含来源身份、元数据、剧集、文件摘要及进度观察。接收端每 5 秒拉取，设备名单最多
每 30 秒刷新；失联不删除上次目录和图片缓存。分页中版本改变则整批拒绝，下次刷新
重读。每个设备保留自己的数据库，只交换目录事实和小型附件。

`mesh/library/file` 接受 `path`（源设备绝对路径）、`fileId` 或 `assetId`，返回大小与
mtime 标记；`mesh/library/read` 携带标记和 offset/length，每次最多 1 MiB。
Rust 在同一 mTLS 连接返回：高位为 1 的 u32 JSON 头长度、JSON 头、u32 字节数、原始
字节。普通 JSON 响应长度高位为 0。Dart/Rust adapter 内部的 base64 不经过网络 JSON
帧；视频不会装进 1 MiB JSON。每段重检文件标记，源文件改变时拒绝后续段。

播放端只监听 **127.0.0.1**，默认随机端口，提供进程生命周期内 HTTP GET/HEAD/Range
转换地址（206、suffix range、416）。不对外开放明文 HTTP。每段数据直接从源节点
的 mTLS 通道读取，不复制整部视频。播放器打开这种地址时临时清除 HTTP 代理，
下一次普通播放恢复原代理；ffprobe/ffmpeg 使用地址时回环也应直连。

每次发放 URL 的路径令牌用 `Random.secure()` 生成 **256 位**随机值，不从设备 ID、
路径或文件 tag 推导。同文件再次发放也生成新令牌；已发放令牌在当前 MeshLibrary
实例关闭/进程退出前保留，关闭清空令牌。重启即使使用同一固定端口，旧令牌也返回
404；未发放/猜测的令牌始终返回 404。源文件变化时旧 tag 的字节读取会失败，须重新
取得地址；源设备离线、证书到期或吊销也仍受原 Mesh 校验约束。URL 是本机可读凭据，
不要打印或记录其完整值。

宿主可在调用/播放端 `mesh.json` 添加 `"fileProxyPort":54321`，允许整数 **1024–65535**。
省略或 0 使用随机端口。它是宿主启动配置，不注册 Agent 设置/修改 Action，设置
注册表拒绝 `fileProxyPort`、`mesh.fileProxyPort`、`mesh/fileProxyPort`；修改配置后重启
本实例生效。监听在第一次发放远端 URL 时启动；并发发放共用一个监听器。
固定端口被本进程或其他进程占用时退回随机端口，仍只绑定回环；其它绑定错误不冒充
端口占用。`state.query {view:"mesh.file_proxy"}` 显示 host、requestedPort、实际 port、
state（not_started/random/fixed/random_fallback/invalid_configuration/closed）、fallback
和 reason；占用原因是 requested_port_in_use。该状态视图不包含访问令牌。

Agent 能力（实际 schema 以 `nipa describe` 为准）：

| 能力 | 输入与结果 |
|---|---|
| `media.library.readable` | 批量 episodeIds；本机 path，远端为接收端回环 URL |
| `media.library.refresh` | 显式刷新合并库 |
| `media.library.progress` | 批量进度观察，允许回退和重置 |
| `media.mesh_files.readable` | entries:[{path,deviceId?}]；任意可读文件的本机 path 或接收端回环 URL |
| `media.mesh_files.begin` | path、size、deviceId?；目标父目录暂存，返回 transferId |
| `media.mesh_files.chunk` | transferId、offset、base64 data、deviceId?；最大 512 KiB 解码字节，相同重试可接受 |
| `media.mesh_files.finish` | transferId、可选 sha256、deviceId?；校验完成后发布，覆盖返回 NeedsDecision |
| `media.mesh_files.delete` | paths 批量、deviceId?；只预览，返回 NeedsDecision |
| `media.mesh_files.confirm` | 决定中的 destructive ActionCall；核对目标未变后执行 |
| `media.mesh_files.cancel` | 丢弃本原语建立的暂存文件 |

省略 deviceId 操作本机。删除和覆盖都先问用户；新建文件可直接执行。确认票据绑定
认证调用设备，只能使用一次；预览后目标变化会拒绝。chunk 的原始内容在 schema 中
标为 secret，不写入调用 journal。大文件写入使用有界 base64 JSON 分段（约 699 KiB
加协议头），读取使用原始二进制帧。传输、确认票据目前不跨进程重启；正常关闭
清除未完成暂存，异常退出留下 `.nipa-transfer-*`，目标文件不提前截断。父目录须已存在。
`--device NAME` 也可调用这些原语；在 Mac 取得本机可读 URL 用本机 Action 的 deviceId。

远端剧集仍通过 `ui.open {entityId}` 播放。绑定弹幕、导入弹幕和同名弹幕以小附件交付，
保留开关、偏移及时间段；同名字幕和字幕选择复用本机事实，图片与附件可缓存。
查询使用 `state.query` 的 `library.merged`；合并和进度策略见 ui_data README。

mesh.invoke 拒绝 destructive，mesh.invoke_destructive 只接受 destructive；
接收端再次核对 effect。NeedsDecision 按每个选项的目标 effect 包装为本机 ActionCall。
网络断开时不自动重试可能已执行的 tools/call，调用者先查目标任务状态。
成功直连后复用地址，后续 Harness RPC 不再逐次请求协调服务；
只读的协议查询发现地址失效时才重新获取候选并建立经过验证的连接。

## 控制面与发现

协调服务通过 NipaPlay 网关的只读 playhistory 验证后解析配置的 JWT 声明；
客户端不自报 accountId，协调服务不持有 AppSecret，也不调用上游 renew。
注册和设备证书续期都签名时间戳、nonce、操作及请求字段，具体数组见协调服务 README。
启动重新同步设备快照；心跳每 900 秒或服务端更长间隔加 0–10% 抖动。
每次心跳上报网卡/手填地址并同步吊销计数和设备列表；更新允许集合立即终止已吊销会话，
并拒绝其新连接。被吊销节点的地址上报会被拒绝，此时仍同步快照并关闭自身监听和会话。
网络失败保留当前状态供下次心跳重试；7 天证书到期后 TLS 拒绝连接。

UDP 32124 每 30 秒广播 deviceId 和监听端口，仅作为地址线索。
网络禁止广播时仍可通过协调服务地址直连。手填 overlay、公网、manual、relay 候选
均经过同样的双向 TLS；用户自有 TCP relay 只需要转发字节，
协调服务从不转发任务或媒体数据。

## 宿主配置与正式 CA

宿主在 AppStorage/next/mesh.json 配置：

~~~json
{
  "coordinator": "https://your-mesh.example",
  "name": "工位机",
  "port": 47812,
  "addresses": [
    {"kind": "overlay", "host": "100.64.0.10", "port": 47812}
  ]
}
~~~

启用和信任配置由宿主管理，Agent 不能通过 Action 给自己开放网络权限或更换签发者。
`broadcastDiscovery` 是宿主 JSON 中的布尔开关，默认 `true`；设为 `false` 不启动 UDP
32124 的广播发现，续证重启监听时仍保留这个选择。`loopbackOnly:true` 使 Mesh 只监听
`127.0.0.1`，也不上报网卡 LAN 地址。无界面宿主强制回环 Mesh 监听；候选可以是用户
自有 SSH 转发端口，同样执行双向 TLS。加入本身不依赖广播。设备自我描述来自已认证
的 `mesh/describe`，不是协调服务代报的磁盘信息；角色与存储标签由宿主配置。
地址可通过 settings.set {key:"mesh.addressCandidates", value:[...]} 修改，下个心跳上报。
登录和退出由现有账号宿主处理；账号凭据仍只在保险库中。Mesh 每 30 秒在本地检查凭据变化，
变化时关闭旧会话；失败的加入尝试至少隔 15 分钟再试。

开发构建使用 NIPAPLAY_MESH_DEV_CA=/absolute/path/to/public-ca.pem。
Release 忽略该变量，仅使用 meshProductionIssuerPem 内置常量；目前常量为空，
显示 issuer_not_configured 并拒绝启用，等待主控确定正式 CA。
主控确认后将公开 CA PEM 写入该常量并随 App 发布（不含签发者私钥）。
轮换需由主控决定新的信任集合与旧证书过渡，再更新内置数据；
不得以首次下载 server-info 响应建立信任，server_public_key 也不替代内置 CA。

## 主控本机端到端验收

自动验收完全使用模拟上游与合成令牌：

~~~sh
~/development/flutter-3.44.6/bin/flutter test --no-pub test/next/mesh_integration_test.dart
~~~

此测试构建 Rust 库和协调服务，调用协调服务 --generate-dev-ca，在同一进程启动两个节点，
并连接真实协调服务进程与本机模拟网关。协调服务启动环境不继承宿主环境、无需 AppSecret；
模拟网关检查 `/dandanplay` 前缀与无应用签名头。没有真实令牌或线上请求。

macOS Debug 构建完成后，可用同一测试验证实际包内 Rust framework：

~~~sh
NIPAPLAY_MESH_TEST_LIBRARY="$PWD/build/macos/Build/Products/Debug/NipaPlay.app/Contents/Frameworks/rust_lib_nipaplay.framework/rust_lib_nipaplay" \
  ~/development/flutter-3.44.6/bin/flutter test --no-pub test/next/mesh_integration_test.dart
~~~

测试夹具显式加载包内 FlutterMacOS framework，补齐 flutter_tester 缺少的应用框架路径。

以下真实账号验收由主控执行。协调服务指向已有网关，网关自行持有 AppSecret；
协调服务环境移除旧 `DANDANPLAY_APP_SECRET` / `DANDANPLAY_APP_SECRET_URLS`、
`DANDANPLAY_UPSTREAM_BASE` / `DANDANPLAY_APP_ID` 配置。实现与自动测试没有执行这一过程。

~~~sh
mkdir -p /tmp/nipaplay-mesh-e2e
cargo run --manifest-path server/nipaplay-mesh-coordinator/Cargo.toml -- \
  --generate-dev-ca /tmp/nipaplay-mesh-e2e/ca.pem /tmp/nipaplay-mesh-e2e/ca.key
export MESH_CA_CERT_FILE=/tmp/nipaplay-mesh-e2e/ca.pem
export MESH_CA_KEY_FILE=/tmp/nipaplay-mesh-e2e/ca.key
export MESH_DATABASE_PATH=/tmp/nipaplay-mesh-e2e/mesh.db
export MESH_LISTEN_ADDR=127.0.0.1:18082
export DANDANPLAY_GATEWAY_BASE=https://nipaplay.aimes-soft.com/dandanplay
# 若主控本机已有运行的网关，可改用 http://127.0.0.1:18081
~~~

先确认声明名：以终端直接启动 Debug App，并开启宿主诊断：

~~~sh
mesh_app="$PWD/build/macos/Build/Products/Debug/NipaPlay.app"
NIPAPLAY_DEBUG_DANDANPLAY_CLAIM_NAMES=1 "$mesh_app/Contents/MacOS/NipaPlay"
~~~

宿主启动时直接从保险库读取 `preferences/dandanplay_token`，本地解析 JWT payload，
stdout 只输出 `[DandanplayClaimNames]` 加声明 JSON Pointer 与 JSON 类型，绝不输出值、
令牌或解码后的 payload。没有令牌时 stderr 提示 `token_not_found`；先通过 GUI 登录，
再退出并带同一个开关重启。格式错误与保险库失败只给固定错误代码。
该诊断不验证令牌有效性、不判断字段是否稳定，不执行网络请求；
Release/Profile 忽略开关，不读取保险库，不注册 Harness Action，不进入 Agent 或 journal。

例如输出包含 `{"pointer":"/UserId","type":"number"}`，且主控确认它是稳定用户 ID，
则设置 `export MESH_ACCOUNT_CLAIM_POINTER=/UserId`；嵌套声明 `/identity/uid` 可直接设置
为 `export MESH_ACCOUNT_CLAIM_POINTER=/identity/uid`。Pointer 中名称的 `~` 与 `/` 分别
转义为 `~0` 与 `~1`，直接复制诊断的 pointer 即可。协调服务接受正整数或 1–128 字节的
字母、数字、`-._` 标识字符串；字段名称和类型只能帮助找候选，不能证明其稳定性。
X45 主控已确认测试账号令牌的声明为 `/UserId`；X46 将它设为默认值。其他
签发格式可由宿主显式设置 pointer；不存在稳定 ID 时交主控裁定。
配置确认后启动（每次修改声明 Pointer 都重启协调服务）：

~~~sh
cargo run --manifest-path server/nipaplay-mesh-coordinator/Cargo.toml
~~~

macOS 非 App Sandbox 的 Debug 版使用两个 lab profile。它们独立保存偏好、钥匙串账号、数据与连接文件；真实媒体目录只读。另一个终端准备：

~~~sh
mesh_app="$PWD/build/macos/Build/Products/Debug/NipaPlay.app"
mesh_data="$HOME/Library/Application Support/NipaPlay/LabProfiles"
mkdir -p "$mesh_data/mesh-a/data/next" "$mesh_data/mesh-b/data/next"
cp /tmp/nipaplay-mesh-e2e/ca.pem "$mesh_data/ca.pem"
cat > "$mesh_data/mesh-a/data/next/mesh.json" <<'JSON'
{"coordinator":"http://127.0.0.1:18082","name":"node-a"}
JSON
cat > "$mesh_data/mesh-b/data/next/mesh.json" <<'JSON'
{"coordinator":"http://127.0.0.1:18082","name":"node-b"}
JSON
NIPAPLAY_PROFILE=mesh-a NIPAPLAY_MESH_DEV_CA="$mesh_data/ca.pem" \
  "$mesh_app/Contents/MacOS/NipaPlay"
~~~

在实验窗口登录弹弹play并开启 Labs Agent 端点；另开终端，以相同 mesh_app/mesh_data 路径启动第二节点：

~~~sh
NIPAPLAY_PROFILE=mesh-b NIPAPLAY_MESH_DEV_CA="$mesh_data/ca.pem" \
  "$mesh_app/Contents/MacOS/NipaPlay"
~~~

两个 profile 分别保存设备身份、Next 数据库、任务、journal、harness、偏好和单实例锁。
需要同一账号时在两个实验窗口分别登录；不会读取真实实例的登录态。
Agent 与 Mesh 端口由系统分配，连接地址从各自 endpoint.json / Mesh 控制面取得。
实验实例不参与真实实例的 UDP LAN 发现广播。开关只在 Debug 生效。
不要复制 mesh-identity.json 创建第二安装。开发 CA 私钥留在协调服务目录，App 只读公开证书。

在 mesh-a 的 harness 连接 Agent，先调用 mesh.devices，确认两台设备具有不同的
公钥派生 ID 且 node-b online；调用 mesh.invoke 指向 node-b 的 download.add，
再用 task.get/task.wait 确认任务在 node-b 执行。
对删除使用 mesh.invoke_destructive，确认普通 mesh.invoke 被拒绝。
播放有多个版本时确认 NeedsDecision 选项已路由到 node-b。
对端授权根目录和下载设置仍由对端自己的 Harness 检查。

吊销验收由宿主调用协调服务 /mesh/v1/devices/<id>/revoke（私有 Bearer 输入）
或宿主的 MeshRuntime.revoke。等待目标收到下次心跳快照后，确认旧会话立即断开、新连接拒绝。
自动集成测试通过手动触发心跳检验此时序，不缩短生产 15 分钟下限。
两台实际设备则各自启动 App，配置可路由网卡、overlay 或公网候选；
各 App 固定同一个公开开发 CA，协调服务依然只有控制面。
