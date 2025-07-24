import 'dart:io';
import 'package:flutter/services.dart' show rootBundle, ByteData;
import 'package:path/path.dart' as p;
import 'dart:convert';

class AssetHelper {
  static Future<void> extractWebAssets(String targetDirectory) async {
    try {
      // Use the main app's asset manifest as the source of truth.
      final manifestContent = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifestMap = json.decode(manifestContent);

      // --- DIAGNOSTIC: Print all keys in the manifest ---
      print('AssetHelper: --- Begin AssetManifest.json Keys ---');
      manifestMap.keys.forEach((key) => print(key));
      print('AssetHelper: --- End AssetManifest.json Keys ---');
      // ----------------------------------------------------

      // Find all assets that are part of the web build.
      final webAssetPaths = manifestMap.keys
          .where((String key) => key.startsWith('assets/web/'))
          .toList();

      if (webAssetPaths.isEmpty) {
        print('AssetHelper: CRITICAL - No assets found under "assets/web/" in the main AssetManifest.json.');
        return;
      }
      
      print('AssetHelper: Found ${webAssetPaths.length} web assets in the main manifest to process.');

      for (final String assetPath in webAssetPaths) {
        // The assetPath is the full, correct path for rootBundle.load().
        
        // Determine the destination path by removing the 'assets/web/' prefix.
        final relativePath = p.relative(assetPath, from: 'assets/web');
        
        // Skip the directory entry itself and other special files like .DS_Store
        if (relativePath == '.' || relativePath.isEmpty || p.basename(relativePath).startsWith('.')) {
          print('AssetHelper: Skipping special/hidden file: $assetPath');
          continue;
        }

        final destinationFile = File(p.join(targetDirectory, relativePath));

        try {
          print('AssetHelper: Extracting [${assetPath}] to [${destinationFile.path}]');
          await destinationFile.parent.create(recursive: true);
          final ByteData assetData = await rootBundle.load(assetPath);
          await destinationFile.writeAsBytes(assetData.buffer.asUint8List(), flush: true);
        } catch (e) {
          print('AssetHelper: FAILED to extract asset [${assetPath}]. Error: $e');
        }
      }
      print('AssetHelper: Web asset extraction process complete.');
    } catch (e) {
      print('AssetHelper: CRITICAL FAILURE: Could not load the main AssetManifest.json. Error: $e');
    }
  }
}
