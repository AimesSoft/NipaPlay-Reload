import 'dart:io';
import 'package:flutter/services.dart' show rootBundle, AssetManifest, ByteData;
import 'package:path/path.dart' as p;

class AssetHelper {
  static Future<void> extractWebAssets(String targetDirectory) async {
    try {
      // Use Flutter's AssetManifest API to be compatible with both
      // AssetManifest.json (legacy) and AssetManifest.bin (current).
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final manifestKeys = manifest.listAssets();

      // Find all assets that are part of the web build.
      final webAssetPaths = manifestKeys
          .where((String key) => key.startsWith('assets/web/'))
          .toList();

      if (webAssetPaths.isEmpty) {
        print(
          'AssetHelper: CRITICAL - No assets found under "assets/web/" in the asset manifest.',
        );
        return;
      }
      
      print(
        'AssetHelper: Extracting ${webAssetPaths.length} web assets to $targetDirectory',
      );

      for (final String assetPath in webAssetPaths) {
        // The assetPath is the full, correct path for rootBundle.load().
        
        // Determine the destination path by removing the 'assets/web/' prefix.
        final relativePath = p.relative(assetPath, from: 'assets/web');
        
        // Skip the directory entry itself and other special files like .DS_Store
        if (relativePath == '.' || relativePath.isEmpty || p.basename(relativePath).startsWith('.')) {
          continue;
        }

        final destinationFile = File(p.join(targetDirectory, relativePath));

        try {
          await destinationFile.parent.create(recursive: true);
          final ByteData assetData = await rootBundle.load(assetPath);
          await destinationFile.writeAsBytes(assetData.buffer.asUint8List(), flush: true);
        } catch (e) {
          print('AssetHelper: FAILED to extract asset [$assetPath]. Error: $e');
        }
      }
      print('AssetHelper: Web asset extraction process complete.');
    } catch (e) {
      print('AssetHelper: CRITICAL FAILURE: Could not load the asset manifest. Error: $e');
    }
  }
}
