# 媒体来源

来源能力复用 Classic 的配置、保险库与客户端，注册在 NextCore。
`media.sources.list` 不联网、不读取凭据；`check` 显式验证一个来源。
`media.sources.search {query,sourceIds?,limit?}` 只读搜索；Jellyfin/Emby 经原客户端
的有界服务器 SearchTerm，SMB/WebDAV 仅查已有文件索引，不枚举或登记新文件。
每个来源独立返回 entries/total 或 error，错误时 total=null；共享保留索引结果，
connected/unverified/failed 表示最近连接观察，未知不是在线。来源默认每组最多 12。
已绑定条目带 Next workId/episodeId；服务器未绑定条目给原样 sourceWorkId/
sourceEpisodeId，共享未绑定文件用 media.sources.play {sourceId,itemId}。
搜索条目另带本机缓存 `poster` 和已绑定作品的 `workTitle`，无缓存为 null，搜索不下载图片。
`media.sources.artwork {sourceId,itemId}` 显式懒加载海报，经 X48 的原认证客户端落到
本机缓存后只返回路径，不返回带认证的地址。宿主未接入图片供应者则返回 unavailable。
能力族契约见 `nipa describe media.sources`，界面接线见 `docs/next/X56_REPORT.md`。
`add/update` 配置地址与用户名，`login` 独立发起登录。

登录默认选择 Jellyfin Quick Connect（启用时），否则打开应用内密码窗口。
密码只在 NipaPlay 的登录窗口输入；能力不接受密码。回执只返回方法和 jobId。
Quick Connect 另返回 code，批准等待、同步都使用现有 tasks.wait/cancel。
验证码批准期限十分钟；窗口取消也会取消任务。

`libraries/select` 管理同步选择，`browse` 完整发现服务器新内容。
Jellyfin/Emby parentId 为远端库/文件夹/系列/季 ID；recursive=true 返回可播放条目。
SMB/WebDAV parentId 为来源内目录路径。共享来源省略 parentId 列作品，
整数为作品 ID，其他值为远端宿主目录路径（包括 Windows 路径）。
`sync` 递归发现所选库，登记统一文件索引，保留缺失文件和所有绑定。
传 `parentIds` 可从指定库或目录开始；`scrape` 则调用 Classic 的 WebDAV/SMB
远程字节识别，保留进度，并迁移已解除匹配记录的进度。

`dandanplay_remote` 是 Classic 的单一弹弹play远程来源，支持配置、用户登录、
刷新、浏览与播放。`play(sourceId,itemId)` 在应用内部解析地址，保留共享续播上下文。
`addresses` 批量管理 Jellyfin/Emby 备用地址、优先级与连通性。
`remote_admin.status/folders/connections` 复用 Classic 共享客户端管理对端目录和连接。
`browse` 支持搜索与排序，`sort` 保存 Jellyfin/Emby 库的 Classic 排序偏好。
来源与对端目录移除只删配置，不删硬盘文件，不需要确认。

`sync.status/configure/login/enable/test/run` 是 WebDAV 多端增量同步原语，
与来源文件发现的 `media.sources.sync` 分开。配置采用 patch，修改地址或用户名
会清除旧凭据。启用、停用、登录、立即同步返回任务回执，设置历史记录调用来源。
`sync.status.hasPassword` 只说明是否有已保存密码，不读回秘密。

文件定位与 Classic 一致；发现不创建观看历史或推断作品身份。
Next 索引按 `sourceId` 隔离远程位置，Jellyfin/Emby 另包括实际 serverId；同类两台服务器即使返回相同 item ID，也得到不同
`fileId`。绑定时使用此 fileId，播放时继续使用原 path。无来源归属的旧记录保留为独立证据。
完整 schema 以实时 Harness 列表为准。实现及实验见 docs/next/X12_REPORT.md。

X48 的片库入口为 `core.libraryData/libraryActions`，能力为 `ui.library.*`，见
`../ui_data/README.md`。原样浏览复用上述客户端，Jellyfin/Emby 使用独立单页
catalogPage，不改变 Classic 的完整 browseCatalog；库排序读取 Classic 保存的偏好。
原样作品和剧集 ID 包含配置及实际服务器身份，图片下载仍由原认证客户端完成。
未绑定条目和条件中的已绑定条目最终都调用同一个 `MediaSourcesService.play`
（现有 `media.sources.play` 的实现），不靠当前激活服务器猜测来源。
