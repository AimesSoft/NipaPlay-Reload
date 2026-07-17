// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'NipaPlay';

  @override
  String get tabHome => 'Home';

  @override
  String get tabVideoPlay => 'Video Player';

  @override
  String get tabMediaLibrary => 'Media Library';

  @override
  String get tabTorrentDownload => 'Downloader';

  @override
  String get tabAccount => 'Account';

  @override
  String get tabDanmakuConsole => 'Danmaku Console';

  @override
  String get externalPlayerConsoleTitle => 'External Player Danmaku Console';

  @override
  String get externalPlayerConsoleEmptyTitle => 'No external player is running';

  @override
  String get externalPlayerConsoleEmptyDescription =>
      'Start playback with an external player to see its session and controls here.';

  @override
  String get externalPlayerConsoleAnime => 'Anime';

  @override
  String get externalPlayerConsoleEpisode => 'Episode';

  @override
  String get externalPlayerConsoleEpisodeId => 'Episode ID';

  @override
  String get externalPlayerConsoleProcessId => 'Player PID';

  @override
  String get externalPlayerConsoleMediaPath => 'Media path';

  @override
  String get externalPlayerConsoleUnknownAnime => 'Unknown anime';

  @override
  String get externalPlayerConsoleUnknownEpisode => 'Unknown episode';

  @override
  String get externalPlayerConsoleProgress => 'Playback progress';

  @override
  String get externalPlayerConsoleProgressUnsupported =>
      'This player does not support progress synchronization.';

  @override
  String get externalPlayerConsoleProgressLoading =>
      'Reading playback progress…';

  @override
  String get externalPlayerConsoleTimestampLabel => 'Exact timestamp';

  @override
  String get externalPlayerConsoleTimestampHint => 'HH:MM:SS / MM:SS / seconds';

  @override
  String get externalPlayerConsoleTimestampInvalid => 'Enter a valid timestamp';

  @override
  String get externalPlayerConsoleTimestampSeek => 'Jump';

  @override
  String get externalPlayerConsoleDanmakuList => 'Danmaku list';

  @override
  String externalPlayerConsoleDanmakuStats(int total, int active) {
    return '$total total · $active on screen';
  }

  @override
  String get externalPlayerConsoleDanmakuEmpty =>
      'No danmaku was loaded for this playback session.';

  @override
  String get externalPlayerConsoleDanmakuUnknownSender => 'Unknown';

  @override
  String get externalPlayerConsoleDanmakuSender => 'Sender';

  @override
  String get externalPlayerConsoleDanmakuTypeScroll => 'Scroll';

  @override
  String get externalPlayerConsoleDanmakuTypeTop => 'Top';

  @override
  String get externalPlayerConsoleDanmakuTypeBottom => 'Bottom';

  @override
  String get externalPlayerConsoleDanmakuActive => 'On screen';

  @override
  String get externalPlayerConsoleDanmakuFollowEnabled => 'Following playback';

  @override
  String get externalPlayerConsoleDanmakuFollowDisabled => 'Auto-follow paused';

  @override
  String get danmakuOpacityTitle => 'Danmaku opacity';

  @override
  String get danmakuOpacitySubtitle =>
      'Adjust danmaku text opacity. Newly opened videos will use this setting.';

  @override
  String get danmakuOutlineEnabledTitle => 'Enable danmaku outline';

  @override
  String get danmakuOutlineEnabledSubtitle =>
      'Show an outline around danmaku text. Newly opened videos will use this setting.';

  @override
  String get danmakuOutlineWidthTitle => 'Danmaku outline thickness';

  @override
  String get externalPlayerConsoleResume => 'Resume';

  @override
  String get externalPlayerConsolePause => 'Pause';

  @override
  String get externalPlayerConsoleClose => 'Close Player';

  @override
  String get tabSettings => 'Settings';

  @override
  String get settingsLabel => 'Settings';

  @override
  String get toggleToLightMode => 'Switch to Light Mode';

  @override
  String get toggleToDarkMode => 'Switch to Dark Mode';

  @override
  String get language => 'Language';

  @override
  String get languageSettingsTitle => 'Language Settings';

  @override
  String get languageSettingsSubtitle => 'Choose the display language';

  @override
  String get languageAuto => 'Auto (Follow System)';

  @override
  String get languageSimplifiedChinese => '简体中文';

  @override
  String get languageTraditionalChinese => '繁體中文';

  @override
  String get languageEnglish => 'English';

  @override
  String currentLanguage(Object language) {
    return 'Current: $language';
  }

  @override
  String currentServer(Object server) {
    return 'Current: $server';
  }

  @override
  String currentTheme(Object theme) {
    return 'Current: $theme';
  }

  @override
  String get languageTileSubtitle =>
      'Switch between Simplified Chinese, Traditional Chinese, or English';

  @override
  String get settingsBasicSection => 'Basic Settings';

  @override
  String get settingsAboutSection => 'About';

  @override
  String get appearance => 'Appearance';

  @override
  String get lightMode => 'Light Mode';

  @override
  String get appearanceLightModeSubtitle =>
      'Bright interface with good contrast.';

  @override
  String get darkMode => 'Dark Mode';

  @override
  String get appearanceDarkModeSubtitle =>
      'Reduces brightness, protects eyes and saves battery.';

  @override
  String get followSystem => 'Follow System';

  @override
  String get appearanceFollowSystemSubtitle =>
      'Automatically switch appearance based on system settings.';

  @override
  String get appearancePreviewTitle => 'Preview';

  @override
  String get appearancePreviewFollowSystemDescription =>
      'Automatically switch between light and dark mode based on system appearance.';

  @override
  String get appearancePreviewDarkDescription =>
      'Uses a dark color scheme, suitable for nighttime or low-light environments.';

  @override
  String get appearancePreviewLightDescription =>
      'Uses a bright color scheme, suitable for daytime or bright environments.';

  @override
  String get appearanceAnimeDetailStyle => 'Anime Detail Style';

  @override
  String get appearanceDetailSimple => 'Simple';

  @override
  String get appearanceDetailSimpleSubtitle =>
      'Classic layout with information in separate columns.';

  @override
  String get appearanceDetailVivid => 'Vivid';

  @override
  String get appearanceDetailVividSubtitle =>
      'Poster-driven visuals with horizontal episode cards.';

  @override
  String get appearanceRecentWatchingStyle => 'Recently Watched Style';

  @override
  String get appearanceRecentSimple => 'Simple';

  @override
  String get appearanceRecentSimpleSubtitle => 'Plain text list, saves space.';

  @override
  String get appearanceRecentDetailed => 'Detailed';

  @override
  String get appearanceRecentDetailedSubtitle =>
      'Horizontal scrolling cards with screenshots.';

  @override
  String get appearanceHomeSections => 'Home Sections';

  @override
  String get restoreDefaults => 'Restore Defaults';

  @override
  String get restoreDefaultsSubtitle =>
      'Restore default sorting and display states';

  @override
  String get uiThemeExperimental => 'Theme (Experimental)';

  @override
  String get uiThemeRestartHint =>
      'Tip: Restart the app after switching themes for full effect.';

  @override
  String get uiThemeSwitchDialogTitle => 'Theme Switch Notice';

  @override
  String uiThemeSwitchDialogMessage(Object theme) {
    return 'Switching to the $theme theme requires a restart to take full effect.\n\nWould you like to restart the app now?';
  }

  @override
  String get restartApp => 'Restart App';

  @override
  String get refreshPageApplyTheme =>
      'Please manually refresh the page to apply the new theme';

  @override
  String get player => 'Player';

  @override
  String get playerKernel => 'Player Kernel';

  @override
  String get playerKernelCurrentMdk => 'Current: MDK';

  @override
  String get playerKernelCurrentVideoPlayer => 'Current: Video Player';

  @override
  String get playerKernelCurrentLibmpv => 'Current: Libmpv';

  @override
  String get playerKernelSwitched => 'Player kernel switched';

  @override
  String get playerKernelDescriptionMdk =>
      'MDK Multimedia Development Kit, supports hardware decoding (default priority; falls back to software decoding when unsupported).';

  @override
  String get playerKernelDescriptionVideoPlayer =>
      'Flutter official Video Player, with good compatibility.';

  @override
  String get playerKernelDescriptionLibmpv =>
      'MediaKit (Libmpv) player, supports hardware decoding and advanced features.';

  @override
  String get externalCall => 'External Player';

  @override
  String get externalPlayerEnabled => 'External player enabled';

  @override
  String get externalPlayerDisabled => 'External player disabled';

  @override
  String get externalPlayerIntroDesktop =>
      'When enabled, all playback will be opened through an external player.';

  @override
  String get externalPlayerIntroUnsupported =>
      'External player is only supported on desktop.';

  @override
  String get externalPlayerEnableTitle => 'Enable External Player';

  @override
  String get externalPlayerEnableSubtitle =>
      'Use an external player for video playback';

  @override
  String get externalPlayerSelectTitle => 'Select External Player';

  @override
  String get externalPlayerNotSelected => 'No external player selected';

  @override
  String get externalPlayerSelectionCanceled =>
      'External player selection canceled';

  @override
  String get externalPlayerUpdated => 'External player updated';

  @override
  String get desktopOnlySupported => 'Desktop only';

  @override
  String get networkSettings => 'Network Settings';

  @override
  String get networkSettingsSubtitle =>
      'DanDanPlay server and custom addresses';

  @override
  String get storage => 'Storage';

  @override
  String get storageSettingsSubtitle =>
      'Manage danmaku cache and cleanup policies';

  @override
  String get networkMediaLibrary => 'Network Media Library';

  @override
  String get mediaServerStatusConnected => 'Connected';

  @override
  String get mediaServerStatusDisconnected => 'Disconnected';

  @override
  String get mediaServerInfoServerUrl => 'Server URL';

  @override
  String get mediaServerInfoUsername => 'Logged in as';

  @override
  String get mediaServerInfoItemCount => 'Media items';

  @override
  String get mediaServerInfoSelectedLibraries => 'Selected libraries';

  @override
  String get mediaServerUnknown => 'Unknown';

  @override
  String get mediaServerAnonymous => 'Anonymous';

  @override
  String get mediaServerViewLibrary => 'View Library';

  @override
  String get mediaServerRefresh => 'Refresh';

  @override
  String get mediaServerManageServer => 'Manage Server';

  @override
  String get mediaServerConnectServer => 'Connect to Server';

  @override
  String get mediaServerDisconnectedHint =>
      'Not connected to this media server yet. Tap the button below to log in.';

  @override
  String get retry => 'Retry';

  @override
  String get save => 'Save';

  @override
  String get disconnect => 'Disconnect';

  @override
  String get loadFailed => 'Load failed';

  @override
  String loadFailedWithError(Object error) {
    return 'Load failed: $error';
  }

  @override
  String operationFailed(Object error) {
    return 'Operation failed: $error';
  }

  @override
  String saveFailedWithError(Object error) {
    return 'Save failed: $error';
  }

  @override
  String connectFailedWithError(Object error) {
    return 'Connection failed: $error';
  }

  @override
  String refreshFailedWithError(Object error) {
    return 'Refresh failed: $error';
  }

  @override
  String disconnectFailedWithError(Object error) {
    return 'Disconnect failed: $error';
  }

  @override
  String get deviceIdTitle => 'Device ID (DeviceId)';

  @override
  String get deviceIdDescription =>
      'Used by Jellyfin / Emby to distinguish different devices and avoid being kicked out.';

  @override
  String get deviceIdCurrent => 'Current DeviceId';

  @override
  String get deviceIdGenerated => 'Auto-generated ID';

  @override
  String get deviceIdCustom => 'Custom DeviceId';

  @override
  String deviceIdCustomSet(Object deviceId) {
    return 'Set to: $deviceId';
  }

  @override
  String get deviceIdCustomUnset => 'Not set (using auto-generated)';

  @override
  String get deviceIdRestoreAuto => 'Restore Auto-Generated';

  @override
  String get deviceIdRestoreAutoSubtitle => 'Clear custom DeviceId';

  @override
  String get deviceIdRestoreSuccess => 'Restored auto-generated device ID';

  @override
  String get deviceIdDialogTitle => 'Custom DeviceId';

  @override
  String get deviceIdDialogHint =>
      'Leave empty to use the auto-generated device ID.';

  @override
  String get deviceIdDialogPlaceholder => 'e.g. My-iPhone-01';

  @override
  String get deviceIdDialogValidationHint =>
      'Do not include double quotes or newlines; max length 128.';

  @override
  String get deviceIdUpdatedHint =>
      'Device ID updated. It is recommended to disconnect and reconnect to the server.';

  @override
  String get deviceIdInvalid =>
      'Invalid DeviceId: avoid double quotes/newlines and keep length ≤ 128';

  @override
  String networkServerConnected(Object server) {
    return '$server server connected';
  }

  @override
  String networkServerSettingsUpdated(Object server) {
    return '$server server settings updated';
  }

  @override
  String disconnectServerConfirm(Object server) {
    return 'Are you sure you want to disconnect from the $server server?';
  }

  @override
  String networkServerDisconnected(Object server) {
    return '$server disconnected';
  }

  @override
  String disconnectServerFailed(Object server, Object error) {
    return 'Failed to disconnect from $server: $error';
  }

  @override
  String networkServerNotConnected(Object server) {
    return 'Not connected to $server server yet';
  }

  @override
  String networkLibraryRefreshed(Object server) {
    return '$server library refreshed';
  }

  @override
  String connectServerDialogTitle(Object server) {
    return 'Connect to $server Server';
  }

  @override
  String get serverUrlInputPlaceholder => 'e.g. http://192.168.1.100:8096';

  @override
  String get inputUsernamePlaceholder => 'Enter username';

  @override
  String get inputPasswordPlaceholder => 'Enter password';

  @override
  String get nextStep => 'Next';

  @override
  String get connectAction => 'Connect';

  @override
  String get testConnection => 'Test Connection';

  @override
  String get canBeEmpty => 'Can be empty';

  @override
  String get leaveEmptyAutoGenerate => 'Leave empty to auto-generate';

  @override
  String get usernameOptional => 'Username (optional)';

  @override
  String get passwordOptional => 'Password (optional)';

  @override
  String get connectFailedCheckCredentials =>
      'Connection failed. Please check the server address and credentials.';

  @override
  String get webdavAddServer => 'Add WebDAV Server';

  @override
  String get webdavEditServer => 'Edit WebDAV Server';

  @override
  String get webdavEnterAddress => 'Enter WebDAV address';

  @override
  String get webdavInvalidUrl => 'Please enter a valid URL (http/https)';

  @override
  String get webdavConnection => 'WebDAV Connection';

  @override
  String webdavTestFailedWithError(Object error) {
    return 'Test failed: $error';
  }

  @override
  String get webdavTestFailedCheckInfo =>
      'Connection test failed. Please check the address and credentials.';

  @override
  String get webdavTestSuccess => 'Connection test successful';

  @override
  String get webdavTestFailed => 'Connection test failed';

  @override
  String get webdavSaveFailedCheckInfo =>
      'Save failed. Please check the address and credentials.';

  @override
  String get webdavConnectHint =>
      'After connecting to a WebDAV server, you can browse directories and select media folders.';

  @override
  String get webdavConnectionNameOptional => 'Connection name (optional)';

  @override
  String get webdavAddress => 'WebDAV Address';

  @override
  String get smbAddServer => 'Add SMB Server';

  @override
  String get smbEditServer => 'Edit SMB Server';

  @override
  String get smbEnterHostOrIp => 'Enter hostname or IP address';

  @override
  String get smbInvalidPortRange =>
      'Invalid port. Please enter a value between 1 and 65535.';

  @override
  String get smbAnonymousHint =>
      'Leave username/password empty for anonymous access. Domain name is supported.';

  @override
  String get smbHostOrIp => 'Host / IP';

  @override
  String get smbHostOrIpPlaceholder => 'e.g. 192.168.1.10 or nas.local';

  @override
  String get smbPort => 'Port';

  @override
  String get smbDefaultPort445 => 'Default: 445';

  @override
  String get smbDomainOptional => 'Domain (optional)';

  @override
  String get smbDomainPlaceholder => 'e.g. WORKGROUP';

  @override
  String get connectJellyfinOrEmbyFirst =>
      'Please connect to a Jellyfin or Emby server first';

  @override
  String get networkMediaLibraryIntro =>
      'Manage Jellyfin / Emby server connections and set up DanDanPlay remote libraries here.';

  @override
  String get currentServerNotConnectedHint =>
      'Current server is not connected. Please go back and select again.';

  @override
  String get loadingRemoteMediaLibrary => 'Loading remote media library...';

  @override
  String get noRemoteMediaItems => 'No remote media items found';

  @override
  String recordedAtDate(Object date) {
    return 'Added on $date';
  }

  @override
  String get jellyfinMediaServerTitle => 'Jellyfin Media Server';

  @override
  String get jellyfinDisconnectedDescription =>
      'Connect to a Jellyfin server to sync your media library and playback history.';

  @override
  String get embyMediaServerTitle => 'Emby Media Server';

  @override
  String get embyDisconnectedDescription =>
      'Connect to an Emby server to browse your media library and play remotely.';

  @override
  String get dandanRemoteCardTitle => 'DanDanPlay Remote Access';

  @override
  String get dandanRemoteManageAccessTitle => 'Manage DanDanPlay Remote Access';

  @override
  String get dandanRemoteConnectAccessTitle =>
      'Connect to DanDanPlay Remote Access';

  @override
  String get dandanRemoteAddressPrompt =>
      'Enter the remote service address shown on your desktop.';

  @override
  String get dandanRemoteAddressPlaceholder => 'e.g. http://192.168.1.2:23333';

  @override
  String get dandanRemoteApiTokenOptionalTitle => 'API Key (optional)';

  @override
  String dandanRemoteApiTokenPrompt(Object actionLabel) {
    return 'If you have enabled API authentication in the DanDanPlay desktop app, enter the corresponding key. Otherwise, just tap $actionLabel.';
  }

  @override
  String get enterApiToken => 'Enter API key';

  @override
  String get optionalApiTokenHint => 'Optional, fill in if needed';

  @override
  String get dandanRemoteStatusSynced => 'Synced';

  @override
  String get dandanRemoteStatusConnectFailed => 'Connection failed';

  @override
  String get dandanRemoteStatusNotConfigured => 'Not configured';

  @override
  String get unknownErrorOccurred => 'An unknown error occurred';

  @override
  String get dandanRemoteServerAddressLabel => 'Server address';

  @override
  String get dandanRemoteLastSyncedLabel => 'Last synced';

  @override
  String get dandanRemoteAnimeEntries => 'Anime entries';

  @override
  String get dandanRemoteVideoFiles => 'Video files';

  @override
  String get dandanRemoteNoRecordsHint =>
      'No remote media records found. Try refreshing or check your remote access settings.';

  @override
  String get dandanRemoteRecentUpdates => 'Recent Updates';

  @override
  String dandanRemoteEpisodeCount(int count) {
    return '$count episodes total';
  }

  @override
  String get dandanRemoteManageConnection => 'Manage Connection';

  @override
  String get dandanRemoteSyncing => 'Syncing...';

  @override
  String get dandanRemoteRefreshLibrary => 'Refresh Library';

  @override
  String get dandanRemoteDisconnectedHintLong =>
      'Enable remote access in the DanDanPlay desktop app to sync anime records from your home PC or NAS and play directly here.';

  @override
  String get pleaseWait => 'Please wait...';

  @override
  String get connectDandanRemoteService =>
      'Connect to DanDanPlay Remote Service';

  @override
  String get noRecordYet => 'No records yet';

  @override
  String get justNow => 'Just now';

  @override
  String minutesAgo(int minutes) {
    return '$minutes min ago';
  }

  @override
  String hoursAgo(int hours) {
    return '$hours hr ago';
  }

  @override
  String daysAgo(int days) {
    return '$days days ago';
  }

  @override
  String get dandanRemoteConfigUpdated =>
      'DanDanPlay remote service configuration updated';

  @override
  String get dandanRemoteConnected => 'DanDanPlay remote service connected';

  @override
  String get dandanRemoteDisconnected =>
      'Disconnected from DanDanPlay remote service';

  @override
  String get disconnectDandanRemoteTitle =>
      'Disconnect DanDanPlay Remote Service';

  @override
  String get disconnectDandanRemoteContent =>
      'Are you sure you want to disconnect from the DanDanPlay remote service?\n\nThis will clear the saved server address and API key.';

  @override
  String get remoteLibraryRefreshed => 'Remote library refreshed';

  @override
  String get noConnectedServer => 'No server connected';

  @override
  String get mediaLibraryNotSelected => 'No library selected';

  @override
  String get mediaLibraryNotMatched => 'No library matched';

  @override
  String mediaLibraryAndCount(Object first, int count) {
    return '$first and $count others';
  }

  @override
  String mediaServerSummary(Object server, Object summary) {
    return '$server · $summary';
  }

  @override
  String serverMediaLibraryTitle(Object server) {
    return '$server Library';
  }

  @override
  String get serverLabel => 'Server';

  @override
  String get accountLabel => 'Account';

  @override
  String get mediaLibrary => 'Media Library';

  @override
  String get noMediaLibrary => 'No libraries available';

  @override
  String get checkServerConnection => 'Please check the server connection';

  @override
  String get transcodeSettings => 'Transcoding Settings';

  @override
  String currentDefaultQuality(Object quality) {
    return 'Current default quality: $quality';
  }

  @override
  String get enableTranscode => 'Enable Transcoding';

  @override
  String get defaultQuality => 'Default Quality';

  @override
  String get tvShowsLibrary => 'TV Shows';

  @override
  String get moviesLibrary => 'Movies';

  @override
  String get boxsetsLibrary => 'Collections';

  @override
  String get folderLibrary => 'Folders';

  @override
  String get mixedLibrary => 'Mixed Library';

  @override
  String get userActivityTitle => 'My Activity';

  @override
  String get userActivityTabWatched => 'Watched';

  @override
  String get userActivityTabFavorites => 'Favorites';

  @override
  String get userActivityTabRated => 'Rated';

  @override
  String userActivityTabWatchedCount(int count) {
    return 'Watched ($count)';
  }

  @override
  String userActivityTabFavoritesCount(int count) {
    return 'Favorites ($count)';
  }

  @override
  String userActivityTabRatedCount(int count) {
    return 'Rated ($count)';
  }

  @override
  String get userActivityNoWatchedRecords => 'No watch history';

  @override
  String get userActivityNoFavorites => 'No favorites';

  @override
  String get userActivityNoRatings => 'No ratings yet';

  @override
  String get userActivityNotLoggedIn => 'Not logged in to DanDanPlay';

  @override
  String userActivityWatchedEpisode(Object episode) {
    return 'Watched: $episode';
  }

  @override
  String userActivityWatchedUpdatedTime(Object time) {
    return 'Updated: $time';
  }

  @override
  String get userActivityWatchedOnly => 'Watched';

  @override
  String userActivityStatusWithValue(Object status) {
    return 'Status: $status';
  }

  @override
  String userActivityRatingWithValue(int rating) {
    return 'Rating: $rating';
  }

  @override
  String get userActivityUnknownTitle => 'Unknown Title';

  @override
  String get ratingLevelMasterpiece => 'Masterpiece';

  @override
  String get ratingLevelGreat => 'Great';

  @override
  String get ratingLevelGood => 'Good';

  @override
  String get ratingLevelAverage => 'Average';

  @override
  String get ratingLevelOkay => 'Okay';

  @override
  String get ratingLevelPoor => 'Poor';

  @override
  String get ratingLevelVeryPoor => 'Very Poor';

  @override
  String get ratingLevelTerrible => 'Terrible';

  @override
  String get favoriteStatusFollowing => 'Following';

  @override
  String get favoriteStatusFinished => 'Finished';

  @override
  String get favoriteStatusAbandoned => 'Dropped';

  @override
  String get favoriteStatusFavorited => 'Favorited';

  @override
  String get weekdaySunday => 'Sun';

  @override
  String get weekdayMonday => 'Mon';

  @override
  String get weekdayTuesday => 'Tue';

  @override
  String get weekdayWednesday => 'Wed';

  @override
  String get weekdayThursday => 'Thu';

  @override
  String get weekdayFriday => 'Fri';

  @override
  String get weekdaySaturday => 'Sat';

  @override
  String get newSeriesNoTodayAnime => 'No new anime today';

  @override
  String get newSeriesUpdateTimeTbd => 'Update time TBD';

  @override
  String get newSeriesSearchDescription =>
      'Search new anime\nFilter by tags and genres\nFind anime you\'re interested in';

  @override
  String get newSeriesSortDescriptionAscending =>
      'Switch to ascending order\nToday\'s new anime shown first';

  @override
  String get newSeriesSortDescriptionDescending =>
      'Switch to descending order\nToday\'s new anime shown last';

  @override
  String get newSeriesInitializingPlayer => 'Initializing player...';

  @override
  String newSeriesPlayerLoadFailedWithError(Object error) {
    return 'Player load failed: $error';
  }

  @override
  String newSeriesErrorOccurredWithError(Object error) {
    return 'Error occurred: $error';
  }

  @override
  String newSeriesHandlePlayRequestFailedWithError(Object error) {
    return 'Error handling play request: $error';
  }

  @override
  String newSeriesAnimeCount(int count) {
    return '$count anime';
  }

  @override
  String get newSeriesRemoteAddressNotConfigured =>
      'Remote access address not configured';

  @override
  String get newSeriesNetworkTimeout =>
      'Network request timed out. Please check your connection and try again.';

  @override
  String get newSeriesNetworkConnectionFailed =>
      'Network connection failed. Please check your network settings.';

  @override
  String get newSeriesServerUnavailableRetryLater =>
      'Server is unavailable. Please try again later.';

  @override
  String get newSeriesServerDataFormatError =>
      'Invalid data format received from server';

  @override
  String get developerOptions => 'Developer Options';

  @override
  String get developerOptionsSubtitle =>
      'Terminal output, dependency versions, build info';

  @override
  String get terminalOutput => 'Terminal Output';

  @override
  String get terminalOutputSubtitle =>
      'View logs, copy content, or generate QR code to share';

  @override
  String get dependencyVersions => 'Dependency Versions';

  @override
  String get dependencyVersionsSubtitle =>
      'View dependencies and version numbers (with GitHub links)';

  @override
  String get invalidLink => 'Invalid link';

  @override
  String get unknown => 'Unknown';

  @override
  String get localSource => 'Local';

  @override
  String get dependencyTypeDirectMain => 'Direct dependency';

  @override
  String get dependencyTypeDirectDev => 'Dev dependency';

  @override
  String get dependencyTypeTransitive => 'Transitive dependency';

  @override
  String get dependencyTypeUnknown => 'Unknown source';

  @override
  String get parsingDependencyInfo => 'Parsing dependency info...';

  @override
  String get readDependencyListFailed => 'Failed to read dependency list';

  @override
  String dependencySummaryWithOther(
      int total, int directMain, int directDev, int transitive, int other) {
    return '$total total · Direct $directMain / Dev $directDev / Transitive $transitive / Other $other';
  }

  @override
  String dependencySummaryNoOther(
      int total, int directMain, int directDev, int transitive) {
    return '$total total · Direct $directMain / Dev $directDev / Transitive $transitive';
  }

  @override
  String dependencyEntrySubtitle(
      Object version, Object dependencyType, Object sourceType) {
    return 'Version: $version · $dependencyType · $sourceType';
  }

  @override
  String get buildInfo => 'Build Info';

  @override
  String get buildInfoSubtitle =>
      'View build time, processor, memory, and system architecture';

  @override
  String get fileLogWriteTitle => 'Write Logs to File';

  @override
  String get fileLogWriteSubtitle =>
      'Writes to disk every 1 second, keeps the last 5 log files';

  @override
  String get fileLogWriteEnabled => 'Log file writing enabled';

  @override
  String get fileLogWriteDisabled => 'Log file writing disabled';

  @override
  String get openLogDirectoryTitle => 'Open Log Directory';

  @override
  String get openLogDirectorySubtitle =>
      'Open the log directory in file manager';

  @override
  String get logDirectoryOpened => 'Log directory opened';

  @override
  String get openLogDirectoryFailed => 'Failed to open log directory';

  @override
  String get spoilerAiDebugPrintTitle => 'Debug: Print AI Response';

  @override
  String get spoilerAiDebugPrintEnabledHint =>
      'When enabled, raw AI response text and matched danmaku will be printed to logs.';

  @override
  String get spoilerAiDebugPrintNeedSpoilerMode =>
      'Enable spoiler prevention mode first';

  @override
  String get spoilerAiDebugPrintEnabled => 'AI debug printing enabled';

  @override
  String get spoilerAiDebugPrintDisabled => 'AI debug printing disabled';

  @override
  String get playerUnavailableOnWeb =>
      'Player settings are not available on the web platform';

  @override
  String get danmakuRenderEngine => 'Danmaku Render Engine';

  @override
  String get danmakuRenderEngineSwitched => 'Danmaku render engine switched';

  @override
  String get danmakuRenderEngineDescriptionCpu =>
      'CPU Rendering: Best compatibility, suitable for most scenarios.';

  @override
  String get danmakuRenderEngineDescriptionGpuExperimental =>
      'GPU Rendering (Experimental): Higher performance, still under development.';

  @override
  String get danmakuRenderEngineDescriptionCanvasExperimental =>
      'Canvas Danmaku (Experimental): High performance, low power consumption.';

  @override
  String get danmakuRenderEngineDescriptionNipaplayNext =>
      'NipaPlay Next: Combines the strengths of both CPU and Canvas danmaku, featuring all advantages of both.';

  @override
  String get danmakuRenderEngineTitleCpu => 'CPU Rendering';

  @override
  String get danmakuRenderEngineTitleGpuExperimental =>
      'GPU Rendering (Experimental)';

  @override
  String get danmakuRenderEngineTitleCanvasExperimental =>
      'Canvas Danmaku (Experimental)';

  @override
  String get danmakuRenderEngineTitleNipaplayNext => 'NipaPlay Next';

  @override
  String get qualityProfileOff => 'Off';

  @override
  String get qualityProfileLite => 'Lite';

  @override
  String get qualityProfileStandard => 'Standard';

  @override
  String get qualityProfileHigh => 'High Quality';

  @override
  String get doubleResolutionPlaybackTitle => 'Double Resolution Playback';

  @override
  String get doubleResolutionPlaybackSubtitle =>
      'Render at 2x resolution for sharper embedded subtitles (Libmpv only, not combinable with Anime4K)';

  @override
  String get settingSavedReopenVideoToApply =>
      'Saved. Reopen the video to apply.';

  @override
  String get doubleResolutionPlaybackEnabled =>
      'Double resolution playback enabled';

  @override
  String get doubleResolutionPlaybackDisabled =>
      'Double resolution playback disabled';

  @override
  String get anime4kSuperResolutionTitle =>
      'Anime4K Super Resolution (Experimental)';

  @override
  String get anime4kProfileDescriptionOff =>
      'Keep original image, no super resolution processing.';

  @override
  String get anime4kProfileDescriptionLite =>
      'Moderate super resolution and denoising with low performance impact.';

  @override
  String get anime4kProfileDescriptionStandard =>
      'Balanced quality and performance.';

  @override
  String get anime4kProfileDescriptionHigh =>
      'Best image quality, highest performance requirements.';

  @override
  String get anime4kDisabled => 'Anime4K disabled';

  @override
  String anime4kSwitchedTo(Object option) {
    return 'Anime4K switched to $option';
  }

  @override
  String get crtDisplayEffectTitle => 'CRT Display Effect';

  @override
  String get crtProfileDescriptionOff => 'Keep original image, no CRT effect.';

  @override
  String get crtProfileDescriptionLite =>
      'Scanlines + vignette, minimal performance impact.';

  @override
  String get crtProfileDescriptionStandard =>
      'Adds curvature and grid for a more authentic CRT look.';

  @override
  String get crtProfileDescriptionHigh =>
      'Adds glow and color fringing, best effect but higher performance cost.';

  @override
  String get crtDisabled => 'CRT disabled';

  @override
  String crtSwitchedTo(Object option) {
    return 'CRT switched to $option';
  }

  @override
  String get enterAiApiUrl => 'Enter AI API URL';

  @override
  String get enterModelName => 'Enter model name';

  @override
  String get enterApiKey => 'Enter API Key';

  @override
  String get spoilerAiSettingsSaved => 'Spoiler prevention AI settings saved';

  @override
  String get spoilerPreventionMode => 'Spoiler Prevention';

  @override
  String get spoilerPreventionModeSubtitle =>
      'When enabled, AI will identify and filter suspected spoiler danmaku after loading.';

  @override
  String get fillAndSaveAiConfigFirst =>
      'Please fill in and save the AI API configuration first';

  @override
  String get spoilerPreventionModeEnabled => 'Spoiler prevention enabled';

  @override
  String get spoilerPreventionModeDisabled => 'Spoiler prevention disabled';

  @override
  String get autoMatchDanmakuOnPlayTitle => 'Auto-Match Danmaku on Play';

  @override
  String get autoMatchDanmakuOnPlaySubtitle =>
      'When disabled, danmaku won\'t be auto-matched on playback. You can manually match in danmaku settings.';

  @override
  String get autoMatchDanmakuOnPlayEnabled =>
      'Auto-match danmaku on play enabled';

  @override
  String get autoMatchDanmakuOnPlayDisabledManual =>
      'Auto-match on play disabled (manual matching available)';

  @override
  String get danmakuAutoLoadStrategyTitle => 'Danmaku Auto-Load';

  @override
  String get danmakuAutoLoadStrategySubtitle =>
      'Choose what danmaku should be loaded automatically when opening a local video.';

  @override
  String get danmakuAutoLoadStrategyRemoteAndLocal =>
      'Remote + Local Same-Name';

  @override
  String get danmakuAutoLoadStrategyRemoteAndLocalDescription =>
      'Default: auto-load remote danmaku and also add same-name .xml/.json files from the video folder.';

  @override
  String get danmakuAutoLoadStrategyRemote => 'Remote Danmaku';

  @override
  String get danmakuAutoLoadStrategyRemoteDescription =>
      'Auto-match and load danmaku from DanDanPlay.';

  @override
  String get danmakuAutoLoadStrategyLocal => 'Local Same-Name File';

  @override
  String get danmakuAutoLoadStrategyLocalDescription =>
      'Load a same-name .xml or .json danmaku file from the video folder.';

  @override
  String get danmakuAutoLoadStrategyManual => 'Manual Selection';

  @override
  String get danmakuAutoLoadStrategyManualDescription =>
      'Do not auto-load danmaku; choose a match manually.';

  @override
  String get danmakuAutoLoadStrategyUpdated =>
      'Danmaku auto-load strategy updated';

  @override
  String get autoMatchOnHashFailTitle => 'Auto-Match on Hash Failure';

  @override
  String get autoMatchOnHashFailSubtitle =>
      'When hash matching fails, automatically use the first filename search result. When disabled, the search danmaku menu will be shown instead.';

  @override
  String get autoMatchOnHashFailEnabled => 'Auto-match on hash failure enabled';

  @override
  String get autoMatchOnHashFailDisabledShowSearch =>
      'Auto-match on hash failure disabled (search menu will be shown)';

  @override
  String get hardwareDecoding => 'Hardware Decoding';

  @override
  String get hardwareDecodingSubtitle => 'Only applies to MDK / Libmpv kernels';

  @override
  String get hardwareDecodingEnabled => 'Hardware decoding enabled';

  @override
  String get hardwareDecodingDisabled => 'Hardware decoding disabled';

  @override
  String get pauseOnBackgroundTitle => 'Pause on Background';

  @override
  String get pauseOnBackgroundSubtitle =>
      'Automatically pause playback when switching to background or locking screen';

  @override
  String get pauseOnBackgroundEnabled => 'Pause on background enabled';

  @override
  String get pauseOnBackgroundDisabled => 'Pause on background disabled';

  @override
  String get playbackEndActionTitle => 'Action After Playback';

  @override
  String get playbackEndActionAutoNextMessage =>
      'Automatically play the next episode after playback ends';

  @override
  String get playbackEndActionLoopMessage =>
      'Loop from the beginning after playback ends';

  @override
  String get playbackEndActionPauseMessage =>
      'Stay on the current page after playback ends';

  @override
  String get playbackEndActionExitMessage =>
      'Return to the previous page after playback ends';

  @override
  String get autoNextCountdownTitle => 'Auto-Next Countdown';

  @override
  String autoNextCountdownWaitSeconds(int seconds) {
    return 'Wait $seconds seconds before auto-playing next episode';
  }

  @override
  String get autoNextCountdownNeedAutoNext =>
      'Enable auto-play next episode first';

  @override
  String get timelinePreviewTitle => 'Timeline Preview Thumbnails';

  @override
  String get timelinePreviewSubtitle =>
      'Show thumbnails when hovering over the progress bar (works for local/WebDAV/SMB/shared libraries)';

  @override
  String get enableWarning => 'Warning';

  @override
  String get timelinePreviewEnableWarningContent =>
      'Enabling timeline preview will generate screenshots in real-time during playback, which may cause stuttering or performance degradation. Continue?';

  @override
  String get timelinePreviewEnabled => 'Timeline preview enabled';

  @override
  String get timelinePreviewDisabled => 'Timeline preview disabled';

  @override
  String get playPrecacheDuration => 'Pre-cache Duration';

  @override
  String get playPrecacheSize => 'Pre-cache Size';

  @override
  String currentPrecacheDurationSeconds(int seconds) {
    return 'Current: $seconds seconds. Changes take effect immediately.';
  }

  @override
  String currentPrecacheSizeMb(int mb) {
    return 'Current: $mb MB. Reopen the video to apply changes.';
  }

  @override
  String get libmpvKernelOnly => 'Only applies to Libmpv kernel';

  @override
  String get spoilerAiSettingsTitle => 'Spoiler Prevention AI Settings';

  @override
  String get spoilerAiSettingsDescription =>
      'Fill in and save the configuration before enabling spoiler prevention (API URL / Key / Model are required).';

  @override
  String get spoilerAiGeminiUrlNote =>
      'Gemini: URL can end at /v1beta/models. The request path /<model>:generateContent will be appended automatically.';

  @override
  String get spoilerAiOpenAiUrlNote =>
      'OpenAI: URL should be /v1/chat/completions (compatible endpoints also work).';

  @override
  String get apiFormatLabel => 'API Format';

  @override
  String get openAiCompatible => 'OpenAI Compatible';

  @override
  String get enterYourApiKey => 'Enter your API Key';

  @override
  String temperatureLabel(Object value) {
    return 'Temperature: $value';
  }

  @override
  String get saveConfiguration => 'Save Configuration';

  @override
  String get about => 'About';

  @override
  String get loading => 'Loading…';

  @override
  String currentVersion(Object version) {
    return 'Current version: $version';
  }

  @override
  String get versionLoadFailed => 'Failed to load version info';

  @override
  String get general => 'General';

  @override
  String get backupAndRestore => 'Backup & Restore';

  @override
  String get shortcuts => 'Shortcuts';

  @override
  String get remoteAccess => 'Remote Access';

  @override
  String get remoteMediaLibrary => 'Remote Media Library';

  @override
  String get appearanceSettings => 'Appearance Settings';

  @override
  String get generalSettings => 'General Settings';

  @override
  String get storageSettings => 'Storage Settings';

  @override
  String get playerSettings => 'Player Settings';

  @override
  String get shortcutsSettings => 'Shortcuts Settings';

  @override
  String get rememberDanmakuOffset => 'Remember Danmaku Offset';

  @override
  String get rememberDanmakuOffsetSubtitle =>
      'Keep the current manual offset when switching videos (auto-matched offset will still reset).';

  @override
  String get rememberDanmakuOffsetEnabled => 'Danmaku offset memory enabled';

  @override
  String get rememberDanmakuOffsetDisabled => 'Danmaku offset memory disabled';

  @override
  String get danmakuConvertToSimplified =>
      'Convert Danmaku to Simplified Chinese';

  @override
  String get danmakuConvertToSimplifiedSubtitle =>
      'When enabled, Traditional Chinese danmaku will be displayed in Simplified Chinese.';

  @override
  String get danmakuConvertToSimplifiedEnabled =>
      'Danmaku conversion to Simplified Chinese enabled';

  @override
  String get danmakuConvertToSimplifiedDisabled =>
      'Danmaku conversion to Simplified Chinese disabled';

  @override
  String get cancel => 'Cancel';

  @override
  String get confirm => 'Confirm';

  @override
  String get close => 'Close';

  @override
  String get saving => 'Saving...';

  @override
  String networkServerSwitchedTo(Object server) {
    return 'DanDanPlay server switched to $server';
  }

  @override
  String get enterServerAddress => 'Enter server address';

  @override
  String get invalidServerAddress =>
      'Invalid server address. Must start with http/https.';

  @override
  String get switchedToCustomServer => 'Switched to custom server';

  @override
  String get networkPrimaryServerRecommended => 'Primary Server (Recommended)';

  @override
  String get networkBackupServer => 'Backup Server';

  @override
  String get networkCurrentCustomServer => 'Current Custom Server';

  @override
  String get networkSelectServer => 'Select DanDanPlay Server';

  @override
  String get primaryServer => 'Primary Server';

  @override
  String get backupServer => 'Backup Server';

  @override
  String get dandanplayServer => 'DanDanPlay Server';

  @override
  String get customServer => 'Custom Server';

  @override
  String get customServerInputHint =>
      'Enter a danmaku server address compatible with DanDanPlay API, e.g. https://example.com';

  @override
  String get customServerPlaceholder => 'https://your-danmaku-server.com';

  @override
  String get useThisServer => 'Use This Server';

  @override
  String get currentServerInfo => 'Current Server Info';

  @override
  String get serverDescriptionTitle => 'Server Description';

  @override
  String serverField(Object server) {
    return 'Server: $server';
  }

  @override
  String urlField(Object url) {
    return 'URL: $url';
  }

  @override
  String serverBullet(Object name, Object description) {
    return '• $name: $description';
  }

  @override
  String get networkServerDescriptionPrimary =>
      'api.dandanplay.net (Official server, recommended)';

  @override
  String get networkServerDescriptionBackup =>
      '139.224.252.88:16001 (Mirror server, use when the primary server is unavailable)';

  @override
  String get networkServerSelectSubtitle =>
      'Select a DanDanPlay danmaku server. The backup server can be used when the primary server is unavailable.';

  @override
  String customServerWithValue(Object server) {
    return 'Custom: $server';
  }

  @override
  String get enabledClearOnLaunchSnack =>
      'Danmaku cache cleanup on launch enabled';

  @override
  String get danmakuCacheCleared => 'Danmaku cache cleared';

  @override
  String clearFailed(Object error) {
    return 'Clear failed: $error';
  }

  @override
  String get imageCacheCleared => 'Image cache cleared';

  @override
  String get confirmClearCacheTitle => 'Confirm Cache Clear';

  @override
  String get confirmClearImageCacheContent =>
      'Are you sure you want to clear the cover and thumbnail image cache?';

  @override
  String get clearDanmakuCacheOnLaunchTitle => 'Clear Danmaku Cache on Launch';

  @override
  String get clearDanmakuCacheOnLaunchSubtitle =>
      'Automatically delete danmaku cache in the cache/danmaku/ directory';

  @override
  String get screenshotSaveLocation => 'Screenshot Save Location';

  @override
  String get defaultDownloadDir => 'Default: Downloads';

  @override
  String get screenshotSaveLocationUpdated =>
      'Screenshot save location updated';

  @override
  String get screenshotDefaultSaveTarget => 'Default Screenshot Save Target';

  @override
  String get screenshotDefaultSaveTargetMessage =>
      'Choose how screenshots are saved by default';

  @override
  String get clearDanmakuCacheNow => 'Clear Danmaku Cache Now';

  @override
  String get clearingInProgress => 'Clearing...';

  @override
  String get clearDanmakuCacheManualHint =>
      'Manually clear when danmaku is abnormal or using too much space';

  @override
  String get clearImageCache => 'Clear Image Cache';

  @override
  String get clearImageCacheHint => 'Clear cover and thumbnail image cache';

  @override
  String get danmakuCacheDescription =>
      'Danmaku cache is stored in the app cache directory cache/danmaku/. Enable auto-cleanup to reduce storage usage.';

  @override
  String get imageCacheDescription =>
      'Image cache includes covers and playback thumbnails, stored in the app cache directory. Can be cleared as needed.';

  @override
  String get clearDanmakuCacheOnLaunchSubtitleNipaplay =>
      'Automatically delete all cached danmaku files when restarting the app to ensure fresh data';

  @override
  String get clearDanmakuCacheManualHintNipaplay =>
      'Manually clear when cache is deleted or abnormal';

  @override
  String get danmakuCacheDescriptionNipaplay =>
      'Danmaku cache files are stored in the cache/danmaku/ directory. Clear anytime if taking up too much space.';

  @override
  String get imageCacheDescriptionNipaplay =>
      'Image cache includes covers and playback thumbnails, stored in the app cache directory. Can be cleared periodically.';

  @override
  String clearDanmakuCacheFailed(Object error) {
    return 'Failed to clear danmaku cache: $error';
  }

  @override
  String clearImageCacheFailed(Object error) {
    return 'Failed to clear image cache: $error';
  }

  @override
  String get screenshotSaveAskDescription =>
      'Show save dialog each time you take a screenshot';

  @override
  String get screenshotSavePhotosDescription =>
      'Save screenshots directly to the photo gallery';

  @override
  String get screenshotSaveFileDescription =>
      'Save screenshots directly as files';

  @override
  String get aboutNoReleaseNotes => 'No release notes available';

  @override
  String aboutFoundNewVersion(Object version) {
    return 'New version $version available';
  }

  @override
  String get aboutCurrentIsLatest => 'You are on the latest version';

  @override
  String aboutCurrentVersionLabel(Object version) {
    return 'Current version: $version';
  }

  @override
  String aboutLatestVersionLabel(Object version) {
    return 'Latest version: $version';
  }

  @override
  String aboutReleaseNameLabel(Object name) {
    return 'Release name: $name';
  }

  @override
  String aboutPublishedAtLabel(Object publishedAt) {
    return 'Published: $publishedAt';
  }

  @override
  String get aboutReleaseNotesTitle => 'Release Notes';

  @override
  String get aboutOpenReleasePage => 'View Release Page';

  @override
  String get updateCheckFailed => 'Update check failed';

  @override
  String get pleaseTryAgainLater => 'Please try again later';

  @override
  String cannotOpenLink(Object url) {
    return 'Cannot open link: $url';
  }

  @override
  String get appreciationCode => 'Tip Jar';

  @override
  String get appreciationCodeHint => 'Tap to view the tip jar';

  @override
  String get appreciationImageLoadFailed => 'Failed to load tip jar image';

  @override
  String get acknowledgements => 'Acknowledgements';

  @override
  String get aboutStoryPrefix =>
      'NipaPlay\'s name comes from Furude Rika\'s catchphrase \"';

  @override
  String get aboutStorySuffix =>
      '\" from Higurashi: When They Cry. I created NipaPlay to solve the inconvenience of watching anime on macOS, Linux, and iOS.';

  @override
  String get aboutThanksDandanplayPrefix =>
      'Thanks to DanDanPlay and developer ';

  @override
  String get aboutThanksDandanplaySuffix =>
      ' for providing the API and development support.';

  @override
  String get aboutThanksSakikoPrefix => 'Thanks to developer ';

  @override
  String get aboutThanksSakikoSuffix =>
      ' for helping implement Emby and Jellyfin media library support.';

  @override
  String get thanksSponsorUsers =>
      'Thanks to the following users for their sponsorship:';

  @override
  String aboutVersionBanner(Object version) {
    return 'NipaPlay Reload Version: $version';
  }

  @override
  String get aboutCheckingUpdates => 'Checking…';

  @override
  String get aboutCheckUpdates => 'Check for Updates';

  @override
  String get aboutAutoCheckUpdates => 'Auto-check for Updates';

  @override
  String get aboutManualOnlyWhenDisabled => 'Manual check only when disabled';

  @override
  String aboutQqGroup(Object id) {
    return 'QQ Group: $id';
  }

  @override
  String get aboutOfficialWebsite => 'NipaPlay Official Website';

  @override
  String get openSourceCommunity => 'Open Source & Community';

  @override
  String get aboutCommunityHint =>
      'Contributions are welcome! Feel free to port the app to more platforms. No Dart experience needed — AI-assisted programming works too.';

  @override
  String get sponsorSupport => 'Sponsor Support';

  @override
  String get aboutSponsorParagraph1 =>
      'If you enjoy NipaPlay and want to support its continued development, consider sponsoring via Afdian.';

  @override
  String get aboutSponsorParagraph2 =>
      'Sponsors\' names will appear in the project\'s README file and the About page after each update.';

  @override
  String get aboutAfdianSponsorPage => 'Afdian Sponsorship Page';
}
