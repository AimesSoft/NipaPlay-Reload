import 'package:http/http.dart' as http;

const bool supportsCustomUserAgentHeader = true;

http.Client createMediaServerClient() => http.Client();
