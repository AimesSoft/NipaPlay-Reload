import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show DefaultTabController, MaterialApp;
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/themes/nipaplay/widgets/nipaplay_main_tab_bar.dart';

void main() {
  testWidgets('builds inside a Cupertino page without a Material ancestor',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CupertinoPageScaffold(
          child: DefaultTabController(
            length: 2,
            child: Builder(
              builder: (context) {
                return NipaplayMainTabBar(
                  controller: DefaultTabController.of(context),
                  showLeadingLogoOnMobile: false,
                  tabs: const [
                    Text('详情'),
                    Text('评论'),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
