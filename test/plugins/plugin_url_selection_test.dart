import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/plugins/url_resolver.dart';
import 'package:nipaplay/themes/nipaplay/widgets/plugin_url_selection_content.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('selection scrolls to the preferred item in ${brightness.name}',
        (tester) async {
      String? selected;
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                      onPressed: () async {
                        selected = await showDialog<String>(
                          context: context,
                          builder: (_) => Dialog(
                              child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: PluginUrlSelectionContent(
                              title: 'Example collection',
                              preferredId: '50',
                              items: List.generate(
                                  100,
                                  (i) => PluginUrlChoice({
                                        'id': '$i',
                                        'title': 'P${i + 1} Episode ${i + 1}',
                                      })),
                            ),
                          )),
                        );
                      },
                      child: const Text('Open'),
                    ))),
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('P51 Episode 51'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('P51 Episode 51'));
      await tester.pumpAndSettle();
      expect(selected, '50');
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(selected, isNull);
    });
  }
  testWidgets('selection works inside a Cupertino presentation',
      (tester) async {
    await tester.pumpWidget(CupertinoApp(
      home: CupertinoPageScaffold(
          child: Center(
              child: PluginUrlSelectionContent(
        title: 'Collection',
        items: [
          PluginUrlChoice({'id': 'one', 'title': 'First item'})
        ],
      ))),
    ));
    await tester.pumpAndSettle();
    expect(find.text('First item'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
