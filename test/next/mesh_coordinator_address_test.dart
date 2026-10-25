import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/mesh/coordinator.dart';
import 'package:nipaplay/next/mesh/trust.dart';

void main() {
  test('the built-in address and an origin both reach /mesh/v1 exactly once',
      () {
    for (final base in [
      meshDefaultCoordinator,
      '$meshDefaultCoordinator/',
      'https://nipaplay.aimes-soft.com',
    ]) {
      expect(
          meshEndpoint(Uri.parse(base), '/mesh/v1/devices/register').toString(),
          'https://nipaplay.aimes-soft.com/mesh/v1/devices/register',
          reason: base);
    }
    expect(
        meshEndpoint(Uri.parse('http://127.0.0.1:18082'), '/mesh/v1/devices')
            .toString(),
        'http://127.0.0.1:18082/mesh/v1/devices');
  });

  test('another prefix is kept in front of the API path', () {
    expect(
        meshEndpoint(Uri.parse('https://host/hub'), '/mesh/v1/addresses')
            .toString(),
        'https://host/hub/mesh/v1/addresses');
    expect(
        meshEndpoint(Uri.parse('https://host/hub/mesh'), '/mesh/v1/addresses')
            .toString(),
        'https://host/hub/mesh/v1/addresses');
    expect(
        meshEndpoint(Uri.parse('https://host/mesh-extra'), '/mesh/v1/x')
            .toString(),
        'https://host/mesh-extra/mesh/v1/x');
  });
}
