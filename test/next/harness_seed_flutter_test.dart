import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/body/next_body.dart';
import 'package:nipaplay/next/harness_seed_flutter.dart';

class _Bundle extends CachingAssetBundle {
  final loaded = <String>[];
  @override
  Future<ByteData> load(String key) async {
    loaded.add(key);
    if (key == 'AssetManifest.bin') {
      return const StandardMessageCodec().encodeMessage({
        'assets/next/harness/.codex/config.toml': <Object?>[],
        'assets/next/knowledge/catalog.json': <Object?>[],
      })!;
    }
    if (key == 'assets/next/harness/.codex/config.toml') {
      return ByteData.sublistView(Uint8List.fromList([1, 2, 3]));
    }
    throw StateError('Unexpected asset: $key');
  }
}

void main() {
  tearDown(() => NextBody.debugBodyOnly = null);

  test('a mobile body starts without loading any desktop Agent assets', () async {
    NextBody.debugBodyOnly = true;
    final bundle = _Bundle();
    expect(await bundledHarnessSeed(bundle: bundle), isEmpty);
    expect(bundle.loaded, isEmpty);
  });

  test('desktop still loads the Agent seed, excluding unrelated assets', () async {
    NextBody.debugBodyOnly = false;
    final bundle = _Bundle();
    expect(await bundledHarnessSeed(bundle: bundle), {
      '.codex/config.toml': [1, 2, 3],
    });
    expect(bundle.loaded, [
      'AssetManifest.bin',
      'assets/next/harness/.codex/config.toml',
    ]);
  });
}
