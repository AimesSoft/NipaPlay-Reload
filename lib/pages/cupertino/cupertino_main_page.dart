import 'dart:io' as io;

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/pages/cupertino/account/cupertino_account_page.dart';
import 'package:nipaplay/pages/cupertino/cupertino_home_page.dart';
import 'package:nipaplay/pages/cupertino/cupertino_media_library_page.dart';
import 'package:nipaplay/pages/cupertino/cupertino_play_video_page.dart';
import 'package:nipaplay/pages/cupertino/cupertino_settings_page.dart';
import 'package:nipaplay/providers/bottom_bar_provider.dart';
import 'package:nipaplay/services/file_picker_service.dart';
import 'package:nipaplay/services/playback_service.dart';
import 'package:nipaplay/utils/tab_change_notifier.dart';
import 'package:nipaplay/widgets/cupertino/cupertino_bounce_wrapper.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_snackbar.dart';

class CupertinoMainPage extends StatefulWidget {
  final String? launchFilePath;

  const CupertinoMainPage({super.key, this.launchFilePath});

  @override
  State<CupertinoMainPage> createState() => _CupertinoMainPageState();
}

class _CupertinoMainPageState extends State<CupertinoMainPage> {
  static const int _importTabIndex = 4;

  int _selectedIndex = 0;
  TabChangeNotifier? _tabChangeNotifier;
  bool _isVideoPagePresented = false;
  bool _isImporting = false;

  final List<GlobalKey<CupertinoBounceWrapperState>> _bounceKeys = [
    GlobalKey<CupertinoBounceWrapperState>(),
    GlobalKey<CupertinoBounceWrapperState>(),
    GlobalKey<CupertinoBounceWrapperState>(),
    GlobalKey<CupertinoBounceWrapperState>(),
  ];

  static const List<Widget> _pages = [
    CupertinoHomePage(),
    CupertinoMediaLibraryPage(),
    CupertinoAccountPage(),
    CupertinoSettingsPage(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      CupertinoBounceWrapper.playAnimation(_bounceKeys[_selectedIndex]);
      _tabChangeNotifier = Provider.of<TabChangeNotifier>(context, listen: false);
      _tabChangeNotifier?.addListener(_handleTabChange);
    });
  }

  @override
  void dispose() {
    _tabChangeNotifier?.removeListener(_handleTabChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cupertinoTheme = CupertinoTheme.of(context);
    final Color activeColor = cupertinoTheme.primaryColor;
    final Color inactiveColor =
        CupertinoDynamicColor.resolve(CupertinoColors.inactiveGray, context);

    return Consumer<BottomBarProvider>(
      builder: (context, bottomBarProvider, _) {
        return AdaptiveScaffold(
          minimizeBehavior: TabBarMinimizeBehavior.never,
          enableBlur: true,
          body: AnimatedSwitcher(
            duration: const Duration(milliseconds: 50),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: KeyedSubtree(
              key: ValueKey<int>(_selectedIndex),
              child: CupertinoBounceWrapper(
                key: _bounceKeys[_selectedIndex],
                autoPlay: false,
                child: _pages[_selectedIndex],
              ),
            ),
          ),
          bottomNavigationBar: AdaptiveBottomNavigationBar(
            useNativeBottomBar: bottomBarProvider.useNativeBottomBar,
            selectedItemColor: activeColor,
            unselectedItemColor: inactiveColor,
            items: const [
              AdaptiveNavigationDestination(
                icon: 'house.fill',
                label: '主页',
              ),
              AdaptiveNavigationDestination(
                icon: 'play.rectangle.fill',
                label: '媒体库',
              ),
              AdaptiveNavigationDestination(
                icon: 'person.crop.circle.fill',
                label: '账户',
              ),
              AdaptiveNavigationDestination(
                icon: 'gearshape.fill',
                label: '设置',
              ),
              AdaptiveNavigationDestination(
                icon: 'plus.circle.fill',
                label: '导入',
              ),
            ],
            selectedIndex: _selectedIndex,
            onTap: (index) {
              if (index == _importTabIndex) {
                _showImportSheet();
              } else {
                _selectTab(index);
              }
            },
          ),
        );
      },
    );
  }

  void _selectTab(int index) {
    if (_selectedIndex == index) {
      return;
    }
    if (index >= _pages.length) {
      return;
    }
    setState(() {
      _selectedIndex = index;
    });
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) {
        CupertinoBounceWrapper.playAnimation(_bounceKeys[index]);
      }
    });
  }

  void _handleTabChange() {
    final notifier = _tabChangeNotifier;
    if (notifier == null) return;

    final targetIndex = notifier.targetTabIndex;
    if (targetIndex == null) {
      return;
    }

    if (targetIndex == 1) {
      _presentVideoPage();
      notifier.clearMainTabIndex();
      return;
    }

    final int clampedIndex = targetIndex.clamp(0, _pages.length - 1).toInt();
    _selectTab(clampedIndex);
    notifier.clearMainTabIndex();
  }

  Future<void> _presentVideoPage() async {
    if (_isVideoPagePresented || !mounted) {
      return;
    }

    _isVideoPagePresented = true;
    final bottomBarProvider = context.read<BottomBarProvider>();
    bottomBarProvider.hideBottomBar();
    try {
      await Navigator.of(context, rootNavigator: true).push(
        CupertinoPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => const CupertinoPlayVideoPage(),
        ),
      );
    } finally {
      bottomBarProvider.showBottomBar();
      if (mounted) {
        _isVideoPagePresented = false;
      }
    }
  }

  Future<void> _showImportSheet() async {
    if (!mounted || _isImporting) return;

    final result = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('导入视频'),
        message: const Text('请选择视频来源'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context).pop('album'),
            child: const Text('相册'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context).pop('file'),
            child: const Text('文件管理器'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ),
    );

    if (!mounted || result == null) return;

    switch (result) {
      case 'album':
        await _startImport(_pickVideoFromAlbum);
        break;
      case 'file':
        await _startImport(_pickVideoFromFileManager);
        break;
    }
  }

  Future<void> _startImport(Future<void> Function() task) async {
    if (_isImporting) return;
    _isImporting = true;
    try {
      await task();
    } catch (e) {
      if (mounted) {
        BlurSnackBar.show(context, '导入视频失败: $e');
      }
    } finally {
      _isImporting = false;
    }
  }

  Future<void> _pickVideoFromAlbum() async {
    try {
      if (io.Platform.isAndroid) {
        final photos = await Permission.photos.request();
        final videos = await Permission.videos.request();
        if (!photos.isGranted || !videos.isGranted) {
          if (mounted) {
            BlurSnackBar.show(context, '需要授予相册与视频权限');
          }
          return;
        }
      }

      final picker = ImagePicker();
      final XFile? picked = await picker.pickVideo(source: ImageSource.gallery);
      if (picked == null) {
        return;
      }
      await _playSelectedFile(picked.path);
    } catch (e) {
      if (mounted) {
        BlurSnackBar.show(context, '选择相册视频失败: $e');
      }
    }
  }

  Future<void> _pickVideoFromFileManager() async {
    final filePickerService = FilePickerService();
    final filePath = await filePickerService.pickVideoFile();
    if (filePath == null) {
      return;
    }
    await _playSelectedFile(filePath);
  }

  Future<void> _playSelectedFile(String path) async {
    try {
      await WatchHistoryManager.initialize();
    } catch (_) {
      // ignore initialization errors
    }

    WatchHistoryItem? historyItem =
        await WatchHistoryManager.getHistoryItem(path);
    historyItem ??= WatchHistoryItem(
      filePath: path,
      animeName: p.basenameWithoutExtension(path),
      watchProgress: 0,
      lastPosition: 0,
      duration: 0,
      lastWatchTime: DateTime.now(),
    );

    final playable = PlayableItem(
      videoPath: path,
      title: historyItem.animeName,
      historyItem: historyItem,
    );

    await PlaybackService().play(playable);
  }
}
