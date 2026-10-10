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
cargo run --manifest-path server/nipaplay-mesh-coordinator/Cargo.toml -- \
  --generate-dev-ca /tmp/mesh/ca.crt.pem /tmp/mesh/ca.key.pem

# 2) 启动服务
MESH_CA_CERT_FILE=/tmp/mesh/ca.crt.pem \
MESH_CA_KEY_FILE=/tmp/mesh/ca.key.pem \
MESH_DATABASE_PATH=/tmp/mesh/mesh.db \
DANDANPLAY_APP_SECRET=... \
cargo run --manifest-path server/nipaplay-mesh-coordinator/Cargo.toml
```

`--generate-dev-ca` 只在文件不存在时写入，私钥以 `0600` 落盘。签发者密钥必须与证书匹配，
否则服务在启动时报错退出。生产部署模板见 `deploy/`。

## 配置

| 环境变量 | 默认 | 说明 |
|---|---|---|
| `MESH_LISTEN_ADDR` | `127.0.0.1:18082` | 监听地址。只监听回环，由 nginx 反代 |
| `MESH_DATABASE_PATH` | `nipaplay-mesh.db` | SQLite 文件路径 |
| `MESH_CA_CERT_FILE` | 必填 | 签发者证书（PEM） |
| `MESH_CA_KEY_FILE` | 必填 | 签发者私钥（PEM，Ed25519 PKCS#8） |
| `MESH_CERT_VALIDITY_SECONDS` | `604800` | 设备证书有效期 |
| `MESH_HEARTBEAT_INTERVAL_SECONDS` | `900` | 下发给客户端的心跳间隔，最小 900 秒 |
| `MESH_ADDRESS_DEFAULT_TTL_SECONDS` | `3600` | 地址候选未指定有效期时的默认值 |
| `MESH_ADDRESS_MAX_TTL_SECONDS` | `7200` | 地址候选有效期上限，服务端强制不超过 2 小时 |
| `MESH_REGISTER_PER_HOUR` | `10` | 每账号每小时注册次数 |
| `MESH_RENEW_PER_HOUR` | `24` | 每账号每小时续期次数 |
| `MESH_ADDRESSES_PER_HOUR` | `60` | 每账号每小时地址请求次数 |
| `MESH_DEVICES_PER_HOUR` | `120` | 每账号每小时设备/吊销请求次数 |
| `MESH_IP_REQUESTS_PER_MINUTE` | `300` | 每 IP 每分钟请求上限（所有接口共用） |
| `MESH_TRUST_PROXY_HEADERS` | `true` | 是否信任 `X-Real-IP` / `X-Forwarded-For` |
| `DANDANPLAY_UPSTREAM_BASE` | `https://api.dandanplay.net` | 上游 API |
| `DANDANPLAY_APP_ID` | `nipaplayv1` | 应用 ID |
| `DANDANPLAY_APP_SECRET` / `DANDANPLAY_APP_SECRET_URLS` | 见网关 | 应用密钥，复用网关的加载逻辑 |

## 认证

所有 `/mesh/v1/*` 接口（`server-info` 除外）都要求：

```
Authorization: Bearer <弹弹play token>
```

服务先用只读的 `/api/v2/playhistory` 验证令牌（有效缓存 10 分钟，无效 30 秒），再调用
`/api/v2/login/renew` 取稳定的数字 `userId` 作为 `accountId`。令牌无效返回 `401`；
上游不可达返回 `503`。请求体中的任何账号字段都被忽略。

## 接口契约

错误响应统一为：

```json
{ "success": false, "error": "invalid_input", "errorCode": 400, "errorMessage": "..." }
```

| `error` | HTTP | 含义 |
|---|---|---|
| `missing_token` | 401 | 缺少 `Authorization: Bearer` |
| `invalid_token` | 401 | 令牌无效或过期 |
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

无需认证，用于客户端内置或首次拉取签发者公钥。

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
  "app_version": "1.0.0"
}
```

`device_name` 1–128 字符，`platform` ≤ 32，`app_version` ≤ 32。
`deviceId` 由服务从公钥派生：`base64url(SHA-256(公钥))`。

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
{ "device_id": "<device_id>", "device_public_key": "<base64url(公钥)>" }
```

公钥必须与注册时一致；已吊销设备返回 `device_revoked`。响应与 `register` 的
`certificate`/`revocation_epoch` 字段一致。

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

响应 `{ "success": true, "revocation_epoch": <n> }`。`revocation_epoch` **按账号独立计数**，只在成功吊销后递增（重复吊销同一设备也会 +1）。吊销会在同一事务里删除该设备的全部地址候选。

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
- 每次上报**替换**该设备全部候选；`expires_in` 会被夹到 `[60, 2 小时]`（服务端硬上限，配置再大也不超过）；
- 响应 `{ "success": true, "accepted": <n> }`。

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
| `subjectAltName` | `URI:nipaplay-mesh://device?account=<accountId>&device=<deviceId>` |
| `authorityKeyIdentifier` | 由 CA 公钥派生 |
| 私有扩展 `1.3.6.1.4.1.61086.1.1` | DER `UTF8String`，内容为 `{"v":1,"accountId":...,"deviceId":...,"publicKey":...}`。**该 OID 为未注册私有弧，正式发布前替换为已注册的 PEN；客户端只依赖文档字段，不硬编码该 OID。** |
| 有效期 | `not_before = 签发时刻 - 5 分钟`，`not_after = 签发时刻 + MESH_CERT_VALIDITY_SECONDS` |

客户端应把内置或首次拉取的签发者公钥（`serverPublicKey`）作为信任根，校验链、`accountId`
与自身一致、设备未吊销且证书在有效期内。吊销以**本账号的** `revocation_epoch` 为准，客户端
本地持久化并在会话建立时比较；不同账号的计数互不影响，也不会泄露平台整体的吊销次数。

## 存储

SQLite（WAL）单文件，四张表：

- `devices(device_id, account_id, public_key, name, platform, app_version, created_at, last_seen_at, revoked_at)`
- `addresses(device_id, kind, host, port, priority, expires_at, updated_at)`
- `certificates(device_id, issued_at, expires_at)`
- `accounts(account_id, revocation_epoch)` —— 每个账号一行，保存该账号自己的吊销版本

吊销设备时在同一个事务里删除它的地址候选。过期的地址候选每小时清理一次。

## 隐私

当前最小版把地址候选**明文**存在 SQLite 里（`kind`/`host`/`port`/`priority`）。这些是用户
自报的可达地址，可能包含公网 IP 或 overlay 地址。缓解措施：

- 有效期短：服务端硬上限 **2 小时**，过期即从查询结果消失，并由后台每小时清理；
- 设备吊销时**立即删除**它的全部地址候选；
- 只有同一账号的已认证设备能读取（接口按账号校验）。

**后续计划**：地址候选改为按**接收设备的公钥做端到端加密**，协调服务只存不透明密文，
既看不到内容也无需理解其结构。最小版先按明文实现。

## 部署

```bash
sudo useradd --system --home /var/lib/nipaplay-mesh-coordinator nipaplay-mesh
sudo install -d -o nipaplay-mesh -g nipaplay-mesh /var/lib/nipaplay-mesh-coordinator
sudo install -d -o root -g nipaplay-mesh -m 750 /etc/nipaplay-mesh-coordinator

cargo build --release --manifest-path server/nipaplay-mesh-coordinator/Cargo.toml
sudo install -m 755 server/nipaplay-mesh-coordinator/target/release/nipaplay-mesh-coordinator \
  /opt/nipaplay-mesh-coordinator/

# 生成并安装 CA（只生成一次；私钥 0600，仅 nipaplay-mesh 可读）
sudo -u nipaplay-mesh /opt/nipaplay-mesh-coordinator/nipaplay-mesh-coordinator \
  --generate-dev-ca /opt/nipaplay-mesh-coordinator/ca.crt.pem /etc/nipaplay-mesh-coordinator/ca.key.pem

sudo install -o root -g root -m 644 deploy/nipaplay-mesh-coordinator.service /etc/systemd/system/
sudo install -o root -g nipaplay-mesh -m 640 deploy/nipaplay-mesh-coordinator.env.example \
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

需要人工检查证书结构时，可运行被忽略的导出测试（写入同一轮的 CA 与叶子证书）：

```bash
NIPAPLAY_MESH_DUMP_DIR=/tmp/mesh-dump \
  cargo test --manifest-path server/nipaplay-mesh-coordinator/Cargo.toml \
  -- --ignored dump_certificates
openssl verify -CAfile /tmp/mesh-dump/ca.pem /tmp/mesh-dump/leaf.pem
```
