// Release gate for the Mesh trust roots.
//
//   dart run -DNIPAPLAY_MESH_ISSUER_PEM_B64=... tool/next/check_mesh_trust.dart
//
// Pass the same --dart-define values the release build gets. Without a define
// the roots compiled into lib/next/mesh/trust.dart are checked. Exits non-zero
// (and the release must not be built) unless the bundle is not empty, every
// certificate parses, every one is a self-issued Ed25519 CA allowed to sign
// certificates, none has expired, and there are at least two different roots.
import 'dart:io';

import 'package:nipaplay/next/mesh/trust.dart';

void main() {
  final report = inspectMeshTrust(meshProductionIssuerPem);
  if (!report.ok) {
    stderr.writeln('Mesh trust roots are not ready for a release:');
    for (final problem in report.problems) {
      stderr.writeln('  - $problem');
    }
    exitCode = 1;
    return;
  }
  stdout.writeln('Mesh trust roots ok: ${report.roots.length} roots, '
      'coordinator $meshDefaultCoordinator');
}
