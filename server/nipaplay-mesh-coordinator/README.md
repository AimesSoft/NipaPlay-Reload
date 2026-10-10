# NipaPlay Mesh Coordinator

Mesh 的控制面服务：验证弹弹play 账号、登记设备公钥、签发短有效期设备证书、维护设备与
地址候选、处理吊销。**只做控制面，不转发任何媒体或任务流量**（`DESIGN.md` §9 第 6 项）。

- 独立 Rust 二进制，SQLite 存储；令牌验证与限流复用共享 crate `server/nipaplay-auth`。
- 账号身份（`accountId`）由服务向上游核实，取弹弹play 稳定的数字 `userId`，**不信任客户端自报**。
- 设备证书为 X.509（Ed25519 签名），有效期短（默认 7 天），随续期接口轮换。
- 按账号与按 IP 限流；心跳间隔不小于 15 分钟。

## 运行

```bash
# 1) 生成开发用 CA（生产请用同一命令生成后妥善保管私钥）
mkdir -p /tmp/mesh
cargo run --manifest-path server/nipaplay-mesh-coordinator/Cargo.toml -- \
  --generate-dev-ca /tmp/mesh/ca.crt.pem /tmp/mesh/ca.key.pem

# 2) 启动服务
MESH_CA_CERT_FILE=/tmp/mesh/ca.crt.pem \
MESH_CA_KEY_FILE=/tmp/mesh/ca.key.pem \
MESH_DATABASE_PATH=/tmp/mesh/mesh.db \
DANDANPLAY_APP_SECRET=... \
cargo run --manifest-path server/nipaplay-mesh-coordinator/Cargo.toml
```

`--generate-dev-ca` 以排他创建写入新文件，私钥从创建时即为 `0600`。Unix 上加载私钥时拒绝
组或其他用户可访问的文件；仅接受普通文件。签发者必须是当前有效、具有 `keyCertSign`
的自签名 Ed25519 CA，密钥必须与证书匹配，否则启动失败。生产部署模板见 `deploy/`。

## 配置

| 环境变量 | 默认 | 说明 |
|---|---|---|
| `MESH_LISTEN_ADDR` | `127.0.0.1:18082` | 监听地址。只监听回环，由 nginx 反代 |
| `MESH_DATABASE_PATH` | `nipaplay-mesh.db` | SQLite 文件路径 |
| `MESH_CA_CERT_FILE` | 必填 | 签发者证书（PEM） |
| `MESH_CA_KEY_FILE` | 必填 | 签发者私钥（PEM，Ed25519 PKCS#8） |
| `MESH_CERT_VALIDITY_SECONDS` | `604800` | 夹到 900–604800 秒，叶子证书到期不晚于 CA |
| `MESH_HEARTBEAT_INTERVAL_SECONDS` | `900` | 下发给客户端的心跳间隔，最小 900 秒 |
| `MESH_ADDRESS_DEFAULT_TTL_SECONDS` | `3600` | 地址候选未指定有效期时的默认值 |
| `MESH_ADDRESS_MAX_TTL_SECONDS` | `7200` | 夹到 60–7200 秒；默认 TTL 同样夹到范围内 |
| `MESH_REGISTER_PER_HOUR` | `10` | 每账号每小时注册次数 |
| `MESH_RENEW_PER_HOUR` | `24` | 每账号每小时续期次数 |
| `MESH_ADDRESSES_PER_HOUR` | `60` | 每账号每小时地址请求次数 |
| `MESH_DEVICES_PER_HOUR` | `120` | 每账号每小时设备/吊销请求次数 |
| `MESH_IP_REQUESTS_PER_MINUTE` | `300` | 每 IP 每分钟请求上限，包括匿名、无效输入和公开接口 |
| `MESH_TRUST_PROXY_HEADERS` | `true` | 仅当 socket 对端为回环代理时信任 `X-Real-IP` / `X-Forwarded-For` |
| `DANDANPLAY_UPSTREAM_BASE` | `https://api.dandanplay.net` | 上游 API |
| `DANDANPLAY_APP_ID` | `nipaplayv1` | 应用 ID |
| `MESH_ACCOUNT_CLAIM_POINTER` | `/userId` | 已验证 JWT 中稳定用户标识的 JSON Pointer；默认声明名尚待真实令牌验收确认 |
| `DANDANPLAY_APP_SECRET` / `DANDANPLAY_APP_SECRET_URLS` | 见网关 | 应用密钥，复用网关的加载逻辑 |

## 认证

所有 `/mesh/v1/*` 接口（`server-info` 除外）都要求：

```
Authorization: Bearer <弹弹play token>
```

服务先用只读的 `/api/v2/playhistory` 验证令牌（有效缓存 10 分钟，无效 30 秒），
上游接受后才解析该 JWT 的 payload，按 `MESH_ACCOUNT_CLAIM_POINTER` 提取稳定用户标识。
接受正整数或 1–128 字节的字母、数字、`-._` 标识字符串；不使用用户名。
协调服务不会调用上游 renew。令牌无效返回 `401`；上游不可达返回 `503`；
JWT 无法解析、声明缺失或类型不符返回 `422 invalid_identity`。客户端自报账号字段被忽略。

正式端到端验收先确认真实 JWT 的声明名。启动配置相同，运行
`nipaplay-mesh-coordinator --inspect-account-claim-names`，从 stdin 提供令牌。
它先请求只读验证接口，再输出声明名的 JSON Pointer 数组，绝不输出声明值或令牌。
不要把令牌放进命令行、仓库或 shell 历史；从私有宿主流程或关闭回显的终端输入。
若没有稳定用户 ID 声明，停止验收并交主控裁定；不得恢复 renew。

IP 限流在解析请求体前执行；令牌限流在上游验证前执行。已解析过的账号也在再次验证前
检查账号额度；新令牌必须先核实身份才能归入账号桶，同账号的不同令牌共用账号额度。
身份缓存有效 10 分钟、拒绝结果 30 秒。令牌最长 4096 字节，不接受空白或控制字符。
HTTP JSON 请求体最多 32 KiB；畸形 JSON 返回 `400 invalid_input`，超限返回 `413 invalid_input`。
所有内部或上游失败仅返回固定错误信息，不返回路径、SQL 或上游响应正文。

## 接口契约

错误响应统一为：

```json
{ "success": false, "error": "invalid_input", "errorCode": 400, "errorMessage": "..." }
```

| `error` | HTTP | 含义 |
|---|---|---|
| `missing_token` | 401 | 缺少 `Authorization: Bearer` |
| `invalid_token` | 401 | 令牌无效或过期 |
| `invalid_identity` | 422 | 已验证 JWT 无法解析、缺少配置声明或声明类型错误 |
| `upstream_unavailable` | 503 | 无法访问上游核实身份，可重试 |
| `invalid_input` | 400 | 请求体或参数不合法 |
| `device_not_found` | 404 | 设备不存在或不属于本账号 |
| `device_conflict` | 403 | 设备 id 已属于其他账号 |
| `device_revoked` | 403 | 设备已被吊销 |
| `rate_limited` | 429 | 触发按账号或按 IP 限流 |
| `internal_error` | 500 | 服务内部错误 |

### `GET /healthz`

```json
{ "ok": true, "service": "nipaplay-mesh-coordinator" }
```

### `GET /mesh/v1/server-info`

无需认证，用于读取服务参数和核对签发者。App 必须预置签发者证书；开发构建可以显式
配置开发 CA。该响应不能用作首次连接时自动建立信任的依据。

```json
{
  "success": true,
  "serverPublicKey": "<base64url(签发者 Ed25519 原始公钥 32 字节)>",
  "serverCertificate": "-----BEGIN CERTIFICATE-----\n...",
  "heartbeatIntervalSeconds": 900,
  "certificateValiditySeconds": 604800,
  "addressMaxTtlSeconds": 7200
}
```

该接口无需认证，因此**不返回吊销版本**：`revocation_epoch` 是按账号计的，只出现在需要
认证的接口响应里。

### `POST /mesh/v1/devices/register`

```json
{
  "device_public_key": "<base64url(32 字节 Ed25519 公钥)>",
  "device_name": "工位机",
  "platform": "macos",
  "app_version": "1.0.0",
  "proof": { "timestamp": 1760000000, "nonce": "<至少 22 字符 base64url>", "signature": "<base64url Ed25519 签名>" }
}
```

字段先去掉首尾空白，再检查：`device_name` 1–128 字符，`platform`、`app_version` 均为
1–32 字节，不接受控制字符。
`deviceId` 由服务从公钥派生：`base64url(SHA-256(公钥))`。
已吊销公钥不能再次注册；要重新加入需生成新的设备密钥。同一公钥不能转移到其他账号。

持钥证明使用设备私钥签名以下无空白 UTF-8 JSON 字符串数组（签名覆盖未 trim 的请求值）：
`["nipaplay-mesh-possession-v1", timestamp的十进制字符串, nonce, "register", device_public_key, device_name, platform, app_version]`。
timestamp 与服务器时间差不得超过 300 秒。nonce 为 22–128 字符 base64url；
同一公钥的 nonce 在 SQLite 事务中一次性消费，并保留 600 秒。缺失、错误、过期、重放证明均不签发证书。

响应：

```json
{
  "success": true,
  "account_id": "424242",
  "device_id": "<base64url(SHA-256(公钥))>",
  "certificate": { "pem": "-----BEGIN CERTIFICATE-----...", "not_before": 1760000000, "not_after": 1760604800 },
  "server_public_key": "<base64url(签发者公钥)>",
  "revocation_epoch": 0,
  "heartbeat_interval_seconds": 900
}
```

### `POST /mesh/v1/devices/renew`

```json
{ "device_id": "<device_id>", "device_public_key": "<base64url(公钥)>",
  "proof": { "timestamp": 1760000000, "nonce": "<base64url>", "signature": "<base64url>" } }
```

公钥必须与注册时一致；已吊销设备返回 `device_revoked`。响应与 `register` 的
`certificate`/`revocation_epoch` 字段一致。
续期签名数组为 `["nipaplay-mesh-possession-v1", timestamp字符串, nonce, "renew", device_public_key, device_id]`。

### `GET /mesh/v1/devices`

```json
{
  "success": true,
  "account_id": "424242",
  "revocation_epoch": 0,
  "devices": [
    { "device_id": "...", "device_name": "工位机", "platform": "macos",
      "created_at": 1760000000, "last_seen_at": 1760000500, "revoked": false }
  ]
}
```

### `POST /mesh/v1/devices/{device_id}/revoke`

```json
{ "device_id": "<device_id>" }
```

路径和 JSON 中的 `device_id` 必须相同。响应 `{ "success": true, "revocation_epoch": <n> }`。
`revocation_epoch` **按账号独立计数**，只在成功吊销后递增（重复吊销同一设备也会 +1）。
吊销会在同一事务里删除该设备的全部地址候选；注册、续期和地址写入在事务内再次检查
归属与吊销状态。设备列表与吊销计数从同一个数据库快照返回。

### `POST /mesh/v1/addresses`

```json
{
  "device_id": "<device_id>",
  "candidates": [
    { "kind": "lan", "host": "192.168.1.20", "port": 1180, "priority": 10, "expires_in": 600 }
  ]
}
```

- `kind` ∈ `lan` / `public` / `overlay` / `relay` / `manual`；每设备最多 32 条；
- `host` 只接受 IPv4、IPv6 或 ASCII DNS 主机名（≤255 字节），不接受 URL、端口或路径；
- `port` 为 1–65535；重复的 `(kind, host, port)` 返回 `400`，保留已有候选；
- 每次上报**替换**该设备全部候选；`expires_in` 会被夹到 `[60, 2 小时]`（服务端硬上限，配置再大也不超过）；
- 响应 `{ "success": true, "accepted": <n>, "revocation_epoch": <本账号计数>, "heartbeat_interval_seconds": 900 }`。
  客户端在每次心跳同步计数；变化时立即拉取设备快照、关闭已吊销设备的 TLS 会话并拒绝其新连接。

### `GET /mesh/v1/addresses?device_id=<id>`

```json
{
  "success": true,
  "device_id": "...",
  "candidates": [
    { "kind": "lan", "host": "192.168.1.20", "port": 1180,
      "priority": 10, "expires_at": 1760000600, "updated_at": 1760000000 }
  ]
}
```

只返回未过期候选，按 `priority` 降序。

## 设备证书字段

签发给设备的叶子证书：

| 字段 | 值 |
|---|---|
| Subject CN | `device-<device_id>` |
| Subject O | `NipaPlay Mesh` |
| Issuer | 部署时配置的 CA 证书 |
| 签名算法 | Ed25519（`1.3.101.112`） |
| `basicConstraints` | `CA:FALSE`（critical） |
| `keyUsage` | `digitalSignature`（critical） |
| `extendedKeyUsage` | `clientAuth`、`serverAuth` |
| `subjectAltName` | 身份 URI `nipaplay-mesh://device?account=<accountId>&device=<deviceId>`；DNS `d-<SHA256公钥摘要十六进制前32字符>.<后32字符>.mesh.nipaplay.invalid` 供标准 TLS 验证器核对目标设备（不解析 DNS） |
| `authorityKeyIdentifier` | 由 CA 公钥派生 |
| 私有扩展 `1.3.6.1.4.1.61086.1.1` | DER `UTF8String`，内容为 `{"v":1,"accountId":...,"deviceId":...,"publicKey":...}`。**该 OID 使用的 PEN 归属尚未核实，正式发布前由主控确定合法的 OID。阶段 M 使用标准 SAN 验证身份，不依赖这个私有 OID。** |
| 有效期 | `not_before = 签发时刻 - 5 分钟`，`not_after = 签发时刻 + MESH_CERT_VALIDITY_SECONDS`，两端均限制在 CA 有效期内 |

客户端以 **App 内置的签发者证书**为信任根，校验链、`accountId` 与自身一致、公钥与
`deviceId` 匹配、设备未吊销且证书在有效期内。`revocation_epoch` 是本账号吊销列表的
版本号，不是某张证书的吊销证明；版本变化后须重新获取列表并更新本地拒绝集合，终止
对应设备的既有会话。仅比较数字不能实现吊销检查。

服务器立即阻止被吊销设备注册、续期和上报，并删除地址。已有直连会话何时停止取决于
客户端获知吊销的机制；本服务没有推送通道。心跳至少间隔 15 分钟，客户端必须加入随机
抖动。离线使用与“所有对端立即获知吊销”的取舍由主控确定，不能声称本服务单独实现
了全网即时吊销。

## 存储

SQLite（WAL）单文件：

- `devices(device_id, account_id, public_key, name, platform, app_version, created_at, last_seen_at, revoked_at)`
- `addresses(device_id, kind, host, port, priority, expires_at, updated_at)`
- `certificates(device_id, issued_at, expires_at)`
- `accounts(account_id, revocation_epoch)` —— 每个账号一行，保存该账号自己的吊销版本
- `possession_proofs(public_key, nonce, seen_at)` —— 注册/续期持钥证明防重放

吊销设备时在同一个事务里删除它的地址候选。过期的地址候选每小时清理一次。

## 隐私

当前最小版把地址候选**明文**存在 SQLite 里（`kind`/`host`/`port`/`priority`）。这些是用户
自报的可达地址，可能包含公网 IP 或 overlay 地址。缓解措施：

- 有效期短：服务端硬上限 **2 小时**，过期即从查询结果消失，并由后台每小时清理；
- 设备吊销时**立即删除**它的全部地址候选；
- 持有同一账号有效令牌的调用者能读取（接口按账号校验；HTTP API 未要求设备私钥证明）。

**后续计划**：地址候选改为按**接收设备的公钥做端到端加密**，协调服务只存不透明密文，
既看不到内容也无需理解其结构。最小版先按明文实现。

## 部署

```bash
sudo useradd --system --home /var/lib/nipaplay-mesh-coordinator nipaplay-mesh
sudo install -d -o nipaplay-mesh -g nipaplay-mesh /var/lib/nipaplay-mesh-coordinator
sudo install -d -o root -g nipaplay-mesh -m 750 /etc/nipaplay-mesh-coordinator
sudo install -d -o root -g root -m 755 /opt/nipaplay-mesh-coordinator

cargo build --release --manifest-path server/nipaplay-mesh-coordinator/Cargo.toml
sudo install -m 755 server/nipaplay-mesh-coordinator/target/release/nipaplay-mesh-coordinator \
  /opt/nipaplay-mesh-coordinator/

# 生成到当前用户可写的暂存目录，然后安装到服务目录（只生成一次）
mesh_ca_stage=$(mktemp -d)
server/nipaplay-mesh-coordinator/target/release/nipaplay-mesh-coordinator \
  --generate-dev-ca "$mesh_ca_stage/ca.crt.pem" "$mesh_ca_stage/ca.key.pem"
sudo install -o root -g root -m 644 "$mesh_ca_stage/ca.crt.pem" /opt/nipaplay-mesh-coordinator/ca.crt.pem
sudo install -o nipaplay-mesh -g nipaplay-mesh -m 600 "$mesh_ca_stage/ca.key.pem" /etc/nipaplay-mesh-coordinator/ca.key.pem
rm "$mesh_ca_stage/ca.crt.pem" "$mesh_ca_stage/ca.key.pem"
rmdir "$mesh_ca_stage"

sudo install -o root -g root -m 644 server/nipaplay-mesh-coordinator/deploy/nipaplay-mesh-coordinator.service /etc/systemd/system/
sudo install -o root -g nipaplay-mesh -m 640 server/nipaplay-mesh-coordinator/deploy/nipaplay-mesh-coordinator.env.example \
  /etc/nipaplay-mesh-coordinator.env
# 编辑 /etc/nipaplay-mesh-coordinator.env 填入密钥
sudo systemctl daemon-reload && sudo systemctl enable --now nipaplay-mesh-coordinator
```

nginx 站点里加入 `deploy/nginx-location.conf`。自检：

```bash
curl -s http://127.0.0.1:18082/healthz
curl -s http://127.0.0.1:18082/mesh/v1/server-info
```

## 测试

```bash
cargo test --manifest-path server/nipaplay-mesh-coordinator/Cargo.toml
```

测试使用模拟上游，不访问线上服务，夹具中不含任何真实令牌。
覆盖签名与证书字段、上游身份类型、跨账号拒绝、吊销后重新注册、并发写入与吊销、SQL
参数化和事务回滚、上游调用次数、输入大小/格式与错误脱敏。手工导出测试被默认忽略，
证书结构与验签由正常运行的自动化测试覆盖。

需要人工检查证书结构时，可运行被忽略的导出测试（写入同一轮的 CA 与叶子证书）：

```bash
NIPAPLAY_MESH_DUMP_DIR=/tmp/mesh-dump \
  cargo test --manifest-path server/nipaplay-mesh-coordinator/Cargo.toml \
  -- --ignored dump_certificates
openssl verify -CAfile /tmp/mesh-dump/ca.pem /tmp/mesh-dump/leaf.pem
```
