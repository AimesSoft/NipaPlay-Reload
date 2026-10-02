import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nipaplay/pages/media_server_detail_page.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/services/large_screen_ui_sfx_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/android_tv_remote_key_scope.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_focusable_action.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_home_page.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_mode_scope.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  var fixture = _DetailFixture();
  TestWidgetsFlutterBinding.ensureInitialized();

  void testDetailWidgets(String description, WidgetTesterCallback body) {
    testWidgets(
        description,
        (tester) => http.runWithClient(
              () async {
                final previousPlatform = debugDefaultTargetPlatformOverride;
                debugDefaultTargetPlatformOverride = TargetPlatform.android;
                try {
                  await body(tester);
                } finally {
                  debugDefaultTargetPlatformOverride = previousPlatform;
                }
              },
              () => MockClient(fixture.handleRequest),
            ));
  }

  setUp(() {
    fixture = _DetailFixture();
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'NipaPlay',
      packageName: 'nipaplay',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    JellyfinService.instance
      ..serverUrl = 'http://jellyfin.test'
      ..accessToken = 'test-token'
      ..userId = 'user'
      ..currentProfile = null
      ..isConnected = true;
  });

  tearDown(() {
    JellyfinService.instance
      ..serverUrl = null
      ..accessToken = null
      ..userId = null
      ..isConnected = false;
  });

  testDetailWidgets('root detail route retains the home-only large-screen mode',
      (tester) async {
    await _openDetail(tester);
    await _waitForSeason(tester, fixture, 's1');
    fixture.completeSeason('s1');
    await tester.pumpAndSettle();
    expect(
      NipaplayLargeScreenModeScope.isActiveOf(
        tester.element(find.byType(MediaServerDetailPage)),
      ),
      isTrue,
    );
    expect(
      DefaultTextStyle.of(tester.element(find.text('1. Episode s1-1')))
          .style
          .decoration,
      isNot(TextDecoration.underline),
    );
  });

  testDetailWidgets(
      'fast episode loading keeps focus after the route transition',
      (tester) async {
    fixture.completeImmediately = true;
    await _openDetail(tester);
    await tester.pumpAndSettle();
    expect(_focusOf(tester, '1. Episode s1-1').hasPrimaryFocus, isTrue);
  });

  testDetailWidgets(
      'loaded episodes receive focus and back restores the media card',
      (tester) async {
    final originalFocus = await _openDetail(tester);
    await _waitForSeason(tester, fixture, 's1');
    fixture.completeSeason('s1');
    await tester.pumpAndSettle();

    expect(_focusOf(tester, '1. Episode s1-1').hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(_focusOf(tester, '2. Episode s1-2').hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(_focusOf(tester, '1. Episode s1-1').hasPrimaryFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.goBack,
        physicalKey: PhysicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(MediaServerDetailPage), findsNothing);
    expect(originalFocus.hasPrimaryFocus, isTrue);
  });

  testDetailWidgets('new and cached seasons focus their first episode',
      (tester) async {
    await _openDetail(tester);
    await _waitForSeason(tester, fixture, 's1');
    fixture.completeSeason('s1');
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    if (_focusOf(tester, 'Season 2').hasPrimaryFocus) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
    }
    expect(_focusOf(tester, 'Season 1').hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await _waitForSeason(tester, fixture, 's2');
    expect(_focusOf(tester, 'Season 2').hasPrimaryFocus, isTrue);
    fixture.completeSeason('s2');
    await tester.pumpAndSettle();
    expect(_focusOf(tester, '1. Episode s2-1').hasPrimaryFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(_focusOf(tester, '1. Episode s1-1').hasPrimaryFocus, isTrue);
    expect(fixture.requestedSeasons.where((id) => id == 's1'), hasLength(1));
  });

  testDetailWidgets('empty episode lists leave focus on the selected season',
      (tester) async {
    await _openDetail(tester);
    await _waitForSeason(tester, fixture, 's1');
    fixture.completeSeason('s1', count: 0);
    await tester.pumpAndSettle();
    expect(_focusOf(tester, 'Season 1').hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(_focusOf(tester, 'Season 2').hasPrimaryFocus, isTrue);
  });

  testDetailWidgets(
      'episode errors focus retry and retry focuses loaded episodes',
      (tester) async {
    await _openDetail(tester);
    await _waitForSeason(tester, fixture, 's1');
    fixture.completeSeason('s1', statusCode: 500);
    await tester.pumpAndSettle();
    expect(_focusOf(tester, '重试').hasPrimaryFocus, isTrue);

    fixture.resetSeason('s1');
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await _waitForSeason(tester, fixture, 's1', count: 2);
    fixture.completeSeason('s1');
    await tester.pumpAndSettle();
    expect(_focusOf(tester, '1. Episode s1-1').hasPrimaryFocus, isTrue);
  });

  testDetailWidgets('an older season response does not move the current focus',
      (tester) async {
    await _openDetail(tester);
    await _waitForSeason(tester, fixture, 's1');
    _focusOf(tester, 'Season 2').requestFocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await _waitForSeason(tester, fixture, 's2');
    fixture.completeSeason('s2');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    final currentFocus = _focusOf(tester, '2. Episode s2-2');
    expect(currentFocus.hasPrimaryFocus, isTrue);

    fixture.completeSeason('s1');
    await tester.pumpAndSettle();
    expect(currentFocus.hasPrimaryFocus, isTrue);
  });

  testDetailWidgets('loaded episodes do not steal focus from a covering dialog',
      (tester) async {
    await _openDetail(tester);
    await _waitForSeason(tester, fixture, 's1');
    unawaited(showDialog<void>(
      context: tester.element(find.byType(MediaServerDetailPage)),
      builder: (_) => AlertDialog(
        content: TextButton(
          autofocus: true,
          onPressed: () {},
          child: const Text('Dialog action'),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(_focusOf(tester, 'Dialog action').hasPrimaryFocus, isTrue);

    fixture.completeSeason('s1');
    await tester.pumpAndSettle();
    expect(_focusOf(tester, 'Dialog action').hasPrimaryFocus, isTrue);
  });

  testDetailWidgets('movie details focus the play action', (tester) async {
    fixture.type = 'Movie';
    await _openDetail(tester);
    await tester.pumpAndSettle();
    expect(_focusOf(tester, '播放', first: true).hasPrimaryFocus, isTrue);
  });
}

FocusNode _focusOf(WidgetTester tester, String label, {bool first = false}) {
  final finder = find.text(label);
  return Focus.of(tester.element(first ? finder.first : finder));
}

Future<FocusNode> _openDetail(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final originalFocus = FocusNode(debugLabel: 'original-media-card');
  addTearDown(originalFocus.dispose);
  final navigatorKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppearanceSettingsProvider()),
        ChangeNotifierProvider(create: (_) => LargeScreenUiSfxService()),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        theme: ThemeData.dark(),
        builder: (_, child) => NipaplayAndroidTvRemoteKeyScope(
          navigatorKey: navigatorKey,
          child: child!,
        ),
        home: NipaplayLargeScreenModeScope(
          isActive: true,
          child: Builder(
            builder: (context) => NipaplayLargeScreenContentPage(
              child: Center(
                child: NipaplayLargeScreenFocusableAction(
                  focusNode: originalFocus,
                  autofocus: true,
                  onActivate: () {
                    unawaited(
                        MediaServerDetailPage.showJellyfin(context, 'media'));
                  },
                  child: const Text('Media card'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.sendKeyEvent(LogicalKeyboardKey.select);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return originalFocus;
}

Future<void> _waitForSeason(
    WidgetTester tester, _DetailFixture fixture, String id,
    {int count = 1}) async {
  for (var frame = 0; frame < 20; frame++) {
    await tester.pump();
    if (fixture.requestedSeasons.where((season) => season == id).length >=
        count) {
      return;
    }
  }
  fail('Season $id was not requested $count times');
}

class _DetailFixture {
  String type = 'Series';
  bool completeImmediately = false;
  final requestedSeasons = <String>[];
  final _episodes = <String, Completer<http.Response>>{};

  Future<http.Response> handleRequest(http.Request request) async {
    final path = request.url.path;
    if (path == '/Users/user/Items/media') {
      return _json({'Id': 'media', 'Name': 'Test media', 'Type': type});
    }
    if (path == '/Shows/media/Seasons') {
      return _json({
        'Items': [
          {'Id': 's1', 'Name': 'Season 1', 'IndexNumber': 1},
          {'Id': 's2', 'Name': 'Season 2', 'IndexNumber': 2},
        ],
      });
    }
    if (path == '/Shows/media/Episodes') {
      final id = request.url.queryParameters['seasonId']!;
      requestedSeasons.add(id);
      final result = _episodes.putIfAbsent(id, Completer<http.Response>.new);
      if (completeImmediately) completeSeason(id);
      return result.future;
    }
    return _json({}, statusCode: 404);
  }

  void resetSeason(String id) => _episodes.remove(id);

  void completeSeason(String id, {int count = 2, int statusCode = 200}) {
    _episodes[id]!.complete(_json({
      'Items': List.generate(
        count,
        (index) => {
          'Id': '$id-${index + 1}',
          'Name': 'Episode $id-${index + 1}',
          'IndexNumber': index + 1,
        },
      ),
    }, statusCode: statusCode));
  }

  http.Response _json(Object data, {int statusCode = 200}) => http.Response(
        jsonEncode(data),
        statusCode,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
}
