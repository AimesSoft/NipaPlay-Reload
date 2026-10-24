import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/ui/widgets/nipa_avatar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Nipa loads a square 256 px avatar asset directly',
      (tester) async {
    final data = await rootBundle.load(NipaFaceImage.asset);
    final buffer =
        await ui.ImmutableBuffer.fromUint8List(data.buffer.asUint8List());
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    expect(descriptor.width, NipaFaceImage.size);
    expect(descriptor.height, NipaFaceImage.size);
    descriptor.dispose();
    buffer.dispose();

    final info = await tester.runAsync(() async {
      final loaded = Completer<ImageInfo>();
      const NipaFaceImage()
          .resolve(ImageConfiguration.empty)
          .addListener(ImageStreamListener((info, _) {
            if (!loaded.isCompleted) loaded.complete(info);
          }, onError: (Object error, StackTrace? stack) {
            if (!loaded.isCompleted) loaded.completeError(error, stack);
          }));
      return loaded.future.timeout(const Duration(seconds: 5));
    });
    expect(info, isNotNull);
    expect(info!.image.width, NipaFaceImage.size);
    expect(info.image.height, NipaFaceImage.size);
    info.dispose();
  });
}
