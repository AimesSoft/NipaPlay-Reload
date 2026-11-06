# Next 发布流程

官方发布统一从 `next` 分支运行 GitHub Actions 的 **Build & Release (Modular)**，填写 `release_title`（`YYYY.MMDD`）。需要更新 TestFlight 时启用 `upload_ios_testflight`；Next 不自动提交 App Store 审核。

## 内置资料源凭据

仓库 Actions Secret `NIPAPLAY_TMDB_TOKEN` 保存应用内置的 TMDB API key 或 Read Access Token。不得把值写入源码、发行说明或构建日志。

发布入口在开始编译前验证凭据存在并通过 TMDB 认证。macOS、Windows、Linux、iOS 和 headless 的构建使用同一凭据；Flutter 通过临时 defines 文件传入，headless 通过 Dart 编译参数传入。各平台在打包前检查编译后的 Dart 二进制确实包含配置的凭据。官方 `next` 构建缺凭据时失败；本地和 fork 的诊断构建可以不内置凭据。

构建成功、应用能启动和外部资料源配置完整是分别检查的事项。运行时用户自行配置的 TMDB 凭据仍优先于内置凭据。

## 发布与补发

全部平台构建以及 macOS ARM / Intel 启动检查通过后，流程将安装包发布为 Prerelease。Next 不替换 Classic 的 Latest。源码 SHA 与构建信息随包记录。

如果只因 GitHub 发布或运行器故障中断，可使用 **macOS Compatibility** 的 `artifact_run_id` 和 `publish_next` 复用已构建的包。补发要求原构建完成内置凭据检查。编译参数缺失、依赖或源码需要修正时，必须重新构建，不能复用旧包。
