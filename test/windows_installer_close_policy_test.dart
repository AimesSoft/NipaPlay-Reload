import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows setup closes tray-resident players without restarting them',
      () {
    final workflow =
        File('.github/actions/build-windows/action.yml').readAsStringSync();
    final installerStep = workflow.split('    - name: ').singleWhere(
          (step) => step.startsWith('Create Windows installer with Inno Setup'),
        );
    final setup = installerStep
        .split('[Setup]')[1]
        .split('[Languages]')[0]
        .split('\n')
        .map((line) => line.trim())
        .toList();

    expect(setup, contains('CloseApplications=force'));
    expect(setup, contains('CloseApplicationsFilter={#MyAppExeName}'));
    expect(setup, contains('RestartApplications=no'));
  });
}
