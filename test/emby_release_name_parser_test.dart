import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/emby_release_name_parser.dart';

void main() {
  group('parseEmbyReleaseIdentity', () {
    test('keeps subtitle variants in the normalized full name', () {
      final bilingual = parseEmbyReleaseIdentity(
        '简繁日内封.喵萌奶茶屋&LoliHouse',
      );
      final simplified = parseEmbyReleaseIdentity(
        '简体内嵌.喵萌奶茶屋&LoliHouse',
      );

      expect(bilingual.families, containsAll({'喵萌奶茶屋', 'lolihouse'}));
      expect(bilingual.features, contains('简繁日内封'));
      expect(
          bilingual.normalizedFullName, isNot(simplified.normalizedFullName));
    });

    test('normalizes Latin case, spacing and separators without losing family',
        () {
      final identity = parseEmbyReleaseIdentity(' WEB-DL · LoliHouse 1080P ');

      expect(identity.normalizedFullName, 'web dl lolihouse');
      expect(identity.families, {'lolihouse'});
      expect(identity.features, {'web-dl'});
    });

    test('keeps release formats as features rather than release families', () {
      final identity = parseEmbyReleaseIdentity('BluRay.LoliHouse.1080p');

      expect(identity.families, {'lolihouse'});
      expect(identity.features, {'bluray'});
    });

    test('normalizes split release formats without leaking tokens to families',
        () {
      final webRip = parseEmbyReleaseIdentity('WEB-Rip.Baha.1080p');
      final bluRay = parseEmbyReleaseIdentity('Blu-Ray.LoliHouse.1080p');
      final bdRip = parseEmbyReleaseIdentity('BD-Rip.Baha.1080p');

      expect(webRip.features, {'web-rip'});
      expect(webRip.families, {'baha'});
      expect(bluRay.features, {'bluray'});
      expect(bluRay.families, {'lolihouse'});
      expect(bdRip.features, {'bdrip'});
      expect(bdRip.families, {'baha'});
    });

    test('preserves non-technical release families across writing systems', () {
      final japanese = parseEmbyReleaseIdentity(
        'WEB-DL.\u3053\u3093\u306b\u3061\u306f\u7d44.1080p',
      );
      final korean = parseEmbyReleaseIdentity(
        'WEB-DL.\ud55c\uae00\ubc30\ud3ec\uadf8\ub8f9.1080p',
      );
      final cyrillic = parseEmbyReleaseIdentity(
        'WEB-DL.\u041a\u0438\u0440\u0438\u043b\u043b\u0433\u0440\u0443\u043f\u043f\u0430.1080p',
      );

      expect(
          japanese.families, contains('\u3053\u3093\u306b\u3061\u306f\u7d44'));
      expect(korean.families, contains('\ud55c\uae00\ubc30\ud3ec\uadf8\ub8f9'));
      expect(
          cyrillic.families,
          contains(
              '\u043a\u0438\u0440\u0438\u043b\u043b\u0433\u0440\u0443\u043f\u043f\u0430'));
    });
  });
}
