import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/capabilities/discover_capability.dart';
import 'package:nipaplay/next/capabilities/ui_capability.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final harness = Harness([DiscoverCapability(), UiCapability()]);
  final invocation = Invocation(origin: 'constraint-test');

  test('invalid discovery inputs fail before network or cache mutations',
      () async {
    for (final input in [
      {'tags': <String>[]},
      {
        'tags': ['机甲'],
        'year': 2026
      },
      {
        'tags': ['a,b']
      },
      {
        'tags': [' ']
      },
      {'minRate': 9, 'maxRate': 2},
      {'minRate': 11},
    ]) {
      final result =
          await harness.invokeJson('discover.search', input, invocation);
      expect(result, isA<Failed>());
      expect((result as Failed).failure.code, FailureCode.invalidInput);
    }
    for (final input in [
      {'kind': 'newAnimeHot', 'range': 'week'},
      {'kind': 'allHot', 'range': 'previousSeason'},
      {'limit': 51},
    ]) {
      final result =
          await harness.invokeJson('discover.trending', input, invocation);
      expect(result, isA<Failed>());
      expect((result as Failed).failure.code, FailureCode.invalidInput);
    }
  });

  test('a malformed batch never executes earlier valid requests', () async {
    final result = await harness.invokeJson(
        'discover.search_batch',
        {
          'requests': [
            {'keyword': '机器人'},
            {'tags': <String>[]}
          ],
        },
        invocation);
    expect(result, isA<Failed>());
    expect((result as Failed).failure.code, FailureCode.invalidInput);
  });

  test('UI target alternatives and subpage ownership are enforced', () async {
    for (final input in [
      {'page': 'home', 'dialog': 'search'},
      {'dialog': 'search', 'subpage': 'about'},
      {'page': 'settings', 'subpage': 'typo'},
      {'animeId': 0},
      {'dialog': 'quarterly_comment'},
      {'dialog': 'search', 'reviewAnimeId': 8353},
      {'page': 'home', 'qr': true},
      {'system': 'logs', 'aboutLink': 'website'},
    ]) {
      final result = await harness.invokeJson('ui.open', input, invocation);
      expect(result, isA<Failed>());
      expect((result as Failed).failure.code, FailureCode.invalidInput);
    }
  });
}
