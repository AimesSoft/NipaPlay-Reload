# 媒体来源

来源能力复用 Classic 的配置、保险库与客户端，注册在 NextCore。
`media.sources.list` 不联网、不读取凭据；`check` 显式验证一个来源。
`add/update` 配置地址与用户名，`login` 独立发起登录。

登录默认选择 Jellyfin Quick Connect（启用时），否则打开应用内密码窗口。
用户主动提供密码时可传 secret 字段 `password`；回执只返回方法和 jobId。
Quick Connect 另返回 code，批准等待、同步都使用现有 tasks.wait/cancel。
验证码批准期限十分钟；窗口取消也会取消任务。

`libraries/select` 管理同步选择，`browse` 完整发现服务器新内容。
Jellyfin/Emby parentId 为远端库/文件夹/系列/季 ID；recursive=true 返回可播放条目。
SMB/WebDAV parentId 为来源内目录路径。共享来源省略 parentId 列作品，
整数为作品 ID，其他值为远端宿主目录路径（包括 Windows 路径）。
`sync` 递归发现所选库，登记统一文件索引，保留缺失文件和所有绑定。

文件定位与 Classic 一致；发现不创建观看历史或推断作品身份。
完整 schema 以实时 Harness 列表为准。实现及实验见 docs/next/X12_REPORT.md。
