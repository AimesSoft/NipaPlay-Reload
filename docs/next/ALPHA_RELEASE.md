# Next Alpha 1 发布与候选流程

首版版本号：`2.0.0-alpha.1`，GitHub 标签：`v2.0.0-alpha.1`。
从 `next` 的同一个已提交 revision 构建。公开发布使用 CI 产物；本地工作目录的
开发签名、未提交修改和个人配置不作为公开发行包。

## 平台与安装方式

| 平台 | 当前构建流程 | 分发与验收要求 |
| --- | --- | --- |
| macOS arm64 / x86_64 / universal | build-macos.yml | 签名、公证后的 DMG/ZIP；检查签名与首次启动 |
| Windows x64 | build-windows.yml | ZIP/安装程序；安装、覆盖更新与防火墙/播放检查 |
| Linux amd64 / arm64 | build-linux.yml | 流程实际生成的 DEB/AppImage/TAR/RPM；干净系统启动、原生库与播放检查 |
| iOS / iPadOS | build-ios.yml | 共用 iOS 构建；当前 release-iOS 为未签名 IPA，需要用户自行签名侧载 |
| Linux headless amd64 / arm64 | build-headless.yml | AOT + 原生库 TAR；启动、加入组网、目录及 Range 文件读取 |

本次 Next Developer Preview 不分发 Android、tvOS 或 HarmonyOS；移动端仅包含 iPhone/iPad。HarmonyOS 的现有播放器 fork 尚不能编译 Next 接口。
iOS/iPadOS 的无签名 IPA 不代表 TestFlight 已准备好。TestFlight 需要独立验证
签名 archive、合法的 Apple 数字版本/递增构建号、App Store Connect 上传和测试组；
不要为 alpha 自动提交 App Store 审核。

## 本次直接发布

本次用户选择从 `next` 的已提交 revision 运行 `main.yml`，直接构建并公开 GitHub prerelease，版本为 `v2.0.0-alpha.1`，定位为 Developer Preview。`submit_ios_for_review=false`；Next 预发布不分发 Android、tvOS 或 HarmonyOS。流程的成功与各平台产物、实机验收须分别确认；启动工作流不代表发布已成功。

包含 Android/tvOS 的旧运行 [Actions #40560045637](https://github.com/AimesSoft/NipaPlay-Reload/actions/runs/40560045637) 已取消。当前运行请查看 [Build & Release 的 next 分支记录](https://github.com/AimesSoft/NipaPlay-Reload/actions/workflows/main.yml?query=branch%3Anext)，以该运行的 SHA 为发行源码。CI 将使用 [DEVELOPER_PREVIEW.md](DEVELOPER_PREVIEW.md) 作为预发布正文并命名 Developer Preview；完成后核对标签、prerelease 标记和实际附件。

## 可供未来使用的独立候选流程

1. 提交修复、锁定依赖，记录 `next` 的准确 SHA。
2. 运行 `build-all-manual.yml`，明确选择 `next`；该流程只上传 Actions artifacts。
3. 所有支持平台成功后，下载同一次 run 的 `release-*` 与 `candidate-manifest`。
   清单记录 SHA、版本、各文件大小及 SHA256；符号文件单独留在 Actions 中。
4. 校验 `SHA256SUMS`，逐平台记录“构建通过”与“实机通过”，二者分别记录。
5. 从这些已验证产物准备 GitHub **draft + prerelease**，目标为清单中的 SHA，
   附安装方式、测试范围、数据目录与已知问题。审核后再将 draft 公开。
   同一候选升级发布时沿用原产物，避免重新构建后失去验收对应关系。

`main.yml` 是直接构建并公开 Release 的现有流程；直接发布不会自动完成独立候选验收。
Next 的更新检查查询公开的 2.x+ 预发布版本，按 SemVer 比较 alpha/beta/正式版；
Classic 继续使用稳定版更新入口。

## 发布前必查

- 本地与 Mesh 远端视频能播放，Range/定位和进度续播正常；另一端重启后目录恢复。
- 丰富演职员资料能同步，不因消息大小把在线设备误判离线；旧缓存 ID 能重映射。
- Classic 识别已有文件后不新建平行作品；同文件身份复用有审计，真实冲突仍拒绝。
- 作品详情能看到各来源评分、演员/角色声优、制作信息与文件技术信息；缺项明确。
- 更新前后媒体、身份、弹幕、登录和个人 harness 保留；只轮换一份应用回退。
- 关于页给出语义版本、构建号、提交、运行架构与环境，可复制到反馈中。
- 首次启动不携带开发者账号、模型密钥、组网身份或个人路径。

## 反馈信息

请附关于页“复制诊断信息”、平台、来源类型、本地或远端、播放内核、复现步骤、
预期和实际结果。日志按需另附；诊断复制按钮只含构建及运行环境事实。

当前尚不能以 Mac/Windows 的本轮结果宣称所有平台已经实机验收。
