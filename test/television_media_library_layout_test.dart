import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/app/app_page_ids.dart';
import 'package:nipaplay/app/unified_media_library_sections.dart';
import 'package:nipaplay/media_library/adaptive_media_library_controls.dart';
import 'package:nipaplay/media_library/television_media_library_layout.dart';
import 'package:nipaplay/providers/shared_remote_library_provider.dart';
import 'package:nipaplay/services/large_screen_ui_sfx_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/shared_remote_library_view.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _shared = UnifiedMediaLibrarySection(
  id: MediaLibrarySectionIds.shared,
  label: '共享媒体库',
  phoneSymbol: 'rectangle.stack',
  contentType: UnifiedMediaLibraryContentType.sharedCollection,
);
const _management = UnifiedMediaLibrarySection(
  id: MediaLibrarySectionIds.sharedManagement,
  label: '共享库管理',
  phoneSymbol: 'folder',
  contentType: UnifiedMediaLibraryContentType.sharedManagement,
);

Widget _app(Widget child, {double textScale = 1, VoidCallback? onAdd}) {
  return ChangeNotifierProvider(
    create: (_) => LargeScreenUiSfxService(),
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
            ),
            child: AppDisplaySurfaceScope(
              surface: AppDisplaySurface.television,
              child: AdaptiveMediaLibraryScaffold(
                sections: const [_shared, _management],
                selectedSection: _shared,
                onSectionSelected: (_) {},
                onSectionOrderChanged: (_) {},
                onRemoteAccess: () {},
                onAddMedia: onAdd ?? () {},
                child: child,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Rect _paintedRect(WidgetTester tester, Finder finder) {
  final box = tester.renderObject<RenderBox>(finder);
  return MatrixUtils.transformRect(
      box.getTransformTo(null), Offset.zero & box.size);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final size in [
    const Size(1920, 1080),
    const Size(1280, 720),
    const Size(960, 540),
    const Size(640, 360),
  ]) {
    for (final textScale in [1.0, 2.0]) {
      testWidgets('shared TV controls fit one third at $size / $textScale',
          (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pumpWidget(
          ChangeNotifierProvider<SharedRemoteLibraryProvider>(
            create: (_) => _LoadingSharedProvider(),
            child: _app(const SharedRemoteLibraryView(), textScale: textScale),
          ),
        );
        await tester.pump();
        final header = find.byKey(
          const ValueKey('television-media-library-controls'),
        );
        final rect = _paintedRect(tester, header);
        expect(rect.height, lessThanOrEqualTo(size.height / 3));
        expect(find.text('媒体库'), findsOneWidget);
        for (final label in [
          '调整顺序',
          '远程访问',
          '添加媒体',
          '最近观看',
          '名称',
          '评分',
          '只看未观看'
        ]) {
          final control = _paintedRect(tester, find.text(label));
          expect(control.top, greaterThanOrEqualTo(rect.top - 1));
          expect(control.bottom, lessThanOrEqualTo(rect.bottom + 1));
          expect(control.right, lessThanOrEqualTo(rect.right + 1));
        }
        final search = _paintedRect(tester, find.byType(TextField));
        final client = _paintedRect(tester, find.text('客户端'));
        expect(client.right, greaterThan(rect.right - rect.width * .1));
        expect(search.width, greaterThan(0));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets(
      'resizing and dynamic notices preserve media size and header input',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final notice = ValueNotifier(false);
    final search = TextEditingController();
    final focus = FocusNode();
    addTearDown(notice.dispose);
    addTearDown(search.dispose);
    addTearDown(focus.dispose);
    var pressed = 0;
    await tester.pumpWidget(_app(
      ValueListenableBuilder<bool>(
        valueListenable: notice,
        builder: (context, showNotice, _) => MediaLibraryBody(
          controls: [
            Row(children: [
              Expanded(child: TextField(controller: search, focusNode: focus)),
              TextButton(onPressed: () => pressed++, child: const Text('刷新测试')),
            ]),
            if (showNotice) const SizedBox(height: 200, child: Text('扫描进度')),
            const SizedBox(height: 18),
          ],
          child: const Align(
            alignment: Alignment.topLeft,
            child:
                SizedBox(key: ValueKey('media-card'), width: 180, height: 120),
          ),
        ),
      ),
      onAdd: () => pressed++,
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加媒体'));
    await tester.tap(find.text('刷新测试'));
    expect(pressed, 2);
    await tester.enterText(find.byType(TextField), '搜索测试');
    notice.value = true;
    tester.view.physicalSize = const Size(960, 360);
    await tester.pumpAndSettle();
    expect(search.text, '搜索测试');
    expect(focus.hasFocus, isTrue);
    final header = _paintedRect(tester,
        find.byKey(const ValueKey('television-media-library-controls')));
    expect(header.height, lessThanOrEqualTo(120));
    expect(_paintedRect(tester, find.byKey(const ValueKey('media-card'))).size,
        const Size(180, 120));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.tap(find.text('刷新测试'));
    expect(pressed, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('source selector keeps remote focus across keyed media views',
      (tester) async {
    final selected = ValueNotifier(_shared);
    addTearDown(selected.dispose);
    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => LargeScreenUiSfxService(),
      child: MaterialApp(
        home: Scaffold(
          body: AppDisplaySurfaceScope(
            surface: AppDisplaySurface.television,
            child: ValueListenableBuilder<UnifiedMediaLibrarySection>(
              valueListenable: selected,
              builder: (context, section, _) => AdaptiveMediaLibraryScaffold(
                sections: const [_shared, _management],
                selectedSection: section,
                onSectionSelected: (id) =>
                    selected.value = id == _shared.id ? _shared : _management,
                onSectionOrderChanged: (_) {},
                onRemoteAccess: () {},
                onAddMedia: () {},
                child: MediaLibraryBody(
                  key: ValueKey(section.id),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final sourceFocus = tester
        .widget<Focus>(find.byWidgetPredicate((widget) =>
            widget is Focus &&
            widget.focusNode?.debugLabel == 'media-library-section-bar'))
        .focusNode!;
    sourceFocus.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(selected.value, _management);
    expect(sourceFocus.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(selected.value, _shared);
    expect(sourceFocus.hasFocus, isTrue);
    expect(find.text('媒体库'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('body without a TV header keeps its original control size',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: MediaLibraryBody(
        controls: [SizedBox(key: ValueKey('desktop-controls'), height: 260)],
        child: SizedBox.expand(),
      ),
    ));
    expect(
        tester.getSize(find.byKey(const ValueKey('desktop-controls'))).height,
        260);
    expect(find.byKey(const ValueKey('television-media-library-controls')),
        findsNothing);
  });
}

class _LoadingSharedProvider extends SharedRemoteLibraryProvider {
  @override
  bool get isInitializing => true;
}
