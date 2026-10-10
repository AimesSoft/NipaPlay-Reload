# 服务端独立审查记录（2026-10-11）

工作区：`~/Desktop/nipaplay-next-wt/review-server`，分支 `next/review-server`。
审查前 HEAD：`52dbcbb5380c89551e03eefa51884188a9807fef`。
网关对照基线 main：`b694ded7d0de9bbe0b8b23db414d2a5d59b57362`。

已读取 TEAM、QUALITY_GATE、MESH_TASKBOOK 全局契约 §2/§3 和 DESIGN §9 第 6 项。
审查覆盖共享认证、网关、协调服务及部署和信任说明。未提交、未 push、未部署，未调用
线上服务；所有 HTTP 测试只连接本地模拟服务，令牌和 AppSecret 均为合成测试值。
本轮未新增依赖或改动 Cargo 构建配置。

网关通过本次独立行为审查。协调服务的本地实现检查通过；完整 Mesh 产品验收还需要
客户端吊销传播、正式信任根以及上游身份契约的集成确认，不能据此宣称全网即时吊销。

## 1. 发现的问题与修复

| 编号 | 分级 | 缺陷和影响 | 处理与证据 |
|---|---|---|---|
| S1 | 必须修 | 抽出的验证请求把 playhistory 查询串签入摘要，与 main 不同，真实上游可拒绝所有正常令牌 | 已修复：签名只含路径；固定独立摘要向量、模拟上游签名断言和双进程 main 对照 |
| S2 | 必须修 | 被吊销设备可再次注册并拿到新证书，API 注册没有吊销检查，存储也不拒绝 | 已修复：API 与事务均拒绝；测试重新注册、续期和地址上报，失败不返回证书 |
| S3 | 必须修 | 两个账号同时抢占同一 deviceId 时，后者的 UPSERT 可能不更新设备却仍记录并返回证书 | 已修复：IMMEDIATE 事务内核对账号、公钥与吊销状态；并发测试只能一个账号成功、只留一条签发记录 |
| S4 | 必须修 | 续期/地址写入的外部预检查与事务分离，吊销后可能继续登记证书或重新写回地址 | 已修复：归属与吊销在写事务内检查；旧快照测试和真实并发上报/吊销测试 |
| S5 | 必须修 | 设备列表与 revocation_epoch 分开查询，会返回旧列表和新版本号 | 已修复：同一读事务快照；吊销后的列表、状态与账号 epoch 一致 |
| S6 | 必须修 | 内部路径、SQL/解析/网络错误可返回客户端；epoch 查询失败还被吞成 0 | 已修复：500/503 固定消息，查询失败显式返回 500；DROP accounts 故障注入和畸形上游测试 |
| S7 | 必须修 | 私钥先普通写入后 chmod，有暴露窗口与路径检查竞态；加载不查权限/CA 用途/当前有效期 | 已修复：create_new + 创建时 0600；普通文件/大小/权限检查；验证自签名 Ed25519 CA、keyCertSign、有效期和密钥匹配。权限、悬空符号链接和坏 CA 测试 |
| S8 | 必须修 | 证书时长任意配置，可能过长或整数转换溢出，叶子有效期也可能超出 CA | 已修复：API/配置夹到 900–604800 秒，签发器另有硬上限；有效期两端限制在 CA 内。极值配置和实际证书测试 |
| S9 | 必须修 | 网关及协调服务默认 Trace span 记录完整 URI，网关网络错误也可能包含 webToken URL | 已修复：Trace URI 不含查询，代理错误去 URL；main 双进程测试实际复现旧日志泄露并确认新日志无合成 webToken |
| S10 | 必须修 | 协调服务无 socket 信任边界，若对外监听，伪造转发头可绕过 IP 限流 | 已修复：仅回环代理可启用转发头；默认仍监听回环 |
| S11 | 必须修 | 共享限流器满 50000 桶后按 10 分钟空闲清理，会提前丢弃仍有效的小时窗口 | 已修复：清理期限不短于桶窗口；超过清理阈值的小时桶测试。网关 60 秒窗口行为不变 |
| M1 | 合并前修 | IP 限流在 JSON 提取之后，公开/畸形请求未受限流；首次身份解析只有 IP 桶保护；续期拒绝没有身份负缓存 | 已修复：入口 IP 中间件、上游前令牌桶、已知账号提前查额度和无效身份 30 秒缓存；检查真实上游调用次数。未知令牌仍需先核实账号才能归入账号桶 |
| M2 | 合并前修 | 吊销接口忽略 URL 中 deviceId，可以按另一个 body id 操作 | 已修复：要求路径与请求体一致；不一致返回 400、不改变设备 |
| M3 | 合并前修 | 输入边界不完整：主机仅检查长度，重复候选变 500，TTL 小于 60 会 panic，deviceId/令牌/元数据格式不严 | 已修复：32 KiB JSON、4096 字节令牌、规范 id/base64、控制字符检查、IP/DNS 主机、重复候选 400、TTL 夹到有效范围。畸形/极值/SQL 文本与事务回滚测试 |
| M4 | 合并前修 | 身份解析只用 GET 续期，与 App 的 POST 优先及 405 + Allow: GET 回退策略不同；接受 0/负数 userId | 已修复：沿用 App 请求策略，只接受正整数；POST 和 GET-only 模拟上游及坏身份测试 |
| M5 | 合并前修 | nginx 模板剥离 /mesh/ 导致全接口 404；部署命令向不可写目录生成 CA；README 推荐首次拉取公钥建立信任 | 已修复：保留路径、暂存后按权限安装 CA、明确 App 内置信任根；双服务器文档标明协调服务尚未部署 |
| T1 | 记录待办 | 私有证书扩展 PEN/OID 归属没有可信证据 | 未改公开证书格式；正式发布前主控确定合法 OID 并同步客户端解析器 |
| T2 | 记录待办 | 无推送且允许离线直连，服务端吊销不能使所有旧会话立即获知 | 服务端拒绝和删除已修复；客户端传播/新鲜度与离线策略由主控协调 M 阶段 |
| T3 | 记录待办 | 续期响应的真实 userId 契约、稳定性及原令牌是否因轮换失效没有在本任务中验证 | 本轮按模拟契约严格检查，未访问线上；部署前需权威契约或受控集成确认 |
| T4 | 记录待办 | HTTP 控制面只要求账号令牌，未要求设备私钥持有证明；证书历史表持续增长 | 与最小账号信任模型一致；PoP 是否加入、签发记录保留期限与地址加密由主控另定 |

SQL 审查没有发现字符串拼接注入：所有运行时值都使用 SQLite 参数绑定。新增测试让
SQL 元字符作为普通账号数据落库，并验证事务失败后原地址与 last_seen 不变。
吊销保留现有约定：每次成功请求使本账号 epoch +1，重复吊销也 +1；其他账号不受影响。
过期地址不返回，物理清理由原有后台小时任务完成；有效期始终不超过 2 小时。

## 2. 网关与 main 的逐项对照

| 项目 | main 行为 | 修复后的行为与结论 |
|---|---|---|
| 路由 | /healthz、/api/v2/*、fallback、已知方法表、未知兼容开关、permissive CORS | 等价；原路由判定代码未改变，双进程覆盖正常/未知/严格模式/多方法/CORS |
| 令牌校验 | Bearer 大小写/trim；playhistory GET 及原查询；401/403 或 success:false 判无效；故障返回 503 | 等价；有效/无效/HTTP 故障/JSON 故障实测 |
| 缓存 | token SHA-256 前 16 位键；有效 600 秒、无效 30 秒；上游错误不作无效缓存 | 等价；实际调用次数、有效期和过期测试 |
| 签名 | base64(SHA-256(appId + timestamp + path + secret))，query 不参与 | 等价；已修 S1，固定向量与两个实际二进制验证 |
| 登录/注册 | 原字段校验、appId/unixTimestamp 与 MD5 hash 重写，其他正文保持原样 | 等价；独立重算两个请求的摘要并比较上游正文 |
| 限流键/窗口 | global、代理解析 IP、token 摘要；固定 60 秒；全部桶允许才递增，0 禁用 | 等价；三个限流域、原子拒绝、窗口边界及并发计数测试 |
| 错误/状态 | 原 JSON 消息与状态码；401/404/400/413/429/503/502/504；透传上游状态 | 等价；main 响应对照，另有超时单测；网络错误分支仅去掉日志 URL |
| 响应头 | 原七项上游头白名单；x-nipaplay-gateway；private, no-store；CORS | 等价；逐头检查，Set-Cookie 与其他私有头不透传 |
| webToken | 仅两个账户页面接受非空 query webToken；上游检查；不解锁其他 API | 等价；两个页面与普通 API、空值、解码规则测试 |
| renew | 必须带 Bearer，但不预先验证旧 token；方法/响应照常代理 | 等价；GET/POST 对照。新 coordinator 的身份查找策略不改变网关代理 |
| 日志 | 业务事件、方法/路径/状态/耗时/IP/摘要、bootstrap 警告；debug URI 可含 webToken | 安全例外：去掉 query 与错误 URL，保留其他字段/等级/事件及原日志 target |
| HTTP 策略/密钥加载 | 同一 reqwest client，5 秒连接/25 秒总超时、无重定向；原环境/legacy bootstrap | 等价；with_client 复用原 client；bootstrap 原逻辑和告警 target 保留 |

独立对照脚本从 git main 提取原 Cargo.toml/Cargo.lock/src/main.rs，构建原版二进制，再
构建当前二进制；同一回环 mock 分别运行，比较响应和上游请求，独立校验 SHA-256/MD5。
每个二进制 142 个请求。**唯一保留的外部行为差异是日志去秘密，属于明确安全修复。**

## 3. 验收命令与真实输出

分别在三个 crate 目录运行：

```sh
cargo fmt --check
cargo clippy --all-targets -- -D warnings
cargo test
```

所有命令退出码为 0；fmt 无输出。以下为最后一次输出摘录（省略编译和逐个测试行）：

```text
nipaplay-auth:
    Finished `dev` profile [unoptimized + debuginfo] target(s) in 0.23s
test result: ok. 9 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.03s
Doc-tests: 0 passed; 0 failed

dandanplay-gateway:
    Finished `dev` profile [unoptimized + debuginfo] target(s) in 0.41s
test result: ok. 12 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.11s

nipaplay-mesh-coordinator:
    Finished `dev` profile [unoptimized + debuginfo] target(s) in 0.74s
test result: ok. 40 passed; 0 failed; 1 ignored; 0 measured; 0 filtered out; finished in 0.35s
```

忽略的是原有手工证书导出测试，不是失败隔离。证书结构和验签有正常自动化测试覆盖。

仓库根目录运行：

```sh
python3 server/dandanplay-gateway/tests/compare_main.py
git diff --check
```

```text
PASS: 142 requests per gateway; responses, upstream requests, signatures, account hashes, caches and rate limits match main.
PASS: debug logs no longer contain the synthetic webToken (baseline reproduced the leak).
```

diff --check 无输出、退出 0。HEAD 没有变化。

## 4. 实现决策与主控事项

内部实现选择：共享 crate 允许注入 HTTP client，使生产网关保留原池和策略、测试禁用代理；
写入使用 IMMEDIATE 事务，读取使用一致快照；保留现有路径/JSON 和重复吊销计数契约；
协调服务使用完整摘要内部键；失败对外只给固定错误，不把数据库坏状态伪装为成功。

主控需要在完整 Mesh 发布/验收前确定：

1. 一个协调服务部署端、App 内置 CA、签发者密钥轮换和旧证书过渡方案。不能把网关的
   主备切换直接套给两个独立 SQLite/CA 协调服务。
2. 正式扩展 OID，与客户端解析器同步。保留开发格式避免单方面改变跨模块契约。
3. 吊销传播机制：推送/连接前强制刷新/允许的离线宽限，以及已有会话终止；客户端心跳
   最少 900 秒并加入抖动。版本号本身不是吊销证明，需同步设备列表。
4. 上游续期的稳定 userId 响应和令牌轮换语义；如果原令牌会失效，须换成经核实的只读
   身份接口或明确客户端令牌交接契约，不能在后台静默使 App 登录失效。
5. 是否将设备私钥持有证明加入 HTTP 注册/续期契约，以及签发历史清理与地址加密排期。

这些事项涉及公开契约、安全产品行为或部署，依 TEAM 由主控决策。本轮已完成可独立
修复的服务端实现、测试与文档，没有执行部署或更改客户端信任规则。
