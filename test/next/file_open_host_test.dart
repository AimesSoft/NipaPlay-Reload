import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/ui/shell/file_open_host.dart';

void main() {
  testWidgets('Next owns file and error events only while mounted',
      (tester) async {
    final files = StreamController<String>.broadcast();
    final errors = StreamController<String>.broadcast();
    final opened = <String>[];
    await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: NextFileOpenHost(
          launchFilePath: '/cold.mkv',
          openFile: (path) async {
            opened.add(path);
          },
          fileEvents: files.stream,
          errorEvents: errors.stream,
          child: const SizedBox.expand(),
        )));
    await tester.pump();
    expect(opened, ['/cold.mkv']);
    expect(files.hasListener, isTrue);
    expect(errors.hasListener, isTrue);
    files.add('/associated.mkv');
    errors.add('导入失败');
    await tester.pump();
    await tester.pump();
    expect(opened, ['/cold.mkv', '/associated.mkv']);
    expect(find.text('导入失败'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(files.hasListener, isFalse);
    expect(errors.hasListener, isFalse);
    files.add('/after-dispose.mkv');
    await tester.pump();
    expect(opened, hasLength(2));
    await files.close();
    await errors.close();
  });
}
