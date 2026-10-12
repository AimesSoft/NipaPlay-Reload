# 技能：弹弹play 网关鉴权与请求格式（TV/服务端通用）

## 背景
TV 版排行榜曾持续 401，弹幕匹配请求（GET 查询参数）无效。用户换镜像地址也无效——
因为**这是账号鉴权，不是域名问题**。

## 事实（全部经 curl 实测）
| 场景 | 响应 |
|---|---|
| `/api/v2/*` 无 token | `{"errorCode":401,"errorMessage":"请先登录弹弹play账号后再使用弹弹play服务"}` |
| 带假 token | `{"errorCode":401,"errorMessage":"弹弹play登录已失效，请重新登录"}` |
| 正确 token | 200 |

**两种 401 的区别就是探针**：改从"请先登录"变成"登录已失效"即证明鉴权头路径正确。

## 请求格式（与手机版 `DandanplayService` 完全一致）
```
登录：POST {gateway}/api/v2/login
  header: X-AppId: nipaplayv1, X-Timestamp: <unix秒>, X-Signature: base64(sha256(appId+ts+path+appSecret))
  body:   {userName, password, appId, unixTimestamp, hash: md5(appId+password+ts+userName+appSecret)}
  appSecret = "server-managed"（core: DandanplayAuth.getAppSecret）

排行：GET  {gateway}/api/v2/trending/{维度}          header: Authorization: Bearer <token>
匹配：POST {gateway}/api/v2/match                    签名头同上 + body {fileName, fileHash, fileSize, matchMode:"hashAndFileName"}
弹幕：GET  {gateway}/api/v2/comment/{episodeId}?withRelated=true&chConvert=0   签名头同上

凭据键（与手机版共享，两版登录态互认）:
  dandanplay_token / dandanplay_username / dandanplay_logged_in
```
p 字段格式：`时间,模式,颜色,uid`（**颜色在索引 2**，不是 3）。

## 适用场景
TV 版任何走弹弹网关的请求（排行/详情/评论/匹配/弹幕）；给第三方做接口联调时的对照表。
