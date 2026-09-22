import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/utils/subtitle_item_visibility.dart';

void main() {
  testWidgets('reports whether a subtitle row is fully in the viewport',
      (tester) async {
    final controller = ScrollController();
    final keys = List.generate(10, (_) => GlobalKey());
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 300,
          child: ListView(
            controller: controller,
            children: [
              for (var index = 0; index < keys.length; index++)
                SizedBox(key: keys[index], height: 100),
            ],
          ),
        ),
      ),
    ));

    expect(isSubtitleItemFullyVisible(keys[0].currentContext!, controller),
        isTrue);
    expect(isSubtitleItemFullyVisible(keys[3].currentContext!, controller),
        isFalse);

    controller.jumpTo(250);
    await tester.pump();
    expect(isSubtitleItemFullyVisible(keys[0].currentContext!, controller),
        isFalse);
    expect(isSubtitleItemFullyVisible(keys[2].currentContext!, controller),
        isFalse);
    expect(isSubtitleItemFullyVisible(keys[3].currentContext!, controller),
        isTrue);
  });
}
