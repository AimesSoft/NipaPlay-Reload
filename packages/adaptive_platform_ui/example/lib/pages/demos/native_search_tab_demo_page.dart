import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

/// Demo page for iOS 26 Native Search Tab Bar
///
/// EXPERIMENTAL: This feature completely replaces Flutter's navigation
class NativeSearchTabDemoPage extends StatefulWidget {
  const NativeSearchTabDemoPage({super.key});

  @override
  State<NativeSearchTabDemoPage> createState() =>
      _NativeSearchTabDemoPageState();
}

class _NativeSearchTabDemoPageState extends State<NativeSearchTabDemoPage> {
  int _currentTab = 0;
  String _searchQuery = '';
  bool _isNativeEnabled = false;

  @override
  void initState() {
    super.initState();
    // Auto-enable native tab bar when page loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _enableNativeTabBar();
    });
  }

  @override
  void dispose() {
    // Auto-disable native tab bar when leaving page
    if (_isNativeEnabled) {
      IOS26NativeSearchTabBar.disable();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      appBar: AdaptiveAppBar(title: 'Native Search Tab (iOS 26+)'),
      body: _buildContent(),
    );
  }

  Widget _buildContent() {
    final topPadding = PlatformInfo.isIOS ? 130.0 : 16.0;

    return ListView(
      padding: EdgeInsets.only(
        left: 16.0,
        right: 16.0,
        top: topPadding,
        bottom: 16.0,
      ),
      children: [
        _buildWarningCard(),
        const SizedBox(height: 24),
        _buildRootCauseCard(),
        const SizedBox(height: 24),
        _buildTechnicalDetailsCard(),
        const SizedBox(height: 24),
        _buildStatusCard(),
        const SizedBox(height: 24),
        _buildControlsCard(),
        if (_searchQuery.isNotEmpty) ...[
          const SizedBox(height: 24),
          _buildSearchResultsCard(),
        ],
        SizedBox(height: 100),
      ],
    );
  }

  Widget _buildWarningCard() {
    return AdaptiveCard(
      padding: const EdgeInsets.all(16),
      color: PlatformInfo.isIOS
          ? CupertinoColors.systemYellow.withValues(alpha: 0.15)
          : Colors.orange.withValues(alpha: 0.15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                PlatformInfo.isIOS
                    ? CupertinoIcons.exclamationmark_triangle_fill
                    : Icons.warning,
                color: PlatformInfo.isIOS
                    ? CupertinoColors.systemYellow
                    : Colors.orange,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'EXPERIMENTAL FEATURE',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: _getTextColor(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'This demo automatically activates when you enter this page and deactivates when you leave.\n\n'
            'The native search tab bar completely replaces Flutter\'s navigation system with UITabBarController.\n\n'
            'Features:\n'
            '• Native tab bar transformation to search\n'
            '• iOS 26+ Liquid Glass effects\n'
            '• Seamless search experience\n\n'
            'Only for iOS 26+ testing!',
            style: TextStyle(
              fontSize: 14,
              color: _getSecondaryTextColor(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    return AdaptiveCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Status',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: _getTextColor(context),
            ),
          ),
          const SizedBox(height: 16),
          _buildStatusRow(
            'Native Tab Bar',
            _isNativeEnabled ? 'Active ✓' : 'Activating...',
          ),
          if (_isNativeEnabled)
            _buildStatusRow('Current Tab', 'Tab $_currentTab'),
          if (_searchQuery.isNotEmpty)
            _buildStatusRow('Search Query', _searchQuery),
        ],
      ),
    );
  }

  Widget _buildStatusRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 15,
              color: _getSecondaryTextColor(context),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: _getTextColor(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlsCard() {
    return AdaptiveCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Controls',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: _getTextColor(context),
            ),
          ),
          const SizedBox(height: 16),
          if (_isNativeEnabled) ...[
            SizedBox(
              width: double.infinity,
              height: 44,
              child: AdaptiveButton(
                style: AdaptiveButtonStyle.tinted,
                label: 'Show Search',
                enabled: false,
                onPressed: () => IOS26NativeSearchTabBar.showSearch(),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Native tab bar is automatically enabled when entering this page and disabled when leaving.',
              style: TextStyle(
                fontSize: 13,
                color: _getSecondaryTextColor(context),
              ),
              textAlign: TextAlign.center,
            ),
          ] else ...[
            Center(child: CupertinoActivityIndicator()),
            const SizedBox(height: 12),
            Text(
              'Activating native tab bar...',
              style: TextStyle(
                fontSize: 13,
                color: _getSecondaryTextColor(context),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRootCauseCard() {
    return AdaptiveCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                PlatformInfo.isIOS
                    ? CupertinoIcons.bolt_fill
                    : Icons.architecture,
                color: PlatformInfo.isIOS
                    ? CupertinoColors.systemBlue
                    : Colors.blue,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Root Cause: Architectural Conflict',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _getTextColor(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'The fundamental issue stems from attempting to merge two incompatible architectural philosophies:',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _getTextColor(context),
            ),
          ),
          const SizedBox(height: 16),
          _buildArchitectureComparison(
            'Flutter Architecture',
            '• Single-threaded Dart runtime\n'
                '• Declarative UI framework (React-like)\n'
                '• Complete control over pixel rendering\n'
                '• Widget tree is the source of truth\n'
                '• Render pipeline: Widget → Element → RenderObject\n'
                '• Expects to own the entire screen canvas\n'
                '• Hot reload relies on widget tree reconstruction\n'
                '• State management tied to widget lifecycle',
            CupertinoColors.systemTeal,
            Colors.teal,
          ),
          const SizedBox(height: 16),
          _buildArchitectureComparison(
            'UIKit/iOS Architecture',
            '• Multi-threaded event-driven system\n'
                '• Imperative UI framework (ViewController-based)\n'
                '• Core Animation handles rendering\n'
                '• View hierarchy is the source of truth\n'
                '• Render pipeline: UIView → CALayer → GPU\n'
                '• View controllers manage sub-views\n'
                '• No hot reload - compile/run cycle required\n'
                '• State stored in ViewController properties',
            CupertinoColors.systemPurple,
            Colors.purple,
          ),
          const SizedBox(height: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'The Conflict:',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: _getTextColor(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'When we insert UITabBarController as the root, Flutter\'s engine still believes it owns the screen. '
                'The Flutter engine continues to render frames and manage widget lifecycles, but now it\'s actually rendering into a child UIView '
                'of the UITabBarController. This creates a parent-child relationship that neither framework was designed to handle.\n\n'
                'Imagine two conductors trying to lead the same orchestra simultaneously - one using hand signals (Flutter\'s declarative approach) '
                'and the other using a baton (UIKit\'s imperative approach). The musicians (UI components) receive conflicting instructions, '
                'leading to timing issues, missed cues, and overall chaos.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: _getSecondaryTextColor(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Why It Works At All:',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: _getTextColor(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Flutter\'s engine is surprisingly flexible. The FlutterViewController is essentially a UIViewController wrapper around the Flutter engine. '
                'By creating multiple FlutterViewControllers (one per tab), we can embed Flutter content in native containers. '
                'The search tab transformation works because UISearchController is a native component that doesn\'t interfere with Flutter\'s render pipeline.\n\n'
                'However, this flexibility was designed for embedding small Flutter modules in native apps (Add-to-App), '
                'not for putting native chrome around an entire Flutter app. We\'re using the API beyond its intended scope.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: _getSecondaryTextColor(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildArchitectureComparison(
    String title,
    String content,
    Color iosColor,
    Color androidColor,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: PlatformInfo.isIOS ? iosColor : androidColor,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          content,
          style: TextStyle(
            fontSize: 13,
            height: 1.5,
            color: _getSecondaryTextColor(context),
          ),
        ),
      ],
    );
  }

  Widget _buildTechnicalDetailsCard() {
    return AdaptiveCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                PlatformInfo.isIOS
                    ? CupertinoIcons.wrench_fill
                    : Icons.engineering,
                color: PlatformInfo.isIOS
                    ? CupertinoColors.systemRed
                    : Colors.red,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Why This Feature is Unstable',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _getTextColor(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'This feature bypasses Flutter\'s standard architecture in fundamental ways:',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _getTextColor(context),
            ),
          ),
          const SizedBox(height: 12),
          _buildTechnicalPoint(
            '1. Root View Controller Replacement',
            'The native implementation replaces Flutter\'s root UIViewController with a UITabBarController. This breaks Flutter\'s assumption that it owns the entire view hierarchy, causing widget lifecycle methods (initState, dispose) to behave unpredictably.',
          ),
          _buildTechnicalPoint(
            '2. Navigation Stack Invalidation',
            'Flutter maintains a navigation stack through Navigator 2.0. When we replace the root controller, all BuildContext references become invalid, and Navigator.pop() calls may fail or crash the app.',
          ),
          _buildTechnicalPoint(
            '3. State Management Conflicts',
            'Flutter\'s state management (Provider, Riverpod, Bloc) assumes widgets remain in the same render tree. Moving content between native UIViewControllers breaks this assumption, causing state to be lost or duplicated.',
          ),
          _buildTechnicalPoint(
            '4. Hot Reload Failure',
            'Hot reload works by rebuilding the widget tree from the root. Since the root is now a native UITabBarController, Flutter cannot properly inject updated code, requiring full app restarts.',
          ),
          _buildTechnicalPoint(
            '5. Platform Channel Race Conditions',
            'Communication between Flutter and native code happens asynchronously via MethodChannels. Tab switches and search queries can arrive out of order, causing UI state mismatches.',
          ),
          _buildTechnicalPoint(
            '6. Memory Management Issues',
            'Flutter\'s garbage collector cannot properly track native UIKit objects. The UITabBarController and embedded FlutterViewControllers may leak memory or be deallocated prematurely.',
          ),
          _buildTechnicalPoint(
            '7. Gesture Recognition Conflicts',
            'Native UIKit gestures (swipe-to-pop, tab bar touches) compete with Flutter\'s gesture detection system. This can cause missed taps, delayed responses, or gesture conflicts.',
          ),
          _buildTechnicalPoint(
            '8. Frame Synchronization',
            'Flutter renders at 60/120fps in its own render loop. Native UIKit animations run independently. Without proper synchronization, you may see visual stuttering or tearing during tab transitions.',
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: PlatformInfo.isIOS
                  ? CupertinoColors.systemRed.withValues(alpha: 0.1)
                  : Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: PlatformInfo.isIOS
                    ? CupertinoColors.systemRed.withValues(alpha: 0.3)
                    : Colors.red.withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              'Recommendation: This feature should only be used for prototyping and demos. For production apps, use Flutter\'s built-in TabBar widgets or implement search within the existing navigation structure.',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: PlatformInfo.isIOS
                    ? CupertinoColors.systemRed
                    : Colors.red,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTechnicalPoint(String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: _getTextColor(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: _getSecondaryTextColor(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResultsCard() {
    return AdaptiveCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Search Results',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: _getTextColor(context),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Query: "$_searchQuery"',
            style: TextStyle(fontSize: 15, color: _getTextColor(context)),
          ),
          const SizedBox(height: 8),
          Text(
            'Search results would appear here...',
            style: TextStyle(
              fontSize: 14,
              color: _getSecondaryTextColor(context),
            ),
          ),
        ],
      ),
    );
  }

  void _enableNativeTabBar() async {
    await IOS26NativeSearchTabBar.enable(
      tabs: [
        const NativeTabConfig(title: 'Home', sfSymbol: 'house.fill'),
        const NativeTabConfig(title: 'Explore', sfSymbol: 'safari'),
        const NativeTabConfig(
          title: 'Search',
          sfSymbol: 'magnifyingglass',
          isSearchTab: true,
        ),
        const NativeTabConfig(title: 'Profile', sfSymbol: 'person.fill'),
      ],
      selectedIndex: 0,
      onTabSelected: (index) {
        if (mounted) {
          setState(() {
            _currentTab = index;
          });
        }
      },
      onSearchQueryChanged: (query) {
        if (mounted) {
          setState(() {
            _searchQuery = query;
          });
        }
      },
      onSearchSubmitted: (query) {
        debugPrint('Search submitted: $query');
      },
      onSearchCancelled: () {
        if (mounted) {
          setState(() {
            _searchQuery = '';
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _isNativeEnabled = true;
      });
    }
  }

  Color _getTextColor(BuildContext context) {
    final isDark = PlatformInfo.isIOS
        ? MediaQuery.platformBrightnessOf(context) == Brightness.dark
        : Theme.of(context).brightness == Brightness.dark;

    return PlatformInfo.isIOS
        ? (isDark ? CupertinoColors.white : CupertinoColors.black)
        : Theme.of(context).colorScheme.onSurface;
  }

  Color _getSecondaryTextColor(BuildContext context) {
    final isDark = PlatformInfo.isIOS
        ? MediaQuery.platformBrightnessOf(context) == Brightness.dark
        : Theme.of(context).brightness == Brightness.dark;

    return PlatformInfo.isIOS
        ? (isDark ? CupertinoColors.systemGrey : CupertinoColors.systemGrey2)
        : Theme.of(context).colorScheme.onSurfaceVariant;
  }
}
