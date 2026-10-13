# 阶段 M：客户端 Mesh

NextCore 创建 MeshRuntime、三个 Mesh Action 和 mesh.addressCandidates 设置项，
并管理 transport 生命周期。NextRuntime 将包含播放能力和 journal 的同一个 Harness
交回 Core；回环 MCP 和 Mesh 复用 nipa_harness/mcp.dart 的 JSON-RPC 分派器。
Mesh 不依赖 Labs 端点开关。可远程调用范围为 task.*、download.*、
media.*、danmaku.*、playback.*、state.query 和 agent.wake。

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
上限 1 MiB。initialize、ping、tools/list、tools/call 与回环 MCP 使用相同分派逻辑。
Mesh 帧增加 mesh: {invocationId, nonce, deadline}；deadline 使用 Unix 毫秒，必须在
当前时间到 1 小时内。ID/nonce 均至少 22 个 base64url 字符。按来源设备分别去重，
先持久化无秘密的去重记录，再进入 Harness；重启不会重置仍有效的窗口。
没有 TLS 0-RTT。并发会话/待分派队列均有上限。

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

例如输出包含 `{"pointer":"/userId","type":"number"}`，且主控确认它是稳定用户 ID，
则设置 `export MESH_ACCOUNT_CLAIM_POINTER=/userId`；嵌套声明 `/identity/uid` 可直接设置
为 `export MESH_ACCOUNT_CLAIM_POINTER=/identity/uid`。Pointer 中名称的 `~` 与 `/` 分别
转义为 `~0` 与 `~1`，直接复制诊断的 pointer 即可。协调服务接受正整数或 1–128 字节的
字母、数字、`-._` 标识字符串；字段名称和类型只能帮助找候选，不能证明其稳定性。
默认 `/userId` 尚未用真实令牌确认。若不存在稳定 ID，停止并交主控裁定。
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
