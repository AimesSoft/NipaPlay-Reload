import 'package:flutter/services.dart';

import 'body/next_body.dart';

/// Mobile bodies have no local Agent and do not bundle its executable seed.
/// Some Flutter forks still list platform-excluded assets in the manifest;
/// do not attempt to load them while initializing the player and Mesh.
Future<Map<String, List<int>>> bundledHarnessSeed({AssetBundle? bundle}) async {
  if (NextBody.bodyOnly) return {};
  final assets = bundle ?? rootBundle;
  final manifest = await AssetManifest.loadFromAssetBundle(assets);
  const prefix = 'assets/next/harness/';
  final seed = <String, List<int>>{};
  for (final asset
      in manifest.listAssets().where((path) => path.startsWith(prefix))) {
    final data = await assets.load(asset);
    seed[asset.substring(prefix.length)] =
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }
  return seed;
}
