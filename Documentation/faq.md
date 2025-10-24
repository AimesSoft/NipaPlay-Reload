# 常见问题（FAQ）

以最短答案直达问题核心，详细步骤请跳转到对应章节。

## 安装与启动

- Windows 被 Defender 拦截
	- 点击“更多信息 → 仍要运行”。
- iOS 安装问题（App Store、TestFlight、侧载）
	- 推荐优先使用 [App Store](https://apps.apple.com/cn/app/nipaplay/id6751284970) 或 [TestFlight](https://testflight.apple.com/join/4JMh3t44)；侧载请参考[安装指南 - iOS](installation.md#ios)。

## 播放与性能

- 启动后黑屏/无声/卡顿
	- 见[故障排查](troubleshooting.md)；可先尝试切换内核、更新驱动、启用硬解。
- 用哪个播放器内核最好？
	- 推荐使用 Libmpv；差异与取舍见[高级设置 - 播放器内核选择](settings.md#播放器内核选择)。

## 资源获取

- 在哪里可以找到动漫资源？
	- NipaPlay 是本地播放器，不提供任何资源。您可以前往 [蜜柑计划](https://mikanani.me/) 等资源站寻找合法动漫资源。
- 如何部署自己的媒体服务器？
	- 推荐使用 Jellyfin 或 Emby，详细部署指引见[媒体服务器整合 - 服务器部署](server-integration.md#服务器部署)。

## 服务器整合（Emby/Jellyfin/NipaPlay）

- 无法连接、403 Forbidden、或认证失败
	- 连接步骤与常见错误见[媒体服务器整合](server-integration.md)。403 多由服务器端限制导致，需联系管理员放行客户端。
- 媒体库类型支持吗？
	- 仅支持"电影/剧集"库类型；详情见[媒体服务器整合 - 媒体库要求](server-integration.md#媒体库要求)。
- 初次选择媒体库很慢
	- 大库初次加载耗时较长，完成后会缓存；说明见[媒体服务器整合](server-integration.md#性能考虑)。
- 选择了媒体库但没有生效
	- 选择媒体库后必须滑动到页面底部点击"保存"按钮，否则设置不会生效；详情见[安装后设置](post-install.md)。
- NipaPlay 局域网共享无法连接
	- 确保两台设备在同一局域网内；检查防火墙设置；确认目标设备已开启远程访问功能。

## 弹幕与字幕

- 弹幕显示异常/需要调整效果
	- 请查看[高级设置 - 弹幕引擎配置](settings.md#弹幕引擎配置)。
- 弹幕匹配错误怎么办？
	- 可在播放界面手动匹配弹幕；详情见[使用指南 - 弹幕与字幕](user-guide.md#弹幕与字幕)。
- Windows系统下PGS/SUP字幕不能显示
	- 请参考[高级设置 - Windows 平台解码器优化](settings.md#windows-平台解码器优化)。

## 账号与同步

- 如何登录弹弹play账号？
	- 在设置→账号→弹弹play账户中输入用户名和密码登录；支持观看同步、评分和发送弹幕功能。
- Bangumi同步如何设置？
	- 访问[bgm.tv访问令牌页面](https://next.bgm.tv/demo/access-token)创建令牌，然后在设置→账号→Bangumi同步中配置；支持同步观看记录、评分和短评。
- 为什么观看记录没有同步？
	- 检查网络连接；确认账号登录状态；查看设置中是否开启了自动同步功能。
- 如何在Bangumi上写短评？
	- 在动画详情页面点击评分按钮，在弹出的对话框中可以编写短评；短评会同步到Bangumi收藏中。

## 故障与恢复

- Windows：有进程但不出界面（断电后）
	- 原因与一键修复见[故障排查 - 意外断电后无法启动](troubleshooting.md#意外断电后无法启动-nipaplay（windows）)。
- 如何导出日志反馈问题？
	- 步骤与注意事项见[故障排查 - 获取日志](troubleshooting.md#获取日志)。

---

**⬅️ 上一篇: [高级设置](settings.md)** | **➡️ 下一篇: [故障排查](troubleshooting.md)**
