import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/cupertino_playlist_pane.dart';
import 'package:nipaplay/utils/video_player_state.dart';

class _StreamState extends ChangeNotifier implements VideoPlayerState {
  _StreamState(this.currentVideoPath);
  @override
  final String currentVideoPath;
  @override
  String? get animeTitle => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final scheme in ['http', 'https']) {
    testWidgets('$scheme stream playlist never enumerates a local directory',
        (tester) async {
      final state = _StreamState('$scheme://example.com/tv.mp4?token=private');
      addTearDown(state.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: CupertinoPlaylistPane(videoState: state)),
      ));
      await tester.pumpAndSettle();
      expect(find.text('网络串流'), findsOneWidget);
      expect(find.text('tv.mp4'), findsOneWidget);
      expect(find.textContaining('视频目录不存在'), findsNothing);
      expect(find.textContaining('token=private'), findsNothing);
    });
  }
}
