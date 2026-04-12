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
  String get darkMode => '深色模式';

  @override
  String get followSystem => '跟随系统';

  @override
  String get player => '播放器';

  @override
  String get playerKernelCurrentMdk => '当前：MDK';

  @override
  String get playerKernelCurrentVideoPlayer => '当前：Video Player';

  @override
  String get playerKernelCurrentLibmpv => '当前：Libmpv';

  @override
  String get externalCall => '外部调用';

  @override
  String get externalPlayerEnabled => '已启用外部播放器';

  @override
  String get externalPlayerDisabled => '未启用外部播放器';

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
  String get developerOptions => '开发者选项';

  @override
  String get developerOptionsSubtitle => '终端输出、依赖版本、构建信息';

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
  String get darkMode => '深色模式';

  @override
  String get followSystem => '跟隨系統';

  @override
  String get player => '播放器';

  @override
  String get playerKernelCurrentMdk => '目前：MDK';

  @override
  String get playerKernelCurrentVideoPlayer => '目前：Video Player';

  @override
  String get playerKernelCurrentLibmpv => '目前：Libmpv';

  @override
  String get externalCall => '外部調用';

  @override
  String get externalPlayerEnabled => '已啟用外部播放器';

  @override
  String get externalPlayerDisabled => '未啟用外部播放器';

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
  String get developerOptions => '開發者選項';

  @override
  String get developerOptionsSubtitle => '終端輸出、依賴版本、建置資訊';

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
}
