import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/mesh/trust.dart';

// Public certificates only, made with `nipaplay-mesh-coordinator --generate-ca`
// (valid for ten years from 2026-10-25) and one device certificate it signed.
const _primary = '''-----BEGIN CERTIFICATE-----
MIIBgTCCATOgAwIBAgIQfU0lFoTyKqIjnzrDKDDdgDAFBgMrZXAwPzElMCMGA1UE
AwwcTmlwYVBsYXkgTWVzaCBDb29yZGluYXRvciBDQTEWMBQGA1UECgwNTmlwYVBs
YXkgTWVzaDAeFw0yNjEwMjUwODQzNDJaFw0zNjEwMjIwODQ4NDJaMD8xJTAjBgNV
BAMMHE5pcGFQbGF5IE1lc2ggQ29vcmRpbmF0b3IgQ0ExFjAUBgNVBAoMDU5pcGFQ
bGF5IE1lc2gwKjAFBgMrZXADIQAKSQCXLASIlVjVox1bVDcTaDPdioklWR4qjV9Y
J4vN3aNFMEMwDgYDVR0PAQH/BAQDAgGGMB0GA1UdDgQWBBR+V4kdX1rvkaDIkySo
Ge9IVddaUTASBgNVHRMBAf8ECDAGAQH/AgEAMAUGAytlcANBAITueWE0kpb9wp2X
ASvZVYW6+4na+EmVhxzp0O5igeO9/k3EozxVXldwo4PoTRBMEeWUbdCo/4A54393
+VMgrQ0=
-----END CERTIFICATE-----
''';
const _standby = '''-----BEGIN CERTIFICATE-----
MIIBgTCCATOgAwIBAgIQWO1Ebh/GB9tD8BRfpsOd8jAFBgMrZXAwPzElMCMGA1UE
AwwcTmlwYVBsYXkgTWVzaCBDb29yZGluYXRvciBDQTEWMBQGA1UECgwNTmlwYVBs
YXkgTWVzaDAeFw0yNjEwMjUwODQzNDJaFw0zNjEwMjIwODQ4NDJaMD8xJTAjBgNV
BAMMHE5pcGFQbGF5IE1lc2ggQ29vcmRpbmF0b3IgQ0ExFjAUBgNVBAoMDU5pcGFQ
bGF5IE1lc2gwKjAFBgMrZXADIQAukQAvl8CHKA8B3Yc3r+lVSvX5ch5EaC3BNtvz
7gQ2K6NFMEMwDgYDVR0PAQH/BAQDAgGGMB0GA1UdDgQWBBSZi2pI/BsI/UP9oR/7
VhLinKXAEjASBgNVHRMBAf8ECDAGAQH/AgEAMAUGAytlcANBABYnz0gA2rQCPKi/
i37GymkaSpIw6fc/VqjNEObVHpxr6i/ZYpj0SuCDRdaP0r1EzRsne6lDcfFLymt3
dfiPWwQ=
-----END CERTIFICATE-----
''';
const _device = '''-----BEGIN CERTIFICATE-----
MIICmDCCAkqgAwIBAgIQHFshfZHeuG3wLwOV9xHxYTAFBgMrZXAwPzElMCMGA1UE
AwwcTmlwYVBsYXkgTWVzaCBDb29yZGluYXRvciBDQTEWMBQGA1UECgwNTmlwYVBs
YXkgTWVzaDAeFw0yNjEwMjUwODQzNDNaFw0yNjExMDEwODQ4NDNaMFUxOzA5BgNV
BAMMMmRldmljZS1KWkV0ZGdpdFM0YjZNd25qVGVOdlZaTkxOMWp0OEMzbW92Nnpm
SktaVTcwMRYwFAYDVQQKDA1OaXBhUGxheSBNZXNoMCowBQYDK2VwAyEAU+eBrrdJ
bQVchby2KEfGAkcd1ySvLbNUodj+SAKhE2SjggFEMIIBQDAfBgNVHSMEGDAWgBSy
zpFh7kmpyYtwhSMn5ORYWL0o4zCBwAYDVR0RBIG4MIG1hlhuaXBhcGxheS1tZXNo
Oi8vZGV2aWNlP2FjY291bnQ9NDI0MjQyJmRldmljZT1KWkV0ZGdpdFM0YjZNd25q
VGVOdlZaTkxOMWp0OEMzbW92NnpmSktaVTcwgllkLTI1OTEyZDc2MDhhZDRiODZm
YTMzMDllMzRkZTM2ZjU1LjkzNGIzNzU4ZWRmMDJkZTZhMmZlYjM3YzkyOTk1M2Jk
Lm1lc2gubmlwYXBsYXkuaW52YWxpZDAOBgNVHQ8BAf8EBAMCB4AwHQYDVR0lBBYw
FAYIKwYBBQUHAwIGCCsGAQUFBwMBMB0GA1UdDgQWBBTDQcoJyamw0vPdBlA3jSJ3
UaEU5jAMBgNVHRMBAf8EAjAAMAUGAytlcANBAKfZV+/2m4BHPjZp8JKiyLKemws9
F6Z6HPktZqsD1/jKIci1rUIrIZi70YCoMtgR/jbQHZG5/QSfPxRYdldCcA4=
-----END CERTIFICATE-----
''';

void main() {
  final now = DateTime.utc(2026, 11, 1);

  test('a primary and a standby root are a shippable bundle', () {
    final report = inspectMeshTrust('$_primary$_standby', now: now);
    expect(report.problems, isEmpty);
    expect(report.roots, hasLength(2));
    expect(report.roots[0], isNot(report.roots[1]));
  });

  test('an empty bundle, one root, or the same root twice is refused', () {
    expect(inspectMeshTrust('', now: now).ok, false);
    expect(
        inspectMeshTrust('  \n', now: now).problems.single, contains('empty'));
    expect(inspectMeshTrust(_primary, now: now).problems.single,
        contains('2 different roots'));
    final twice = inspectMeshTrust('$_primary$_primary', now: now);
    expect(twice.ok, false);
    expect(twice.problems.join(), contains('repeats'));
  });

  test(
      'a certificate that is not a CA, text that is not a certificate, or a mangled block is refused',
      () {
    final leaf = inspectMeshTrust('$_primary$_device', now: now);
    expect(leaf.problems.join(), contains('not a CA'));
    expect(
        inspectMeshTrust('$_primary$_standby\nnot a certificate', now: now).ok,
        false);
    final lines = _standby.trim().split('\n');
    final mangled = [
      lines.first,
      base64.encode(utf8.encode('garbage')),
      lines.last
    ].join('\n');
    expect(inspectMeshTrust('$_primary$mangled', now: now).ok, false);
  });

  test('an expired root is refused', () {
    final report =
        inspectMeshTrust('$_primary$_standby', now: DateTime.utc(2037, 1, 1));
    expect(report.problems.join(), contains('expired'));
  });

  test('the default coordinator is the production address with its path prefix',
      () {
    expect(meshDefaultCoordinator, 'https://nipaplay.aimes-soft.com/mesh');
  });
}
