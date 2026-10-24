import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/ui/dev/fake_settings.dart';
import 'package:nipaplay/next/ui/shell/nipa_setup.dart';

/// What the person sees of Nipa not being ready: the amber chip asks for a
/// model; while NipaPlay fetches the runtime it says how far; when both are
/// in place it is gone.
void main() {
  test('needs a model, then shows the runtime being fetched, then nothing', () async {
    final host = FakeSettings().host
      ..modelState = 'empty'
      ..dshState = 'none';
    final setup = NipaSetup(host);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(setup.needsModel, true);
    expect(setup.preparing, false);

    // A model is there; the runtime is not.
    host.modelState = 'key';
    host.changed();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(setup.needsModel, true);
    expect(setup.preparing, false);

    final done = host.installDsh();
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(setup.needsModel, true);
    expect(setup.preparing, true);
    expect(setup.progress, inInclusiveRange(0.0, 1.0));
    final seen = setup.progress!;
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(setup.progress!, greaterThan(seen));

    await done;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(setup.preparing, false);
    expect(setup.needsModel, false);
    setup.dispose();
  });
}
