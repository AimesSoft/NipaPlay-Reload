# 阶段 L 第一步：Classic LAN API A 档实施报告

日期：2026-10-11。工作目录：`~/Desktop/nipaplay-next-wt/lan-l`，分支：`next/lan-l`。

## 1. 完成了什么

先核对当前实现，再实施 A1–A6。未提交 commit、未 push、未运行 pub get，未新增依赖，未改变 Classic 的功能开关、访问方式、路由或响应正文契约。

### A 档核实与修复

| 项目 | 修改前核实 | 修复与兼容性依据 | 回归证据 |
|---|---|---|---|
| A1 令牌外层 URL 泄露 | 仍存在：`DandanplayHttpClient.send` 使用递归展开后的地址判断，但发送原请求 | 凭据策略和网关健康统计只使用实际 `request.url`。Web 内层识别只接受已配置宿主的精确 scheme/host/有效 port、精确代理路径，展开一层，仅用于登录门槛。官方与明确选定 custom 上游照常注入账号凭据；第三方自己的 Authorization 保留 | `dandanplay_http_client_test.dart`；`lan_api_compatibility_test.dart` 实际 image/web 代理嵌套攻击者地址不获得合成宿主令牌；Chrome `lan_web_relay_test.dart` |
| A2 Origin 前缀误判 | 仍存在：`proxyUri` 用 URL 字符串前缀判断同宿主 | 解析并比较 scheme、host、有效 port；base path 按区段边界、大小写敏感比较。默认端口与含 userInfo 的 Basic 地址正常；另一个共享实例继续走代理 | `web_remote_access_origin_test.dart`；Chrome 测试实际 `proxyUri` 分支 |
| A3 撤销残留/旧弹窗恢复 | 仍存在：删除 trusted 未删除 approved；pending 结果不检查撤销 | 撤销同步清除 trusted、approved、denied、pending，并增加审批代次。旧批准和旧拒绝均不能影响新审批；旧 Future 完成不能删除新 pending。信任持久写入串行化，加载信任等待写入并核对代次 | `remote_control_access_guard_test.dart`：立即失效、旧信任结果不入盘、重新审批正常、旧拒绝不撤销新批准 |
| A4 HEAD 被 GET 遮蔽 | 仍存在：share 4 个文件接口、manage 2 个文件接口和 web_proxy 均先注册 GET | 显式 HEAD 先注册；使用现成 `headOnly`。代理 HEAD 保留上游 Content-Length，继续发送实际 HEAD 方法 | `lan_media_head_test.dart` 记录真实文件响应入口的 headOnly，并验证视频/字幕/音轨/字体；`lan_api_compatibility_test.dart` 验证 manage GET/HEAD/Range 和代理 HEAD |
| A5 敏感日志/缓存 | 仍存在：完整请求 URI、静态回退 URI、WebToken 数据/URL；还发现续期 body 预览、令牌片段和 refresh_login 查询/上游诊断日志 | 请求日志只记录固定路由模板、方法、状态、耗时；输入 key、shareId 和未知路径均替换。静态回退复用模板。移除 WebToken、账号页 URL、续期正文/令牌片段与刷新查询日志，相关异常日志仅记录类型。API 全部加 no-store，覆盖成功、错误和预检；输入 HTML 加 no-referrer | `lan_http_policy_test.dart` 检查查询、userInfo、凭据、输入 key、未知路径、异常不进入请求日志；`dandanplay_sensitive_log_test.dart` 用合成响应验证 WebToken、注销/绑定 URL、实际 refresh_login 保持可用且诊断不泄密 |
| A6 CORS 一致性 | 仍存在：默认 CORS 会被 image 的 `*` 和代理上游头覆盖，缺少 Vary: Origin 与 HEAD | 统一响应策略覆盖下游 Access-Control-*；去掉图片内部 `*`，代理隔离上游 CORS。保留来源回显、credentials 和 OPTIONS 200；支持 HEAD、Authorization、Range、遥控声明及自定义上游预检头；合并原有 Vary 与 Origin，保留多值响应头 | `lan_http_policy_test.dart`：独立/同源/原生、预检、上游覆盖、Vary、多个 Set-Cookie 不折叠；实际 image/web 路由测试 |

实现位置：`lib/services/lan_http_policy.dart`、`web_server_service.dart`、`web_api_service.dart`、`web_ui_proxy_api.dart`、`web_remote_access_service.dart`、`dandanplay_http_client.dart`、`remote_control_access_guard_service.dart`、`remote_text_input_service.dart`、`local_media_share_api.dart`、`local_media_management_api.dart`、弹弹play IO/stub。

### R1 §5 每项漏洞在当前代码的核实结果

下表中的“仍存在”是当前代码核实结果；未把条件性攻击推导写成已完成的运行时利用。

| R1 | 当前核实证据 | 是否修复、兼容性依据与剩余边界 |
|---|---|---|
| 5.1 任意 Origin 跨站访问 | `web_server_service.dart` pipeline；旧 API 没有统一身份校验 | 保留。A6 只修一致性与缓存，不建立授权。独立 Web UI 是合法调用方，不能改成仅同源 |
| 5.2 web_proxy SSRF | `web_ui_proxy_api.dart:22`：url/x-proxy-url 仍控制 HTTP/HTTPS 目标，方法/正文/上游授权头仍可转发 | 保留。C11 的自定义 AI、媒体服务器、其他共享实例目标不能由固定公共域名白名单覆盖；代理原样方法/正文/第三方授权兼容测试通过 |
| 5.3 弹弹play凭据代理与外层泄露 | 修改前 `dandanplay_http_client.dart` 展开任意同名代理路径；当前 `send` 依据 request.url | 外层泄露已修。匿名调用宿主代理使用宿主账号访问获信任上游的能力仍存在，依赖后续账号授权迁移 |
| 5.4 image_proxy 本地图片/网络 SSRF | `web_api_service.dart:166`：本地扩展名检查仍在，未校验共享根；网络分支直接请求目标 | A1/A5/A6 已覆盖此入口；本地图片登记与 SSRF 授权未做。C6 及 R1 §3.3 合法使用任意本地缩略图/封面与网络图片，禁止这些路径会改变显示功能 |
| 5.5 未鉴权 folders 扩大共享范围 | `local_media_management_api.dart:606` 接收路径；`scan_service.dart:1006` 添加目录；manage stream 仍有媒体扩展名与字符串根检查 | 保留。**当前这条链并非无扩展名限制的任意文件读取**：`.txt` 被 403 拒绝，browse 过滤非媒体；这项限制原本就存在。本次实测添加目录、browse、播放均正常。要求目录预先登记或本机再批准会破坏 C15 的远程添加目录；canonical 限制还可能改变既有树外符号链接媒体库 |
| 5.6 history/progress → share stream 任意文件读取 | `web_api_service.dart` 接收 filePath/animeId 并新建历史；`local_media_share_service.dart:147` 所有带 animeId 记录入映射；`:409` 流不检查根/扩展名 | 保留。实测扫描根之外的单文件、无扩展名资源仍可同步历史并共享读取。这是现有契约的一部分，根约束或扩展名白名单会使其失效；只列扫描格式也漏掉独立打开的资源。需要把历史写入与共享资源授权分离 |
| 5.7 匿名 WebToken | `web_api_service.dart` webtoken 路由调用宿主账号服务并返回正文；business 仍由调用者指定 | 仅日志与缓存修复。C8 仍须接收业务 WebToken、打开注销/绑定入口；增加身份或删除业务会改变现有客户端 |
| 5.8 settings/network 未授权写入 | `network_media_settings_api.dart` POST 仍调用连接、选库、断开逻辑，没有统一身份校验 | 保留。C16 的 Web 配置同步仍使用该入口，包含无显式 application/json 的 POST；未改变解析或增加认证 |
| 5.9 WebDAV/SMB 凭据返回 | `local_media_management_api.dart:107` 返回连接 toJson；`webdav_service.dart` 与 `smb_service.dart` toJson 仍含 password | 保留。当前落盘已使用 CredentialStore，**保险库存储没有消除 HTTP 明文返回**。C15/provider 仍解析密码用于远端连接、编辑和播放，不能直接删除字段。响应已 no-store |
| 5.10 XFF/clientId 冒充 | `remote_control_access_guard_service.dart` `_resolveRemoteIp` 仍优先 XFF；身份仍为自报 id 或 IP | 保留。撤销语义已修，但身份伪造未修；默认改真实 socket peer 会改变反向代理下的既有 IP 授权，需要可信代理配置/迁移策略 |
| 5.11 DNS rebinding | `web_server_service.dart` 未增加 Host allowlist，仍使用 requestedUri.origin 构造入口参数 | 保留代码支持的攻击面；浏览器可利用条件未复现。任意宿主地址、独立 UI、反向代理部署需先有公开 Host 契约 |
| 5.12 Torrent 回环流经 SSRF 暴露 | `rust/src/api/torrent.rs:478` 仍绑定 127.0.0.1 随机端口；仅 GET/HEAD，无身份/Host 校验，连接独立线程 | 保留。没有把回环监听误报成公网监听；通用代理仍能请求回环 HTTP 服务。本次未调用实际 Torrent 服务，需随代理/资源授权收口 |
| 5.13 撤销、日志、资源消耗、缩略图覆盖 | 撤销/日志见上；代理 body 和图片仍完整缓冲；`local_media_share_service.dart:1025` 仍优先复用已有 thumbnailPath | 撤销、列出的敏感日志已修。体积/并发限制与缩略图路径边界未改变：现有媒体、截图、日志/AI body 无统一大小契约；复用已登记缩略图是当前 C14 行为。远程输入原本已有长度校验和 no-store，但长度检查发生在读取之后，不能称为统一流式体积限制 |

### R1 §3 调用方兼容性

`lan_http_policy_test.dart` 按 C1–C18 枚举现有方法/路径，在原生、同源 Web、独立 Web 三种请求形式下验证：请求对象、正文、Basic Authorization、Range、遥控身份声明不被修改；状态、正文和媒体响应头保留。C16 仍接受正文为 JSON 字符串、Content-Type 为 text/plain 的旧格式。

这组矩阵验证的是本次变更的 HTTP 边界，不冒充各上游服务或完整 GUI 端到端验收。另有实际路由/文件测试覆盖 C1/C6/C8/C10/C11/C12/C13/C15/C17/C18，现有共享库、二维码、遥控设置、远程输入、字幕、媒体获取与图片客户端测试也已运行。Chrome 单独验证真正的 kIsWeb 分支，包括合法代理登录门槛和跨实例地址包装。

## 2. 决策

1. 凭据接收方与 Web 登录门槛分开：任何“内层服务识别”都不能扩大凭据接收范围。保留 `targetUri` 给既有图片消费者使用，但原生不展开、Web 仅识别配置宿主的精确代理入口。
2. 在 server 外层统一 CORS/no-store，覆盖业务成功、错误与预检；使用 header 增量更新，避免把多个 Set-Cookie 合并成一个字符串。全部 API no-store 是兼容的保守缓存策略，静态 Web 资源不统一禁缓存。
3. 撤销代次同步生效，持久信任写入串行化，防止旧结果重新授权及并发写入丢失撤销；批准机制、设备名称、UI 和拒绝冷却时长保持现状。
4. 不新增 A7 的监听/Host/代理/Origin 设置：本次是第一步修缺陷，新增可见配置与迁移策略需要主控决定。未新增产品功能，因此不新增 Harness Action 或设置 schema。
5. 三项重点高危问题不假定媒体白名单、扫描根或固定代理域名能够零兼容收口；用实际兼容测试验证边界，并保留现有合法调用。
6. 修改涉及文件原有的少量 analyzer 问题（显式 call tear-off、冗余非空断言、花括号和 print）已局部处理，以满足要求的 analyze 零问题；未做无关整文件格式化。
7. 补充运行图片客户端测试时，旧断言要求组件源码直接出现 `loadNetworkImageBytes`，但当前组件已通过 ImageCacheManager 访问统一加载器。将该过时源码断言改为真实客户端下载、解码及关闭磁盘缓存的行为测试；回环 transport 测试显式设置 DIRECT，避开 Flutter 测试绑定的 HTTP 拦截。未改图片产品实现。

## 3. 验收命令与真实输出

所有 Flutter/Dart 均使用 `~/development/flutter-3.44.6/bin/`；Flutter analyze/test 全部 `--no-pub`。测试使用合成凭据、MockClient、临时目录或本机 Mesh 模拟上游，没有访问生产服务、读取真实账号或写系统保险库。首次 Chrome 运行由 Flutter 获取了缺失的 Web SDK，属于工具运行时准备，测试业务请求仍全部为夹具。

```sh
~/development/flutter-3.44.6/bin/flutter analyze --no-pub \
  lib/services/dandanplay_http_client.dart lib/services/web_remote_access_service.dart \
  lib/services/remote_control_access_guard_service.dart lib/services/lan_http_policy.dart \
  lib/services/web_server_service.dart lib/services/web_ui_proxy_api.dart \
  lib/services/web_api_service.dart lib/services/local_media_share_api.dart \
  lib/services/local_media_management_api.dart lib/services/remote_text_input_service.dart \
  lib/services/dandanplay_service_io.dart lib/services/dandanplay_service_stub.dart \
  test/dandanplay_http_client_test.dart test/web_remote_access_origin_test.dart \
  test/remote_control_access_guard_test.dart test/lan_http_policy_test.dart \
  test/lan_media_head_test.dart test/dandanplay_sensitive_log_test.dart \
  test/lan_api_compatibility_test.dart test/lan_web_relay_test.dart \
  test/media_server_image_loader_test.dart
```

```text
Analyzing 21 items...
No issues found!
```

```sh
CARGO_NET_OFFLINE=true ~/development/flutter-3.44.6/bin/flutter test --no-pub \
  test/dandanplay_http_client_test.dart test/web_ui_proxy_api_test.dart \
  test/web_remote_access_origin_test.dart test/remote_control_access_guard_test.dart \
  test/lan_http_policy_test.dart test/lan_media_head_test.dart \
  test/dandanplay_sensitive_log_test.dart test/lan_api_compatibility_test.dart \
  test/shared_remote_library_connection_test.dart test/remote_text_input_service_test.dart \
  test/remote_control_settings_test.dart test/remote_access_qr_service_test.dart \
  test/remote_media_fetcher_user_agent_test.dart test/remote_subtitle_cache_test.dart test/next
```

```text
00:27 +384: All tests passed!
```

包含真实 TLS Mesh 集成的撤销、重放、账号归属、过期证书、不可信签发者测试；其中输出的 `mesh connection rejected` 是拒绝路径断言的预期诊断。

```sh
~/development/flutter-3.44.6/bin/flutter test --no-pub --platform chrome test/lan_web_relay_test.dart
```

```text
00:00 +1: All tests passed!
```

补充图片客户端与网关路由兼容测试：

```sh
HTTP_PROXY='' HTTPS_PROXY='' http_proxy='' https_proxy='' \
  ~/development/flutter-3.44.6/bin/flutter test --no-pub \
  test/media_server_network_image_test.dart test/media_server_image_loader_test.dart \
  test/nipaplay_server_router_test.dart
```

```text
00:00 +34: All tests passed!
```

完整命令输出保存在 `/tmp/lan-l-analyze-final.log`、`/tmp/lan-l-final-test.log`、`/tmp/lan-l-web-final.log`、`/tmp/lan-l-image-test.log`；`git diff --check` 无输出。

## 4. 问题：需要主控决定的事项

1. **folders**：远程新增根目录怎样迁移到 Mesh `library.manage` 或本机明确许可；是否保留既有树外符号链接。现有媒体扩展名检查只减小读取类型，不能替代根目录授权。
2. **history → share stream**：单文件、无扩展名/特殊格式、扫描根之外的历史资源怎样登记授权；历史写入必须与资源发布权限分离。不能仅按 shareId 或扫描目录信任资源。
3. **web/image_proxy SSRF**：自定义 AI、媒体服务器、图片来源及其他共享实例怎样授权目标 origin/port/path；需要涵盖重定向、DNS、实际连接地址与回环资源，不能只用固定公共域名白名单。
4. **账号、WebToken、网络配置、WebDAV/SMB 凭据**：按 Mesh 安全通道迁移客户端与资源访问；密码字段删除要与 provider 编辑/播放改造同步。当前 A 档仍保留匿名旧 API。
5. **Web 接入和旧遥控身份**：独立 Web UI 的可信 bootstrap/会话，Host 与可信代理配置，旧 IP/clientId 信任的重新配对/迁移；A6 不解决跨站授权、DNS rebinding 或身份冒充。
6. **资源限制与缩略图**：分别明确代理 body、图片、缩略图、并发、超时的兼容阈值与缩略图写入授权路径；Torrent 回环资源只授予指定文件。
7. **迁移提示**：阶段 L 后续的旧接口风险提示与退出兼容模式时间表由主控决定；本步未新增用户可见提示/功能。

## 5. 主控决定（2026-10-11）

用户决定暂时维持现状：A 档兼容修复已合并（4820ff98），以上 7 项不单独修复，旧匿名接口保持现有行为。这些事项与 Mesh 设备身份、原生对端迁移、Web UI 配对接入一起处理；在此之前不再单独提出热修复，除非情况发生变化（例如默认暴露面扩大，或出现实际被利用的迹象）。
