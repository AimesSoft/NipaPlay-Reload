import 'package:nipa_harness/nipa_harness.dart';

import '../media/media_service.dart';
import 'ui_open.dart';

final class UiCapability implements Capability {
  UiCapability({
    MediaService Function()? media,
    Future<bool> Function(String page)? openPage,
    Future<bool> Function(int animeId)? openDetail,
    Future<Outcome<JsonEncodable>> Function(JsonMap, Invocation)? play,
  }) : actions = [
          UiOpenAction(
              media: media,
              openPage: openPage,
              openDetail: openDetail,
              play: play),
        ];

  @override
  final List<Action> actions;
}
