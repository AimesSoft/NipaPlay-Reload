# 技能：投影媒体流的"文件名"必须穿透到播放层

## 背景
TV 版媒体库加载弹弹远程服务后能列出 1248 条、137 个番剧，但播放页弹幕恒为"0 条弹幕"。
诊断日志（`[TVDanmaku]`）一开始**完全没有输出**，说明匹配链路从未执行。

## 根因
远程流播放地址是投影服务生成的流地址：
```
playUri: http://192.168.3.39:30000/api/v1/stream/id/3b01018c-b649-...
```
播放页从 `playUri` 推导"文件名"得到的是 **UUID**，弹弹网关按 `fileName` 匹配自然永远失败。
而**真实文件名**（`Kill la Kill 01 [BD 1920x1080 HEVC-10bit AAC ASSx2].mkv`）与 `hash`
一直存在于远程库条目里（`Name` / `Hash`），只是没传到播放页。

## 方案
在数据链路里显式传递媒体身份字段：
1. `TvLibraryEpisode` 增加 `fileName` / `fileHash`，构造时透传 `e.name` / `e.hash`；
2. `TvPlayerPage` 增加同名入参；
3. 详情页打开播放页时透传；
4. 匹配请求使用 `matchMode: 'hashAndFileName'`（hash 失败时仍可按文件名匹配）。

播放页对 `fileName` 做兜底：为空时退回 URI 末段。

## 验证
- 网关探针：`curl -H "Authorization: Bearer fake" .../api/v2/match?...` 返回
  `{"errorCode":401,"errorMessage":"弹弹play登录已失效"}` 而非 404 → 端点存在、鉴权生效。
- 修复后 logcat 应打出 `match POST ... file=Kill la Kill 01...`、`match HTTP 200`、
  `comment HTTP 200`、`加载 N 条弹幕`。
- 单元测试：16/16（含焦点断言与网格列数）通过。

## 适用场景
- 任何"投影/流地址"（dandanplay remote、Emby/Jellyfin 直链、WebDAV 流）做弹幕/字幕匹配；
- 需要把服务端条目身份（文件名、hash、size）穿透到播放层的场景；
- **教训**：流地址不等于媒体身份，二者必须在模型里分离。
