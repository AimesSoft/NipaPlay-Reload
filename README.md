<div style="display: flex; align-items: center; justify-content: center;">
  <img src="https://github.com/user-attachments/assets/5366a99f-8906-4198-b2cf-2553252c0fb4" height="100" style="margin-right: 20px;">
  <img src="macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png" height="100">
</div>

# NipaPlay-Reload

<div align="center">
  <img src="https://count.getloli.com/get/@nipaplay?theme=moebooru" alt="访问统计" />
</div>

<div align="center" style="margin: 10px 0;">
  <img src="https://img.shields.io/github/downloads/mcdfsteve/nipaplay-reload/total?style=for-the-badge&logo=github&label=总下载量&color=brightgreen" alt="下载统计">
  <img src="https://img.shields.io/badge/QQ群-701184841-12B7F5?style=for-the-badge&logo=tencentqq&logoColor=white" alt="QQ群">
  <img src="https://img.shields.io/badge/番剧-追番中-ff69b4?style=for-the-badge&logo=anilist" alt="追番状态">
  <img src="https://img.shields.io/badge/弹幕-密集-ff6b6b?style=for-the-badge&logo=wechat" alt="弹幕密度">
  <img src="https://img.shields.io/badge/播放器-高性能-ffa500?style=for-the-badge&logo=flutter" alt="播放器性能">
  <img src="https://img.shields.io/badge/主题-可切换-ffd700?style=for-the-badge&logo=materialdesign" alt="主题切换">
  <img src="https://img.shields.io/badge/字幕-多轨道-4169e1?style=for-the-badge&logo=substack" alt="字幕支持">
  <img src="https://img.shields.io/badge/音频-多轨道-2e8b57?style=for-the-badge&logo=spotify" alt="音频支持">
</div>

<div align="center" style="margin: 10px 0;">
  <img src="https://img.shields.io/badge/Windows-0078D6?style=for-the-badge&logo=windows&logoColor=white" alt="Windows">
  <img src="https://img.shields.io/badge/macOS-000000?style=for-the-badge&logo=apple&logoColor=white" alt="macOS">
  <img src="https://img.shields.io/badge/Linux-FCC624?style=for-the-badge&logo=linux&logoColor=black" alt="Linux">
  <img src="https://img.shields.io/badge/Android-3DDC84?style=for-the-badge&logo=android&logoColor=white" alt="Android">
  <img src="https://img.shields.io/badge/iOS-000000?style=for-the-badge&logo=ios&logoColor=white" alt="iOS">
</div>

<div align="center" style="margin: 10px 0;">
  <img src="https://api.star-history.com/svg?repos=mcdfsteve/nipaplay-reload&type=Date&theme=moebooru" alt="Star History Chart">
</div>

> NipaPlay使用Flutter的再次重写，一个现代化的视频播放器应用。支持 Windows、macOS、Linux、Android 和 iOS 五大操作系统，为用户提供跨平台的统一体验。

## 📸 应用截图

<div align="center">
  <p><strong>主界面</strong></p>
  <img src="others/主界面.png" width="80%" alt="主界面">
  
  <p><strong>新番更新界面</strong></p>
  <img src="others/新番更新界面.png" width="80%" alt="新番更新界面">
  
  <p><strong>新番详情界面</strong></p>
  <img src="others/新番详情界面.png" width="80%" alt="新番详情界面">
  
  <p><strong>播放界面</strong></p>
  <img src="others/播放界面.png" width="80%" alt="播放界面">
  
  <p><strong>播放界面UI展示</strong></p>
  <img src="others/播放界面-UI展示.png" width="80%" alt="播放界面UI展示">
</div>

## ✨ 已实现功能

- 🎬 **视频播放**
  - 支持本地视频文件播放
  - 支持弹幕显示（集成弹弹play）
    - 滚动弹幕、顶部弹幕、底部弹幕
    - 弹幕记忆运动轨迹
    - 时间轴跳转时弹幕位置同步
    - 弹幕轨道管理系统
    - 合并弹幕显示
    - 开关弹幕覆盖
  - 字幕支持
    - 支持 ASS、SRT 格式字幕
    - 支持内嵌字幕和外挂字幕
    - 支持多字幕轨道切换
    - 支持字幕样式自定义
  - 音频支持
    - 支持多音频轨道切换
  - 视频信息自动匹配
  - 播放进度记忆

- 📺 **番剧管理**
  - 新番时间表展示
  - 按星期分类显示
  - 番剧详情查看
    - 日文简介支持翻译成中文（ChatGPT4omini）
  - 图片缓存管理
  - 历史记录同步

- ⚙️ **设置中心**
  - 毛玻璃设计风格，提供现代感界面
  - 主题模式切换（亮色/暗色）
  - 背景图片自定义更换
  - 快捷键自定义
  - 账户设置
  - 关于页面

## 🚀 开发进度

> 持续开发中，欢迎关注 Releases 获取最新版本

## 📋 待加入功能

- 🎯 **字幕增强**
  - 外挂字幕文件支持
  - 字幕样式自定义
  - 字幕位置调整
  - 字幕大小调节

- 🎨 **界面优化**
  - 更多主题样式
  - 自定义播放器皮肤
  - 动画效果增强

- 🔄 **功能扩展**
  - 播放列表管理
  - 视频收藏功能
  - 云存储支持

- 🔊 **音频增强**
  - 音频延迟调整

## 📦 使用的第三方库

- **核心功能库**
  - [fvp](https://pub.dev/packages/fvp) - 高性能视频播放器
  - [http](https://pub.dev/packages/http) - HTTP 请求处理
  - [crypto](https://pub.dev/packages/crypto) - 加密功能

- **UI 相关**
  - [glassmorphism](https://pub.dev/packages/glassmorphism) - 毛玻璃效果
  - [hugeicons](https://pub.dev/packages/hugeicons) - 图标库
  - [kmbal_ionicons](https://pub.dev/packages/kmbal_ionicons) - 图标库

- **文件处理**
  - [file_picker](https://pub.dev/packages/file_picker) - 文件选择器
  - [path_provider](https://pub.dev/packages/path_provider) - 路径提供
  - [path](https://pub.dev/packages/path) - 路径处理
  - [image_picker](https://pub.dev/packages/image_picker) - 图片选择器
  - [image](https://pub.dev/packages/image) - 图片处理

- **状态管理**
  - [provider](https://pub.dev/packages/provider) - 状态管理
  - [synchronized](https://pub.dev/packages/synchronized) - 同步控制

- **数据存储**
  - [shared_preferences](https://pub.dev/packages/shared_preferences) - 本地存储

- **网络相关**
  - [cached_network_image](https://pub.dev/packages/cached_network_image) - 网络图片缓存

- **系统功能**
  - [window_manager](https://pub.dev/packages/window_manager) - 窗口管理
  - [package_info_plus](https://pub.dev/packages/package_info_plus) - 包信息
  - [url_launcher](https://pub.dev/packages/url_launcher) - URL 启动器

- **开发工具**
  - [flutter_lints](https://pub.dev/packages/flutter_lints) - 代码检查

## 🛠️ 技术栈

- Flutter
- Dart
- fvp 播放器
- 弹弹play API
- Bangumi API
## 关于看板娘

- 新的图还没画，暂时使用这张替代：https://www.pixiv.net/artworks/122857380 （作者くしだ）