import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Bangumi auth launches directly and only reports real success', () {
    final source = File(
      'lib/themes/nipaplay/pages/account/material_account_page.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('canLaunchUrl(uri)')));
    expect(
      source,
      contains(
        'final opened = await launchUrl(\n'
        '        uri,\n'
        '        mode: LaunchMode.externalApplication,\n'
        '      );',
      ),
    );
    expect(source, contains('if (!opened || !mounted) return;'));
    expect(source, contains('return opened;'));
  });
}
