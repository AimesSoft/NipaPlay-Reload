// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'NipaPlay';

  @override
  String get tabHome => '主页';

  @override
  String get tabVideoPlay => '视频播放';

  @override
  String get tabMediaLibrary => '媒体库';

  @override
  String get tabAccount => '个人中心';

  @override
  String get tabSettings => '设置';

  @override
  String get settingsLabel => '设置';

  @override
  String get toggleToLightMode => '切换到日间模式';

  @override
  String get toggleToDarkMode => '切换到夜间模式';

  @override
  String get language => '语言';

  @override
  String get languageSettingsTitle => '语言设置';

  @override
  String get languageSettingsSubtitle => '选择界面显示语言';

  @override
  String get languageAuto => '自动（跟随系统）';

  @override
  String get languageSimplifiedChinese => '简体中文';

  @override
  String get languageTraditionalChinese => '繁體中文';

  @override
  String currentLanguage(Object language) {
    return '当前：$language';
  }

  @override
  String currentServer(Object server) {
    return '当前：$server';
  }

  @override
  String currentTheme(Object theme) {
    return '当前：$theme';
  }

  @override
  String get languageTileSubtitle => '切换简体中文或繁體中文';

  @override
  String get settingsBasicSection => '基础设置';

  @override
  String get settingsAboutSection => '关于';

  @override
  String get appearance => '外观';

  @override
  String get lightMode => '浅色模式';

  @override
  String get appearanceLightModeSubtitle => '保持明亮的界面与对比度。';

  @override
  String get darkMode => '深色模式';

  @override
  String get appearanceDarkModeSubtitle => '降低亮度，保护视力并节省电量。';

  @override
  String get followSystem => '跟随系统';

  @override
  String get appearanceFollowSystemSubtitle => '自动根据系统设置切换外观。';

  @override
  String get appearancePreviewTitle => '效果预览';

  @override
  String get appearancePreviewFollowSystemDescription => '根据系统外观自动切换浅色或深色模式。';

  @override
  String get appearancePreviewDarkDescription => '使用偏暗的配色方案，适合夜间或弱光环境。';

  @override
  String get appearancePreviewLightDescription => '使用明亮的配色方案，适合日间或高亮环境。';

  @override
  String get appearanceAnimeDetailStyle => '番剧详情样式';

  @override
  String get appearanceDetailSimple => '简洁模式';

  @override
  String get appearanceDetailSimpleSubtitle => '经典布局，信息分栏展示。';

  @override
  String get appearanceDetailVivid => '绚丽模式';

  @override
  String get appearanceDetailVividSubtitle => '海报主视觉、横向剧集卡片。';

  @override
  String get appearanceRecentWatchingStyle => '最近观看样式';

  @override
  String get appearanceRecentSimple => '简洁版';

  @override
  String get appearanceRecentSimpleSubtitle => '纯文本列表，节省空间。';

  @override
  String get appearanceRecentDetailed => '详细版';

  @override
  String get appearanceRecentDetailedSubtitle => '带截图的横向滚动卡片。';

  @override
  String get appearanceHomeSections => '主页板块';

  @override
  String get restoreDefaults => '恢复默认';

  @override
  String get restoreDefaultsSubtitle => '恢复默认排序与显示状态';

  @override
  String get uiThemeExperimental => '主题（实验性）';

  @override
  String get uiThemeRestartHint => '提示：切换主题后需要重新启动应用才能完全生效。';

  @override
  String get uiThemeSwitchDialogTitle => '主题切换提示';

  @override
  String uiThemeSwitchDialogMessage(Object theme) {
    return '切换到 $theme 主题需要重启应用才能完全生效。\n\n是否要立即重启应用？';
  }

  @override
  String get restartApp => '重启应用';

  @override
  String get refreshPageApplyTheme => '请手动刷新页面以应用新主题';

  @override
  String get player => '播放器';

  @override
  String get playerKernel => '播放器内核';

  @override
  String get playerKernelCurrentMdk => '当前：MDK';

  @override
  String get playerKernelCurrentVideoPlayer => '当前：Video Player';

  @override
  String get playerKernelCurrentLibmpv => '当前：Libmpv';

  @override
  String get playerKernelSwitched => '播放器内核已切换';

  @override
  String get playerKernelDescriptionMdk =>
      'MDK 多媒体开发套件，支持硬件解码（默认优先；不支持时回落软件解码）。';

  @override
  String get playerKernelDescriptionVideoPlayer =>
      'Flutter 官方 Video Player，兼容性好。';

  @override
  String get playerKernelDescriptionLibmpv =>
      'MediaKit (Libmpv) 播放器，支持硬件解码与高级特性。';

  @override
  String get externalCall => '外部调用';

  @override
  String get externalPlayerEnabled => '已启用外部播放器';

  @override
  String get externalPlayerDisabled => '未启用外部播放器';

  @override
  String get externalPlayerIntroDesktop => '启用后，所有播放操作将通过外部播放器打开。';

  @override
  String get externalPlayerIntroUnsupported => '仅桌面端支持外部播放器调用。';

  @override
  String get externalPlayerEnableTitle => '启用外部播放器';

  @override
  String get externalPlayerEnableSubtitle => '开启后将使用外部播放器播放视频';

  @override
  String get externalPlayerSelectTitle => '选择外部播放器';

  @override
  String get externalPlayerNotSelected => '未选择外部播放器';

  @override
  String get externalPlayerSelectionCanceled => '已取消选择外部播放器';

  @override
  String get externalPlayerUpdated => '已更新外部播放器';

  @override
  String get desktopOnlySupported => '仅桌面端支持';

  @override
  String get networkSettings => '网络设置';

  @override
  String get networkSettingsSubtitle => '弹弹play 服务器及自定义地址';

  @override
  String get storage => '存储';

  @override
  String get storageSettingsSubtitle => '管理弹幕缓存与清理策略';

  @override
  String get networkMediaLibrary => '网络媒体库';

  @override
  String get mediaServerStatusConnected => '已连接';

  @override
  String get mediaServerStatusDisconnected => '未连接';

  @override
  String get mediaServerInfoServerUrl => '服务器地址';

  @override
  String get mediaServerInfoUsername => '登录用户';

  @override
  String get mediaServerInfoItemCount => '媒体条目';

  @override
  String get mediaServerInfoSelectedLibraries => '已选媒体库';

  @override
  String get mediaServerUnknown => '未知';

  @override
  String get mediaServerAnonymous => '匿名';

  @override
  String get mediaServerViewLibrary => '查看媒体库';

  @override
  String get mediaServerRefresh => '刷新';

  @override
  String get mediaServerManageServer => '管理服务器';

  @override
  String get mediaServerConnectServer => '连接服务器';

  @override
  String get mediaServerDisconnectedHint => '尚未连接此媒体服务器，点击下方按钮完成登录。';

  @override
  String get retry => '重试';

  @override
  String get save => '保存';

  @override
  String get disconnect => '断开连接';

  @override
  String get loadFailed => '加载失败';

  @override
  String loadFailedWithError(Object error) {
    return '加载失败：$error';
  }

  @override
  String operationFailed(Object error) {
    return '操作失败：$error';
  }

  @override
  String saveFailedWithError(Object error) {
    return '保存失败：$error';
  }

  @override
  String connectFailedWithError(Object error) {
    return '连接失败：$error';
  }

  @override
  String refreshFailedWithError(Object error) {
    return '刷新失败：$error';
  }

  @override
  String disconnectFailedWithError(Object error) {
    return '断开失败：$error';
  }

  @override
  String get deviceIdTitle => '设备标识 (DeviceId)';

  @override
  String get deviceIdDescription => '用于 Jellyfin / Emby 区分不同设备，避免互踢登出。';

  @override
  String get deviceIdCurrent => '当前 DeviceId';

  @override
  String get deviceIdGenerated => '自动生成标识';

  @override
  String get deviceIdCustom => '自定义 DeviceId';

  @override
  String deviceIdCustomSet(Object deviceId) {
    return '已设置：$deviceId';
  }

  @override
  String get deviceIdCustomUnset => '未设置（使用自动生成）';

  @override
  String get deviceIdRestoreAuto => '恢复自动生成';

  @override
  String get deviceIdRestoreAutoSubtitle => '清除自定义 DeviceId';

  @override
  String get deviceIdRestoreSuccess => '已恢复自动生成的设备ID';

  @override
  String get deviceIdDialogTitle => '自定义 DeviceId';

  @override
  String get deviceIdDialogHint => '留空表示使用自动生成的设备标识。';

  @override
  String get deviceIdDialogPlaceholder => '例如: My-iPhone-01';

  @override
  String get deviceIdDialogValidationHint => '不要包含双引号/换行，长度不超过128。';

  @override
  String get deviceIdUpdatedHint => '设备ID已更新，建议断开并重新连接服务器';

  @override
  String get deviceIdInvalid => 'DeviceId 无效：请避免双引号/换行，且长度 ≤ 128';

  @override
  String networkServerConnected(Object server) {
    return '$server 服务器已连接';
  }

  @override
  String networkServerSettingsUpdated(Object server) {
    return '$server 服务器设置已更新';
  }

  @override
  String disconnectServerConfirm(Object server) {
    return '确定要断开与 $server 服务器的连接吗？';
  }

  @override
  String networkServerDisconnected(Object server) {
    return '$server 已断开连接';
  }

  @override
  String disconnectServerFailed(Object server, Object error) {
    return '断开 $server 失败：$error';
  }

  @override
  String networkServerNotConnected(Object server) {
    return '尚未连接到 $server 服务器';
  }

  @override
  String networkLibraryRefreshed(Object server) {
    return '$server 媒体库已刷新';
  }

  @override
  String connectServerDialogTitle(Object server) {
    return '连接 $server 服务器';
  }

  @override
  String get serverUrlInputPlaceholder => '例如：http://192.168.1.100:8096';

  @override
  String get inputUsernamePlaceholder => '输入用户名';

  @override
  String get inputPasswordPlaceholder => '输入密码';

  @override
  String get nextStep => '下一步';

  @override
  String get connectAction => '连接';

  @override
  String get testConnection => '测试连接';

  @override
  String get canBeEmpty => '可留空';

  @override
  String get leaveEmptyAutoGenerate => '留空自动生成';

  @override
  String get usernameOptional => '用户名（可选）';

  @override
  String get passwordOptional => '密码（可选）';

  @override
  String get connectFailedCheckCredentials => '连接失败，请检查服务器地址和凭证';

  @override
  String get webdavAddServer => '添加 WebDAV 服务器';

  @override
  String get webdavEditServer => '编辑 WebDAV 服务器';

  @override
  String get webdavEnterAddress => '请输入 WebDAV 地址';

  @override
  String get webdavInvalidUrl => '请输入有效的 URL（http/https）';

  @override
  String get webdavConnection => 'WebDAV 连接';

  @override
  String webdavTestFailedWithError(Object error) {
    return '测试失败：$error';
  }

  @override
  String get webdavTestFailedCheckInfo => '连接测试失败，请检查地址和认证信息';

  @override
  String get webdavTestSuccess => '连接测试成功';

  @override
  String get webdavTestFailed => '连接测试失败';

  @override
  String get webdavSaveFailedCheckInfo => '保存失败，请检查地址和认证信息';

  @override
  String get webdavConnectHint => '连接 WebDAV 服务器后可浏览目录并选择媒体文件夹。';

  @override
  String get webdavConnectionNameOptional => '连接名称（可选）';

  @override
  String get webdavAddress => 'WebDAV 地址';

  @override
  String get smbAddServer => '添加 SMB 服务器';

  @override
  String get smbEditServer => '编辑 SMB 服务器';

  @override
  String get smbEnterHostOrIp => '请输入主机或 IP 地址';

  @override
  String get smbInvalidPortRange => '端口无效，请输入 1-65535';

  @override
  String get smbAnonymousHint => '用户名/密码可留空以匿名访问；支持填写域名。';

  @override
  String get smbHostOrIp => '主机 / IP';

  @override
  String get smbHostOrIpPlaceholder => '例如：192.168.1.10 或 nas.local';

  @override
  String get smbPort => '端口';

  @override
  String get smbDefaultPort445 => '默认 445';

  @override
  String get smbDomainOptional => '域（可选）';

  @override
  String get smbDomainPlaceholder => '例如：WORKGROUP';

  @override
  String get connectJellyfinOrEmbyFirst => '请先连接 Jellyfin 或 Emby 服务器';

  @override
  String get networkMediaLibraryIntro =>
      '在此管理 Jellyfin / Emby 服务器连接，并设置弹弹play 远程媒体库。';

  @override
  String get currentServerNotConnectedHint => '当前服务器未连接，请返回重新选择。';

  @override
  String get loadingRemoteMediaLibrary => '正在加载远程媒体库...';

  @override
  String get noRemoteMediaItems => '暂未获取到远程媒体条目';

  @override
  String recordedAtDate(Object date) {
    return '收录于 $date';
  }

  @override
  String get jellyfinMediaServerTitle => 'Jellyfin 媒体服务器';

  @override
  String get jellyfinDisconnectedDescription => '连接 Jellyfin 服务器以同步远程媒体库与播放记录。';

  @override
  String get embyMediaServerTitle => 'Emby 媒体服务器';

  @override
  String get embyDisconnectedDescription => '连接 Emby 服务器后可浏览个人媒体库并远程播放。';

  @override
  String get dandanRemoteCardTitle => '弹弹play 远程访问';

  @override
  String get dandanRemoteManageAccessTitle => '管理弹弹play远程访问';

  @override
  String get dandanRemoteConnectAccessTitle => '连接弹弹play远程访问';

  @override
  String get dandanRemoteAddressPrompt => '请输入桌面端显示的远程服务地址。';

  @override
  String get dandanRemoteAddressPlaceholder => '例如：http://192.168.1.2:23333';

  @override
  String get dandanRemoteApiTokenOptionalTitle => 'API 密钥（可选）';

  @override
  String dandanRemoteApiTokenPrompt(Object actionLabel) {
    return '如已在弹弹play 桌面端启用 API 验证，请输入对应的密钥；未启用可直接点击$actionLabel。';
  }

  @override
  String get enterApiToken => '请输入 API 密钥';

  @override
  String get optionalApiTokenHint => '可留空，按需填写';

  @override
  String get dandanRemoteStatusSynced => '已同步';

  @override
  String get dandanRemoteStatusConnectFailed => '连接失败';

  @override
  String get dandanRemoteStatusNotConfigured => '未配置';

  @override
  String get unknownErrorOccurred => '出现未知错误';

  @override
  String get dandanRemoteServerAddressLabel => '服务器地址';

  @override
  String get dandanRemoteLastSyncedLabel => '最近同步';

  @override
  String get dandanRemoteAnimeEntries => '番剧条目';

  @override
  String get dandanRemoteVideoFiles => '视频文件';

  @override
  String get dandanRemoteNoRecordsHint => '暂无远程媒体记录，可尝试刷新或确认远程访问设置。';

  @override
  String get dandanRemoteRecentUpdates => '最近更新';

  @override
  String dandanRemoteEpisodeCount(int count) {
    return '共 $count 集';
  }

  @override
  String get dandanRemoteManageConnection => '管理连接';

  @override
  String get dandanRemoteSyncing => '同步中...';

  @override
  String get dandanRemoteRefreshLibrary => '刷新媒体库';

  @override
  String get dandanRemoteDisconnectedHintLong =>
      '通过弹弹play 桌面端开启远程访问后，可在此同步家中电脑或 NAS 上的番剧记录并直接播放。';

  @override
  String get pleaseWait => '请稍候...';

  @override
  String get connectDandanRemoteService => '连接弹弹play 远程服务';

  @override
  String get noRecordYet => '暂无记录';

  @override
  String get justNow => '刚刚';

  @override
  String minutesAgo(int minutes) {
    return '$minutes 分钟前';
  }

  @override
  String hoursAgo(int hours) {
    return '$hours 小时前';
  }

  @override
  String daysAgo(int days) {
    return '$days 天前';
  }

  @override
  String get dandanRemoteConfigUpdated => '弹弹play 远程服务配置已更新';

  @override
  String get dandanRemoteConnected => '弹弹play 远程服务已连接';

  @override
  String get dandanRemoteDisconnected => '已断开与弹弹play远程服务的连接';

  @override
  String get disconnectDandanRemoteTitle => '断开弹弹play远程服务';

  @override
  String get disconnectDandanRemoteContent =>
      '确定要断开与弹弹play远程服务的连接吗？\n\n这将清除保存的服务器地址与 API 密钥。';

  @override
  String get remoteLibraryRefreshed => '远程媒体库已刷新';

  @override
  String get noConnectedServer => '尚未连接任何服务器';

  @override
  String get mediaLibraryNotSelected => '未选择媒体库';

  @override
  String get mediaLibraryNotMatched => '未匹配到媒体库';

  @override
  String mediaLibraryAndCount(Object first, int count) {
    return '$first 等 $count 个';
  }

  @override
  String mediaServerSummary(Object server, Object summary) {
    return '$server · $summary';
  }

  @override
  String serverMediaLibraryTitle(Object server) {
    return '$server 媒体库';
  }

  @override
  String get serverLabel => '服务器';

  @override
  String get accountLabel => '账户';

  @override
  String get mediaLibrary => '媒体库';

  @override
  String get noMediaLibrary => '暂无媒体库';

  @override
  String get checkServerConnection => '请检查服务器连接';

  @override
  String get transcodeSettings => '转码设置';

  @override
  String currentDefaultQuality(Object quality) {
    return '当前默认质量: $quality';
  }

  @override
  String get enableTranscode => '启用转码';

  @override
  String get defaultQuality => '默认清晰度';

  @override
  String get tvShowsLibrary => '电视剧库';

  @override
  String get moviesLibrary => '电影库';

  @override
  String get boxsetsLibrary => '合集库';

  @override
  String get folderLibrary => '文件夹';

  @override
  String get mixedLibrary => '混合库';

  @override
  String get userActivityTitle => '我的活动记录';

  @override
  String get userActivityTabWatched => '观看';

  @override
  String get userActivityTabFavorites => '收藏';

  @override
  String get userActivityTabRated => '评分';

  @override
  String userActivityTabWatchedCount(int count) {
    return '观看($count)';
  }

  @override
  String userActivityTabFavoritesCount(int count) {
    return '收藏($count)';
  }

  @override
  String userActivityTabRatedCount(int count) {
    return '评分($count)';
  }

  @override
  String get userActivityNoWatchedRecords => '暂无观看记录';

  @override
  String get userActivityNoFavorites => '暂无收藏';

  @override
  String get userActivityNoRatings => '暂无评分记录';

  @override
  String get userActivityNotLoggedIn => '未登录弹弹play账号';

  @override
  String userActivityWatchedEpisode(Object episode) {
    return '看到：$episode';
  }

  @override
  String userActivityWatchedUpdatedTime(Object time) {
    return '更新时间：$time';
  }

  @override
  String get userActivityWatchedOnly => '已观看';

  @override
  String userActivityStatusWithValue(Object status) {
    return '状态：$status';
  }

  @override
  String userActivityRatingWithValue(int rating) {
    return '评分：$rating';
  }

  @override
  String get userActivityUnknownTitle => '未知标题';

  @override
  String get ratingLevelMasterpiece => '神作';

  @override
  String get ratingLevelGreat => '很棒';

  @override
  String get ratingLevelGood => '不错';

  @override
  String get ratingLevelAverage => '一般';

  @override
  String get ratingLevelOkay => '还行';

  @override
  String get ratingLevelPoor => '较差';

  @override
  String get ratingLevelVeryPoor => '很差';

  @override
  String get ratingLevelTerrible => '极差';

  @override
  String get favoriteStatusFollowing => '关注中';

  @override
  String get favoriteStatusFinished => '已完成';

  @override
  String get favoriteStatusAbandoned => '已弃坑';

  @override
  String get favoriteStatusFavorited => '已收藏';

  @override
  String get weekdaySunday => '周日';

  @override
  String get weekdayMonday => '周一';

  @override
  String get weekdayTuesday => '周二';

  @override
  String get weekdayWednesday => '周三';

  @override
  String get weekdayThursday => '周四';

  @override
  String get weekdayFriday => '周五';

  @override
  String get weekdaySaturday => '周六';

  @override
  String get newSeriesNoTodayAnime => '本日无新番';

  @override
  String get newSeriesUpdateTimeTbd => '更新时间未定';

  @override
  String get newSeriesSearchDescription => '搜索新番\n按标签、类型快速筛选\n查找你感兴趣的新番';

  @override
  String get newSeriesSortDescriptionAscending => '切换为正序显示\n今天的新番排在最前';

  @override
  String get newSeriesSortDescriptionDescending => '切换为倒序显示\n今天的新番排在最后';

  @override
  String get newSeriesInitializingPlayer => '正在初始化播放器...';

  @override
  String newSeriesPlayerLoadFailedWithError(Object error) {
    return '播放器加载失败: $error';
  }

  @override
  String newSeriesErrorOccurredWithError(Object error) {
    return '发生错误: $error';
  }

  @override
  String newSeriesHandlePlayRequestFailedWithError(Object error) {
    return '处理播放请求时出错: $error';
  }

  @override
  String newSeriesAnimeCount(int count) {
    return '$count 部动画';
  }

  @override
  String get newSeriesRemoteAddressNotConfigured => '未配置远程访问地址';

  @override
  String get newSeriesNetworkTimeout => '网络请求超时，请检查网络连接后重试';

  @override
  String get newSeriesNetworkConnectionFailed => '网络连接失败，请检查网络设置';

  @override
  String get newSeriesServerUnavailableRetryLater => '服务器无法连接，请稍后重试';

  @override
  String get newSeriesServerDataFormatError => '服务器返回数据格式错误';

  @override
  String get developerOptions => '开发者选项';

  @override
  String get developerOptionsSubtitle => '终端输出、依赖版本、构建信息';

  @override
  String get terminalOutput => '终端输出';

  @override
  String get terminalOutputSubtitle => '查看日志、复制内容或生成二维码分享';

  @override
  String get dependencyVersions => '依赖库版本';

  @override
  String get dependencyVersionsSubtitle => '查看依赖库与版本号（含 GitHub 跳转）';

  @override
  String get invalidLink => '链接无效';

  @override
  String get unknown => '未知';

  @override
  String get localSource => '本地';

  @override
  String get dependencyTypeDirectMain => '直接依赖';

  @override
  String get dependencyTypeDirectDev => '开发依赖';

  @override
  String get dependencyTypeTransitive => '间接依赖';

  @override
  String get dependencyTypeUnknown => '未知来源';

  @override
  String get parsingDependencyInfo => '正在解析依赖信息...';

  @override
  String get readDependencyListFailed => '读取依赖列表失败';

  @override
  String dependencySummaryWithOther(
      int total, int directMain, int directDev, int transitive, int other) {
    return '共 $total 个库 · 直接 $directMain / 开发 $directDev / 间接 $transitive / 其他 $other';
  }

  @override
  String dependencySummaryNoOther(
      int total, int directMain, int directDev, int transitive) {
    return '共 $total 个库 · 直接 $directMain / 开发 $directDev / 间接 $transitive';
  }

  @override
  String dependencyEntrySubtitle(
      Object version, Object dependencyType, Object sourceType) {
    return '版本: $version · $dependencyType · $sourceType';
  }

  @override
  String get buildInfo => '构建信息';

  @override
  String get buildInfoSubtitle => '查看构建时间、处理器、内存与系统架构';

  @override
  String get fileLogWriteTitle => '日志写入文件';

  @override
  String get fileLogWriteSubtitle => '每 1 秒写入磁盘，保留最近 5 份日志文件';

  @override
  String get fileLogWriteEnabled => '已开启日志写入文件';

  @override
  String get fileLogWriteDisabled => '已关闭日志写入文件';

  @override
  String get openLogDirectoryTitle => '打开日志路径';

  @override
  String get openLogDirectorySubtitle => '在文件管理器中打开日志目录';

  @override
  String get logDirectoryOpened => '已打开日志目录';

  @override
  String get openLogDirectoryFailed => '打开日志目录失败';

  @override
  String get spoilerAiDebugPrintTitle => '调试：打印 AI 返回内容';

  @override
  String get spoilerAiDebugPrintEnabledHint => '开启后会在日志里打印 AI 返回的原始文本与命中弹幕。';

  @override
  String get spoilerAiDebugPrintNeedSpoilerMode => '需先启用防剧透模式';

  @override
  String get spoilerAiDebugPrintEnabled => '已开启 AI 调试打印';

  @override
  String get spoilerAiDebugPrintDisabled => '已关闭 AI 调试打印';

  @override
  String get playerUnavailableOnWeb => '播放器设置在 Web 平台不可用';

  @override
  String get danmakuRenderEngine => '弹幕渲染引擎';

  @override
  String get danmakuRenderEngineSwitched => '弹幕渲染引擎已切换';

  @override
  String get danmakuRenderEngineDescriptionCpu => 'CPU 渲染：兼容性最佳，适合大多数场景。';

  @override
  String get danmakuRenderEngineDescriptionGpuExperimental =>
      'GPU 渲染（实验性）：性能更高，但仍在开发中。';

  @override
  String get danmakuRenderEngineDescriptionCanvasExperimental =>
      'Canvas 弹幕（实验性）：高性能，低功耗。';

  @override
  String get danmakuRenderEngineDescriptionNipaplayNext =>
      'NipaPlay Next：CPU 弹幕和 Canvas 弹幕优点的集合体，包含两边的全部优点。';

  @override
  String get danmakuRenderEngineTitleCpu => 'CPU 渲染';

  @override
  String get danmakuRenderEngineTitleGpuExperimental => 'GPU 渲染 (实验性)';

  @override
  String get danmakuRenderEngineTitleCanvasExperimental => 'Canvas 弹幕 (实验性)';

  @override
  String get danmakuRenderEngineTitleNipaplayNext => 'NipaPlay Next';

  @override
  String get qualityProfileOff => '关闭';

  @override
  String get qualityProfileLite => '轻量';

  @override
  String get qualityProfileStandard => '标准';

  @override
  String get qualityProfileHigh => '高质量';

  @override
  String get doubleResolutionPlaybackTitle => '双倍分辨率播放视频';

  @override
  String get doubleResolutionPlaybackSubtitle =>
      '以 2x 分辨率渲染画面，改善内嵌字幕清晰度（仅 Libmpv，不与 Anime4K 叠加）';

  @override
  String get settingSavedReopenVideoToApply => '已保存，重新打开视频生效';

  @override
  String get doubleResolutionPlaybackEnabled => '已开启双倍分辨率播放';

  @override
  String get doubleResolutionPlaybackDisabled => '已关闭双倍分辨率播放';

  @override
  String get anime4kSuperResolutionTitle => 'Anime4K 超分辨率（实验性）';

  @override
  String get anime4kProfileDescriptionOff => '保持原始画面，不进行超分辨率处理。';

  @override
  String get anime4kProfileDescriptionLite => '适度超分辨率与降噪，性能消耗较低。';

  @override
  String get anime4kProfileDescriptionStandard => '画质与性能平衡的标准方案。';

  @override
  String get anime4kProfileDescriptionHigh => '追求最佳画质，性能需求最高。';

  @override
  String get anime4kDisabled => '已关闭 Anime4K';

  @override
  String anime4kSwitchedTo(Object option) {
    return 'Anime4K 已切换为 $option';
  }

  @override
  String get crtDisplayEffectTitle => 'CRT 显示效果';

  @override
  String get crtProfileDescriptionOff => '保持原始画面，不启用 CRT 效果。';

  @override
  String get crtProfileDescriptionLite => '扫描线 + 暗角，性能开销较小。';

  @override
  String get crtProfileDescriptionStandard => '增加曲面与栅格，画面更接近 CRT。';

  @override
  String get crtProfileDescriptionHigh => '加入辉光与色散，效果最佳但性能开销更高。';

  @override
  String get crtDisabled => '已关闭 CRT';

  @override
  String crtSwitchedTo(Object option) {
    return 'CRT 已切换为 $option';
  }

  @override
  String get enterAiApiUrl => '请输入 AI 接口 URL';

  @override
  String get enterModelName => '请输入模型名称';

  @override
  String get enterApiKey => '请输入 API Key';

  @override
  String get spoilerAiSettingsSaved => '防剧透 AI 设置已保存';

  @override
  String get spoilerPreventionMode => '防剧透模式';

  @override
  String get spoilerPreventionModeSubtitle => '开启后，加载弹幕后将通过 AI 识别并屏蔽疑似剧透弹幕。';

  @override
  String get fillAndSaveAiConfigFirst => '请先填写并保存 AI 接口配置';

  @override
  String get spoilerPreventionModeEnabled => '已开启防剧透模式';

  @override
  String get spoilerPreventionModeDisabled => '已关闭防剧透模式';

  @override
  String get autoMatchDanmakuOnPlayTitle => '播放时自动匹配弹幕';

  @override
  String get autoMatchDanmakuOnPlaySubtitle => '关闭后播放时不再自动识别并加载弹幕，可在弹幕设置中手动匹配。';

  @override
  String get autoMatchDanmakuOnPlayEnabled => '已开启播放时自动匹配弹幕';

  @override
  String get autoMatchDanmakuOnPlayDisabledManual => '已关闭播放时自动匹配弹幕（可手动匹配）';

  @override
  String get autoMatchOnHashFailTitle => '哈希匹配失败自动匹配弹幕';

  @override
  String get autoMatchOnHashFailSubtitle =>
      '哈希匹配失败时默认使用文件名搜索的第一个结果自动匹配；关闭后将弹出搜索弹幕菜单。';

  @override
  String get autoMatchOnHashFailEnabled => '已开启匹配失败自动匹配';

  @override
  String get autoMatchOnHashFailDisabledShowSearch => '已关闭匹配失败自动匹配（将弹出搜索弹幕菜单）';

  @override
  String get hardwareDecoding => '硬件解码';

  @override
  String get hardwareDecodingSubtitle => '仅对 MDK / Libmpv 生效';

  @override
  String get hardwareDecodingEnabled => '已开启硬件解码';

  @override
  String get hardwareDecodingDisabled => '已关闭硬件解码';

  @override
  String get pauseOnBackgroundTitle => '后台自动暂停';

  @override
  String get pauseOnBackgroundSubtitle => '切到后台或锁屏时自动暂停播放';

  @override
  String get pauseOnBackgroundEnabled => '后台自动暂停已开启';

  @override
  String get pauseOnBackgroundDisabled => '后台自动暂停已关闭';

  @override
  String get playbackEndActionTitle => '播放结束操作';

  @override
  String get playbackEndActionAutoNextMessage => '播放结束后将自动进入下一话';

  @override
  String get playbackEndActionLoopMessage => '播放结束后将从头循环播放';

  @override
  String get playbackEndActionPauseMessage => '播放结束后将停留在当前页面';

  @override
  String get playbackEndActionExitMessage => '播放结束后将返回上一页';

  @override
  String get autoNextCountdownTitle => '自动连播倒计时';

  @override
  String autoNextCountdownWaitSeconds(int seconds) {
    return '自动跳转下一话前等待 $seconds 秒';
  }

  @override
  String get autoNextCountdownNeedAutoNext => '需先启用自动播放下一话';

  @override
  String get timelinePreviewTitle => '时间轴截图预览';

  @override
  String get timelinePreviewSubtitle => '悬停进度条时显示缩略图（本地/WebDAV/SMB/共享媒体库生效）';

  @override
  String get enableWarning => '开启警告';

  @override
  String get timelinePreviewEnableWarningContent =>
      '开启时间轴截图预览会在后台实时生成截图，可能导致播放卡顿或性能下降。是否确认开启？';

  @override
  String get timelinePreviewEnabled => '已开启时间轴截图预览';

  @override
  String get timelinePreviewDisabled => '已关闭时间轴截图预览';

  @override
  String get playPrecacheDuration => '播放预缓存时长';

  @override
  String get playPrecacheSize => '播放预缓存大小';

  @override
  String currentPrecacheDurationSeconds(int seconds) {
    return '当前 $seconds 秒，修改后立即生效';
  }

  @override
  String currentPrecacheSizeMb(int mb) {
    return '当前 $mb MB，修改后重新打开视频生效';
  }

  @override
  String get libmpvKernelOnly => '仅 Libmpv 内核生效';

  @override
  String get spoilerAiSettingsTitle => '防剧透 AI 设置';

  @override
  String get spoilerAiSettingsDescription =>
      '开启防剧透前请先填写并保存配置（必须提供接口 URL / Key / 模型）。';

  @override
  String get spoilerAiGeminiUrlNote =>
      'Gemini：URL 可填到 /v1beta/models，实际请求会自动拼接 /<模型>:generateContent。';

  @override
  String get spoilerAiOpenAiUrlNote =>
      'OpenAI：URL 建议填写 /v1/chat/completions（兼容接口亦可）。';

  @override
  String get apiFormatLabel => '接口格式';

  @override
  String get openAiCompatible => 'OpenAI 兼容';

  @override
  String get enterYourApiKey => '请输入你的 API Key';

  @override
  String temperatureLabel(Object value) {
    return '温度：$value';
  }

  @override
  String get saveConfiguration => '保存配置';

  @override
  String get about => '关于';

  @override
  String get loading => '加载中…';

  @override
  String currentVersion(Object version) {
    return '当前版本：$version';
  }

  @override
  String get versionLoadFailed => '版本信息获取失败';

  @override
  String get general => '通用';

  @override
  String get backupAndRestore => '备份与恢复';

  @override
  String get shortcuts => '快捷键';

  @override
  String get remoteAccess => '远程访问';

  @override
  String get remoteMediaLibrary => '远程媒体库';

  @override
  String get appearanceSettings => '外观设置';

  @override
  String get generalSettings => '通用设置';

  @override
  String get storageSettings => '存储设置';

  @override
  String get playerSettings => '播放器设置';

  @override
  String get shortcutsSettings => '快捷键设置';

  @override
  String get rememberDanmakuOffset => '记忆弹幕偏移';

  @override
  String get rememberDanmakuOffsetSubtitle => '切换视频时保留当前手动偏移（自动匹配偏移仍会重置）。';

  @override
  String get rememberDanmakuOffsetEnabled => '已开启弹幕偏移记忆';

  @override
  String get rememberDanmakuOffsetDisabled => '已关闭弹幕偏移记忆';

  @override
  String get danmakuConvertToSimplified => '弹幕转换简体中文';

  @override
  String get danmakuConvertToSimplifiedSubtitle => '开启后，将繁体中文弹幕转换为简体显示。';

  @override
  String get danmakuConvertToSimplifiedEnabled => '已开启弹幕转换简体中文';

  @override
  String get danmakuConvertToSimplifiedDisabled => '已关闭弹幕转换简体中文';

  @override
  String get cancel => '取消';

  @override
  String get confirm => '确定';

  @override
  String get close => '关闭';

  @override
  String get saving => '保存中...';

  @override
  String networkServerSwitchedTo(Object server) {
    return '弹弹play 服务器已切换到 $server';
  }

  @override
  String get enterServerAddress => '请输入服务器地址';

  @override
  String get invalidServerAddress => '服务器地址格式不正确，请以 http/https 开头';

  @override
  String get switchedToCustomServer => '已切换到自定义服务器';

  @override
  String get networkPrimaryServerRecommended => '主服务器 (推荐)';

  @override
  String get networkBackupServer => '备用服务器';

  @override
  String get networkCurrentCustomServer => '当前自定义服务器';

  @override
  String get networkSelectServer => '选择弹弹play 服务器';

  @override
  String get primaryServer => '主服务器';

  @override
  String get backupServer => '备用服务器';

  @override
  String get dandanplayServer => '弹弹play 服务器';

  @override
  String get customServer => '自定义服务器';

  @override
  String get customServerInputHint =>
      '输入兼容弹弹play API 的弹幕服务器地址，例如 https://example.com';

  @override
  String get customServerPlaceholder => 'https://your-danmaku-server.com';

  @override
  String get useThisServer => '使用该服务器';

  @override
  String get currentServerInfo => '当前服务器信息';

  @override
  String get serverDescriptionTitle => '服务器说明';

  @override
  String serverField(Object server) {
    return '服务器：$server';
  }

  @override
  String urlField(Object url) {
    return 'URL：$url';
  }

  @override
  String serverBullet(Object name, Object description) {
    return '• $name：$description';
  }

  @override
  String get networkServerDescriptionPrimary =>
      'api.dandanplay.net（官方服务器，推荐使用）';

  @override
  String get networkServerDescriptionBackup =>
      '139.224.252.88:16001（镜像服务器，主服务器无法访问时使用）';

  @override
  String get networkServerSelectSubtitle => '选择弹弹play弹幕服务器。备用服务器可在主服务器无法访问时使用。';

  @override
  String customServerWithValue(Object server) {
    return '自定义：$server';
  }

  @override
  String get enabledClearOnLaunchSnack => '已启用启动时清理弹幕缓存';

  @override
  String get danmakuCacheCleared => '弹幕缓存已清理';

  @override
  String clearFailed(Object error) {
    return '清理失败: $error';
  }

  @override
  String get imageCacheCleared => '图片缓存已清除';

  @override
  String get confirmClearCacheTitle => '确认清除缓存';

  @override
  String get confirmClearImageCacheContent => '确定要清除封面与缩略图等图片缓存吗？';

  @override
  String get clearDanmakuCacheOnLaunchTitle => '每次启动时清理弹幕缓存';

  @override
  String get clearDanmakuCacheOnLaunchSubtitle =>
      '自动删除 cache/danmaku/ 目录下的弹幕缓存';

  @override
  String get screenshotSaveLocation => '截图保存位置';

  @override
  String get defaultDownloadDir => '默认：下载目录';

  @override
  String get screenshotSaveLocationUpdated => '截图保存位置已更新';

  @override
  String get screenshotDefaultSaveTarget => '截图默认保存位置';

  @override
  String get screenshotDefaultSaveTargetMessage => '选择截图后的默认保存方式';

  @override
  String get clearDanmakuCacheNow => '立即清理弹幕缓存';

  @override
  String get clearingInProgress => '正在清理...';

  @override
  String get clearDanmakuCacheManualHint => '当弹幕异常或占用空间过大时可手动清理';

  @override
  String get clearImageCache => '清除图片缓存';

  @override
  String get clearImageCacheHint => '清除封面与缩略图等图片缓存';

  @override
  String get danmakuCacheDescription =>
      '弹幕缓存将存储在应用缓存目录 cache/danmaku/ 中，启用自动清理可减轻空间占用。';

  @override
  String get imageCacheDescription => '图片缓存包含封面与播放缩略图，存储在应用缓存目录中，可按需清理。';

  @override
  String get clearDanmakuCacheOnLaunchSubtitleNipaplay =>
      '重启应用时自动删除所有已缓存的弹幕文件，确保数据实时';

  @override
  String get clearDanmakuCacheManualHintNipaplay => '删除缓存/缓存异常时可手动清理';

  @override
  String get danmakuCacheDescriptionNipaplay =>
      '弹幕缓存文件存储在 cache/danmaku/ 目录下，占用空间较大时可随时清理。';

  @override
  String get imageCacheDescriptionNipaplay =>
      '图片缓存包含封面与播放缩略图，存储在应用缓存目录中，可定期清理。';

  @override
  String clearDanmakuCacheFailed(Object error) {
    return '清理弹幕缓存失败: $error';
  }

  @override
  String clearImageCacheFailed(Object error) {
    return '清除图片缓存失败: $error';
  }

  @override
  String get screenshotSaveAskDescription => '每次截图时弹出选择框';

  @override
  String get screenshotSavePhotosDescription => '截图后直接保存到相册';

  @override
  String get screenshotSaveFileDescription => '截图后直接保存为文件';

  @override
  String get aboutNoReleaseNotes => '暂无更新内容';

  @override
  String aboutFoundNewVersion(Object version) {
    return '发现新版本 $version';
  }

  @override
  String get aboutCurrentIsLatest => '当前已是最新版本';

  @override
  String aboutCurrentVersionLabel(Object version) {
    return '当前版本: $version';
  }

  @override
  String aboutLatestVersionLabel(Object version) {
    return '最新版本: $version';
  }

  @override
  String aboutReleaseNameLabel(Object name) {
    return '版本名称: $name';
  }

  @override
  String aboutPublishedAtLabel(Object publishedAt) {
    return '发布时间: $publishedAt';
  }

  @override
  String get aboutReleaseNotesTitle => '更新内容';

  @override
  String get aboutOpenReleasePage => '查看发布页';

  @override
  String get updateCheckFailed => '检查更新失败';

  @override
  String get pleaseTryAgainLater => '请稍后再试';

  @override
  String cannotOpenLink(Object url) {
    return '无法打开链接: $url';
  }

  @override
  String get appreciationCode => '赞赏码';

  @override
  String get appreciationImageLoadFailed => '赞赏码图片加载失败';

  @override
  String get acknowledgements => '致谢';

  @override
  String get aboutStoryPrefix => 'NipaPlay，名字来自《寒蝉鸣泣之时》中古手梨花的口头禅 \"';

  @override
  String get aboutStorySuffix =>
      '\"。为了解决我在 macOS、Linux、iOS 上看番不便的问题，我创造了 NipaPlay。';

  @override
  String get aboutThanksDandanplayPrefix => '感谢弹弹play (DandanPlay) 以及开发者 ';

  @override
  String get aboutThanksDandanplaySuffix => ' 提供的接口与开发帮助。';

  @override
  String get aboutThanksSakikoPrefix => '感谢开发者 ';

  @override
  String get aboutThanksSakikoSuffix => ' 帮助实现 Emby 与 Jellyfin 媒体库支持。';

  @override
  String get thanksSponsorUsers => '感谢下列用户的赞助支持：';

  @override
  String aboutVersionBanner(Object version) {
    return 'NipaPlay Reload 当前版本：$version';
  }

  @override
  String get aboutCheckingUpdates => '检测中…';

  @override
  String get aboutCheckUpdates => '检测更新';

  @override
  String get aboutAutoCheckUpdates => '自动检测更新';

  @override
  String get aboutManualOnlyWhenDisabled => '关闭后仅手动检测';

  @override
  String aboutQqGroup(Object id) {
    return 'QQ群: $id';
  }

  @override
  String get aboutOfficialWebsite => 'NipaPlay 官方网站';

  @override
  String get openSourceCommunity => '开源与社区';

  @override
  String get aboutCommunityHint =>
      '欢迎贡献代码，或将应用发布到更多平台。不会 Dart 也没关系，借助 AI 编程同样可以。';

  @override
  String get sponsorSupport => '赞助支持';

  @override
  String get aboutSponsorParagraph1 =>
      '如果你喜欢 NipaPlay 并且希望支持项目的持续开发，欢迎通过爱发电进行赞助。';

  @override
  String get aboutSponsorParagraph2 =>
      '赞助者的名字将会出现在项目的 README 文件和每次软件更新后的关于页面名单中。';

  @override
  String get aboutAfdianSponsorPage => '爱发电赞助页面';
}

/// The translations for Chinese, using the Han script (`zh_Hant`).
class AppLocalizationsZhHant extends AppLocalizationsZh {
  AppLocalizationsZhHant() : super('zh_Hant');

  @override
  String get appTitle => 'NipaPlay';

  @override
  String get tabHome => '主頁';

  @override
  String get tabVideoPlay => '影片播放';

  @override
  String get tabMediaLibrary => '媒體庫';

  @override
  String get tabAccount => '個人中心';

  @override
  String get tabSettings => '設定';

  @override
  String get settingsLabel => '設定';

  @override
  String get toggleToLightMode => '切換到日間模式';

  @override
  String get toggleToDarkMode => '切換到夜間模式';

  @override
  String get language => '語言';

  @override
  String get languageSettingsTitle => '語言設定';

  @override
  String get languageSettingsSubtitle => '選擇介面顯示語言';

  @override
  String get languageAuto => '自動（跟隨系統）';

  @override
  String get languageSimplifiedChinese => '簡體中文';

  @override
  String get languageTraditionalChinese => '繁體中文';

  @override
  String currentLanguage(Object language) {
    return '目前：$language';
  }

  @override
  String currentServer(Object server) {
    return '目前：$server';
  }

  @override
  String currentTheme(Object theme) {
    return '目前：$theme';
  }

  @override
  String get languageTileSubtitle => '切換簡體中文或繁體中文';

  @override
  String get settingsBasicSection => '基礎設定';

  @override
  String get settingsAboutSection => '關於';

  @override
  String get appearance => '外觀';

  @override
  String get lightMode => '淺色模式';

  @override
  String get appearanceLightModeSubtitle => '保持明亮的介面與對比度。';

  @override
  String get darkMode => '深色模式';

  @override
  String get appearanceDarkModeSubtitle => '降低亮度，保護視力並節省電量。';

  @override
  String get followSystem => '跟隨系統';

  @override
  String get appearanceFollowSystemSubtitle => '自動依系統設定切換外觀。';

  @override
  String get appearancePreviewTitle => '效果預覽';

  @override
  String get appearancePreviewFollowSystemDescription => '依系統外觀自動切換淺色或深色模式。';

  @override
  String get appearancePreviewDarkDescription => '使用偏暗的配色方案，適合夜間或弱光環境。';

  @override
  String get appearancePreviewLightDescription => '使用明亮的配色方案，適合日間或高亮環境。';

  @override
  String get appearanceAnimeDetailStyle => '番劇詳情樣式';

  @override
  String get appearanceDetailSimple => '簡潔模式';

  @override
  String get appearanceDetailSimpleSubtitle => '經典佈局，資訊分欄展示。';

  @override
  String get appearanceDetailVivid => '絢麗模式';

  @override
  String get appearanceDetailVividSubtitle => '海報主視覺、橫向劇集卡片。';

  @override
  String get appearanceRecentWatchingStyle => '最近觀看樣式';

  @override
  String get appearanceRecentSimple => '簡潔版';

  @override
  String get appearanceRecentSimpleSubtitle => '純文字列表，節省空間。';

  @override
  String get appearanceRecentDetailed => '詳細版';

  @override
  String get appearanceRecentDetailedSubtitle => '帶截圖的橫向捲動卡片。';

  @override
  String get appearanceHomeSections => '主頁板塊';

  @override
  String get restoreDefaults => '恢復預設';

  @override
  String get restoreDefaultsSubtitle => '恢復預設排序與顯示狀態';

  @override
  String get uiThemeExperimental => '主題（實驗性）';

  @override
  String get uiThemeRestartHint => '提示：切換主題後需要重新啟動應用才能完全生效。';

  @override
  String get uiThemeSwitchDialogTitle => '主題切換提示';

  @override
  String uiThemeSwitchDialogMessage(Object theme) {
    return '切換到 $theme 主題需要重新啟動應用才能完全生效。\n\n是否要立即重新啟動應用？';
  }

  @override
  String get restartApp => '重新啟動應用';

  @override
  String get refreshPageApplyTheme => '請手動重新整理頁面以套用新主題';

  @override
  String get player => '播放器';

  @override
  String get playerKernel => '播放器內核';

  @override
  String get playerKernelCurrentMdk => '目前：MDK';

  @override
  String get playerKernelCurrentVideoPlayer => '目前：Video Player';

  @override
  String get playerKernelCurrentLibmpv => '目前：Libmpv';

  @override
  String get playerKernelSwitched => '播放器內核已切換';

  @override
  String get playerKernelDescriptionMdk =>
      'MDK 多媒體開發套件，支援硬體解碼（預設優先；不支援時回退軟體解碼）。';

  @override
  String get playerKernelDescriptionVideoPlayer =>
      'Flutter 官方 Video Player，相容性佳。';

  @override
  String get playerKernelDescriptionLibmpv =>
      'MediaKit (Libmpv) 播放器，支援硬體解碼與進階特性。';

  @override
  String get externalCall => '外部調用';

  @override
  String get externalPlayerEnabled => '已啟用外部播放器';

  @override
  String get externalPlayerDisabled => '未啟用外部播放器';

  @override
  String get externalPlayerIntroDesktop => '啟用後，所有播放操作將透過外部播放器開啟。';

  @override
  String get externalPlayerIntroUnsupported => '僅桌面端支援外部播放器調用。';

  @override
  String get externalPlayerEnableTitle => '啟用外部播放器';

  @override
  String get externalPlayerEnableSubtitle => '開啟後將使用外部播放器播放影片';

  @override
  String get externalPlayerSelectTitle => '選擇外部播放器';

  @override
  String get externalPlayerNotSelected => '未選擇外部播放器';

  @override
  String get externalPlayerSelectionCanceled => '已取消選擇外部播放器';

  @override
  String get externalPlayerUpdated => '已更新外部播放器';

  @override
  String get desktopOnlySupported => '僅桌面端支援';

  @override
  String get networkSettings => '網路設定';

  @override
  String get networkSettingsSubtitle => '彈彈play 伺服器及自訂地址';

  @override
  String get storage => '儲存';

  @override
  String get storageSettingsSubtitle => '管理彈幕快取與清理策略';

  @override
  String get networkMediaLibrary => '網路媒體庫';

  @override
  String get mediaServerStatusConnected => '已連接';

  @override
  String get mediaServerStatusDisconnected => '未連接';

  @override
  String get mediaServerInfoServerUrl => '伺服器地址';

  @override
  String get mediaServerInfoUsername => '登入用戶';

  @override
  String get mediaServerInfoItemCount => '媒體條目';

  @override
  String get mediaServerInfoSelectedLibraries => '已選媒體庫';

  @override
  String get mediaServerUnknown => '未知';

  @override
  String get mediaServerAnonymous => '匿名';

  @override
  String get mediaServerViewLibrary => '查看媒體庫';

  @override
  String get mediaServerRefresh => '重新整理';

  @override
  String get mediaServerManageServer => '管理伺服器';

  @override
  String get mediaServerConnectServer => '連接伺服器';

  @override
  String get mediaServerDisconnectedHint => '尚未連接此媒體伺服器，點擊下方按鈕完成登入。';

  @override
  String get retry => '重試';

  @override
  String get save => '儲存';

  @override
  String get disconnect => '斷開連接';

  @override
  String get loadFailed => '載入失敗';

  @override
  String loadFailedWithError(Object error) {
    return '載入失敗：$error';
  }

  @override
  String operationFailed(Object error) {
    return '操作失敗：$error';
  }

  @override
  String saveFailedWithError(Object error) {
    return '儲存失敗：$error';
  }

  @override
  String connectFailedWithError(Object error) {
    return '連接失敗：$error';
  }

  @override
  String refreshFailedWithError(Object error) {
    return '重新整理失敗：$error';
  }

  @override
  String disconnectFailedWithError(Object error) {
    return '斷開失敗：$error';
  }

  @override
  String get deviceIdTitle => '裝置識別 (DeviceId)';

  @override
  String get deviceIdDescription => '用於 Jellyfin / Emby 區分不同裝置，避免互踢登出。';

  @override
  String get deviceIdCurrent => '目前 DeviceId';

  @override
  String get deviceIdGenerated => '自動產生識別';

  @override
  String get deviceIdCustom => '自訂 DeviceId';

  @override
  String deviceIdCustomSet(Object deviceId) {
    return '已設定：$deviceId';
  }

  @override
  String get deviceIdCustomUnset => '未設定（使用自動產生）';

  @override
  String get deviceIdRestoreAuto => '恢復自動產生';

  @override
  String get deviceIdRestoreAutoSubtitle => '清除自訂 DeviceId';

  @override
  String get deviceIdRestoreSuccess => '已恢復自動產生的裝置ID';

  @override
  String get deviceIdDialogTitle => '自訂 DeviceId';

  @override
  String get deviceIdDialogHint => '留空表示使用自動產生的裝置識別。';

  @override
  String get deviceIdDialogPlaceholder => '例如: My-iPhone-01';

  @override
  String get deviceIdDialogValidationHint => '不要包含雙引號/換行，長度不超過128。';

  @override
  String get deviceIdUpdatedHint => '裝置ID已更新，建議斷開並重新連接伺服器';

  @override
  String get deviceIdInvalid => 'DeviceId 無效：請避免雙引號/換行，且長度 ≤ 128';

  @override
  String networkServerConnected(Object server) {
    return '$server 伺服器已連接';
  }

  @override
  String networkServerSettingsUpdated(Object server) {
    return '$server 伺服器設定已更新';
  }

  @override
  String disconnectServerConfirm(Object server) {
    return '確定要斷開與 $server 伺服器的連接嗎？';
  }

  @override
  String networkServerDisconnected(Object server) {
    return '$server 已斷開連接';
  }

  @override
  String disconnectServerFailed(Object server, Object error) {
    return '斷開 $server 失敗：$error';
  }

  @override
  String networkServerNotConnected(Object server) {
    return '尚未連接到 $server 伺服器';
  }

  @override
  String networkLibraryRefreshed(Object server) {
    return '$server 媒體庫已重新整理';
  }

  @override
  String connectServerDialogTitle(Object server) {
    return '連接 $server 伺服器';
  }

  @override
  String get serverUrlInputPlaceholder => '例如：http://192.168.1.100:8096';

  @override
  String get inputUsernamePlaceholder => '輸入用戶名';

  @override
  String get inputPasswordPlaceholder => '輸入密碼';

  @override
  String get nextStep => '下一步';

  @override
  String get connectAction => '連接';

  @override
  String get testConnection => '測試連接';

  @override
  String get canBeEmpty => '可留空';

  @override
  String get leaveEmptyAutoGenerate => '留空自動產生';

  @override
  String get usernameOptional => '用戶名（可選）';

  @override
  String get passwordOptional => '密碼（可選）';

  @override
  String get connectFailedCheckCredentials => '連接失敗，請檢查伺服器地址與憑證';

  @override
  String get webdavAddServer => '新增 WebDAV 伺服器';

  @override
  String get webdavEditServer => '編輯 WebDAV 伺服器';

  @override
  String get webdavEnterAddress => '請輸入 WebDAV 位址';

  @override
  String get webdavInvalidUrl => '請輸入有效的 URL（http/https）';

  @override
  String get webdavConnection => 'WebDAV 連接';

  @override
  String webdavTestFailedWithError(Object error) {
    return '測試失敗：$error';
  }

  @override
  String get webdavTestFailedCheckInfo => '連接測試失敗，請檢查位址和認證資訊';

  @override
  String get webdavTestSuccess => '連接測試成功';

  @override
  String get webdavTestFailed => '連接測試失敗';

  @override
  String get webdavSaveFailedCheckInfo => '儲存失敗，請檢查位址和認證資訊';

  @override
  String get webdavConnectHint => '連接 WebDAV 伺服器後可瀏覽目錄並選擇媒體資料夾。';

  @override
  String get webdavConnectionNameOptional => '連接名稱（可選）';

  @override
  String get webdavAddress => 'WebDAV 位址';

  @override
  String get smbAddServer => '新增 SMB 伺服器';

  @override
  String get smbEditServer => '編輯 SMB 伺服器';

  @override
  String get smbEnterHostOrIp => '請輸入主機或 IP 位址';

  @override
  String get smbInvalidPortRange => '連接埠無效，請輸入 1-65535';

  @override
  String get smbAnonymousHint => '用戶名/密碼可留空以匿名存取；支援填寫網域名稱。';

  @override
  String get smbHostOrIp => '主機 / IP';

  @override
  String get smbHostOrIpPlaceholder => '例如：192.168.1.10 或 nas.local';

  @override
  String get smbPort => '連接埠';

  @override
  String get smbDefaultPort445 => '預設 445';

  @override
  String get smbDomainOptional => '網域（可選）';

  @override
  String get smbDomainPlaceholder => '例如：WORKGROUP';

  @override
  String get connectJellyfinOrEmbyFirst => '請先連接 Jellyfin 或 Emby 伺服器';

  @override
  String get networkMediaLibraryIntro =>
      '在此管理 Jellyfin / Emby 伺服器連接，並設定彈彈play 遠端媒體庫。';

  @override
  String get currentServerNotConnectedHint => '目前伺服器未連接，請返回重新選擇。';

  @override
  String get loadingRemoteMediaLibrary => '正在載入遠端媒體庫...';

  @override
  String get noRemoteMediaItems => '尚未取得遠端媒體條目';

  @override
  String recordedAtDate(Object date) {
    return '收錄於 $date';
  }

  @override
  String get jellyfinMediaServerTitle => 'Jellyfin 媒體伺服器';

  @override
  String get jellyfinDisconnectedDescription => '連接 Jellyfin 伺服器以同步遠端媒體庫與播放記錄。';

  @override
  String get embyMediaServerTitle => 'Emby 媒體伺服器';

  @override
  String get embyDisconnectedDescription => '連接 Emby 伺服器後可瀏覽個人媒體庫並遠端播放。';

  @override
  String get dandanRemoteCardTitle => '彈彈play 遠端存取';

  @override
  String get dandanRemoteManageAccessTitle => '管理彈彈play遠端存取';

  @override
  String get dandanRemoteConnectAccessTitle => '連接彈彈play遠端存取';

  @override
  String get dandanRemoteAddressPrompt => '請輸入桌面端顯示的遠端服務地址。';

  @override
  String get dandanRemoteAddressPlaceholder => '例如：http://192.168.1.2:23333';

  @override
  String get dandanRemoteApiTokenOptionalTitle => 'API 金鑰（可選）';

  @override
  String dandanRemoteApiTokenPrompt(Object actionLabel) {
    return '若已在彈彈play 桌面端啟用 API 驗證，請輸入對應金鑰；未啟用可直接點擊$actionLabel。';
  }

  @override
  String get enterApiToken => '請輸入 API 金鑰';

  @override
  String get optionalApiTokenHint => '可留空，按需填寫';

  @override
  String get dandanRemoteStatusSynced => '已同步';

  @override
  String get dandanRemoteStatusConnectFailed => '連接失敗';

  @override
  String get dandanRemoteStatusNotConfigured => '未設定';

  @override
  String get unknownErrorOccurred => '發生未知錯誤';

  @override
  String get dandanRemoteServerAddressLabel => '伺服器地址';

  @override
  String get dandanRemoteLastSyncedLabel => '最近同步';

  @override
  String get dandanRemoteAnimeEntries => '番劇條目';

  @override
  String get dandanRemoteVideoFiles => '影片檔案';

  @override
  String get dandanRemoteNoRecordsHint => '暫無遠端媒體記錄，可嘗試重新整理或確認遠端存取設定。';

  @override
  String get dandanRemoteRecentUpdates => '最近更新';

  @override
  String dandanRemoteEpisodeCount(int count) {
    return '共 $count 集';
  }

  @override
  String get dandanRemoteManageConnection => '管理連接';

  @override
  String get dandanRemoteSyncing => '同步中...';

  @override
  String get dandanRemoteRefreshLibrary => '重新整理媒體庫';

  @override
  String get dandanRemoteDisconnectedHintLong =>
      '透過彈彈play 桌面端開啟遠端存取後，可在此同步家中電腦或 NAS 上的番劇記錄並直接播放。';

  @override
  String get pleaseWait => '請稍候...';

  @override
  String get connectDandanRemoteService => '連接彈彈play 遠端服務';

  @override
  String get noRecordYet => '暫無記錄';

  @override
  String get justNow => '剛剛';

  @override
  String minutesAgo(int minutes) {
    return '$minutes 分鐘前';
  }

  @override
  String hoursAgo(int hours) {
    return '$hours 小時前';
  }

  @override
  String daysAgo(int days) {
    return '$days 天前';
  }

  @override
  String get dandanRemoteConfigUpdated => '彈彈play 遠端服務設定已更新';

  @override
  String get dandanRemoteConnected => '彈彈play 遠端服務已連接';

  @override
  String get dandanRemoteDisconnected => '已斷開與彈彈play遠端服務的連接';

  @override
  String get disconnectDandanRemoteTitle => '斷開彈彈play遠端服務';

  @override
  String get disconnectDandanRemoteContent =>
      '確定要斷開與彈彈play遠端服務的連接嗎？\n\n這將清除已儲存的伺服器地址與 API 金鑰。';

  @override
  String get remoteLibraryRefreshed => '遠端媒體庫已重新整理';

  @override
  String get noConnectedServer => '尚未連接任何伺服器';

  @override
  String get mediaLibraryNotSelected => '未選擇媒體庫';

  @override
  String get mediaLibraryNotMatched => '未匹配到媒體庫';

  @override
  String mediaLibraryAndCount(Object first, int count) {
    return '$first 等 $count 個';
  }

  @override
  String mediaServerSummary(Object server, Object summary) {
    return '$server · $summary';
  }

  @override
  String serverMediaLibraryTitle(Object server) {
    return '$server 媒體庫';
  }

  @override
  String get serverLabel => '伺服器';

  @override
  String get accountLabel => '帳戶';

  @override
  String get mediaLibrary => '媒體庫';

  @override
  String get noMediaLibrary => '暫無媒體庫';

  @override
  String get checkServerConnection => '請檢查伺服器連接';

  @override
  String get transcodeSettings => '轉碼設定';

  @override
  String currentDefaultQuality(Object quality) {
    return '目前預設畫質: $quality';
  }

  @override
  String get enableTranscode => '啟用轉碼';

  @override
  String get defaultQuality => '預設清晰度';

  @override
  String get tvShowsLibrary => '電視劇庫';

  @override
  String get moviesLibrary => '電影庫';

  @override
  String get boxsetsLibrary => '合集庫';

  @override
  String get folderLibrary => '資料夾';

  @override
  String get mixedLibrary => '混合庫';

  @override
  String get userActivityTitle => '我的活動記錄';

  @override
  String get userActivityTabWatched => '觀看';

  @override
  String get userActivityTabFavorites => '收藏';

  @override
  String get userActivityTabRated => '評分';

  @override
  String userActivityTabWatchedCount(int count) {
    return '觀看($count)';
  }

  @override
  String userActivityTabFavoritesCount(int count) {
    return '收藏($count)';
  }

  @override
  String userActivityTabRatedCount(int count) {
    return '評分($count)';
  }

  @override
  String get userActivityNoWatchedRecords => '暫無觀看記錄';

  @override
  String get userActivityNoFavorites => '暫無收藏';

  @override
  String get userActivityNoRatings => '暫無評分記錄';

  @override
  String get userActivityNotLoggedIn => '未登入彈彈play帳號';

  @override
  String userActivityWatchedEpisode(Object episode) {
    return '看到：$episode';
  }

  @override
  String userActivityWatchedUpdatedTime(Object time) {
    return '更新時間：$time';
  }

  @override
  String get userActivityWatchedOnly => '已觀看';

  @override
  String userActivityStatusWithValue(Object status) {
    return '狀態：$status';
  }

  @override
  String userActivityRatingWithValue(int rating) {
    return '評分：$rating';
  }

  @override
  String get userActivityUnknownTitle => '未知標題';

  @override
  String get ratingLevelMasterpiece => '神作';

  @override
  String get ratingLevelGreat => '很棒';

  @override
  String get ratingLevelGood => '不錯';

  @override
  String get ratingLevelAverage => '一般';

  @override
  String get ratingLevelOkay => '還行';

  @override
  String get ratingLevelPoor => '較差';

  @override
  String get ratingLevelVeryPoor => '很差';

  @override
  String get ratingLevelTerrible => '極差';

  @override
  String get favoriteStatusFollowing => '關注中';

  @override
  String get favoriteStatusFinished => '已完成';

  @override
  String get favoriteStatusAbandoned => '已棄坑';

  @override
  String get favoriteStatusFavorited => '已收藏';

  @override
  String get weekdaySunday => '週日';

  @override
  String get weekdayMonday => '週一';

  @override
  String get weekdayTuesday => '週二';

  @override
  String get weekdayWednesday => '週三';

  @override
  String get weekdayThursday => '週四';

  @override
  String get weekdayFriday => '週五';

  @override
  String get weekdaySaturday => '週六';

  @override
  String get newSeriesNoTodayAnime => '本日無新番';

  @override
  String get newSeriesUpdateTimeTbd => '更新時間未定';

  @override
  String get newSeriesSearchDescription => '搜尋新番\n按標籤、類型快速篩選\n查找你感興趣的新番';

  @override
  String get newSeriesSortDescriptionAscending => '切換為正序顯示\n今天的新番排在最前';

  @override
  String get newSeriesSortDescriptionDescending => '切換為倒序顯示\n今天的新番排在最後';

  @override
  String get newSeriesInitializingPlayer => '正在初始化播放器...';

  @override
  String newSeriesPlayerLoadFailedWithError(Object error) {
    return '播放器載入失敗: $error';
  }

  @override
  String newSeriesErrorOccurredWithError(Object error) {
    return '發生錯誤: $error';
  }

  @override
  String newSeriesHandlePlayRequestFailedWithError(Object error) {
    return '處理播放請求時出錯: $error';
  }

  @override
  String newSeriesAnimeCount(int count) {
    return '$count 部動畫';
  }

  @override
  String get newSeriesRemoteAddressNotConfigured => '未配置遠端存取位址';

  @override
  String get newSeriesNetworkTimeout => '網路請求逾時，請檢查網路連線後重試';

  @override
  String get newSeriesNetworkConnectionFailed => '網路連線失敗，請檢查網路設定';

  @override
  String get newSeriesServerUnavailableRetryLater => '伺服器無法連線，請稍後重試';

  @override
  String get newSeriesServerDataFormatError => '伺服器回傳資料格式錯誤';

  @override
  String get developerOptions => '開發者選項';

  @override
  String get developerOptionsSubtitle => '終端輸出、依賴版本、建置資訊';

  @override
  String get terminalOutput => '終端輸出';

  @override
  String get terminalOutputSubtitle => '查看日誌、複製內容或產生 QR Code 分享';

  @override
  String get dependencyVersions => '依賴庫版本';

  @override
  String get dependencyVersionsSubtitle => '查看依賴庫與版本號（含 GitHub 跳轉）';

  @override
  String get invalidLink => '連結無效';

  @override
  String get unknown => '未知';

  @override
  String get localSource => '本地';

  @override
  String get dependencyTypeDirectMain => '直接依賴';

  @override
  String get dependencyTypeDirectDev => '開發依賴';

  @override
  String get dependencyTypeTransitive => '間接依賴';

  @override
  String get dependencyTypeUnknown => '未知來源';

  @override
  String get parsingDependencyInfo => '正在解析依賴資訊...';

  @override
  String get readDependencyListFailed => '讀取依賴清單失敗';

  @override
  String dependencySummaryWithOther(
      int total, int directMain, int directDev, int transitive, int other) {
    return '共 $total 個庫 · 直接 $directMain / 開發 $directDev / 間接 $transitive / 其他 $other';
  }

  @override
  String dependencySummaryNoOther(
      int total, int directMain, int directDev, int transitive) {
    return '共 $total 個庫 · 直接 $directMain / 開發 $directDev / 間接 $transitive';
  }

  @override
  String dependencyEntrySubtitle(
      Object version, Object dependencyType, Object sourceType) {
    return '版本: $version · $dependencyType · $sourceType';
  }

  @override
  String get buildInfo => '建置資訊';

  @override
  String get buildInfoSubtitle => '查看建置時間、處理器、記憶體與系統架構';

  @override
  String get fileLogWriteTitle => '日誌寫入檔案';

  @override
  String get fileLogWriteSubtitle => '每 1 秒寫入磁碟，保留最近 5 份日誌檔案';

  @override
  String get fileLogWriteEnabled => '已開啟日誌寫入檔案';

  @override
  String get fileLogWriteDisabled => '已關閉日誌寫入檔案';

  @override
  String get openLogDirectoryTitle => '開啟日誌路徑';

  @override
  String get openLogDirectorySubtitle => '在檔案管理器中開啟日誌目錄';

  @override
  String get logDirectoryOpened => '已開啟日誌目錄';

  @override
  String get openLogDirectoryFailed => '開啟日誌目錄失敗';

  @override
  String get spoilerAiDebugPrintTitle => '除錯：列印 AI 回傳內容';

  @override
  String get spoilerAiDebugPrintEnabledHint => '開啟後會在日誌中列印 AI 回傳的原始文字與命中彈幕。';

  @override
  String get spoilerAiDebugPrintNeedSpoilerMode => '需先啟用防劇透模式';

  @override
  String get spoilerAiDebugPrintEnabled => '已開啟 AI 除錯列印';

  @override
  String get spoilerAiDebugPrintDisabled => '已關閉 AI 除錯列印';

  @override
  String get playerUnavailableOnWeb => '播放器設定在 Web 平台不可用';

  @override
  String get danmakuRenderEngine => '彈幕渲染引擎';

  @override
  String get danmakuRenderEngineSwitched => '彈幕渲染引擎已切換';

  @override
  String get danmakuRenderEngineDescriptionCpu => 'CPU 渲染：相容性最佳，適合大多數場景。';

  @override
  String get danmakuRenderEngineDescriptionGpuExperimental =>
      'GPU 渲染（實驗性）：效能更高，但仍在開發中。';

  @override
  String get danmakuRenderEngineDescriptionCanvasExperimental =>
      'Canvas 彈幕（實驗性）：高效能、低功耗。';

  @override
  String get danmakuRenderEngineDescriptionNipaplayNext =>
      'NipaPlay Next：CPU 彈幕和 Canvas 彈幕優點的集合體，包含兩邊的全部優點。';

  @override
  String get danmakuRenderEngineTitleCpu => 'CPU 渲染';

  @override
  String get danmakuRenderEngineTitleGpuExperimental => 'GPU 渲染 (實驗性)';

  @override
  String get danmakuRenderEngineTitleCanvasExperimental => 'Canvas 彈幕 (實驗性)';

  @override
  String get danmakuRenderEngineTitleNipaplayNext => 'NipaPlay Next';

  @override
  String get qualityProfileOff => '關閉';

  @override
  String get qualityProfileLite => '輕量';

  @override
  String get qualityProfileStandard => '標準';

  @override
  String get qualityProfileHigh => '高品質';

  @override
  String get doubleResolutionPlaybackTitle => '雙倍解析度播放影片';

  @override
  String get doubleResolutionPlaybackSubtitle =>
      '以 2x 解析度渲染畫面，改善內嵌字幕清晰度（僅 Libmpv，不與 Anime4K 疊加）';

  @override
  String get settingSavedReopenVideoToApply => '已儲存，重新開啟影片生效';

  @override
  String get doubleResolutionPlaybackEnabled => '已開啟雙倍解析度播放';

  @override
  String get doubleResolutionPlaybackDisabled => '已關閉雙倍解析度播放';

  @override
  String get anime4kSuperResolutionTitle => 'Anime4K 超解析度（實驗性）';

  @override
  String get anime4kProfileDescriptionOff => '保持原始畫面，不進行超解析度處理。';

  @override
  String get anime4kProfileDescriptionLite => '適度超解析度與降噪，效能消耗較低。';

  @override
  String get anime4kProfileDescriptionStandard => '畫質與效能平衡的標準方案。';

  @override
  String get anime4kProfileDescriptionHigh => '追求最佳畫質，效能需求最高。';

  @override
  String get anime4kDisabled => '已關閉 Anime4K';

  @override
  String anime4kSwitchedTo(Object option) {
    return 'Anime4K 已切換為 $option';
  }

  @override
  String get crtDisplayEffectTitle => 'CRT 顯示效果';

  @override
  String get crtProfileDescriptionOff => '保持原始畫面，不啟用 CRT 效果。';

  @override
  String get crtProfileDescriptionLite => '掃描線 + 暗角，效能開銷較小。';

  @override
  String get crtProfileDescriptionStandard => '增加曲面與柵格，畫面更接近 CRT。';

  @override
  String get crtProfileDescriptionHigh => '加入輝光與色散，效果最佳但效能開銷更高。';

  @override
  String get crtDisabled => '已關閉 CRT';

  @override
  String crtSwitchedTo(Object option) {
    return 'CRT 已切換為 $option';
  }

  @override
  String get enterAiApiUrl => '請輸入 AI 介面 URL';

  @override
  String get enterModelName => '請輸入模型名稱';

  @override
  String get enterApiKey => '請輸入 API Key';

  @override
  String get spoilerAiSettingsSaved => '防劇透 AI 設定已儲存';

  @override
  String get spoilerPreventionMode => '防劇透模式';

  @override
  String get spoilerPreventionModeSubtitle => '開啟後，載入彈幕時將透過 AI 識別並屏蔽疑似劇透彈幕。';

  @override
  String get fillAndSaveAiConfigFirst => '請先填寫並儲存 AI 介面設定';

  @override
  String get spoilerPreventionModeEnabled => '已開啟防劇透模式';

  @override
  String get spoilerPreventionModeDisabled => '已關閉防劇透模式';

  @override
  String get autoMatchDanmakuOnPlayTitle => '播放時自動匹配彈幕';

  @override
  String get autoMatchDanmakuOnPlaySubtitle => '關閉後播放時不再自動識別並載入彈幕，可在彈幕設定中手動匹配。';

  @override
  String get autoMatchDanmakuOnPlayEnabled => '已開啟播放時自動匹配彈幕';

  @override
  String get autoMatchDanmakuOnPlayDisabledManual => '已關閉播放時自動匹配彈幕（可手動匹配）';

  @override
  String get autoMatchOnHashFailTitle => '哈希匹配失敗自動匹配彈幕';

  @override
  String get autoMatchOnHashFailSubtitle =>
      '哈希匹配失敗時預設使用檔名搜尋的第一個結果自動匹配；關閉後將彈出搜尋彈幕選單。';

  @override
  String get autoMatchOnHashFailEnabled => '已開啟匹配失敗自動匹配';

  @override
  String get autoMatchOnHashFailDisabledShowSearch => '已關閉匹配失敗自動匹配（將彈出搜尋彈幕選單）';

  @override
  String get hardwareDecoding => '硬體解碼';

  @override
  String get hardwareDecodingSubtitle => '僅對 MDK / Libmpv 生效';

  @override
  String get hardwareDecodingEnabled => '已開啟硬體解碼';

  @override
  String get hardwareDecodingDisabled => '已關閉硬體解碼';

  @override
  String get pauseOnBackgroundTitle => '背景自動暫停';

  @override
  String get pauseOnBackgroundSubtitle => '切到背景或鎖屏時自動暫停播放';

  @override
  String get pauseOnBackgroundEnabled => '背景自動暫停已開啟';

  @override
  String get pauseOnBackgroundDisabled => '背景自動暫停已關閉';

  @override
  String get playbackEndActionTitle => '播放結束操作';

  @override
  String get playbackEndActionAutoNextMessage => '播放結束後將自動進入下一話';

  @override
  String get playbackEndActionLoopMessage => '播放結束後將從頭循環播放';

  @override
  String get playbackEndActionPauseMessage => '播放結束後將停留在目前頁面';

  @override
  String get playbackEndActionExitMessage => '播放結束後將返回上一頁';

  @override
  String get autoNextCountdownTitle => '自動連播倒計時';

  @override
  String autoNextCountdownWaitSeconds(int seconds) {
    return '自動跳轉下一話前等待 $seconds 秒';
  }

  @override
  String get autoNextCountdownNeedAutoNext => '需先啟用自動播放下一話';

  @override
  String get timelinePreviewTitle => '時間軸截圖預覽';

  @override
  String get timelinePreviewSubtitle => '懸停進度條時顯示縮圖（本地/WebDAV/SMB/共享媒體庫生效）';

  @override
  String get enableWarning => '開啟警告';

  @override
  String get timelinePreviewEnableWarningContent =>
      '開啟時間軸截圖預覽會在背景即時生成截圖，可能導致播放卡頓或效能下降。是否確認開啟？';

  @override
  String get timelinePreviewEnabled => '已開啟時間軸截圖預覽';

  @override
  String get timelinePreviewDisabled => '已關閉時間軸截圖預覽';

  @override
  String get playPrecacheDuration => '播放預快取時長';

  @override
  String get playPrecacheSize => '播放預快取大小';

  @override
  String currentPrecacheDurationSeconds(int seconds) {
    return '目前 $seconds 秒，修改後立即生效';
  }

  @override
  String currentPrecacheSizeMb(int mb) {
    return '目前 $mb MB，修改後重新開啟影片生效';
  }

  @override
  String get libmpvKernelOnly => '僅 Libmpv 內核生效';

  @override
  String get spoilerAiSettingsTitle => '防劇透 AI 設定';

  @override
  String get spoilerAiSettingsDescription =>
      '開啟防劇透前請先填寫並儲存設定（必須提供介面 URL / Key / 模型）。';

  @override
  String get spoilerAiGeminiUrlNote =>
      'Gemini：URL 可填到 /v1beta/models，實際請求會自動拼接 /<模型>:generateContent。';

  @override
  String get spoilerAiOpenAiUrlNote =>
      'OpenAI：URL 建議填寫 /v1/chat/completions（相容介面亦可）。';

  @override
  String get apiFormatLabel => '介面格式';

  @override
  String get openAiCompatible => 'OpenAI 相容';

  @override
  String get enterYourApiKey => '請輸入你的 API Key';

  @override
  String temperatureLabel(Object value) {
    return '溫度：$value';
  }

  @override
  String get saveConfiguration => '儲存設定';

  @override
  String get about => '關於';

  @override
  String get loading => '載入中…';

  @override
  String currentVersion(Object version) {
    return '目前版本：$version';
  }

  @override
  String get versionLoadFailed => '版本資訊取得失敗';

  @override
  String get general => '通用';

  @override
  String get backupAndRestore => '備份與復原';

  @override
  String get shortcuts => '快捷鍵';

  @override
  String get remoteAccess => '遠端存取';

  @override
  String get remoteMediaLibrary => '遠端媒體庫';

  @override
  String get appearanceSettings => '外觀設定';

  @override
  String get generalSettings => '通用設定';

  @override
  String get storageSettings => '儲存設定';

  @override
  String get playerSettings => '播放器設定';

  @override
  String get shortcutsSettings => '快捷鍵設定';

  @override
  String get rememberDanmakuOffset => '記憶彈幕偏移';

  @override
  String get rememberDanmakuOffsetSubtitle => '切換影片時保留目前手動偏移（自動匹配偏移仍會重置）。';

  @override
  String get rememberDanmakuOffsetEnabled => '已開啟彈幕偏移記憶';

  @override
  String get rememberDanmakuOffsetDisabled => '已關閉彈幕偏移記憶';

  @override
  String get danmakuConvertToSimplified => '彈幕轉換簡體中文';

  @override
  String get danmakuConvertToSimplifiedSubtitle => '開啟後，將繁體中文彈幕轉換為簡體顯示。';

  @override
  String get danmakuConvertToSimplifiedEnabled => '已開啟彈幕轉換簡體中文';

  @override
  String get danmakuConvertToSimplifiedDisabled => '已關閉彈幕轉換簡體中文';

  @override
  String get cancel => '取消';

  @override
  String get confirm => '確定';

  @override
  String get close => '關閉';

  @override
  String get saving => '儲存中...';

  @override
  String networkServerSwitchedTo(Object server) {
    return '彈彈play 伺服器已切換到 $server';
  }

  @override
  String get enterServerAddress => '請輸入伺服器地址';

  @override
  String get invalidServerAddress => '伺服器地址格式不正確，請以 http/https 開頭';

  @override
  String get switchedToCustomServer => '已切換到自訂伺服器';

  @override
  String get networkPrimaryServerRecommended => '主伺服器 (推薦)';

  @override
  String get networkBackupServer => '備用伺服器';

  @override
  String get networkCurrentCustomServer => '目前自訂伺服器';

  @override
  String get networkSelectServer => '選擇彈彈play 伺服器';

  @override
  String get primaryServer => '主伺服器';

  @override
  String get backupServer => '備用伺服器';

  @override
  String get dandanplayServer => '彈彈play 伺服器';

  @override
  String get customServer => '自訂伺服器';

  @override
  String get customServerInputHint =>
      '輸入相容彈彈play API 的彈幕伺服器地址，例如 https://example.com';

  @override
  String get customServerPlaceholder => 'https://your-danmaku-server.com';

  @override
  String get useThisServer => '使用此伺服器';

  @override
  String get currentServerInfo => '目前伺服器資訊';

  @override
  String get serverDescriptionTitle => '伺服器說明';

  @override
  String serverField(Object server) {
    return '伺服器：$server';
  }

  @override
  String urlField(Object url) {
    return 'URL：$url';
  }

  @override
  String serverBullet(Object name, Object description) {
    return '• $name：$description';
  }

  @override
  String get networkServerDescriptionPrimary =>
      'api.dandanplay.net（官方伺服器，建議使用）';

  @override
  String get networkServerDescriptionBackup =>
      '139.224.252.88:16001（鏡像伺服器，主伺服器無法存取時使用）';

  @override
  String get networkServerSelectSubtitle => '選擇彈彈play 彈幕伺服器。主伺服器無法存取時可使用備用伺服器。';

  @override
  String customServerWithValue(Object server) {
    return '自訂：$server';
  }

  @override
  String get enabledClearOnLaunchSnack => '已啟用啟動時清理彈幕快取';

  @override
  String get danmakuCacheCleared => '彈幕快取已清理';

  @override
  String clearFailed(Object error) {
    return '清理失敗: $error';
  }

  @override
  String get imageCacheCleared => '圖片快取已清除';

  @override
  String get confirmClearCacheTitle => '確認清除快取';

  @override
  String get confirmClearImageCacheContent => '確定要清除封面與縮圖等圖片快取嗎？';

  @override
  String get clearDanmakuCacheOnLaunchTitle => '每次啟動時清理彈幕快取';

  @override
  String get clearDanmakuCacheOnLaunchSubtitle =>
      '自動刪除 cache/danmaku/ 目錄下的彈幕快取';

  @override
  String get screenshotSaveLocation => '截圖儲存位置';

  @override
  String get defaultDownloadDir => '預設：下載目錄';

  @override
  String get screenshotSaveLocationUpdated => '截圖儲存位置已更新';

  @override
  String get screenshotDefaultSaveTarget => '截圖預設儲存位置';

  @override
  String get screenshotDefaultSaveTargetMessage => '選擇截圖後的預設儲存方式';

  @override
  String get clearDanmakuCacheNow => '立即清理彈幕快取';

  @override
  String get clearingInProgress => '正在清理...';

  @override
  String get clearDanmakuCacheManualHint => '當彈幕異常或佔用空間過大時可手動清理';

  @override
  String get clearImageCache => '清除圖片快取';

  @override
  String get clearImageCacheHint => '清除封面與縮圖等圖片快取';

  @override
  String get danmakuCacheDescription =>
      '彈幕快取將儲存在應用快取目錄 cache/danmaku/ 中，啟用自動清理可減少空間佔用。';

  @override
  String get imageCacheDescription => '圖片快取包含封面與播放縮圖，儲存在應用快取目錄中，可按需清理。';

  @override
  String get clearDanmakuCacheOnLaunchSubtitleNipaplay =>
      '重啟應用時自動刪除所有已快取彈幕檔案，確保資料即時';

  @override
  String get clearDanmakuCacheManualHintNipaplay => '刪除快取/快取異常時可手動清理';

  @override
  String get danmakuCacheDescriptionNipaplay =>
      '彈幕快取檔案儲存在 cache/danmaku/ 目錄下，空間佔用較大時可隨時清理。';

  @override
  String get imageCacheDescriptionNipaplay => '圖片快取包含封面與播放縮圖，儲存在應用快取目錄中，可定期清理。';

  @override
  String clearDanmakuCacheFailed(Object error) {
    return '清理彈幕快取失敗: $error';
  }

  @override
  String clearImageCacheFailed(Object error) {
    return '清除圖片快取失敗: $error';
  }

  @override
  String get screenshotSaveAskDescription => '每次截圖時彈出選擇框';

  @override
  String get screenshotSavePhotosDescription => '截圖後直接儲存到相簿';

  @override
  String get screenshotSaveFileDescription => '截圖後直接儲存為檔案';

  @override
  String get aboutNoReleaseNotes => '暫無更新內容';

  @override
  String aboutFoundNewVersion(Object version) {
    return '發現新版本 $version';
  }

  @override
  String get aboutCurrentIsLatest => '目前已是最新版本';

  @override
  String aboutCurrentVersionLabel(Object version) {
    return '目前版本: $version';
  }

  @override
  String aboutLatestVersionLabel(Object version) {
    return '最新版本: $version';
  }

  @override
  String aboutReleaseNameLabel(Object name) {
    return '版本名稱: $name';
  }

  @override
  String aboutPublishedAtLabel(Object publishedAt) {
    return '發佈時間: $publishedAt';
  }

  @override
  String get aboutReleaseNotesTitle => '更新內容';

  @override
  String get aboutOpenReleasePage => '查看發佈頁';

  @override
  String get updateCheckFailed => '檢查更新失敗';

  @override
  String get pleaseTryAgainLater => '請稍後再試';

  @override
  String cannotOpenLink(Object url) {
    return '無法開啟連結: $url';
  }

  @override
  String get appreciationCode => '贊賞碼';

  @override
  String get appreciationImageLoadFailed => '贊賞碼圖片載入失敗';

  @override
  String get acknowledgements => '致謝';

  @override
  String get aboutStoryPrefix => 'NipaPlay，名字來自《寒蟬鳴泣之時》中古手梨花的口頭禪 \"';

  @override
  String get aboutStorySuffix =>
      '\"。為了解決我在 macOS、Linux、iOS 上看番不便的問題，我創造了 NipaPlay。';

  @override
  String get aboutThanksDandanplayPrefix => '感謝彈彈play (DandanPlay) 以及開發者 ';

  @override
  String get aboutThanksDandanplaySuffix => ' 提供的介面與開發協助。';

  @override
  String get aboutThanksSakikoPrefix => '感謝開發者 ';

  @override
  String get aboutThanksSakikoSuffix => ' 協助實現 Emby 與 Jellyfin 媒體庫支援。';

  @override
  String get thanksSponsorUsers => '感謝下列用戶的贊助支持：';

  @override
  String aboutVersionBanner(Object version) {
    return 'NipaPlay Reload 目前版本：$version';
  }

  @override
  String get aboutCheckingUpdates => '檢測中…';

  @override
  String get aboutCheckUpdates => '檢測更新';

  @override
  String get aboutAutoCheckUpdates => '自動檢測更新';

  @override
  String get aboutManualOnlyWhenDisabled => '關閉後僅手動檢測';

  @override
  String aboutQqGroup(Object id) {
    return 'QQ群: $id';
  }

  @override
  String get aboutOfficialWebsite => 'NipaPlay 官方網站';

  @override
  String get openSourceCommunity => '開源與社群';

  @override
  String get aboutCommunityHint =>
      '歡迎貢獻程式碼，或將應用發佈到更多平台。不會 Dart 也沒關係，借助 AI 編程同樣可以。';

  @override
  String get sponsorSupport => '贊助支持';

  @override
  String get aboutSponsorParagraph1 =>
      '如果你喜歡 NipaPlay 並希望支持專案持續開發，歡迎透過愛發電進行贊助。';

  @override
  String get aboutSponsorParagraph2 => '贊助者名稱將出現在專案 README 與每次軟體更新後的關於頁名單中。';

  @override
  String get aboutAfdianSponsorPage => '愛發電贊助頁面';
}
