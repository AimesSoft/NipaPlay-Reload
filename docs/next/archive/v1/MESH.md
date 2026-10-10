# 阶段 M 实现报告

## 1. 完成了什么

NextCore 接入客户端 Mesh：保险库 Ed25519 身份、公钥派生 deviceId、注册/续期/地址上报/
设备列表/吊销、网卡与 UDP 广播线索、手填 overlay/公网地址、TLS 1.3 双向认证、
共享 Harness JSON-RPC、mesh.devices / mesh.invoke / mesh.invoke_destructive、
远端 NeedsDecision 选项路由与持久化防重放。

协调服务先通过只读 playhistory 验证令牌，再读取可配置 JSON Pointer 的 JWT 声明；
已移除全部上游 renew 调用。解析/缺少声明返回明确的 invalid_identity。
新增 --inspect-account-claim-names，只输出声明名称，且在输出前执行只读令牌验证。
注册与设备证书续期要求 Ed25519 持钥证明，并在 SQLite 中原子消费 nonce。
地址心跳返回本账号吊销计数；客户端同步快照后立即关闭已吊销设备的会话并拒绝新连接。

6 项真实 TLS 集成测试覆盖同进程双向 Harness 调用、effect 与 Decision 包装、
invocation id/nonce/deadline/重启防重放、心跳吊销活跃会话、新连接拒绝、
账号不一致、证书过期和非法签发链。协调服务上游始终为本机模拟，没有真实令牌。

[客户端协议、配置和主控端到端步骤](../../lib/next/mesh/README.md)；
[协调服务 HTTP 契约](../../server/nipaplay-mesh-coordinator/README.md)。
未提交 commit、未 push、未部署，未运行 pub get，未访问线上弹弹play。

## 2. 决策

- TLS 与密钥操作放在 Rust：通过 rustls 的协议版本列表强制 TLS 1.3；
  使用标准链、用途、DNS SAN 验证，再核对身份 URI、原始公钥摘要、账号和设备快照。
  不以 onBadCertificate 或首次下载公钥建立信任。正式私有 OID 不参与客户端身份验证。
  DNS SAN 将公钥摘要的十六进制拆为合法标签，避免 base64url ID 以连字符开头时被 DNS 验证器拒绝。
- MCP 传输共用 McpRpc 分派器。Mesh 限定任务书的 Action 范围，发送端和接收端都校验 effect。
  每个 Decision 选项按其自身 effect 包装，破坏性选项使用 mesh.invoke_destructive。
  mesh.devices 使用元数据中的原始 Action 输出 schema；MCP 的标准输出仍描述 Outcome envelope。
- 注册签名使用带时间戳的请求，窗口 300 秒，覆盖 nonce、操作和原始字段；
  续期也要求持钥证明，避免出现无需持钥的续签路径。nonce 在数据库保留 600 秒。
- 防重放窗口最长 1 小时，按来源设备分别去重；只持久化 ID、nonce、deadline，
  在运行 Harness 前写盘。证书到期与吊销变化会中断仍在等待结果的 TLS 会话。
  不自动重试结果未知的 tools/call，避免重复副作用。
- 心跳至少 900 秒并加入抖动；设备快照同时发现新增设备并同步吊销。
  地址上报被拒绝时也拉取快照，让被吊销节点在自身心跳时关闭监听和已有会话。
  登录凭据变化只在本地检查，失败加入重试不短于 15 分钟。广播只提供不可信地址线索。
  成功的直连地址保留在内存中，后续 RPC 不重复查询协调服务；地址失效时重新获取候选。
- 保持既有 TaskEngine ownerDeviceId，避免旧任务变成外来任务而停止恢复；
  Mesh deviceId、证书及 origin 独立使用公钥摘要。未迁移已持久化的任务与媒体定位归属。
- 新安装数据目录区分保险库条目。仅 Debug 支持 NIPAPLAY_DATA_DIR、
  NIPAPLAY_AGENT_PORT 与开发 CA 配置；单实例锁也按 Debug 数据目录隔离。
  现有账号钥匙串和系统 SharedPreferences 仍属于同一个 App，不复制秘密。
  回环 MCP 继续只绑定 127.0.0.1。
- macOS build 自动刷新了与本阶段无关的 Erika Podfile.lock 两行，构建后恢复原值；
  未纳入无关依赖升级。
- Cargokit 只对宿主 src 和顶层 Cargo 文件计算缓存摘要，不跟踪本地 path 依赖源码。
  因而独立 Mesh crate 的 lib 指向 rust/src/mesh_transport.rs，源码只有一份，
  同时进入应用构建缓存摘要；不改动第三方构建工具。包内原生库另外运行真实 TLS 集成验证。

没有新增 Dart 依赖。新增 Rust 直接依赖逐项如下；已有间接依赖也列出其直接使用理由：

| 依赖 | 使用处 | 理由 |
|---|---|---|
| 本地 nipaplay-mesh | Rust 宿主 | 隔离 TLS/身份实现，FRB API 与可独立验证的传输内核共用 |
| ring 0.17 | Mesh 内核 | 成熟维护中的 Ed25519 生成、签名、安全随机数；不手写密码学 |
| rustls 0.23 | Mesh 内核 | 成熟维护中的 TLS/WebPKI；强制 TLS 1.3，校验证书链和双向身份 |
| tokio-rustls 0.26 | Mesh 内核 | 将 rustls 与现有 Tokio 网络模型连接，提供真实异步 TLS socket |
| rustls-pemfile 2 | Mesh 内核 | 使用标准库实现解析 PEM，避免自制 PEM 解码器 |
| x509-parser 0.18 | Mesh 内核 | 解析已通过标准链验证的证书 SAN、公钥、有效期，完成账号/设备绑定 |
| sha2 0.10 | Mesh 内核 | 标准 SHA-256 公钥派生设备 ID |
| base64 0.22 | Mesh 内核 | 标准 base64url 身份、公钥及签名编码 |
| tokio 1 | Mesh 内核 | 复用宿主异步生态；监听、分帧、队列、取消、时间限制与并发上限 |
| rcgen 0.14，仅 dev | 离线证书例程 | 生成受控的过期/其他签发者叶子证书，用于真实 TLS 拒绝测试 |
| time 0.3，仅 dev | 离线证书例程 | 精确控制证书测试的有效期 |
| serde_json 1，仅 dev | 离线证书例程 | 测试进程通过 stdin 传入公开签发参数，stdout 只返回公开证书 |

## 3. 验收命令与真实输出

Flutter/Dart 使用 ~/development/flutter-3.44.6/bin。
所有下列必需命令退出 0：

| 命令 | 输出摘录 |
|---|---|
| cd packages/nipa_harness && ~/development/flutter-3.44.6/bin/dart test | +86: All tests passed! |
| ~/development/flutter-3.44.6/bin/flutter analyze --no-pub lib/next test/next | No issues found! |
| ~/development/flutter-3.44.6/bin/flutter test --no-pub test/next | +277: All tests passed! |
| cargo fmt --manifest-path server/nipaplay-mesh-coordinator/Cargo.toml --check | 无输出，退出 0 |
| cargo clippy --manifest-path server/nipaplay-mesh-coordinator/Cargo.toml --all-targets -- -D warnings | Finished dev profile，退出 0 |
| cargo test --manifest-path server/nipaplay-mesh-coordinator/Cargo.toml | 42 passed; 0 failed; 1 ignored |
| ~/development/flutter-3.44.6/bin/flutter build macos --debug --no-pub | ✓ Built build/macos/Build/Products/Debug/NipaPlay.app |

ignored 为原有手工证书导出测试。构建有既有插件、编译器与 script phase 警告，不影响退出状态。
最终整套 Flutter 测试设置 NIPAPLAY_MESH_TEST_LIBRARY 为包内 Rust framework 的绝对路径，
因此这 277 项同时覆盖了实际应用构建中的原生库。

额外检查：

- 使用最终 macOS App 包内原生 framework 的真实 TLS 集成：6 passed，拒绝日志包含 device revoked、account mismatch、
  certificate expired、invalid peer certificate: BadSignature。
  命令为 NIPAPLAY_MESH_TEST_LIBRARY="$PWD/build/macos/Build/Products/Debug/NipaPlay.app/Contents/Frameworks/rust_lib_nipaplay.framework/rust_lib_nipaplay"
  ~/development/flutter-3.44.6/bin/flutter test --no-pub test/next/mesh_integration_test.dart。
  首次附加测试因 flutter_tester 没有应用框架搜索路径而无法加载；夹具显式加载包内
  FlutterMacOS framework 后通过。应用包和源代码均无需修改框架路径。
- cargo test --manifest-path server/nipaplay-auth/Cargo.toml：9 passed; 0 failed；Doc-tests 0 failed。
- Mesh 内核 cargo fmt --check、cargo clippy --all-targets -- -D warnings：退出 0。
- cargo test --manifest-path rust/mesh/Cargo.toml：1 passed; 0 failed，覆盖设备 ID 的全部首字节取值。
- 新增单实例隔离与存储路径文件的 Flutter analyze：No issues found!
- git diff --check：无输出，退出 0。

完整运行日志保留在 /tmp/nipaplay-mesh-{harness-tests,flutter-tests,coordinator-tests,
auth-tests,native-tests,bundle-tls-tests,macos-build}.log。

## 4. 问题：主控事项

1. /userId 只是可配置默认值，真实 JWT 的稳定声明名仍由主控使用只输出名称的调试路径确认。
   若真实令牌没有稳定用户 ID，停止端到端验收；不改回 renew。
2. 正式 CA、轮换与旧证书过渡由主控决定。Release 内置 CA 当前为空并拒绝启用；
   内置公开 PEM 的位置和开发配置方法已写入客户端 README。
3. 协调服务既有私有扩展 OID 的 PEN 归属仍待主控裁定；本客户端使用标准 SAN 完成身份验证。
4. 真实账号、Mac GUI 与第二台实际设备的端到端验收由主控执行。
   本机双实例步骤包含沙盒内两个空白数据目录、独立单实例锁、不同 Mesh/Agent 端口，
   不需要复制私钥或将回环 MCP 改为外部监听。
