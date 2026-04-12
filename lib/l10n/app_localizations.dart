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

  /// No description provided for @currentTheme.
  ///
  /// In zh, this message translates to:
  /// **'当前：{theme}'**
  String currentTheme(Object theme);

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

  /// No description provided for @appearancePreviewTitle.
  ///
  /// In zh, this message translates to:
  /// **'效果预览'**
  String get appearancePreviewTitle;

  /// No description provided for @appearancePreviewFollowSystemDescription.
  ///
  /// In zh, this message translates to:
  /// **'根据系统外观自动切换浅色或深色模式。'**
  String get appearancePreviewFollowSystemDescription;

  /// No description provided for @appearancePreviewDarkDescription.
  ///
  /// In zh, this message translates to:
  /// **'使用偏暗的配色方案，适合夜间或弱光环境。'**
  String get appearancePreviewDarkDescription;

  /// No description provided for @appearancePreviewLightDescription.
  ///
  /// In zh, this message translates to:
  /// **'使用明亮的配色方案，适合日间或高亮环境。'**
  String get appearancePreviewLightDescription;

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

  /// No description provided for @playerKernel.
  ///
  /// In zh, this message translates to:
  /// **'播放器内核'**
  String get playerKernel;

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

  /// No description provided for @playerKernelSwitched.
  ///
  /// In zh, this message translates to:
  /// **'播放器内核已切换'**
  String get playerKernelSwitched;

  /// No description provided for @playerKernelDescriptionMdk.
  ///
  /// In zh, this message translates to:
  /// **'MDK 多媒体开发套件，支持硬件解码（默认优先；不支持时回落软件解码）。'**
  String get playerKernelDescriptionMdk;

  /// No description provided for @playerKernelDescriptionVideoPlayer.
  ///
  /// In zh, this message translates to:
  /// **'Flutter 官方 Video Player，兼容性好。'**
  String get playerKernelDescriptionVideoPlayer;

  /// No description provided for @playerKernelDescriptionLibmpv.
  ///
  /// In zh, this message translates to:
  /// **'MediaKit (Libmpv) 播放器，支持硬件解码与高级特性。'**
  String get playerKernelDescriptionLibmpv;

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

  /// No description provided for @mediaServerStatusConnected.
  ///
  /// In zh, this message translates to:
  /// **'已连接'**
  String get mediaServerStatusConnected;

  /// No description provided for @mediaServerStatusDisconnected.
  ///
  /// In zh, this message translates to:
  /// **'未连接'**
  String get mediaServerStatusDisconnected;

  /// No description provided for @mediaServerInfoServerUrl.
  ///
  /// In zh, this message translates to:
  /// **'服务器地址'**
  String get mediaServerInfoServerUrl;

  /// No description provided for @mediaServerInfoUsername.
  ///
  /// In zh, this message translates to:
  /// **'登录用户'**
  String get mediaServerInfoUsername;

  /// No description provided for @mediaServerInfoItemCount.
  ///
  /// In zh, this message translates to:
  /// **'媒体条目'**
  String get mediaServerInfoItemCount;

  /// No description provided for @mediaServerInfoSelectedLibraries.
  ///
  /// In zh, this message translates to:
  /// **'已选媒体库'**
  String get mediaServerInfoSelectedLibraries;

  /// No description provided for @mediaServerUnknown.
  ///
  /// In zh, this message translates to:
  /// **'未知'**
  String get mediaServerUnknown;

  /// No description provided for @mediaServerAnonymous.
  ///
  /// In zh, this message translates to:
  /// **'匿名'**
  String get mediaServerAnonymous;

  /// No description provided for @mediaServerViewLibrary.
  ///
  /// In zh, this message translates to:
  /// **'查看媒体库'**
  String get mediaServerViewLibrary;

  /// No description provided for @mediaServerRefresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新'**
  String get mediaServerRefresh;

  /// No description provided for @mediaServerManageServer.
  ///
  /// In zh, this message translates to:
  /// **'管理服务器'**
  String get mediaServerManageServer;

  /// No description provided for @mediaServerConnectServer.
  ///
  /// In zh, this message translates to:
  /// **'连接服务器'**
  String get mediaServerConnectServer;

  /// No description provided for @mediaServerDisconnectedHint.
  ///
  /// In zh, this message translates to:
  /// **'尚未连接此媒体服务器，点击下方按钮完成登录。'**
  String get mediaServerDisconnectedHint;

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

  /// No description provided for @connectServerDialogTitle.
  ///
  /// In zh, this message translates to:
  /// **'连接 {server} 服务器'**
  String connectServerDialogTitle(Object server);

  /// No description provided for @serverUrlInputPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'例如：http://192.168.1.100:8096'**
  String get serverUrlInputPlaceholder;

  /// No description provided for @inputUsernamePlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'输入用户名'**
  String get inputUsernamePlaceholder;

  /// No description provided for @inputPasswordPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'输入密码'**
  String get inputPasswordPlaceholder;

  /// No description provided for @nextStep.
  ///
  /// In zh, this message translates to:
  /// **'下一步'**
  String get nextStep;

  /// No description provided for @connectAction.
  ///
  /// In zh, this message translates to:
  /// **'连接'**
  String get connectAction;

  /// No description provided for @testConnection.
  ///
  /// In zh, this message translates to:
  /// **'测试连接'**
  String get testConnection;

  /// No description provided for @canBeEmpty.
  ///
  /// In zh, this message translates to:
  /// **'可留空'**
  String get canBeEmpty;

  /// No description provided for @leaveEmptyAutoGenerate.
  ///
  /// In zh, this message translates to:
  /// **'留空自动生成'**
  String get leaveEmptyAutoGenerate;

  /// No description provided for @usernameOptional.
  ///
  /// In zh, this message translates to:
  /// **'用户名（可选）'**
  String get usernameOptional;

  /// No description provided for @passwordOptional.
  ///
  /// In zh, this message translates to:
  /// **'密码（可选）'**
  String get passwordOptional;

  /// No description provided for @connectFailedCheckCredentials.
  ///
  /// In zh, this message translates to:
  /// **'连接失败，请检查服务器地址和凭证'**
  String get connectFailedCheckCredentials;

  /// No description provided for @webdavAddServer.
  ///
  /// In zh, this message translates to:
  /// **'添加 WebDAV 服务器'**
  String get webdavAddServer;

  /// No description provided for @webdavEditServer.
  ///
  /// In zh, this message translates to:
  /// **'编辑 WebDAV 服务器'**
  String get webdavEditServer;

  /// No description provided for @webdavEnterAddress.
  ///
  /// In zh, this message translates to:
  /// **'请输入 WebDAV 地址'**
  String get webdavEnterAddress;

  /// No description provided for @webdavInvalidUrl.
  ///
  /// In zh, this message translates to:
  /// **'请输入有效的 URL（http/https）'**
  String get webdavInvalidUrl;

  /// No description provided for @webdavConnection.
  ///
  /// In zh, this message translates to:
  /// **'WebDAV 连接'**
  String get webdavConnection;

  /// No description provided for @webdavTestFailedWithError.
  ///
  /// In zh, this message translates to:
  /// **'测试失败：{error}'**
  String webdavTestFailedWithError(Object error);

  /// No description provided for @webdavTestFailedCheckInfo.
  ///
  /// In zh, this message translates to:
  /// **'连接测试失败，请检查地址和认证信息'**
  String get webdavTestFailedCheckInfo;

  /// No description provided for @webdavTestSuccess.
  ///
  /// In zh, this message translates to:
  /// **'连接测试成功'**
  String get webdavTestSuccess;

  /// No description provided for @webdavTestFailed.
  ///
  /// In zh, this message translates to:
  /// **'连接测试失败'**
  String get webdavTestFailed;

  /// No description provided for @webdavSaveFailedCheckInfo.
  ///
  /// In zh, this message translates to:
  /// **'保存失败，请检查地址和认证信息'**
  String get webdavSaveFailedCheckInfo;

  /// No description provided for @webdavConnectHint.
  ///
  /// In zh, this message translates to:
  /// **'连接 WebDAV 服务器后可浏览目录并选择媒体文件夹。'**
  String get webdavConnectHint;

  /// No description provided for @webdavConnectionNameOptional.
  ///
  /// In zh, this message translates to:
  /// **'连接名称（可选）'**
  String get webdavConnectionNameOptional;

  /// No description provided for @webdavAddress.
  ///
  /// In zh, this message translates to:
  /// **'WebDAV 地址'**
  String get webdavAddress;

  /// No description provided for @smbAddServer.
  ///
  /// In zh, this message translates to:
  /// **'添加 SMB 服务器'**
  String get smbAddServer;

  /// No description provided for @smbEditServer.
  ///
  /// In zh, this message translates to:
  /// **'编辑 SMB 服务器'**
  String get smbEditServer;

  /// No description provided for @smbEnterHostOrIp.
  ///
  /// In zh, this message translates to:
  /// **'请输入主机或 IP 地址'**
  String get smbEnterHostOrIp;

  /// No description provided for @smbInvalidPortRange.
  ///
  /// In zh, this message translates to:
  /// **'端口无效，请输入 1-65535'**
  String get smbInvalidPortRange;

  /// No description provided for @smbAnonymousHint.
  ///
  /// In zh, this message translates to:
  /// **'用户名/密码可留空以匿名访问；支持填写域名。'**
  String get smbAnonymousHint;

  /// No description provided for @smbHostOrIp.
  ///
  /// In zh, this message translates to:
  /// **'主机 / IP'**
  String get smbHostOrIp;

  /// No description provided for @smbHostOrIpPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'例如：192.168.1.10 或 nas.local'**
  String get smbHostOrIpPlaceholder;

  /// No description provided for @smbPort.
  ///
  /// In zh, this message translates to:
  /// **'端口'**
  String get smbPort;

  /// No description provided for @smbDefaultPort445.
  ///
  /// In zh, this message translates to:
  /// **'默认 445'**
  String get smbDefaultPort445;

  /// No description provided for @smbDomainOptional.
  ///
  /// In zh, this message translates to:
  /// **'域（可选）'**
  String get smbDomainOptional;

  /// No description provided for @smbDomainPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'例如：WORKGROUP'**
  String get smbDomainPlaceholder;

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

  /// No description provided for @currentServerNotConnectedHint.
  ///
  /// In zh, this message translates to:
  /// **'当前服务器未连接，请返回重新选择。'**
  String get currentServerNotConnectedHint;

  /// No description provided for @loadingRemoteMediaLibrary.
  ///
  /// In zh, this message translates to:
  /// **'正在加载远程媒体库...'**
  String get loadingRemoteMediaLibrary;

  /// No description provided for @noRemoteMediaItems.
  ///
  /// In zh, this message translates to:
  /// **'暂未获取到远程媒体条目'**
  String get noRemoteMediaItems;

  /// No description provided for @recordedAtDate.
  ///
  /// In zh, this message translates to:
  /// **'收录于 {date}'**
  String recordedAtDate(Object date);

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

  /// No description provided for @dandanRemoteCardTitle.
  ///
  /// In zh, this message translates to:
  /// **'弹弹play 远程访问'**
  String get dandanRemoteCardTitle;

  /// No description provided for @dandanRemoteManageAccessTitle.
  ///
  /// In zh, this message translates to:
  /// **'管理弹弹play远程访问'**
  String get dandanRemoteManageAccessTitle;

  /// No description provided for @dandanRemoteConnectAccessTitle.
  ///
  /// In zh, this message translates to:
  /// **'连接弹弹play远程访问'**
  String get dandanRemoteConnectAccessTitle;

  /// No description provided for @dandanRemoteAddressPrompt.
  ///
  /// In zh, this message translates to:
  /// **'请输入桌面端显示的远程服务地址。'**
  String get dandanRemoteAddressPrompt;

  /// No description provided for @dandanRemoteAddressPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'例如：http://192.168.1.2:23333'**
  String get dandanRemoteAddressPlaceholder;

  /// No description provided for @dandanRemoteApiTokenOptionalTitle.
  ///
  /// In zh, this message translates to:
  /// **'API 密钥（可选）'**
  String get dandanRemoteApiTokenOptionalTitle;

  /// No description provided for @dandanRemoteApiTokenPrompt.
  ///
  /// In zh, this message translates to:
  /// **'如已在弹弹play 桌面端启用 API 验证，请输入对应的密钥；未启用可直接点击{actionLabel}。'**
  String dandanRemoteApiTokenPrompt(Object actionLabel);

  /// No description provided for @enterApiToken.
  ///
  /// In zh, this message translates to:
  /// **'请输入 API 密钥'**
  String get enterApiToken;

  /// No description provided for @optionalApiTokenHint.
  ///
  /// In zh, this message translates to:
  /// **'可留空，按需填写'**
  String get optionalApiTokenHint;

  /// No description provided for @dandanRemoteStatusSynced.
  ///
  /// In zh, this message translates to:
  /// **'已同步'**
  String get dandanRemoteStatusSynced;

  /// No description provided for @dandanRemoteStatusConnectFailed.
  ///
  /// In zh, this message translates to:
  /// **'连接失败'**
  String get dandanRemoteStatusConnectFailed;

  /// No description provided for @dandanRemoteStatusNotConfigured.
  ///
  /// In zh, this message translates to:
  /// **'未配置'**
  String get dandanRemoteStatusNotConfigured;

  /// No description provided for @unknownErrorOccurred.
  ///
  /// In zh, this message translates to:
  /// **'出现未知错误'**
  String get unknownErrorOccurred;

  /// No description provided for @dandanRemoteServerAddressLabel.
  ///
  /// In zh, this message translates to:
  /// **'服务器地址'**
  String get dandanRemoteServerAddressLabel;

  /// No description provided for @dandanRemoteLastSyncedLabel.
  ///
  /// In zh, this message translates to:
  /// **'最近同步'**
  String get dandanRemoteLastSyncedLabel;

  /// No description provided for @dandanRemoteAnimeEntries.
  ///
  /// In zh, this message translates to:
  /// **'番剧条目'**
  String get dandanRemoteAnimeEntries;

  /// No description provided for @dandanRemoteVideoFiles.
  ///
  /// In zh, this message translates to:
  /// **'视频文件'**
  String get dandanRemoteVideoFiles;

  /// No description provided for @dandanRemoteNoRecordsHint.
  ///
  /// In zh, this message translates to:
  /// **'暂无远程媒体记录，可尝试刷新或确认远程访问设置。'**
  String get dandanRemoteNoRecordsHint;

  /// No description provided for @dandanRemoteRecentUpdates.
  ///
  /// In zh, this message translates to:
  /// **'最近更新'**
  String get dandanRemoteRecentUpdates;

  /// No description provided for @dandanRemoteEpisodeCount.
  ///
  /// In zh, this message translates to:
  /// **'共 {count} 集'**
  String dandanRemoteEpisodeCount(int count);

  /// No description provided for @dandanRemoteManageConnection.
  ///
  /// In zh, this message translates to:
  /// **'管理连接'**
  String get dandanRemoteManageConnection;

  /// No description provided for @dandanRemoteSyncing.
  ///
  /// In zh, this message translates to:
  /// **'同步中...'**
  String get dandanRemoteSyncing;

  /// No description provided for @dandanRemoteRefreshLibrary.
  ///
  /// In zh, this message translates to:
  /// **'刷新媒体库'**
  String get dandanRemoteRefreshLibrary;

  /// No description provided for @dandanRemoteDisconnectedHintLong.
  ///
  /// In zh, this message translates to:
  /// **'通过弹弹play 桌面端开启远程访问后，可在此同步家中电脑或 NAS 上的番剧记录并直接播放。'**
  String get dandanRemoteDisconnectedHintLong;

  /// No description provided for @pleaseWait.
  ///
  /// In zh, this message translates to:
  /// **'请稍候...'**
  String get pleaseWait;

  /// No description provided for @connectDandanRemoteService.
  ///
  /// In zh, this message translates to:
  /// **'连接弹弹play 远程服务'**
  String get connectDandanRemoteService;

  /// No description provided for @noRecordYet.
  ///
  /// In zh, this message translates to:
  /// **'暂无记录'**
  String get noRecordYet;

  /// No description provided for @justNow.
  ///
  /// In zh, this message translates to:
  /// **'刚刚'**
  String get justNow;

  /// No description provided for @minutesAgo.
  ///
  /// In zh, this message translates to:
  /// **'{minutes} 分钟前'**
  String minutesAgo(int minutes);

  /// No description provided for @hoursAgo.
  ///
  /// In zh, this message translates to:
  /// **'{hours} 小时前'**
  String hoursAgo(int hours);

  /// No description provided for @daysAgo.
  ///
  /// In zh, this message translates to:
  /// **'{days} 天前'**
  String daysAgo(int days);

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

  /// No description provided for @serverMediaLibraryTitle.
  ///
  /// In zh, this message translates to:
  /// **'{server} 媒体库'**
  String serverMediaLibraryTitle(Object server);

  /// No description provided for @serverLabel.
  ///
  /// In zh, this message translates to:
  /// **'服务器'**
  String get serverLabel;

  /// No description provided for @accountLabel.
  ///
  /// In zh, this message translates to:
  /// **'账户'**
  String get accountLabel;

  /// No description provided for @mediaLibrary.
  ///
  /// In zh, this message translates to:
  /// **'媒体库'**
  String get mediaLibrary;

  /// No description provided for @noMediaLibrary.
  ///
  /// In zh, this message translates to:
  /// **'暂无媒体库'**
  String get noMediaLibrary;

  /// No description provided for @checkServerConnection.
  ///
  /// In zh, this message translates to:
  /// **'请检查服务器连接'**
  String get checkServerConnection;

  /// No description provided for @transcodeSettings.
  ///
  /// In zh, this message translates to:
  /// **'转码设置'**
  String get transcodeSettings;

  /// No description provided for @currentDefaultQuality.
  ///
  /// In zh, this message translates to:
  /// **'当前默认质量: {quality}'**
  String currentDefaultQuality(Object quality);

  /// No description provided for @enableTranscode.
  ///
  /// In zh, this message translates to:
  /// **'启用转码'**
  String get enableTranscode;

  /// No description provided for @defaultQuality.
  ///
  /// In zh, this message translates to:
  /// **'默认清晰度'**
  String get defaultQuality;

  /// No description provided for @tvShowsLibrary.
  ///
  /// In zh, this message translates to:
  /// **'电视剧库'**
  String get tvShowsLibrary;

  /// No description provided for @moviesLibrary.
  ///
  /// In zh, this message translates to:
  /// **'电影库'**
  String get moviesLibrary;

  /// No description provided for @boxsetsLibrary.
  ///
  /// In zh, this message translates to:
  /// **'合集库'**
  String get boxsetsLibrary;

  /// No description provided for @folderLibrary.
  ///
  /// In zh, this message translates to:
  /// **'文件夹'**
  String get folderLibrary;

  /// No description provided for @mixedLibrary.
  ///
  /// In zh, this message translates to:
  /// **'混合库'**
  String get mixedLibrary;

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

  /// No description provided for @invalidLink.
  ///
  /// In zh, this message translates to:
  /// **'链接无效'**
  String get invalidLink;

  /// No description provided for @unknown.
  ///
  /// In zh, this message translates to:
  /// **'未知'**
  String get unknown;

  /// No description provided for @localSource.
  ///
  /// In zh, this message translates to:
  /// **'本地'**
  String get localSource;

  /// No description provided for @dependencyTypeDirectMain.
  ///
  /// In zh, this message translates to:
  /// **'直接依赖'**
  String get dependencyTypeDirectMain;

  /// No description provided for @dependencyTypeDirectDev.
  ///
  /// In zh, this message translates to:
  /// **'开发依赖'**
  String get dependencyTypeDirectDev;

  /// No description provided for @dependencyTypeTransitive.
  ///
  /// In zh, this message translates to:
  /// **'间接依赖'**
  String get dependencyTypeTransitive;

  /// No description provided for @dependencyTypeUnknown.
  ///
  /// In zh, this message translates to:
  /// **'未知来源'**
  String get dependencyTypeUnknown;

  /// No description provided for @parsingDependencyInfo.
  ///
  /// In zh, this message translates to:
  /// **'正在解析依赖信息...'**
  String get parsingDependencyInfo;

  /// No description provided for @readDependencyListFailed.
  ///
  /// In zh, this message translates to:
  /// **'读取依赖列表失败'**
  String get readDependencyListFailed;

  /// No description provided for @dependencySummaryWithOther.
  ///
  /// In zh, this message translates to:
  /// **'共 {total} 个库 · 直接 {directMain} / 开发 {directDev} / 间接 {transitive} / 其他 {other}'**
  String dependencySummaryWithOther(
      int total, int directMain, int directDev, int transitive, int other);

  /// No description provided for @dependencySummaryNoOther.
  ///
  /// In zh, this message translates to:
  /// **'共 {total} 个库 · 直接 {directMain} / 开发 {directDev} / 间接 {transitive}'**
  String dependencySummaryNoOther(
      int total, int directMain, int directDev, int transitive);

  /// No description provided for @dependencyEntrySubtitle.
  ///
  /// In zh, this message translates to:
  /// **'版本: {version} · {dependencyType} · {sourceType}'**
  String dependencyEntrySubtitle(
      Object version, Object dependencyType, Object sourceType);

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

  /// No description provided for @playerUnavailableOnWeb.
  ///
  /// In zh, this message translates to:
  /// **'播放器设置在 Web 平台不可用'**
  String get playerUnavailableOnWeb;

  /// No description provided for @danmakuRenderEngine.
  ///
  /// In zh, this message translates to:
  /// **'弹幕渲染引擎'**
  String get danmakuRenderEngine;

  /// No description provided for @danmakuRenderEngineSwitched.
  ///
  /// In zh, this message translates to:
  /// **'弹幕渲染引擎已切换'**
  String get danmakuRenderEngineSwitched;

  /// No description provided for @danmakuRenderEngineDescriptionCpu.
  ///
  /// In zh, this message translates to:
  /// **'CPU 渲染：兼容性最佳，适合大多数场景。'**
  String get danmakuRenderEngineDescriptionCpu;

  /// No description provided for @danmakuRenderEngineDescriptionGpuExperimental.
  ///
  /// In zh, this message translates to:
  /// **'GPU 渲染（实验性）：性能更高，但仍在开发中。'**
  String get danmakuRenderEngineDescriptionGpuExperimental;

  /// No description provided for @danmakuRenderEngineDescriptionCanvasExperimental.
  ///
  /// In zh, this message translates to:
  /// **'Canvas 弹幕（实验性）：高性能，低功耗。'**
  String get danmakuRenderEngineDescriptionCanvasExperimental;

  /// No description provided for @danmakuRenderEngineDescriptionNipaplayNext.
  ///
  /// In zh, this message translates to:
  /// **'NipaPlay Next：CPU 弹幕和 Canvas 弹幕优点的集合体，包含两边的全部优点。'**
  String get danmakuRenderEngineDescriptionNipaplayNext;

  /// No description provided for @danmakuRenderEngineTitleCpu.
  ///
  /// In zh, this message translates to:
  /// **'CPU 渲染'**
  String get danmakuRenderEngineTitleCpu;

  /// No description provided for @danmakuRenderEngineTitleGpuExperimental.
  ///
  /// In zh, this message translates to:
  /// **'GPU 渲染 (实验性)'**
  String get danmakuRenderEngineTitleGpuExperimental;

  /// No description provided for @danmakuRenderEngineTitleCanvasExperimental.
  ///
  /// In zh, this message translates to:
  /// **'Canvas 弹幕 (实验性)'**
  String get danmakuRenderEngineTitleCanvasExperimental;

  /// No description provided for @danmakuRenderEngineTitleNipaplayNext.
  ///
  /// In zh, this message translates to:
  /// **'NipaPlay Next'**
  String get danmakuRenderEngineTitleNipaplayNext;

  /// No description provided for @qualityProfileOff.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get qualityProfileOff;

  /// No description provided for @qualityProfileLite.
  ///
  /// In zh, this message translates to:
  /// **'轻量'**
  String get qualityProfileLite;

  /// No description provided for @qualityProfileStandard.
  ///
  /// In zh, this message translates to:
  /// **'标准'**
  String get qualityProfileStandard;

  /// No description provided for @qualityProfileHigh.
  ///
  /// In zh, this message translates to:
  /// **'高质量'**
  String get qualityProfileHigh;

  /// No description provided for @doubleResolutionPlaybackTitle.
  ///
  /// In zh, this message translates to:
  /// **'双倍分辨率播放视频'**
  String get doubleResolutionPlaybackTitle;

  /// No description provided for @doubleResolutionPlaybackSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'以 2x 分辨率渲染画面，改善内嵌字幕清晰度（仅 Libmpv，不与 Anime4K 叠加）'**
  String get doubleResolutionPlaybackSubtitle;

  /// No description provided for @settingSavedReopenVideoToApply.
  ///
  /// In zh, this message translates to:
  /// **'已保存，重新打开视频生效'**
  String get settingSavedReopenVideoToApply;

  /// No description provided for @doubleResolutionPlaybackEnabled.
  ///
  /// In zh, this message translates to:
  /// **'已开启双倍分辨率播放'**
  String get doubleResolutionPlaybackEnabled;

  /// No description provided for @doubleResolutionPlaybackDisabled.
  ///
  /// In zh, this message translates to:
  /// **'已关闭双倍分辨率播放'**
  String get doubleResolutionPlaybackDisabled;

  /// No description provided for @anime4kSuperResolutionTitle.
  ///
  /// In zh, this message translates to:
  /// **'Anime4K 超分辨率（实验性）'**
  String get anime4kSuperResolutionTitle;

  /// No description provided for @anime4kProfileDescriptionOff.
  ///
  /// In zh, this message translates to:
  /// **'保持原始画面，不进行超分辨率处理。'**
  String get anime4kProfileDescriptionOff;

  /// No description provided for @anime4kProfileDescriptionLite.
  ///
  /// In zh, this message translates to:
  /// **'适度超分辨率与降噪，性能消耗较低。'**
  String get anime4kProfileDescriptionLite;

  /// No description provided for @anime4kProfileDescriptionStandard.
  ///
  /// In zh, this message translates to:
  /// **'画质与性能平衡的标准方案。'**
  String get anime4kProfileDescriptionStandard;

  /// No description provided for @anime4kProfileDescriptionHigh.
  ///
  /// In zh, this message translates to:
  /// **'追求最佳画质，性能需求最高。'**
  String get anime4kProfileDescriptionHigh;

  /// No description provided for @anime4kDisabled.
  ///
  /// In zh, this message translates to:
  /// **'已关闭 Anime4K'**
  String get anime4kDisabled;

  /// No description provided for @anime4kSwitchedTo.
  ///
  /// In zh, this message translates to:
  /// **'Anime4K 已切换为 {option}'**
  String anime4kSwitchedTo(Object option);

  /// No description provided for @crtDisplayEffectTitle.
  ///
  /// In zh, this message translates to:
  /// **'CRT 显示效果'**
  String get crtDisplayEffectTitle;

  /// No description provided for @crtProfileDescriptionOff.
  ///
  /// In zh, this message translates to:
  /// **'保持原始画面，不启用 CRT 效果。'**
  String get crtProfileDescriptionOff;

  /// No description provided for @crtProfileDescriptionLite.
  ///
  /// In zh, this message translates to:
  /// **'扫描线 + 暗角，性能开销较小。'**
  String get crtProfileDescriptionLite;

  /// No description provided for @crtProfileDescriptionStandard.
  ///
  /// In zh, this message translates to:
  /// **'增加曲面与栅格，画面更接近 CRT。'**
  String get crtProfileDescriptionStandard;

  /// No description provided for @crtProfileDescriptionHigh.
  ///
  /// In zh, this message translates to:
  /// **'加入辉光与色散，效果最佳但性能开销更高。'**
  String get crtProfileDescriptionHigh;

  /// No description provided for @crtDisabled.
  ///
  /// In zh, this message translates to:
  /// **'已关闭 CRT'**
  String get crtDisabled;

  /// No description provided for @crtSwitchedTo.
  ///
  /// In zh, this message translates to:
  /// **'CRT 已切换为 {option}'**
  String crtSwitchedTo(Object option);

  /// No description provided for @enterAiApiUrl.
  ///
  /// In zh, this message translates to:
  /// **'请输入 AI 接口 URL'**
  String get enterAiApiUrl;

  /// No description provided for @enterModelName.
  ///
  /// In zh, this message translates to:
  /// **'请输入模型名称'**
  String get enterModelName;

  /// No description provided for @enterApiKey.
  ///
  /// In zh, this message translates to:
  /// **'请输入 API Key'**
  String get enterApiKey;

  /// No description provided for @spoilerAiSettingsSaved.
  ///
  /// In zh, this message translates to:
  /// **'防剧透 AI 设置已保存'**
  String get spoilerAiSettingsSaved;

  /// No description provided for @spoilerPreventionMode.
  ///
  /// In zh, this message translates to:
  /// **'防剧透模式'**
  String get spoilerPreventionMode;

  /// No description provided for @spoilerPreventionModeSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'开启后，加载弹幕后将通过 AI 识别并屏蔽疑似剧透弹幕。'**
  String get spoilerPreventionModeSubtitle;

  /// No description provided for @fillAndSaveAiConfigFirst.
  ///
  /// In zh, this message translates to:
  /// **'请先填写并保存 AI 接口配置'**
  String get fillAndSaveAiConfigFirst;

  /// No description provided for @spoilerPreventionModeEnabled.
  ///
  /// In zh, this message translates to:
  /// **'已开启防剧透模式'**
  String get spoilerPreventionModeEnabled;

  /// No description provided for @spoilerPreventionModeDisabled.
  ///
  /// In zh, this message translates to:
  /// **'已关闭防剧透模式'**
  String get spoilerPreventionModeDisabled;

  /// No description provided for @autoMatchDanmakuOnPlayTitle.
  ///
  /// In zh, this message translates to:
  /// **'播放时自动匹配弹幕'**
  String get autoMatchDanmakuOnPlayTitle;

  /// No description provided for @autoMatchDanmakuOnPlaySubtitle.
  ///
  /// In zh, this message translates to:
  /// **'关闭后播放时不再自动识别并加载弹幕，可在弹幕设置中手动匹配。'**
  String get autoMatchDanmakuOnPlaySubtitle;

  /// No description provided for @autoMatchDanmakuOnPlayEnabled.
  ///
  /// In zh, this message translates to:
  /// **'已开启播放时自动匹配弹幕'**
  String get autoMatchDanmakuOnPlayEnabled;

  /// No description provided for @autoMatchDanmakuOnPlayDisabledManual.
  ///
  /// In zh, this message translates to:
  /// **'已关闭播放时自动匹配弹幕（可手动匹配）'**
  String get autoMatchDanmakuOnPlayDisabledManual;

  /// No description provided for @autoMatchOnHashFailTitle.
  ///
  /// In zh, this message translates to:
  /// **'哈希匹配失败自动匹配弹幕'**
  String get autoMatchOnHashFailTitle;

  /// No description provided for @autoMatchOnHashFailSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'哈希匹配失败时默认使用文件名搜索的第一个结果自动匹配；关闭后将弹出搜索弹幕菜单。'**
  String get autoMatchOnHashFailSubtitle;

  /// No description provided for @autoMatchOnHashFailEnabled.
  ///
  /// In zh, this message translates to:
  /// **'已开启匹配失败自动匹配'**
  String get autoMatchOnHashFailEnabled;

  /// No description provided for @autoMatchOnHashFailDisabledShowSearch.
  ///
  /// In zh, this message translates to:
  /// **'已关闭匹配失败自动匹配（将弹出搜索弹幕菜单）'**
  String get autoMatchOnHashFailDisabledShowSearch;

  /// No description provided for @hardwareDecoding.
  ///
  /// In zh, this message translates to:
  /// **'硬件解码'**
  String get hardwareDecoding;

  /// No description provided for @hardwareDecodingSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'仅对 MDK / Libmpv 生效'**
  String get hardwareDecodingSubtitle;

  /// No description provided for @hardwareDecodingEnabled.
  ///
  /// In zh, this message translates to:
  /// **'已开启硬件解码'**
  String get hardwareDecodingEnabled;

  /// No description provided for @hardwareDecodingDisabled.
  ///
  /// In zh, this message translates to:
  /// **'已关闭硬件解码'**
  String get hardwareDecodingDisabled;

  /// No description provided for @pauseOnBackgroundTitle.
  ///
  /// In zh, this message translates to:
  /// **'后台自动暂停'**
  String get pauseOnBackgroundTitle;

  /// No description provided for @pauseOnBackgroundSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'切到后台或锁屏时自动暂停播放'**
  String get pauseOnBackgroundSubtitle;

  /// No description provided for @pauseOnBackgroundEnabled.
  ///
  /// In zh, this message translates to:
  /// **'后台自动暂停已开启'**
  String get pauseOnBackgroundEnabled;

  /// No description provided for @pauseOnBackgroundDisabled.
  ///
  /// In zh, this message translates to:
  /// **'后台自动暂停已关闭'**
  String get pauseOnBackgroundDisabled;

  /// No description provided for @playbackEndActionTitle.
  ///
  /// In zh, this message translates to:
  /// **'播放结束操作'**
  String get playbackEndActionTitle;

  /// No description provided for @playbackEndActionAutoNextMessage.
  ///
  /// In zh, this message translates to:
  /// **'播放结束后将自动进入下一话'**
  String get playbackEndActionAutoNextMessage;

  /// No description provided for @playbackEndActionLoopMessage.
  ///
  /// In zh, this message translates to:
  /// **'播放结束后将从头循环播放'**
  String get playbackEndActionLoopMessage;

  /// No description provided for @playbackEndActionPauseMessage.
  ///
  /// In zh, this message translates to:
  /// **'播放结束后将停留在当前页面'**
  String get playbackEndActionPauseMessage;

  /// No description provided for @playbackEndActionExitMessage.
  ///
  /// In zh, this message translates to:
  /// **'播放结束后将返回上一页'**
  String get playbackEndActionExitMessage;

  /// No description provided for @autoNextCountdownTitle.
  ///
  /// In zh, this message translates to:
  /// **'自动连播倒计时'**
  String get autoNextCountdownTitle;

  /// No description provided for @autoNextCountdownWaitSeconds.
  ///
  /// In zh, this message translates to:
  /// **'自动跳转下一话前等待 {seconds} 秒'**
  String autoNextCountdownWaitSeconds(int seconds);

  /// No description provided for @autoNextCountdownNeedAutoNext.
  ///
  /// In zh, this message translates to:
  /// **'需先启用自动播放下一话'**
  String get autoNextCountdownNeedAutoNext;

  /// No description provided for @timelinePreviewTitle.
  ///
  /// In zh, this message translates to:
  /// **'时间轴截图预览'**
  String get timelinePreviewTitle;

  /// No description provided for @timelinePreviewSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'悬停进度条时显示缩略图（本地/WebDAV/SMB/共享媒体库生效）'**
  String get timelinePreviewSubtitle;

  /// No description provided for @enableWarning.
  ///
  /// In zh, this message translates to:
  /// **'开启警告'**
  String get enableWarning;

  /// No description provided for @timelinePreviewEnableWarningContent.
  ///
  /// In zh, this message translates to:
  /// **'开启时间轴截图预览会在后台实时生成截图，可能导致播放卡顿或性能下降。是否确认开启？'**
  String get timelinePreviewEnableWarningContent;

  /// No description provided for @timelinePreviewEnabled.
  ///
  /// In zh, this message translates to:
  /// **'已开启时间轴截图预览'**
  String get timelinePreviewEnabled;

  /// No description provided for @timelinePreviewDisabled.
  ///
  /// In zh, this message translates to:
  /// **'已关闭时间轴截图预览'**
  String get timelinePreviewDisabled;

  /// No description provided for @playPrecacheDuration.
  ///
  /// In zh, this message translates to:
  /// **'播放预缓存时长'**
  String get playPrecacheDuration;

  /// No description provided for @playPrecacheSize.
  ///
  /// In zh, this message translates to:
  /// **'播放预缓存大小'**
  String get playPrecacheSize;

  /// No description provided for @currentPrecacheDurationSeconds.
  ///
  /// In zh, this message translates to:
  /// **'当前 {seconds} 秒，修改后立即生效'**
  String currentPrecacheDurationSeconds(int seconds);

  /// No description provided for @currentPrecacheSizeMb.
  ///
  /// In zh, this message translates to:
  /// **'当前 {mb} MB，修改后重新打开视频生效'**
  String currentPrecacheSizeMb(int mb);

  /// No description provided for @libmpvKernelOnly.
  ///
  /// In zh, this message translates to:
  /// **'仅 Libmpv 内核生效'**
  String get libmpvKernelOnly;

  /// No description provided for @spoilerAiSettingsTitle.
  ///
  /// In zh, this message translates to:
  /// **'防剧透 AI 设置'**
  String get spoilerAiSettingsTitle;

  /// No description provided for @spoilerAiSettingsDescription.
  ///
  /// In zh, this message translates to:
  /// **'开启防剧透前请先填写并保存配置（必须提供接口 URL / Key / 模型）。'**
  String get spoilerAiSettingsDescription;

  /// No description provided for @spoilerAiGeminiUrlNote.
  ///
  /// In zh, this message translates to:
  /// **'Gemini：URL 可填到 /v1beta/models，实际请求会自动拼接 /<模型>:generateContent。'**
  String get spoilerAiGeminiUrlNote;

  /// No description provided for @spoilerAiOpenAiUrlNote.
  ///
  /// In zh, this message translates to:
  /// **'OpenAI：URL 建议填写 /v1/chat/completions（兼容接口亦可）。'**
  String get spoilerAiOpenAiUrlNote;

  /// No description provided for @apiFormatLabel.
  ///
  /// In zh, this message translates to:
  /// **'接口格式'**
  String get apiFormatLabel;

  /// No description provided for @openAiCompatible.
  ///
  /// In zh, this message translates to:
  /// **'OpenAI 兼容'**
  String get openAiCompatible;

  /// No description provided for @enterYourApiKey.
  ///
  /// In zh, this message translates to:
  /// **'请输入你的 API Key'**
  String get enterYourApiKey;

  /// No description provided for @temperatureLabel.
  ///
  /// In zh, this message translates to:
  /// **'温度：{value}'**
  String temperatureLabel(Object value);

  /// No description provided for @saveConfiguration.
  ///
  /// In zh, this message translates to:
  /// **'保存配置'**
  String get saveConfiguration;

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
