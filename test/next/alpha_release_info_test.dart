import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/system/alpha_updates.dart';
import 'package:nipaplay/next/ui/data/settings_data.dart';
import 'package:nipaplay/utils/app_build_info.dart';

void main() {
  test('alpha version is preserved separately from native numeric version', () {
    final facts = appBuildInfoFacts({
      'app_version': '2.0.0-alpha.1',
      'git_commit': 'abc123',
      'git_dirty': true,
    },
        nativeVersion: '2.0.0.1',
        buildNumber: '2026102706',
        os: 'macos',
        osVersion: '26',
        abi: 'macos_arm64',
        dartVersion: '3.12',
        mode: 'Release');
    expect(facts['应用版本'], '2.0.0-alpha.1');
    expect(facts['安装包版本'], '2.0.0.1');
    expect(facts['源码状态'], '包含本地修改');
    expect(facts['Flutter'], '未提供');
    final text = UiAbout(facts: facts).diagnosticsText;
    expect(text, contains('构建号: 2026102706'));
    expect(text, contains('源码提交: abc123'));
    expect(text, isNot(contains('null')));
  });

  test(
      'Next picks semantic highest published release, ignores drafts and Classic',
      () {
    final releases = [
      {'tag_name': 'v1.99.9', 'draft': false},
      {'tag_name': 'v2.0.0-alpha.10', 'draft': false},
      {'tag_name': 'v2.0.0-alpha.2', 'draft': false},
      {'tag_name': 'v2.0.0', 'draft': true},
      {'tag_name': 'nightly', 'draft': false},
    ];
    expect(selectNextRelease(releases)?['tag_name'], 'v2.0.0-alpha.10');
    expect(
        selectNextRelease([
          ...releases,
          {'tag_name': 'v2.0.0-beta.1'}
        ])?['tag_name'],
        'v2.0.0-beta.1');
    expect(
        selectNextRelease([
          ...releases,
          {'tag_name': 'v2.0.0'}
        ])?['tag_name'],
        'v2.0.0');
    expect(
        selectNextRelease([
          {'tag_name': 'v1.9.0'}
        ]),
        isNull);
    expect(
        releaseVersion('v2.0.0-alpha.1+1'), releaseVersion('2.0.0-alpha.1+2'));
  });
}
