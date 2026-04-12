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

  /// No description provided for @darkMode.
  ///
  /// In zh, this message translates to:
  /// **'深色模式'**
  String get darkMode;

  /// No description provided for @followSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get followSystem;

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
