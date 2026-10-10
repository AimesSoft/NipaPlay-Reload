import 'package:nipa_harness/nipa_harness.dart';

import 'media_models.dart';

final class NavigationCapability implements Capability {
  NavigationCapability({required void Function(String pageId) changePage})
      : actions = [NavigateAction._(changePage)];

  @override
  final List<Action> actions;
}

final class NavigateAction extends Action<NavigateInput, NavigateOutput> {
  const NavigateAction._(this._changePage);

  final void Function(String pageId) _changePage;

  static const _spec = ActionSpec(
    id: 'ui.navigate',
    title: 'Navigate to a page',
    description: 'Switch the main interface to a primary page by its page ID. '
        'Returns the requested page ID after dispatching the navigation.',
    effect: Effect.write,
    input: navigateInputSchema,
    output: navigateOutputSchema,
  );

  @override
  ActionSpec get spec => _spec;

  @override
  NavigateInput decodeInput(JsonMap json) =>
      NavigateInput(page: json['page'] as String);

  @override
  Future<Outcome<NavigateOutput>> run(
    NavigateInput input,
    Invocation invocation,
  ) async {
    _changePage(input.page);
    return Completed(NavigateOutput(page: input.page));
  }
}
