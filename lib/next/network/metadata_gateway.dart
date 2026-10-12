import 'package:http/http.dart' as http;

abstract interface class MetadataGateway {
  http.Client get client;
  Future<Uri> resolve(Uri endpoint);
}
