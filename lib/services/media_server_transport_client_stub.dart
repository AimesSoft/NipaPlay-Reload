import 'package:http/http.dart' as http;

const bool supportsCustomUserAgentHeader = false;

http.Client createMediaServerClient() => http.Client();
