# 平台登录会话实现报告

## 1. 完成了什么

- 在 next/sessions worktree 实现 macOS 优酷、B 站内置 WebView 登录；用户亲自登录，
  点击「完成登录并保存」，宿主捕获所需 cookie 并写入现有 CredentialVault / Keychain。
- GUI 入口为「设置 → 实验室 → 平台登录」，可以查看会话状态、打开登录窗口、注销。
- 提供 sessions.status（read）、sessions.logout（write）、ui.open_platform_login（write），
  能力覆盖基线同步增加三项。状态支持批量平台；注销支持批量和幂等。
- 实现 VaultYoukuSessionBridge，签名、token 正常握手、请求与会话字段过滤都在宿主；
  B 站已有请求 profile 可由宿主附加会话。来源只获得作用域受限的 host 和引用。
- 未登录、过期、平台拒绝、保险库失败与未支持平台如实报告。新增 20 项离线行为测试。
- 未新增依赖，未运行 pub get，未提交 commit，未 push。构建自动刷新了与本任务无关的
  Erika Pod lock 元数据，验收完成后已恢复，最终没有构建配置变更。

## 2. 决策

- 仓库不存在 lib/next/vault，实际接口位于 lib/security/credential_vault.dart；复用
  NextCore 暴露的保险库，使用 next.platform-session 命名空间、平台.v1 条目。
- 已确认安装的 webview_flutter 4.14.1 / webview_flutter_wkwebview 3.26.0 支持 macOS。
  插件公开 API 缺少隔离数据存储和完整 cookie 属性，所以在已有 macOS Runner 文件内
  直接使用同一系统 WebKit。每个窗口独立使用 nonPersistent 存储，不共享插件渲染器、
  其他平台或系统浏览器；关闭即释放。无需新依赖或新构建配置。
- 只接受 HTTPS 登录导航，保存时按平台域名与所需 cookie 名称筛选；包括 HttpOnly
  cookie，保留域、路径、Secure、到期时间。cookie 不通过页面 JavaScript 提取。
- sessionPresent 表示本地 cookie 检查通过，verification=localCookiesOnly；不宣称
  在线登录已验证。正常 MTOP token 更新最多重试一次，会员、DRM、付费墙拒绝不绕过。
- CredentialRef 与来源 ID、v1、固定 profile 绑定；accessRef 是适配现有弹幕输入的
  引用字符串。带会话的请求拒绝重定向；来源不获得 token、cookie、签名 URL 或账户字段。
- 窗口和会话分别使用代次，注销/重新登录后的迟到保存与请求不能恢复旧会话。
  写入、删除都回读验证，无明文回落。恢复错误可见且不阻塞其他平台和应用启动。
- 其他平台保留 PlatformLoginPort，状态为 unsupported；本次只实现、验证 macOS。

## 3. 验收命令与真实输出

所有 Flutter / Dart 使用 ~/development/flutter-3.44.6/bin/。

```text
flutter analyze --no-pub lib/next test/next
No issues found!

flutter test --no-pub test/next
00:25 +332: All tests passed!

flutter build macos --debug --no-pub
✓ Built build/macos/Build/Products/Debug/NipaPlay.app
```

三项退出码均为 0。GUI 接入文件也已单独纳入 analyze，无问题。
构建保留项目既有的 Swift Package Manager 支持提示与构建脚本警告。
新增测试只用内存保险库、合成 cookie、MockClient / 取消夹具，不访问线上服务。
完整 test/next 中既有 Mesh 测试使用本地合成账号、临时 CA 和回环 TLS 服务。
没有读取系统浏览器数据或个人配置，也没有使用真实登录态运行测试。
个人 danmaku.py 仅用于只读核对优酷会话与公开签名机制，未执行该文件。

## 4. 问题与主控真机验收

没有需要主控决定的新依赖、契约迁移或构建配置事项。
离线测试不能证明真实平台页面、SSO、接口字段或用户 Keychain 授权当前可用；
这些由主控用自己的账号真机验收。

1. 启动构建出的 NipaPlay，在「设置 → 实验室 → 平台登录」打开优酷，亲自登录，
   点击「完成登录并保存」。GUI 应显示会话已保存；sessions.status 应返回 accessRef，
   并标明 localCookiesOnly。Agent 可以打开页面，不能输入密码。
2. 播放《长安十二时辰》某一集，告诉 Agent：
   「刷新当前这一集的优酷弹幕，使用对应的公开视频 ID / URL；获取失败时保留旧弹幕。」
   Agent 使用 sessions.status 的 accessRef 作为 credentialRef，核对当前文件与优酷
   视频身份，提供有依据的时长，用 danmaku.attach 的 refresh=true 获取并替换；
   已有绑定也可用 danmaku.fetch 的 refresh=true。task.wait 等待完成，再检查
   danmaku.tracks 中只有一条对应的优酷轨道，播放器可见新弹幕。
3. 如果视频旁已有优酷 XML，明确刷新仍应在线获取并替换；失败保留旧轨道/缓存。
   重启后检查会话恢复。注销优酷后再次刷新应明确提示需要登录；B 站状态不受影响。
4. 在同一入口登录 B 站，核对登录专用请求可使用用户自己的会话；无权限内容仍应拒绝。

详细实现、Action 输入输出和生命周期见 lib/next/sessions/README.md。
