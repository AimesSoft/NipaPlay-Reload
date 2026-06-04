import 'package:flutter/foundation.dart';

import 'build_target_label_common.dart';

String getBuildTargetLabel() {
  return buildTargetLabelFromParts(
    architecture: '',
    platform: kIsWeb ? 'web' : defaultTargetPlatform.name,
  );
}
