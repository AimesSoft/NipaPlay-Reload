import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _step(String workflow, String name) {
  final marker = '      - name: $name';
  final start = workflow.indexOf(marker);
  expect(start, isNonNegative, reason: 'Missing workflow step: $name');
  final next = workflow.indexOf('\n      - name: ', start + marker.length);
  return workflow.substring(start, next < 0 ? workflow.length : next);
}

void main() {
  test('Windows workflow uploads only the directly runnable folder', () {
    final workflow =
        File('.github/workflows/build-windows.yml').readAsStringSync();
    final verification = _step(workflow, 'Verify portable Windows artifact');
    final upload = _step(workflow, 'Upload Windows Artifacts');

    expect(
      verification,
      matches(
        RegExp(
          r'if\s*\(\s*-not\s*\(\s*Test-Path[\s\S]*?NipaPlay\.exe'
          r'[\s\S]*?\)\s*\)',
        ),
      ),
    );
    expect(verification, contains('throw'));
    expect(upload, contains('uses: actions/upload-artifact@v4'));
    expect(
      upload,
      matches(
        RegExp(
          r'^\s+path: build/windows/NipaPlay_\*_Windows_x64/\s*$',
          multiLine: true,
        ),
      ),
    );
    expect(
      RegExp(r'actions/upload-artifact@v4').allMatches(workflow),
      hasLength(1),
    );
    expect(upload, isNot(contains('path: |')));
    expect(
        RegExp(r'^\s+path:', multiLine: true).allMatches(upload), hasLength(1));
    expect(workflow, isNot(contains('dart-symbols-Windows')));
  });
}
