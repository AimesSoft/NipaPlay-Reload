import 'package:path/path.dart' as p;

/// Returns the decoded final path segment from a local path or media URI.
String mediaPathName(String path) {
  final uri = Uri.tryParse(path);
  if (uri != null && uri.pathSegments.isNotEmpty) {
    return uri.pathSegments.last;
  }
  return p.basename(path);
}
