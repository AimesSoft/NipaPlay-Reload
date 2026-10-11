import 'package:nipa_harness/nipa_harness.dart';

import '../media/media_service.dart';
import 'ui_open.dart';

final class UiCapability implements Capability {
  UiCapability({
    MediaService Function()? media,
    Future<bool> Function(String page)? openPage,
    Future<bool> Function(int animeId)? openDetail,
    Future<JsonMap?> Function(JsonMap)? openTarget,
    Future<JsonMap> Function()? close,
    Future<Outcome<JsonEncodable>> Function(JsonMap, Invocation)? play,
  }) : actions = [
          UiOpenAction(
              media: media,
              openPage: openPage,
              openDetail: openDetail,
              openTarget: openTarget,
              play: play),
          if (close != null) UiCloseAction(close),
        ];

  @override
  final List<Action> actions;
}

final class UiCloseAction extends Action<UiOpenValue, UiOpenValue> {
  const UiCloseAction(this.close);
  final Future<JsonMap> Function() close;
  @override
  ActionSpec get spec => const ActionSpec(
      id: 'ui.close',
      title: 'Close current dialog',
      description:
          'Close the top Classic modal/page route, discarding unsaved drafts. No confirmation or secret submission. closed=false on the root page.',
      effect: Effect.write,
      input: ObjectSchema({}),
      output: ObjectSchema({}, additionalProperties: true));
  @override
  UiOpenValue decodeInput(JsonMap input) => UiOpenValue(input);
  @override
  Future<Outcome<UiOpenValue>> run(
          UiOpenValue input, Invocation invocation) async =>
      Completed(UiOpenValue(await close()));
}
