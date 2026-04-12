import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('zh'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant')
  ];

  /// No description provided for @appTitle.
  ///
  /// In zh, this message translates to:
  /// **'NipaPlay'**
  String get appTitle;

  /// No description provided for @tabHome.
  ///
  /// In zh, this message translates to:
  /// **'主页'**
  String get tabHome;

  /// No description provided for @tabVideoPlay.
  ///
  /// In zh, this message translates to:
  /// **'视频播放'**
  String get tabVideoPlay;

  /// No description provided for @tabMediaLibrary.
  ///
  /// In zh, this message translates to:
  /// **'媒体库'**
  String get tabMediaLibrary;

  /// No description provided for @tabAccount.
  ///
  /// In zh, this message translates to:
  /// **'个人中心'**
  String get tabAccount;

  /// No description provided for @tabSettings.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get tabSettings;

  /// No description provided for @settingsLabel.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get settingsLabel;

  /// No description provided for @toggleToLightMode.
  ///
  /// In zh, this message translates to:
  /// **'切换到日间模式'**
  String get toggleToLightMode;

  /// No description provided for @toggleToDarkMode.
  ///
  /// In zh, this message translates to:
  /// **'切换到夜间模式'**
  String get toggleToDarkMode;

  /// No description provided for @language.
  ///
  /// In zh, this message translates to:
  /// **'语言'**
  String get language;

  /// No description provided for @languageSettingsTitle.
  ///
  /// In zh, this message translates to:
  /// **'语言设置'**
  String get languageSettingsTitle;

  /// No description provided for @languageSettingsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'选择界面显示语言'**
  String get languageSettingsSubtitle;

  /// No description provided for @languageAuto.
  ///
  /// In zh, this message translates to:
  /// **'自动（跟随系统）'**
  String get languageAuto;

  /// No description provided for @languageSimplifiedChinese.
  ///
  /// In zh, this message translates to:
  /// **'简体中文'**
  String get languageSimplifiedChinese;

  /// No description provided for @languageTraditionalChinese.
  ///
  /// In zh, this message translates to:
  /// **'繁體中文'**
  String get languageTraditionalChinese;

  /// No description provided for @currentLanguage.
  ///
  /// In zh, this message translates to:
  /// **'当前：{language}'**
  String currentLanguage(Object language);

  /// No description provided for @currentServer.
  ///
  /// In zh, this message translates to:
  /// **'当前：{server}'**
  String currentServer(Object server);

  /// No description provided for @languageTileSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'切换简体中文或繁體中文'**
  String get languageTileSubtitle;

  /// No description provided for @settingsBasicSection.
  ///
  /// In zh, this message translates to:
  /// **'基础设置'**
  String get settingsBasicSection;

  /// No description provided for @settingsAboutSection.
  ///
  /// In zh, this message translates to:
  /// **'关于'**
  String get settingsAboutSection;

  /// No description provided for @appearance.
  ///
  /// In zh, this message translates to:
  /// **'外观'**
  String get appearance;

  /// No description provided for @lightMode.
  ///
  /// In zh, this message translates to:
  /// **'浅色模式'**
  String get lightMode;

  /// No description provided for @appearanceLightModeSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'保持明亮的界面与对比度。'**
  String get appearanceLightModeSubtitle;

  /// No description provided for @darkMode.
  ///
  /// In zh, this message translates to:
  /// **'深色模式'**
  String get darkMode;

  /// No description provided for @appearanceDarkModeSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'降低亮度，保护视力并节省电量。'**
  String get appearanceDarkModeSubtitle;

  /// No description provided for @followSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get followSystem;

  /// No description provided for @appearanceFollowSystemSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'自动根据系统设置切换外观。'**
  String get appearanceFollowSystemSubtitle;

  /// No description provided for @appearanceAnimeDetailStyle.
  ///
  /// In zh, this message translates to:
  /// **'番剧详情样式'**
  String get appearanceAnimeDetailStyle;

  /// No description provided for @appearanceDetailSimple.
  ///
  /// In zh, this message translates to:
  /// **'简洁模式'**
  String get appearanceDetailSimple;

  /// No description provided for @appearanceDetailSimpleSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'经典布局，信息分栏展示。'**
  String get appearanceDetailSimpleSubtitle;

  /// No description provided for @appearanceDetailVivid.
  ///
  /// In zh, this message translates to:
  /// **'绚丽模式'**
  String get appearanceDetailVivid;

  /// No description provided for @appearanceDetailVividSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'海报主视觉、横向剧集卡片。'**
  String get appearanceDetailVividSubtitle;

  /// No description provided for @appearanceRecentWatchingStyle.
  ///
  /// In zh, this message translates to:
  /// **'最近观看样式'**
  String get appearanceRecentWatchingStyle;

  /// No description provided for @appearanceRecentSimple.
  ///
  /// In zh, this message translates to:
  /// **'简洁版'**
  String get appearanceRecentSimple;

  /// No description provided for @appearanceRecentSimpleSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'纯文本列表，节省空间。'**
  String get appearanceRecentSimpleSubtitle;

  /// No description provided for @appearanceRecentDetailed.
  ///
  /// In zh, this message translates to:
  /// **'详细版'**
  String get appearanceRecentDetailed;

  /// No description provided for @appearanceRecentDetailedSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'带截图的横向滚动卡片。'**
  String get appearanceRecentDetailedSubtitle;

  /// No description provided for @appearanceHomeSections.
  ///
  /// In zh, this message translates to:
  /// **'主页板块'**
  String get appearanceHomeSections;

  /// No description provided for @restoreDefaults.
  ///
  /// In zh, this message translates to:
  /// **'恢复默认'**
  String get restoreDefaults;

  /// No description provided for @restoreDefaultsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'恢复默认排序与显示状态'**
  String get restoreDefaultsSubtitle;

  /// No description provided for @uiThemeExperimental.
  ///
  /// In zh, this message translates to:
  /// **'主题（实验性）'**
  String get uiThemeExperimental;

  /// No description provided for @uiThemeRestartHint.
  ///
  /// In zh, this message translates to:
  /// **'提示：切换主题后需要重新启动应用才能完全生效。'**
  String get uiThemeRestartHint;

  /// No description provided for @uiThemeSwitchDialogTitle.
  ///
  /// In zh, this message translates to:
  /// **'主题切换提示'**
  String get uiThemeSwitchDialogTitle;

  /// No description provided for @uiThemeSwitchDialogMessage.
  ///
  /// In zh, this message translates to:
  /// **'切换到 {theme} 主题需要重启应用才能完全生效。\n\n是否要立即重启应用？'**
  String uiThemeSwitchDialogMessage(Object theme);

  /// No description provided for @restartApp.
  ///
  /// In zh, this message translates to:
  /// **'重启应用'**
  String get restartApp;

  /// No description provided for @refreshPageApplyTheme.
  ///
  /// In zh, this message translates to:
  /// **'请手动刷新页面以应用新主题'**
  String get refreshPageApplyTheme;

  /// No description provided for @player.
  ///
  /// In zh, this message translates to:
  /// **'播放器'**
  String get player;

  /// No description provided for @playerKernelCurrentMdk.
  ///
  /// In zh, this message translates to:
  /// **'当前：MDK'**
  String get playerKernelCurrentMdk;

  /// No description provided for @playerKernelCurrentVideoPlayer.
  ///
  /// In zh, this message translates to:
  /// **'当前：Video Player'**
  String get playerKernelCurrentVideoPlayer;

  /// No description provided for @playerKernelCurrentLibmpv.
  ///
  /// In zh, this message translates to:
  /// **'当前：Libmpv'**
  String get playerKernelCurrentLibmpv;

  /// No description provided for @externalCall.
  ///
  /// In zh, this message translates to:
  /// **'外部调用'**
  String get externalCall;

  /// No description provided for @externalPlayerEnabled.
  ///
  /// In zh, this message translates to:
  /// **'已启用外部播放器'**
  String get externalPlayerEnabled;

  /// No description provided for @externalPlayerDisabled.
  ///
  /// In zh, this message translates to:
  /// **'未启用外部播放器'**
  String get externalPlayerDisabled;

  /// No description provided for @externalPlayerIntroDesktop.
  ///
  /// In zh, this message translates to:
  /// **'启用后，所有播放操作将通过外部播放器打开。'**
  String get externalPlayerIntroDesktop;

  /// No description provided for @externalPlayerIntroUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'仅桌面端支持外部播放器调用。'**
  String get externalPlayerIntroUnsupported;

  /// No description provided for @externalPlayerEnableTitle.
  ///
  /// In zh, this message translates to:
  /// **'启用外部播放器'**
  String get externalPlayerEnableTitle;

  /// No description provided for @externalPlayerEnableSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'开启后将使用外部播放器播放视频'**
  String get externalPlayerEnableSubtitle;

  /// No description provided for @externalPlayerSelectTitle.
  ///
  /// In zh, this message translates to:
  /// **'选择外部播放器'**
  String get externalPlayerSelectTitle;

  /// No description provided for @externalPlayerNotSelected.
  ///
  /// In zh, this message translates to:
  /// **'未选择外部播放器'**
  String get externalPlayerNotSelected;

  /// No description provided for @externalPlayerSelectionCanceled.
  ///
  /// In zh, this message translates to:
  /// **'已取消选择外部播放器'**
  String get externalPlayerSelectionCanceled;

  /// No description provided for @externalPlayerUpdated.
  ///
  /// In zh, this message translates to:
  /// **'已更新外部播放器'**
  String get externalPlayerUpdated;

  /// No description provided for @desktopOnlySupported.
  ///
  /// In zh, this message translates to:
  /// **'仅桌面端支持'**
  String get desktopOnlySupported;

  /// No description provided for @networkSettings.
  ///
  /// In zh, this message translates to:
  /// **'网络设置'**
  String get networkSettings;

  /// No description provided for @networkSettingsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'弹弹play 服务器及自定义地址'**
  String get networkSettingsSubtitle;

  /// No description provided for @storage.
  ///
  /// In zh, this message translates to:
  /// **'存储'**
  String get storage;

  /// No description provided for @storageSettingsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'管理弹幕缓存与清理策略'**
  String get storageSettingsSubtitle;

  /// No description provided for @networkMediaLibrary.
  ///
  /// In zh, this message translates to:
  /// **'网络媒体库'**
  String get networkMediaLibrary;

  /// No description provided for @retry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get retry;

  /// No description provided for @save.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get save;

  /// No description provided for @disconnect.
  ///
  /// In zh, this message translates to:
  /// **'断开连接'**
  String get disconnect;

  /// No description provided for @loadFailed.
  ///
  /// In zh, this message translates to:
  /// **'加载失败'**
  String get loadFailed;

  /// No description provided for @loadFailedWithError.
  ///
  /// In zh, this message translates to:
  /// **'加载失败：{error}'**
  String loadFailedWithError(Object error);

  /// No description provided for @operationFailed.
  ///
  /// In zh, this message translates to:
  /// **'操作失败：{error}'**
  String operationFailed(Object error);

  /// No description provided for @saveFailedWithError.
  ///
  /// In zh, this message translates to:
  /// **'保存失败：{error}'**
  String saveFailedWithError(Object error);

  /// No description provided for @connectFailedWithError.
  ///
  /// In zh, this message translates to:
  /// **'连接失败：{error}'**
  String connectFailedWithError(Object error);

  /// No description provided for @refreshFailedWithError.
  ///
  /// In zh, this message translates to:
  /// **'刷新失败：{error}'**
  String refreshFailedWithError(Object error);

  /// No description provided for @disconnectFailedWithError.
  ///
  /// In zh, this message translates to:
  /// **'断开失败：{error}'**
  String disconnectFailedWithError(Object error);

  /// No description provided for @deviceIdTitle.
  ///
  /// In zh, this message translates to:
  /// **'设备标识 (DeviceId)'**
  String get deviceIdTitle;

  /// No description provided for @deviceIdDescription.
  ///
  /// In zh, this message translates to:
  /// **'用于 Jellyfin / Emby 区分不同设备，避免互踢登出。'**
  String get deviceIdDescription;

  /// No description provided for @deviceIdCurrent.
  ///
  /// In zh, this message translates to:
  /// **'当前 DeviceId'**
  String get deviceIdCurrent;

  /// No description provided for @deviceIdGenerated.
  ///
  /// In zh, this message translates to:
  /// **'自动生成标识'**
  String get deviceIdGenerated;

  /// No description provided for @deviceIdCustom.
  ///
  /// In zh, this message translates to:
  /// **'自定义 DeviceId'**
  String get deviceIdCustom;

  /// No description provided for @deviceIdCustomSet.
  ///
  /// In zh, this message translates to:
  /// **'已设置：{deviceId}'**
  String deviceIdCustomSet(Object deviceId);

  /// No description provided for @deviceIdCustomUnset.
  ///
  /// In zh, this message translates to:
  /// **'未设置（使用自动生成）'**
  String get deviceIdCustomUnset;

  /// No description provided for @deviceIdRestoreAuto.
  ///
  /// In zh, this message translates to:
  /// **'恢复自动生成'**
  String get deviceIdRestoreAuto;

  /// No description provided for @deviceIdRestoreAutoSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'清除自定义 DeviceId'**
  String get deviceIdRestoreAutoSubtitle;

  /// No description provided for @deviceIdRestoreSuccess.
  ///
  /// In zh, this message translates to:
  /// **'已恢复自动生成的设备ID'**
  String get deviceIdRestoreSuccess;

  /// No description provided for @deviceIdDialogTitle.
  ///
  /// In zh, this message translates to:
  /// **'自定义 DeviceId'**
  String get deviceIdDialogTitle;

  /// No description provided for @deviceIdDialogHint.
  ///
  /// In zh, this message translates to:
  /// **'留空表示使用自动生成的设备标识。'**
  String get deviceIdDialogHint;

  /// No description provided for @deviceIdDialogPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'例如: My-iPhone-01'**
  String get deviceIdDialogPlaceholder;

  /// No description provided for @deviceIdDialogValidationHint.
  ///
  /// In zh, this message translates to:
  /// **'不要包含双引号/换行，长度不超过128。'**
  String get deviceIdDialogValidationHint;

  /// No description provided for @deviceIdUpdatedHint.
  ///
  /// In zh, this message translates to:
  /// **'设备ID已更新，建议断开并重新连接服务器'**
  String get deviceIdUpdatedHint;

  /// No description provided for @deviceIdInvalid.
  ///
  /// In zh, this message translates to:
  /// **'DeviceId 无效：请避免双引号/换行，且长度 ≤ 128'**
  String get deviceIdInvalid;

  /// No description provided for @networkServerConnected.
  ///
  /// In zh, this message translates to:
  /// **'{server} 服务器已连接'**
  String networkServerConnected(Object server);

  /// No description provided for @networkServerSettingsUpdated.
  ///
  /// In zh, this message translates to:
  /// **'{server} 服务器设置已更新'**
  String networkServerSettingsUpdated(Object server);

  /// No description provided for @disconnectServerConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定要断开与 {server} 服务器的连接吗？'**
  String disconnectServerConfirm(Object server);

  /// No description provided for @networkServerDisconnected.
  ///
  /// In zh, this message translates to:
  /// **'{server} 已断开连接'**
  String networkServerDisconnected(Object server);

  /// No description provided for @disconnectServerFailed.
  ///
  /// In zh, this message translates to:
  /// **'断开 {server} 失败：{error}'**
  String disconnectServerFailed(Object server, Object error);

  /// No description provided for @networkServerNotConnected.
  ///
  /// In zh, this message translates to:
  /// **'尚未连接到 {server} 服务器'**
  String networkServerNotConnected(Object server);

  /// No description provided for @networkLibraryRefreshed.
  ///
  /// In zh, this message translates to:
  /// **'{server} 媒体库已刷新'**
  String networkLibraryRefreshed(Object server);

  /// No description provided for @connectJellyfinOrEmbyFirst.
  ///
  /// In zh, this message translates to:
  /// **'请先连接 Jellyfin 或 Emby 服务器'**
  String get connectJellyfinOrEmbyFirst;

  /// No description provided for @networkMediaLibraryIntro.
  ///
  /// In zh, this message translates to:
  /// **'在此管理 Jellyfin / Emby 服务器连接，并设置弹弹play 远程媒体库。'**
  String get networkMediaLibraryIntro;

  /// No description provided for @jellyfinMediaServerTitle.
  ///
  /// In zh, this message translates to:
  /// **'Jellyfin 媒体服务器'**
  String get jellyfinMediaServerTitle;

  /// No description provided for @jellyfinDisconnectedDescription.
  ///
  /// In zh, this message translates to:
  /// **'连接 Jellyfin 服务器以同步远程媒体库与播放记录。'**
  String get jellyfinDisconnectedDescription;

  /// No description provided for @embyMediaServerTitle.
  ///
  /// In zh, this message translates to:
  /// **'Emby 媒体服务器'**
  String get embyMediaServerTitle;

  /// No description provided for @embyDisconnectedDescription.
  ///
  /// In zh, this message translates to:
  /// **'连接 Emby 服务器后可浏览个人媒体库并远程播放。'**
  String get embyDisconnectedDescription;

  /// No description provided for @dandanRemoteConfigUpdated.
  ///
  /// In zh, this message translates to:
  /// **'弹弹play 远程服务配置已更新'**
  String get dandanRemoteConfigUpdated;

  /// No description provided for @dandanRemoteConnected.
  ///
  /// In zh, this message translates to:
  /// **'弹弹play 远程服务已连接'**
  String get dandanRemoteConnected;

  /// No description provided for @dandanRemoteDisconnected.
  ///
  /// In zh, this message translates to:
  /// **'已断开与弹弹play远程服务的连接'**
  String get dandanRemoteDisconnected;

  /// No description provided for @disconnectDandanRemoteTitle.
  ///
  /// In zh, this message translates to:
  /// **'断开弹弹play远程服务'**
  String get disconnectDandanRemoteTitle;

  /// No description provided for @disconnectDandanRemoteContent.
  ///
  /// In zh, this message translates to:
  /// **'确定要断开与弹弹play远程服务的连接吗？\n\n这将清除保存的服务器地址与 API 密钥。'**
  String get disconnectDandanRemoteContent;

  /// No description provided for @remoteLibraryRefreshed.
  ///
  /// In zh, this message translates to:
  /// **'远程媒体库已刷新'**
  String get remoteLibraryRefreshed;

  /// No description provided for @noConnectedServer.
  ///
  /// In zh, this message translates to:
  /// **'尚未连接任何服务器'**
  String get noConnectedServer;

  /// No description provided for @mediaLibraryNotSelected.
  ///
  /// In zh, this message translates to:
  /// **'未选择媒体库'**
  String get mediaLibraryNotSelected;

  /// No description provided for @mediaLibraryNotMatched.
  ///
  /// In zh, this message translates to:
  /// **'未匹配到媒体库'**
  String get mediaLibraryNotMatched;

  /// No description provided for @mediaLibraryAndCount.
  ///
  /// In zh, this message translates to:
  /// **'{first} 等 {count} 个'**
  String mediaLibraryAndCount(Object first, int count);

  /// No description provided for @mediaServerSummary.
  ///
  /// In zh, this message translates to:
  /// **'{server} · {summary}'**
  String mediaServerSummary(Object server, Object summary);

  /// No description provided for @developerOptions.
  ///
  /// In zh, this message translates to:
  /// **'开发者选项'**
  String get developerOptions;

  /// No description provided for @developerOptionsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'终端输出、依赖版本、构建信息'**
  String get developerOptionsSubtitle;

  /// No description provided for @terminalOutput.
  ///
  /// In zh, this message translates to:
  /// **'终端输出'**
  String get terminalOutput;

  /// No description provided for @terminalOutputSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'查看日志、复制内容或生成二维码分享'**
  String get terminalOutputSubtitle;

  /// No description provided for @dependencyVersions.
  ///
  /// In zh, this message translates to:
  /// **'依赖库版本'**
  String get dependencyVersions;

  /// No description provided for @dependencyVersionsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'查看依赖库与版本号（含 GitHub 跳转）'**
  String get dependencyVersionsSubtitle;

  /// No description provided for @buildInfo.
  ///
  /// In zh, this message translates to:
  /// **'构建信息'**
  String get buildInfo;

  /// No description provided for @buildInfoSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'查看构建时间、处理器、内存与系统架构'**
  String get buildInfoSubtitle;

  /// No description provided for @fileLogWriteTitle.
  ///
  /// In zh, this message translates to:
  /// **'日志写入文件'**
  String get fileLogWriteTitle;

  /// No description provided for @fileLogWriteSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'每 1 秒写入磁盘，保留最近 5 份日志文件'**
  String get fileLogWriteSubtitle;

  /// No description provided for @fileLogWriteEnabled.
  ///
  /// In zh, this message translates to:
  /// **'已开启日志写入文件'**
  String get fileLogWriteEnabled;

  /// No description provided for @fileLogWriteDisabled.
  ///
  /// In zh, this message translates to:
  /// **'已关闭日志写入文件'**
  String get fileLogWriteDisabled;

  /// No description provided for @openLogDirectoryTitle.
  ///
  /// In zh, this message translates to:
  /// **'打开日志路径'**
  String get openLogDirectoryTitle;

  /// No description provided for @openLogDirectorySubtitle.
  ///
  /// In zh, this message translates to:
  /// **'在文件管理器中打开日志目录'**
  String get openLogDirectorySubtitle;

  /// No description provided for @logDirectoryOpened.
  ///
  /// In zh, this message translates to:
  /// **'已打开日志目录'**
  String get logDirectoryOpened;

  /// No description provided for @openLogDirectoryFailed.
  ///
  /// In zh, this message translates to:
  /// **'打开日志目录失败'**
  String get openLogDirectoryFailed;

  /// No description provided for @spoilerAiDebugPrintTitle.
  ///
  /// In zh, this message translates to:
  /// **'调试：打印 AI 返回内容'**
  String get spoilerAiDebugPrintTitle;

  /// No description provided for @spoilerAiDebugPrintEnabledHint.
  ///
  /// In zh, this message translates to:
  /// **'开启后会在日志里打印 AI 返回的原始文本与命中弹幕。'**
  String get spoilerAiDebugPrintEnabledHint;

  /// No description provided for @spoilerAiDebugPrintNeedSpoilerMode.
  ///
  /// In zh, this message translates to:
  /// **'需先启用防剧透模式'**
  String get spoilerAiDebugPrintNeedSpoilerMode;

  /// No description provided for @spoilerAiDebugPrintEnabled.
  ///
  /// In zh, this message translates to:
  /// **'已开启 AI 调试打印'**
  String get spoilerAiDebugPrintEnabled;

  /// No description provided for @spoilerAiDebugPrintDisabled.
  ///
  /// In zh, this message translates to:
  /// **'已关闭 AI 调试打印'**
  String get spoilerAiDebugPrintDisabled;

  /// No description provided for @about.
  ///
  /// In zh, this message translates to:
  /// **'关于'**
  String get about;

  /// No description provided for @loading.
  ///
  /// In zh, this message translates to:
  /// **'加载中…'**
  String get loading;

  /// No description provided for @currentVersion.
  ///
  /// In zh, this message translates to:
  /// **'当前版本：{version}'**
  String currentVersion(Object version);

  /// No description provided for @versionLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'版本信息获取失败'**
  String get versionLoadFailed;

  /// No description provided for @general.
  ///
  /// In zh, this message translates to:
  /// **'通用'**
  String get general;

  /// No description provided for @backupAndRestore.
  ///
  /// In zh, this message translates to:
  /// **'备份与恢复'**
  String get backupAndRestore;

  /// No description provided for @shortcuts.
  ///
  /// In zh, this message translates to:
  /// **'快捷键'**
  String get shortcuts;

  /// No description provided for @remoteAccess.
  ///
  /// In zh, this message translates to:
  /// **'远程访问'**
  String get remoteAccess;

  /// No description provided for @remoteMediaLibrary.
  ///
  /// In zh, this message translates to:
  /// **'远程媒体库'**
  String get remoteMediaLibrary;

  /// No description provided for @appearanceSettings.
  ///
  /// In zh, this message translates to:
  /// **'外观设置'**
  String get appearanceSettings;

  /// No description provided for @generalSettings.
  ///
  /// In zh, this message translates to:
  /// **'通用设置'**
  String get generalSettings;

  /// No description provided for @storageSettings.
  ///
  /// In zh, this message translates to:
  /// **'存储设置'**
  String get storageSettings;

  /// No description provided for @playerSettings.
  ///
  /// In zh, this message translates to:
  /// **'播放器设置'**
  String get playerSettings;

  /// No description provided for @shortcutsSettings.
  ///
  /// In zh, this message translates to:
  /// **'快捷键设置'**
  String get shortcutsSettings;

  /// No description provided for @rememberDanmakuOffset.
  ///
  /// In zh, this message translates to:
  /// **'记忆弹幕偏移'**
  String get rememberDanmakuOffset;

  /// No description provided for @rememberDanmakuOffsetSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'切换视频时保留当前手动偏移（自动匹配偏移仍会重置）。'**
  String get rememberDanmakuOffsetSubtitle;

  /// No description provided for @rememberDanmakuOffsetEnabled.
  ///
  /// In zh, this message translates to:
  /// **'已开启弹幕偏移记忆'**
  String get rememberDanmakuOffsetEnabled;

  /// No description provided for @rememberDanmakuOffsetDisabled.
  ///
  /// In zh, this message translates to:
  /// **'已关闭弹幕偏移记忆'**
  String get rememberDanmakuOffsetDisabled;

  /// No description provided for @danmakuConvertToSimplified.
  ///
  /// In zh, this message translates to:
  /// **'弹幕转换简体中文'**
  String get danmakuConvertToSimplified;

  /// No description provided for @danmakuConvertToSimplifiedSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'开启后，将繁体中文弹幕转换为简体显示。'**
  String get danmakuConvertToSimplifiedSubtitle;

  /// No description provided for @danmakuConvertToSimplifiedEnabled.
  ///
  /// In zh, this message translates to:
  /// **'已开启弹幕转换简体中文'**
  String get danmakuConvertToSimplifiedEnabled;

  /// No description provided for @danmakuConvertToSimplifiedDisabled.
  ///
  /// In zh, this message translates to:
  /// **'已关闭弹幕转换简体中文'**
  String get danmakuConvertToSimplifiedDisabled;

  /// No description provided for @cancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get cancel;

  /// No description provided for @confirm.
  ///
  /// In zh, this message translates to:
  /// **'确定'**
  String get confirm;

  /// No description provided for @close.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get close;

  /// No description provided for @saving.
  ///
  /// In zh, this message translates to:
  /// **'保存中...'**
  String get saving;

  /// No description provided for @networkServerSwitchedTo.
  ///
  /// In zh, this message translates to:
  /// **'弹弹play 服务器已切换到 {server}'**
  String networkServerSwitchedTo(Object server);

  /// No description provided for @enterServerAddress.
  ///
  /// In zh, this message translates to:
  /// **'请输入服务器地址'**
  String get enterServerAddress;

  /// No description provided for @invalidServerAddress.
  ///
  /// In zh, this message translates to:
  /// **'服务器地址格式不正确，请以 http/https 开头'**
  String get invalidServerAddress;

  /// No description provided for @switchedToCustomServer.
  ///
  /// In zh, this message translates to:
  /// **'已切换到自定义服务器'**
  String get switchedToCustomServer;

  /// No description provided for @networkPrimaryServerRecommended.
  ///
  /// In zh, this message translates to:
  /// **'主服务器 (推荐)'**
  String get networkPrimaryServerRecommended;

  /// No description provided for @networkBackupServer.
  ///
  /// In zh, this message translates to:
  /// **'备用服务器'**
  String get networkBackupServer;

  /// No description provided for @networkCurrentCustomServer.
  ///
  /// In zh, this message translates to:
  /// **'当前自定义服务器'**
  String get networkCurrentCustomServer;

  /// No description provided for @networkSelectServer.
  ///
  /// In zh, this message translates to:
  /// **'选择弹弹play 服务器'**
  String get networkSelectServer;

  /// No description provided for @primaryServer.
  ///
  /// In zh, this message translates to:
  /// **'主服务器'**
  String get primaryServer;

  /// No description provided for @backupServer.
  ///
  /// In zh, this message translates to:
  /// **'备用服务器'**
  String get backupServer;

  /// No description provided for @dandanplayServer.
  ///
  /// In zh, this message translates to:
  /// **'弹弹play 服务器'**
  String get dandanplayServer;

  /// No description provided for @customServer.
  ///
  /// In zh, this message translates to:
  /// **'自定义服务器'**
  String get customServer;

  /// No description provided for @customServerInputHint.
  ///
  /// In zh, this message translates to:
  /// **'输入兼容弹弹play API 的弹幕服务器地址，例如 https://example.com'**
  String get customServerInputHint;

  /// No description provided for @customServerPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'https://your-danmaku-server.com'**
  String get customServerPlaceholder;

  /// No description provided for @useThisServer.
  ///
  /// In zh, this message translates to:
  /// **'使用该服务器'**
  String get useThisServer;

  /// No description provided for @currentServerInfo.
  ///
  /// In zh, this message translates to:
  /// **'当前服务器信息'**
  String get currentServerInfo;

  /// No description provided for @serverDescriptionTitle.
  ///
  /// In zh, this message translates to:
  /// **'服务器说明'**
  String get serverDescriptionTitle;

  /// No description provided for @serverField.
  ///
  /// In zh, this message translates to:
  /// **'服务器：{server}'**
  String serverField(Object server);

  /// No description provided for @urlField.
  ///
  /// In zh, this message translates to:
  /// **'URL：{url}'**
  String urlField(Object url);

  /// No description provided for @serverBullet.
  ///
  /// In zh, this message translates to:
  /// **'• {name}：{description}'**
  String serverBullet(Object name, Object description);

  /// No description provided for @networkServerDescriptionPrimary.
  ///
  /// In zh, this message translates to:
  /// **'api.dandanplay.net（官方服务器，推荐使用）'**
  String get networkServerDescriptionPrimary;

  /// No description provided for @networkServerDescriptionBackup.
  ///
  /// In zh, this message translates to:
  /// **'139.224.252.88:16001（镜像服务器，主服务器无法访问时使用）'**
  String get networkServerDescriptionBackup;

  /// No description provided for @networkServerSelectSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'选择弹弹play弹幕服务器。备用服务器可在主服务器无法访问时使用。'**
  String get networkServerSelectSubtitle;

  /// No description provided for @customServerWithValue.
  ///
  /// In zh, this message translates to:
  /// **'自定义：{server}'**
  String customServerWithValue(Object server);

  /// No description provided for @enabledClearOnLaunchSnack.
  ///
  /// In zh, this message translates to:
  /// **'已启用启动时清理弹幕缓存'**
  String get enabledClearOnLaunchSnack;

  /// No description provided for @danmakuCacheCleared.
  ///
  /// In zh, this message translates to:
  /// **'弹幕缓存已清理'**
  String get danmakuCacheCleared;

  /// No description provided for @clearFailed.
  ///
  /// In zh, this message translates to:
  /// **'清理失败: {error}'**
  String clearFailed(Object error);

  /// No description provided for @imageCacheCleared.
  ///
  /// In zh, this message translates to:
  /// **'图片缓存已清除'**
  String get imageCacheCleared;

  /// No description provided for @confirmClearCacheTitle.
  ///
  /// In zh, this message translates to:
  /// **'确认清除缓存'**
  String get confirmClearCacheTitle;

  /// No description provided for @confirmClearImageCacheContent.
  ///
  /// In zh, this message translates to:
  /// **'确定要清除封面与缩略图等图片缓存吗？'**
  String get confirmClearImageCacheContent;

  /// No description provided for @clearDanmakuCacheOnLaunchTitle.
  ///
  /// In zh, this message translates to:
  /// **'每次启动时清理弹幕缓存'**
  String get clearDanmakuCacheOnLaunchTitle;

  /// No description provided for @clearDanmakuCacheOnLaunchSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'自动删除 cache/danmaku/ 目录下的弹幕缓存'**
  String get clearDanmakuCacheOnLaunchSubtitle;

  /// No description provided for @screenshotSaveLocation.
  ///
  /// In zh, this message translates to:
  /// **'截图保存位置'**
  String get screenshotSaveLocation;

  /// No description provided for @defaultDownloadDir.
  ///
  /// In zh, this message translates to:
  /// **'默认：下载目录'**
  String get defaultDownloadDir;

  /// No description provided for @screenshotSaveLocationUpdated.
  ///
  /// In zh, this message translates to:
  /// **'截图保存位置已更新'**
  String get screenshotSaveLocationUpdated;

  /// No description provided for @screenshotDefaultSaveTarget.
  ///
  /// In zh, this message translates to:
  /// **'截图默认保存位置'**
  String get screenshotDefaultSaveTarget;

  /// No description provided for @screenshotDefaultSaveTargetMessage.
  ///
  /// In zh, this message translates to:
  /// **'选择截图后的默认保存方式'**
  String get screenshotDefaultSaveTargetMessage;

  /// No description provided for @clearDanmakuCacheNow.
  ///
  /// In zh, this message translates to:
  /// **'立即清理弹幕缓存'**
  String get clearDanmakuCacheNow;

  /// No description provided for @clearingInProgress.
  ///
  /// In zh, this message translates to:
  /// **'正在清理...'**
  String get clearingInProgress;

  /// No description provided for @clearDanmakuCacheManualHint.
  ///
  /// In zh, this message translates to:
  /// **'当弹幕异常或占用空间过大时可手动清理'**
  String get clearDanmakuCacheManualHint;

  /// No description provided for @clearImageCache.
  ///
  /// In zh, this message translates to:
  /// **'清除图片缓存'**
  String get clearImageCache;

  /// No description provided for @clearImageCacheHint.
  ///
  /// In zh, this message translates to:
  /// **'清除封面与缩略图等图片缓存'**
  String get clearImageCacheHint;

  /// No description provided for @danmakuCacheDescription.
  ///
  /// In zh, this message translates to:
  /// **'弹幕缓存将存储在应用缓存目录 cache/danmaku/ 中，启用自动清理可减轻空间占用。'**
  String get danmakuCacheDescription;

  /// No description provided for @imageCacheDescription.
  ///
  /// In zh, this message translates to:
  /// **'图片缓存包含封面与播放缩略图，存储在应用缓存目录中，可按需清理。'**
  String get imageCacheDescription;

  /// No description provided for @clearDanmakuCacheOnLaunchSubtitleNipaplay.
  ///
  /// In zh, this message translates to:
  /// **'重启应用时自动删除所有已缓存的弹幕文件，确保数据实时'**
  String get clearDanmakuCacheOnLaunchSubtitleNipaplay;

  /// No description provided for @clearDanmakuCacheManualHintNipaplay.
  ///
  /// In zh, this message translates to:
  /// **'删除缓存/缓存异常时可手动清理'**
  String get clearDanmakuCacheManualHintNipaplay;

  /// No description provided for @danmakuCacheDescriptionNipaplay.
  ///
  /// In zh, this message translates to:
  /// **'弹幕缓存文件存储在 cache/danmaku/ 目录下，占用空间较大时可随时清理。'**
  String get danmakuCacheDescriptionNipaplay;

  /// No description provided for @imageCacheDescriptionNipaplay.
  ///
  /// In zh, this message translates to:
  /// **'图片缓存包含封面与播放缩略图，存储在应用缓存目录中，可定期清理。'**
  String get imageCacheDescriptionNipaplay;

  /// No description provided for @clearDanmakuCacheFailed.
  ///
  /// In zh, this message translates to:
  /// **'清理弹幕缓存失败: {error}'**
  String clearDanmakuCacheFailed(Object error);

  /// No description provided for @clearImageCacheFailed.
  ///
  /// In zh, this message translates to:
  /// **'清除图片缓存失败: {error}'**
  String clearImageCacheFailed(Object error);

  /// No description provided for @screenshotSaveAskDescription.
  ///
  /// In zh, this message translates to:
  /// **'每次截图时弹出选择框'**
  String get screenshotSaveAskDescription;

  /// No description provided for @screenshotSavePhotosDescription.
  ///
  /// In zh, this message translates to:
  /// **'截图后直接保存到相册'**
  String get screenshotSavePhotosDescription;

  /// No description provided for @screenshotSaveFileDescription.
  ///
  /// In zh, this message translates to:
  /// **'截图后直接保存为文件'**
  String get screenshotSaveFileDescription;

  /// No description provided for @aboutNoReleaseNotes.
  ///
  /// In zh, this message translates to:
  /// **'暂无更新内容'**
  String get aboutNoReleaseNotes;

  /// No description provided for @aboutFoundNewVersion.
  ///
  /// In zh, this message translates to:
  /// **'发现新版本 {version}'**
  String aboutFoundNewVersion(Object version);

  /// No description provided for @aboutCurrentIsLatest.
  ///
  /// In zh, this message translates to:
  /// **'当前已是最新版本'**
  String get aboutCurrentIsLatest;

  /// No description provided for @aboutCurrentVersionLabel.
  ///
  /// In zh, this message translates to:
  /// **'当前版本: {version}'**
  String aboutCurrentVersionLabel(Object version);

  /// No description provided for @aboutLatestVersionLabel.
  ///
  /// In zh, this message translates to:
  /// **'最新版本: {version}'**
  String aboutLatestVersionLabel(Object version);

  /// No description provided for @aboutReleaseNameLabel.
  ///
  /// In zh, this message translates to:
  /// **'版本名称: {name}'**
  String aboutReleaseNameLabel(Object name);

  /// No description provided for @aboutPublishedAtLabel.
  ///
  /// In zh, this message translates to:
  /// **'发布时间: {publishedAt}'**
  String aboutPublishedAtLabel(Object publishedAt);

  /// No description provided for @aboutReleaseNotesTitle.
  ///
  /// In zh, this message translates to:
  /// **'更新内容'**
  String get aboutReleaseNotesTitle;

  /// No description provided for @aboutOpenReleasePage.
  ///
  /// In zh, this message translates to:
  /// **'查看发布页'**
  String get aboutOpenReleasePage;

  /// No description provided for @updateCheckFailed.
  ///
  /// In zh, this message translates to:
  /// **'检查更新失败'**
  String get updateCheckFailed;

  /// No description provided for @pleaseTryAgainLater.
  ///
  /// In zh, this message translates to:
  /// **'请稍后再试'**
  String get pleaseTryAgainLater;

  /// No description provided for @cannotOpenLink.
  ///
  /// In zh, this message translates to:
  /// **'无法打开链接: {url}'**
  String cannotOpenLink(Object url);

  /// No description provided for @appreciationCode.
  ///
  /// In zh, this message translates to:
  /// **'赞赏码'**
  String get appreciationCode;

  /// No description provided for @appreciationImageLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'赞赏码图片加载失败'**
  String get appreciationImageLoadFailed;

  /// No description provided for @acknowledgements.
  ///
  /// In zh, this message translates to:
  /// **'致谢'**
  String get acknowledgements;

  /// No description provided for @aboutStoryPrefix.
  ///
  /// In zh, this message translates to:
  /// **'NipaPlay，名字来自《寒蝉鸣泣之时》中古手梨花的口头禅 \"'**
  String get aboutStoryPrefix;

  /// No description provided for @aboutStorySuffix.
  ///
  /// In zh, this message translates to:
  /// **'\"。为了解决我在 macOS、Linux、iOS 上看番不便的问题，我创造了 NipaPlay。'**
  String get aboutStorySuffix;

  /// No description provided for @aboutThanksDandanplayPrefix.
  ///
  /// In zh, this message translates to:
  /// **'感谢弹弹play (DandanPlay) 以及开发者 '**
  String get aboutThanksDandanplayPrefix;

  /// No description provided for @aboutThanksDandanplaySuffix.
  ///
  /// In zh, this message translates to:
  /// **' 提供的接口与开发帮助。'**
  String get aboutThanksDandanplaySuffix;

  /// No description provided for @aboutThanksSakikoPrefix.
  ///
  /// In zh, this message translates to:
  /// **'感谢开发者 '**
  String get aboutThanksSakikoPrefix;

  /// No description provided for @aboutThanksSakikoSuffix.
  ///
  /// In zh, this message translates to:
  /// **' 帮助实现 Emby 与 Jellyfin 媒体库支持。'**
  String get aboutThanksSakikoSuffix;

  /// No description provided for @thanksSponsorUsers.
  ///
  /// In zh, this message translates to:
  /// **'感谢下列用户的赞助支持：'**
  String get thanksSponsorUsers;

  /// No description provided for @aboutVersionBanner.
  ///
  /// In zh, this message translates to:
  /// **'NipaPlay Reload 当前版本：{version}'**
  String aboutVersionBanner(Object version);

  /// No description provided for @aboutCheckingUpdates.
  ///
  /// In zh, this message translates to:
  /// **'检测中…'**
  String get aboutCheckingUpdates;

  /// No description provided for @aboutCheckUpdates.
  ///
  /// In zh, this message translates to:
  /// **'检测更新'**
  String get aboutCheckUpdates;

  /// No description provided for @aboutAutoCheckUpdates.
  ///
  /// In zh, this message translates to:
  /// **'自动检测更新'**
  String get aboutAutoCheckUpdates;

  /// No description provided for @aboutManualOnlyWhenDisabled.
  ///
  /// In zh, this message translates to:
  /// **'关闭后仅手动检测'**
  String get aboutManualOnlyWhenDisabled;

  /// No description provided for @aboutQqGroup.
  ///
  /// In zh, this message translates to:
  /// **'QQ群: {id}'**
  String aboutQqGroup(Object id);

  /// No description provided for @aboutOfficialWebsite.
  ///
  /// In zh, this message translates to:
  /// **'NipaPlay 官方网站'**
  String get aboutOfficialWebsite;

  /// No description provided for @openSourceCommunity.
  ///
  /// In zh, this message translates to:
  /// **'开源与社区'**
  String get openSourceCommunity;

  /// No description provided for @aboutCommunityHint.
  ///
  /// In zh, this message translates to:
  /// **'欢迎贡献代码，或将应用发布到更多平台。不会 Dart 也没关系，借助 AI 编程同样可以。'**
  String get aboutCommunityHint;

  /// No description provided for @sponsorSupport.
  ///
  /// In zh, this message translates to:
  /// **'赞助支持'**
  String get sponsorSupport;

  /// No description provided for @aboutSponsorParagraph1.
  ///
  /// In zh, this message translates to:
  /// **'如果你喜欢 NipaPlay 并且希望支持项目的持续开发，欢迎通过爱发电进行赞助。'**
  String get aboutSponsorParagraph1;

  /// No description provided for @aboutSponsorParagraph2.
  ///
  /// In zh, this message translates to:
  /// **'赞助者的名字将会出现在项目的 README 文件和每次软件更新后的关于页面名单中。'**
  String get aboutSponsorParagraph2;

  /// No description provided for @aboutAfdianSponsorPage.
  ///
  /// In zh, this message translates to:
  /// **'爱发电赞助页面'**
  String get aboutAfdianSponsorPage;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+script codes are specified.
  switch (locale.languageCode) {
    case 'zh':
      {
        switch (locale.scriptCode) {
          case 'Hant':
            return AppLocalizationsZhHant();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
