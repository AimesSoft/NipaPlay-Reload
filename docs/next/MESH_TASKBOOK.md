# 凭据保险库 + 最小版 Mesh 任务书

> 工作方式见 `docs/next/TEAM.md`。设计依据：`DESIGN.md` §2.3、§3（NextCore）、§9 第 3 项与第 6 项。调研输入：`research/VAULT_AND_MESH.md`（R6）与 `research/LAN_SECURITY.md`（R1）。

## 目标

1. **凭据保险库**：桌面端的所有秘密进入系统钥匙串；Agent 可读的位置不再出现明文凭据。
2. **最小版 Mesh**：同一账号的设备自动互信；Mac 上的 Agent 能调用工位机 NipaPlay 的 Harness，例如让工位机下载、查看工位机上的任务。
3. **旧局域网 API 收口**：随 Mesh 一起修复 R1 列出的问题（2026-10-10 决定不单独热修）。

### 验收场景

- Mac 上对 Codex 说“让工位机下载这个磁链，下完告诉我”：
  - Agent 先 `mesh.devices`，再 `mesh.invoke {工位机, download.add}`，然后用 `mesh.invoke {工位机, task.wait}` 等到 `succeeded`；
  - 全程不经过 NipaPlay 服务器转发数据。
- 同一账号的第二台设备首次启动并登录后自动出现在设备列表里，无需配对操作；吊销后立刻无法再调用。
- 应用里搜索钥匙串以外的存储位置（偏好设置、`next/` 目录、备份文件、日志），都找不到明文的弹弹play / Bangumi 令牌和 WebDAV / SMB 密码。

---

## 全局契约（主控决定）

### 1. 凭据保险库

```dart
/// 不透明引用：可以持久化、可以出现在日志与备份中，但不含秘密本身。
final class CredentialRef { /* namespace + key；toString 不含秘密 */ }

abstract interface class CredentialVault {
  Future<String?> read(CredentialRef ref);
  Future<void> write(CredentialRef ref, String secret);
  Future<void> delete(CredentialRef ref);
}
```

- 实现：Dart 接口加上 Rust 侧的 `VaultService`，通过现有 FRB 桥调用。
  - 第一期桌面平台：macOS Keychain、Windows Credential Manager、Linux Secret Service（`keyring` 类 crate，允许新增此 Rust 依赖）。
  - 移动、电视与鸿蒙第一期保持现有存储，留出后端接口，另行迁移。
- **迁移规则**：首次启动时读出旧明文、写入保险库、回读核对一致后删除旧明文。迁移失败时保留旧值并记录原因，不得静默丢失凭据。
- 迁移对象以 R6 §1 的盘点为准：弹弹play、Bangumi、WebDAV、SMB、Emby、Jellyfin、剧透 AI 密钥、`next/credentials.json`、插件存储中的秘密等。
- 备份与 WebDAV 同步只写 `CredentialRef`，不写值；恢复到新设备时提示重新登录。
- `journal.jsonl` 与日志不得包含秘密：输入 schema 中标记为秘密的字段，记录前替换为引用。
- **例外**：`next/workspace/.codex/config.toml` 中的本机端点令牌暂时保留。它只授权访问回环 MCP，本来就是给 Agent 用的；M3 改为在 `thread/start` 时注入后，就不再落盘。

### 2. 设备身份与证书

- 每个安装生成一对 Ed25519 密钥，私钥只存在保险库中。`deviceId` 由公钥派生。
- 协调服务充当证书签发者，为 `(accountId, deviceId, 设备公钥, 有效期)` 签发 X.509 设备证书，有效期短（例如 7 天），随心跳续期。
- **签发者的公钥证书内置在 App 中**（开发构建可配置开发用 CA），不在首次连接时才信任服务器给的证书。
- `accountId` 必须是弹弹play 稳定的用户 ID，由协调服务向上游核实，不信任客户端自报。
- **获取方式（2026-10-11 决定）**：弹弹play 开放 API 中，只有登录、注册与 `/login/renew` 返回 `userId`，而 renew 会签发新令牌。协调服务**不得调用 renew**，改为：
  1. 先用只读接口（`/api/v2/playhistory`）验证令牌有效。上游接受即证明令牌真实、未被篡改；
  2. 再解析该 JWT 的 payload，读出稳定的用户标识声明，作为 `accountId`。声明路径可配置。
  - 声明名称在端到端验收时用真实令牌确认：只输出声明名，不输出任何值。
  - 若 JWT 中没有稳定的用户标识，停下来交主控决定备用方案，不得改回调用 renew。

### 3. 协调服务（控制面）

- 独立的 Rust 二进制 `server/nipaplay-mesh-coordinator`，SQLite 存储。
- 令牌验证复用 `server/dandanplay-gateway` 的现有逻辑：抽成共享 crate，不复制粘贴。
- 接口以 R6 §4.1 为基础：
  - 注册设备，返回证书；
  - 列出本账号设备；
  - 上报与获取地址候选；
  - 吊销设备；
  - 证书续期。
- 只处理控制面，**不转发任何媒体或任务流量**。按账号与按 IP 限流；心跳间隔不小于 15 分钟，并加入随机抖动。
- 部署由用户在自己的服务器上完成。仓库提供 systemd 单元与部署说明，格式与 `server/` 下现有服务一致。

### 4. Mesh 传输

- 设备之间使用 TLS 1.3 双向认证：校验证书链到内置签发者，并核对 `accountId` 与自身一致、设备未被吊销、证书在有效期内。
- 在安全通道上承载 MCP JSON-RPC 语义，调用同一个 Harness，`Invocation.origin = 'mesh:<deviceId>'`。
- Mesh 监听是新的 transport，**回环 MCP 端点保持只监听 127.0.0.1，不得改为对外监听**。
- 地址候选的来源：本机网卡、局域网广播线索、用户手动填写的 overlay 或公网地址。直连失败时，可以使用用户自有节点做中继，但中继只转发加密流量。
- 防重放：每次调用带 invocation id、nonce 与 deadline。

### 5. Action

| id | effect | 语义 |
|---|---|---|
| `mesh.devices` | read | 列出本账号设备、在线状态，以及每台设备可调用的 Action 目录（名称、effect、输入输出 schema） |
| `mesh.invoke` | write | `{deviceId, action, input}`。**拒绝调用 effect 为 destructive 的目标 Action**，返回 `invalid_input` 并提示改用下一项 |
| `mesh.invoke_destructive` | destructive | 同上，但只允许调用 destructive 目标。Codex 每次执行前会询问用户 |

- 目标设备按自己的 Harness 规则执行，返回相同的 Outcome envelope；远端返回的 `NeedsDecision` 选项要包装成本机可直接执行的 `mesh.invoke` 调用。
- 第一期远程可调用的范围：`task.*`、`download.*`、`media.library.*`、`playback.*`（播放发生在目标设备上）。

### 6. 旧局域网 API 收口

- 按 R1 §6 的 A 档与 R6 §6 的顺序执行。
- 账号副作用、凭据读取、任意路径读取、通用代理这几类旧接口，在 Mesh 上线后只在安全通道上提供。
- 浏览器 Web UI 的接入方式按 R1 §7.6 设计。在 Web UI 改造完成之前，相关旧接口保留现状，但必须在设置中明确提示风险。

---

## 阶段与并行

| 阶段 | 内容 | 依赖 |
|---|---|---|
| V | 凭据保险库：Dart 接口、Rust 后端、迁移、备份与日志的秘密过滤 | 无 |
| C | 协调服务与共享认证 crate | 无（接口按 §3） |
| M | 客户端 Mesh：设备身份、注册与续期、地址上报与发现、TLS 传输、Harness 接入、`mesh.*` Action | 使用 V 的接口与 C 的 HTTP 契约；三条线可以并行开发，最后集成 |
| L | 旧局域网 API 收口 | 在 M 的安全通道可用之后；A 档中不依赖安全通道的修复可以提前做 |

## 验收

- 各阶段的单元与集成测试。M 阶段要有“同一进程内两个节点经真实 TLS 互相调用”的集成测试，以及吊销、证书过期、账号不一致、重放的拒绝测试。
- 协调服务的测试使用模拟的上游；**不得把真实令牌写进测试或夹具**。
- 端到端验收由主控完成：本机运行协调服务，Mac 与另一台设备（用户的工位机，或第二个隔离数据目录的实例）组网。
