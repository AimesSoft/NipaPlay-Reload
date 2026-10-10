# 平台会话（macOS）

用户入口：设置 → 实验室 → 平台登录 → 优酷 / B 站 → 打开登录页。
用户在 NipaPlay 的 WebView 内完成登录，然后点击「完成登录并保存」。
登录成功的本地判据为可用于 API 域名的优酷 P_sck / yktk 或 B 站 SESSDATA；
仅有优酷匿名签名 token 不表示用户已登录。没有自动输入秘密的 API。

现有依赖含支持 macOS 的 webview_flutter / WKWebView，但公开 Dart API 不提供
隔离的 nonPersistent 数据存储与完整 cookie 属性。macOS 宿主因此直接使用相同
系统 WebKit，在现有 MainFlutterWindow 中注册内部 MethodChannel；未新增依赖、
未修改构建配置。每个登录窗口独立使用 WKWebsiteDataStore.nonPersistent，
不共享渲染插件、其他平台或系统浏览器的 cookie；窗口关闭即释放该存储。
登录窗口仅允许 HTTPS；不设置证书例外。SSO 可以在窗口内导航，保存时只接受
对应平台根域及子域，再按宿主需要的 cookie 名称白名单筛选，保留 HttpOnly cookie、
域名、路径、Secure 与到期时间。认证秘密加入既有诊断脱敏；用户 ID 等公开属性
不作为任意文本替换值，避免破坏正常响应中的 ID。
这些属性只在宿主中处理，不通过 JavaScript 提取。

NextCore 通过现有 CredentialVault 使用 `next.platform-session/<platform>.v1`
的系统保险库条目（macOS Keychain）。写入后完整回读验证；注销后回读验证删除。
不建立偏好或磁盘明文回落。读写/注销失败有明确错误或 notice；恢复失败不阻塞
其他平台与应用启动。会话代次阻止注销或重新登录后旧请求覆盖新会话，窗口代次
拒绝已关闭/注销的迟到保存。关闭应用窗口释放 WebView，但保险库会话保留。

| Action | Effect | 输入及结果 |
|---|---|---|
| sessions.status | read | 可选 platforms（1–2 个不同平台），省略查全部；返回本地状态、notice、CredentialRef 和兼容现有弹幕输入的 accessRef，均无秘密 |
| sessions.logout | write | platforms（1–2 个不同平台）；按输入顺序注销本机条目与窗口，重复注销幂等；保险库删除失败返回 Failed，已执行项不回滚 |
| ui.open_platform_login | write | platform；立即打开内置登录窗口并返回 opened=true，用户完成登录之前不宣称登录成功 |

平台值：youku、bilibili。状态：loggedOut、sessionPresent、expiredOrRejected、
unavailable、unsupported。sessionPresent 仅表示本地登录 cookie 存在且未过期，
verification=localCookiesOnly；不代表已在线验证、会员权限或播放权限。
平台拒绝认证时停止使用该会话，并指向同一登录入口。其他操作系统如实返回
unsupported / unavailable；PlatformLoginPort 保留后续平台实现的入口。

来源只有 ScopedDanmakuHost 和 DanmakuAccess。宿主校验来源 ID、v1 版本、固定
profile 与精确 CredentialRef，不接收任意请求 URL。优酷将公开协议 body 签名与
MTOP token 签名都留在宿主，正常 token 更新限一次，过滤响应中的会话字段。
B 站登录后由宿主为已有 view / season / segment / search / WBI profile 附加
符合域名、路径、安全与到期条件的 cookie；未登录继续允许公开接口，登录专用
接口拒绝时提供明确提示。匿名 WBI nav 返回 -101 时仍可使用公开图像签名键。
认证请求不跟随重定向，响应和请求时限沿用宿主预算；取消、注销或替换会话后
不会把旧响应提交给来源。仅使用公开接口和用户自己的登录态，不涉及会员、
DRM、付费墙或历史弹幕权限绕过。

测试：test/next/platform_sessions_test.dart，仅内存保险库、合成 cookie 和
MockClient / Abortable 夹具；无线上服务、真实账号或真实 cookie。

主控真机验收：

1. 在 macOS 启动调试版 NipaPlay，从上述入口打开优酷页面，亲自完成登录，点击
   「完成登录并保存」；页面应显示会话已保存，sessions.status 应给出 accessRef。
2. 在 NipaPlay 播放《长安十二时辰》某一集。向 Agent 请求：
   「刷新当前这一集的优酷弹幕；使用对应的公开视频 ID / URL，保留失败前的旧弹幕。」
   Agent 使用 sessions.status 的 accessRef，明确视频身份和有依据的时长，经
   danmaku.attach 的 refresh=true 获取并替换，task.wait 等待，danmaku.tracks
   核对仅一条优酷轨道。也可对已有绑定用 danmaku.fetch 的 refresh=true。
3. 已有同名优酷 XML 的情况下，应仍发生明确的在线刷新；获取失败时保留旧池。
   重启后检查会话恢复。注销优酷后再尝试刷新，应提示需要登录；B 站会话不受影响。
4. B 站登录后检查同一来源请求可使用用户自己的会话；无权限内容应继续拒绝。
   真实接口字段、登录页面 / SSO 和 Keychain 行为由本轮真机验收确认；离线夹具
   不构成线上成功的证据。
