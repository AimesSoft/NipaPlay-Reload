import 'package:http/http.dart' as http;

class GithubAccelResolver {
  static const List<String> defaultSources = <String>[
    'https://gh-proxy.com/',
    'https://ghfast.top/',
    'https://ghproxy.net/',
  ];

  static Future<String?> resolveFirstReachable(String rawUrl) async {
    for (final source in defaultSources) {
      try {
        final normalized = source.endsWith('/') ? source : '${source}/';
        final url = '${normalized}$rawUrl';
        final response = await http.head(Uri.parse(url)).timeout(const Duration(seconds: 5));
        if (response.statusCode == 200) return url;
      } catch (_) {}
    }
    return null;
  }
}
