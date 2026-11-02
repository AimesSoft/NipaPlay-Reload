# X14：实验 7 的账号、快速连接、登录窗口与弹幕回执

2026-10-11，worktree `~/Desktop/nipaplay-next-wt/accounts`，分支 `next/accounts`。

## 1. 完成了什么

新增九项账号能力，通过 `NextCore` 提供给 Agent，复用 Classic 的 `DandanplayService`、`BangumiApiService` 和 `BangumiSyncService`。没有经由 Web 远程访问的匿名账号接口，也没有另写外部账号客户端。

| Action | 行为 |
|---|---|
| `accounts.status` | 读取两种账号的本地登录状态及用户名，不返回秘密。 |
| `accounts.login` | 发起可等待的登录任务；用户提供密码/个人访问令牌时直接使用，否则打开 NipaPlay 内的登录表单。 |
| `accounts.logout` | 经 Classic 清除对应账号登录态及保存的凭据。 |
| `accounts.collections.get` | 批量读取收藏、评分与作品状态；Dandanplay 使用 animeId，Bangumi 使用 subjectId。 |
| `accounts.collections.update` | 批量更新收藏、评分、作品状态与评论；Bangumi 支持 private，Dandanplay 支持移除收藏。 |
| `accounts.episodes.get` | 读取 Dandanplay 播放历史或指定 Bangumi 作品的剧集收藏状态。 |
| `accounts.episodes.update` | 批量提交剧集观看状态。 |
| `accounts.bangumi.sync` | 运行 Classic 的观看历史同步，返回可等待任务；默认增量，full=true 为全量。 |
| `accounts.bangumi.sync_status` | 读取 Classic 已保存的同步统计。 |

批量操作支持 1–100 项，逐项返回成功或失败。登录态列表只陈述本地状态；写收藏的回执只陈述服务器接受了请求，另用 get 读回。Bangumi 同步的逐作品错误会进入失败回执，不把 Classic 的顶层 success=true 当作全部成功。

`media.sources.login` 的说明和返回值现在直接陈述：验证码要交给用户在 Jellyfin 中批准；用返回的任务等待批准结果。返回值保留原来的 code/jobId，并新增 approval，包含用途、有效期和 `task.wait` 调用。

Next 媒体来源、Dandanplay 与 Bangumi 登录表单统一使用主窗口内的 `DialogRoute`，打开时显示并聚焦主窗口。修复不依赖实验开关，普通实例走相同代码；实际用户实例未启动或访问。Classic 原有账号页面和弹窗调用保持原样。

弹幕评论请求现在使用 Classic 客户端的重定向处理。失败回执新增本次缓存、既有绑定缓存、Classic 缓存及当前播放器轨道的实际可用性快照，保留获取失败的事实及原缓存，不把旧弹幕当作本次获取成功。Next 的播放器视图也能识别 Classic 的 dandanplay 轨道及当前 episodeId。

## 2. 决策

1. **秘密只经过当前进程。** 登录 schema 的 password/accessToken 标记为 secret。任务持久输入只保存 provider、方法和可选用户名；用户提供的秘密放在进程内，认证或终态后清理。重启后不能重放对话密码，必须重新发起。认证成功后的会话保存仍由 Classic 服务及现有凭据存储处理。没有调用 credentials.retry 或解除既有凭据拒绝状态。
2. **登录成功验证有具体含义。** 服务认证响应成功后读回 Classic 登录态，回执说明这验证了认证响应及本地状态，不声称独立复查服务器会话。登录或同步在提交效果后中断，恢复时报告中断和可能的部分结果，不自动重放写入。
3. **保留 Classic 的实际接口语义。** Dandanplay 的 updateEpisodeWatchStatus 即使传 false 也会 POST 已看历史；Next 仅接受 state=2，并明确拒绝撤销已看。Bangumi 的作品状态和剧集状态分别按 Classic 支持的枚举提交。未调用会吞掉网络错误并返回 false/0 的 Dandanplay 收藏、评分、观看状态便捷方法，而是从现有抛错的请求入口读取真实响应。
4. **主窗口路由解决窗口问题。** 应用通过 desktop_multi_window 开启 Flutter 3.44 的 windowing；此时 showDialog 选择实验性的原生对话框路径，新 FlutterView 停在 0×0。Next 直接 push DialogRoute，使用已经有尺寸的主视图，取消只移除自己的路由。没有修改 Flutter、vendored 窗口包或 Classic 弹窗行为。
5. **302 不能直接等同于访问拒绝。** 本次实际 Location 指向弹弹play CAS 评论 CDN。仅 comments profile 开启现有客户端的重定向处理；其他请求保留原设置。没有另起客户端发送账号令牌到 CDN。真实回环检查确认 Dart/Classic 的重定向处理会移除跨主机 Authorization。无法解析的结果和真实认证/网络错误仍为失败。
6. **获取结果与可用性分别记录。** availability 是回执生成时的观察，包含时间；缓存数量、已加载数量与请求覆盖分别陈述，不把它们相加。之后开始播放不会改写已完成任务的历史回执。

## 3. 实验

完整脱敏公开输出保存在 [receipts.json](evidence/x14/receipts.json)。本节摘取其中的真实字段；截图只截实验进程的窗口，没有截用户其他应用。

### 环境与隔离

只在本 worktree 构建并直接运行：

```sh
ERIKA_PREBUILT_CACHE_DIR=/tmp/nipa-next/x2-erika-cache \
~/development/flutter-3.44.6/bin/flutter build macos --debug --no-pub

NIPAPLAY_PROFILE=x14-accounts-20261011 \
./build/macos/Build/Products/Debug/NipaPlay.app/Contents/MacOS/NipaPlay
```

实验进程 PID 16513、22329、23794 都带相同临时 profile，按 PID 结束。另一次启动器退出后被工具结束的进程 15940 没有进入业务实验。所有偏好、观看历史、任务、保险库和 harness 都在这个新建的实验目录内；没有读取真实 NipaPlay 数据或登录钥匙串，没有使用 open/osascript 启动应用。回环 HTTP 请求使用 DIRECT / ProxyHandler({})。

构建成功。Flutter 自带 pod install 根据已解析的本地插件刷新了 Podfile.lock；最后恢复该文件，未更改依赖或运行 pub get。主仓库没有构建。

### 弹弹play 真实测试账号

通过实验应用的 Agent 端点调用 accounts.login，密码只从 `/tmp/nipa-next/testservers.json` 读入进程内，没有写入命令参数或输出。初始空 profile 的真实输出：

```json
{"accounts":[{"provider":"dandanplay","loggedIn":false,"username":null},{"provider":"bangumi","loggedIn":false,"username":null}]}
{"provider":"dandanplay","method":"provided","jobId":"account-login-87a36950-e5f7-4d26-8c31-fe3f1a759b41"}
```

登录任务最终 state=succeeded，receipt：

```json
{"verification":"verified","details":{"provider":"dandanplay","loggedIn":true,"username":"<测试账号>","verificationMeaning":"Classic authentication response accepted and local login state read back."}}
```

对作品 17864 提交收藏及评分。首次组合请求返回接受，但立即读回 userRating=0；随后独立提交评分 9，服务端读回 9。再次经最终构建提交 favorited/rating=8，读回结果：

```json
{"results":[{"index":0,"status":"completed","result":{"provider":"dandanplay","workId":17864,"acknowledged":true}}]}
```

get 的真实结果中：

```json
{"provider":"dandanplay","workId":17864,"collection":{"animeId":17864,"favoriteStatus":"favorited","userRating":8,"rating":6.6},"rating":8}
```

6.6 是作品公共评分，8 是账号评分，没有混用。首次评分未立即反映的原因没有进一步确定，因此写接口保持 acknowledged，由 Agent 通过 get 判断实际值。

注销及之后状态的真实输出：

```json
{"provider":"dandanplay","loggedIn":false,"username":null}
{"accounts":[{"provider":"dandanplay","loggedIn":false,"username":null},{"provider":"bangumi","loggedIn":false,"username":null}]}
```

未提供秘密时，accounts.login 返回 method=window，真实弹窗见 [弹弹play 登录窗口](evidence/x14/dandanplay-login.png)。取消后任务 state=cancelled，sideEffectCommitted=false，没有认证或保存密码。

### Quick Connect 与可见登录界面

最终 auto 返回：

```json
{"sourceId":"jellyfin:1791706407510","method":"quickConnect","jobId":"source-login-cb8d4871-e814-4f8b-82f5-c746be8eb004","code":"932977","approval":{"code":"932977","message":"Give this code to the user to approve in Jellyfin. Await the approval result with the returned task.","expiresAt":"2026-10-11T08:25:46.643524Z","wait":{"action":"task.wait","input":{"jobId":"source-login-cb8d4871-e814-4f8b-82f5-c746be8eb004"}}}}
```

在临时 Jellyfin 使用测试管理员令牌批准，然后通过 task.wait 按 revision 等待终态：

```text
X14 Jellyfin approved: true
```

```json
{"verification":"verified","details":{"sourceId":"jellyfin:1791706407510","connected":true,"method":"quickConnect"}}
```

随后 media.sources.check 实际目录请求也返回 connected=true / checked=true。

首次批准请求只用了 X-Emby-Token，Jellyfin 12.2 返回 401；改用完整 Authorization: MediaBrowser 头后，原 testservers.json 中的管理员令牌即可批准。不是令牌过期，也没有修改服务器设置。另一次新取得的临时管理员会话文件已删除。

method=window 的窗口实际可见：

```json
{"bounds":{"Height":874,"Width":1512,"X":0,"Y":33},"id":41986,"layer":0,"onScreen":true,"title":"NipaPlay · LAB [x14-accounts-20261011]"}
```

见 [Jellyfin 登录窗口](evidence/x14/jellyfin-login.png)。同一路径还实际打开了 [Bangumi 令牌登录窗口](evidence/x14/bangumi-login.png)，随后取消；没有使用真实 Bangumi 账号。普通 profile 之外的用户实例受任务约束未运行，修复代码没有 LabProfile 分支。

### 弹幕请求、重定向和缓存

先用禁止重定向的版本，在完全没有该集缓存时运行 fetch；它真实失败：

```text
state=failed
dandanplay: accessDenied; HTTP 302; host=nipaplay.aimes-soft.com; path=/dandanplay/api/v2/comment/178640001; content-type=unavailable
classicCache={present:false,count:0}
attemptedCache.count=0
player={loaded:false,count:0,tracks:[]}
```

随后浏览临时 Jellyfin 六集，播放第 1 集。Classic 实际日志与 tracks 输出：

```text
发送弹幕请求到: https://nipaplay.aimes-soft.com/dandanplay/api/v2/comment/178640001?withRelated=true&chConvert=1
从网络加载弹幕成功: 178640001, 格式化后数量: 615, 去重后数量: 584
弹幕已保存到缓存: 178640001
```

```json
{"trackId":"dandanplay","name":"弹弹play","source":"dandanplay","count":584,"enabled":true,"loaded":true}
```

因此本次差异不是旧缓存或部分获取：先前确实没有缓存，Classic 后来完成了网络获取。分别观察香港和国内网关的重定向，公开输出仅保留主机和路径：

```text
status 302 origin nipaplay.aimes-soft.com redirect-host cas2.dandanplay.net redirect-path /api/comment/178640001 type None
status 302 origin 43.142.85.190 redirect-host cas2.dandanplay.net redirect-path /api/comment/178640001 type None
```

本次重现的 302 是合法 CDN 跳转；没有实验 7 当时的 Location 原始证据，不能断言历史上所有 302 都相同，也不能仅凭状态码判为校园网拦截。

修复后，用 refresh=true 在最终构建中再次通过 Agent 获取，没有使用 Classic 缓存替代新请求。真实回执字段：

```json
{"state":"succeeded","receipt":{"verification":"verified","details":{"status":"complete","complete":true,"loaded":false,"partial":false,"rawCount":615,"cachedUniqueCount":615,"bindingId":"danmaku-142b498b-4021-4062-aa18-165757b95ee2"}}}
```

615 与 Classic 的 584 分别是来源记录数量和 Classic 显示去重后的数量；任务没有把 loaded=false 写成正在播放。

然后注销账号，强制刷新同一绑定。本次请求被现有认证门禁拒绝，任务失败，原绑定缓存仍在：

```json
{"state":"failed","receipt":{"verification":"acknowledged","details":{"status":"authenticationRequired","complete":false,"loaded":false,"acquisitionSucceeded":false,"available":{"classicCache":{"present":true,"count":584},"assignedCache":{"cacheKey":"danmaku-cache-dff4570214e0238a526e19169971c5f18f21b18239a1230be08a22e99401352d","count":615},"attemptedCache":{"cacheKey":"danmaku-cache-57d56177ed64b148d13f1115d39391bf1acb5e1f8e7c3df093686f645cacb918","count":0},"player":{"loaded":false,"count":0,"tracks":[]}}}}}
```

随后的 danmaku.tracks 查询确认同一绑定的 cacheKey 没有变化、coverage 仍在、loaded=false，与失败回执一致。旧绑定和缓存没有被失败的新请求覆盖。另有回归检查覆盖 already-loaded=true、已有缓存以及完全无缓存的失败分支。

### 自动化约束检查与限制

```sh
~/development/flutter-3.44.6/bin/flutter test --no-pub \
  test/next/accounts_test.dart test/next/media_sources_test.dart \
  test/next/danmaku_receipt_test.dart test/next/danmaku_source_test.dart \
  test/next/next_core_test.dart test/next/danmaku_flow_test.dart \
  test/next/danmaku_registry_test.dart test/next/danmaku_runtime_binding_test.dart
```

```text
00:01 +54: All tests passed!
```

检查覆盖：登录秘密不进入任务或 journal、重启不重放秘密；Bangumi 批量更新保留未指定字段和逐项请求失败；失败刷新不替换缓存/播放器数据；跨主机 CDN 重定向不发送账号 Authorization；原有身份、任务、来源、弹幕绑定回归。

Bangumi 使用本测试创建的回环 HTTP fixture，经真实 Classic 服务验证 token 登录/注销、收藏状态、评分和剧集已看读回。它不是真实 Bangumi 网站。没有提供真实 Bangumi 测试令牌，因此全量远程同步未做真实账号实验；实现复用 Classic 同步，没有宣称逐集远端状态已被独立验证。

修改的账号、来源、弹幕目录、Core 和相关测试静态检查：

```text
No issues found! (ran in 5.1s)
```

完整本地检查日志为 `/tmp/nipa-next/x14-regression-final.log`、`x14-analyze-final.log`、`x14-build-final.log`。git diff --check 通过。

意外：windowed 启动设置会触发现有 screen_retriever 对多视图执行 Iterable.single 的异常，实验改用默认 maximized 设置；未修改该无关启动路径。MDK 播放后，实验实例两次出现回环调用迟迟不返回，后一次 pause 请求 65 秒超时。按 PID 重启后账号、弹窗及缓存实验恢复可调用；没有把超时期间的 loaded=true 失败回执算作真实验证，也没有改播放器内核。原始 Classic 加载 584 条、修复后任务获取 615 条和未播放时保留缓存的失败回执都有独立成功输出。

### 脱敏与清理

对本实验偏好、SQLite、journal 和两次应用日志逐字节检查用户提供的密码与实际会话令牌，均未出现。保险库及 endpoint 凭据文件属于预期秘密存储，未发布；公开 receipts 再次通过密码/令牌检查。

```text
X14 plaintext scan preferences.json noPasswordOrToken= True
X14 plaintext scan next.db noPasswordOrToken= True
X14 plaintext scan journal.jsonl noPasswordOrToken= True
X14 plaintext scan x14-app.log noPasswordOrToken= True
X14 plaintext scan x14-app-final.log noPasswordOrToken= True
X14 public receipts written; no supplied password or token= True
X14 cleanup: processStopped=true profileDeleted=true temporaryAdminCredentialDeleted=true
```

所有实验应用进程已经结束，`x14-accounts-20261011` 整个实验目录已经删除，临时管理员凭据文件已删除。只保留脱敏公开证据和检查日志。没有 commit 或 push。

## 4. 需要主控决定的问题

是否另立任务调查 MDK 播放后的回环请求超时，以及 windowed 启动时 screen_retriever 的多视图异常。这两项不阻止本批账号、Quick Connect、登录路由与弹幕请求/缓存回执交付，但本次没有改它们。其余本批接口与实现没有待决策问题。
