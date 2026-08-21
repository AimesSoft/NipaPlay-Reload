# 跨平台存储目录

NipaPlay 通过 `StorageService` 统一确定应用数据及缓存目录. 业务代码应调用
该服务获取路径, 不要自行拼接平台目录.

## 应用数据根目录

`StorageService.getAppStorageDirectory()` 按以下规则选择根目录:

| 平台    | 目录规则                                                                |
| ------- | ----------------------------------------------------------------------- |
| Linux   | `${XDG_DATA_HOME}/NipaPlay`; 未设置时为 `~/.local/share/NipaPlay`       |
| Android | 优先使用可访问的用户自定义目录, 否则使用外部应用存储目录下的 `NipaPlay` |
| iOS     | `getApplicationDocumentsDirectory()` 返回的 Documents 目录              |
| macOS   | Documents 目录下的 `nipaplay`                                           |
| Windows | Documents 目录下的 `nipaplay`                                           |

Android 外部存储不可用, 目录不可访问或其他平台目录解析失败时, 会回退到
`getApplicationDocumentsDirectory()`; 除 iOS 外, 正常情况下会在其下创建
`nipaplay` 子目录.

Linux 会优先读取 `XDG_DATA_HOME`. 如果未设置, 则使用 `HOME` 计算默认路径.
无法创建 XDG 目录时才会最终回退到 Documents 目录.

## 主要目录结构

以下目录会在应用数据根目录下由 `StorageService` 按需创建:

```text
<应用数据根目录>/
├── cache/ # 缓存根目录
│   ├── danmaku/ # 弹幕 JSON 缓存
│   ├── dandanplay/ # 弹弹play动画与剧集信息缓存
│   └── bangumi/ # Bangumi动画与剧集信息缓存
├── temp/        # 临时文件
├── downloads/ # 默认下载目录
└── videos/ # 默认视频目录
```

数据库, 日志, 图片缓存, 插件数据等模块也可能直接在应用数据根目录下创建
自己的文件或子目录, 因此实际内容可能比上表更多.

## 缓存根目录

所有平台的通用缓存入口为 `StorageService.getCacheDirectory()`:

```text
<应用数据根目录>/cache
```

例如弹幕缓存位于:

```text
<应用数据根目录>/cache/danmaku
```

部分模块目前直接在应用数据根目录中维护自己的缓存子目录. 例如图片缓存可
使用 `<应用数据根目录>/compressed_images`, 不一定全部位于通用 `cache`
目录下.

### Linux XDG 缓存目录

项目也提供了 `LinuxStorageMigration.getXDGCacheDirectory()`, 其路径为:

```text
${XDG_CACHE_HOME}/NipaPlay
```

未设置 `XDG_CACHE_HOME` 时默认为:

```text
~/.cache/NipaPlay
```

但当前通用缓存入口并未使用该目录. Linux 上实际返回的是
`${XDG_DATA_HOME}/NipaPlay/cache`, 默认即
`~/.local/share/NipaPlay/cache`.

## Android 自定义目录

Android 支持通过设置保存自定义存储路径. 启动时会检查目录是否存在且可读;
检查通过后, 该目录会直接成为应用数据根目录. 清除或无法访问自定义路径后,
程序会继续尝试外部应用存储目录.

## 获取实际路径

代码中应通过 `StorageService` 获取目录, 不要自行拼接平台路径:

```dart
final dataDir = await StorageService.getAppStorageDirectory();
final cacheDir = await StorageService.getCacheDirectory();

debugPrint('数据目录: ${dataDir.path}');
debugPrint('缓存目录: ${cacheDir.path}');
```

当前数据目录, 缓存目录以及 Linux 的 XDG 环境变量也可在应用的开发者选项
中查看.

## 相关实现

- `lib/utils/storage_service.dart`
- `lib/utils/linux_storage_migration.dart`
- `lib/utils/macos_storage_migration.dart`
- `lib/utils/android_storage_helper.dart`
- `lib/services/danmaku_cache_manager.dart`
