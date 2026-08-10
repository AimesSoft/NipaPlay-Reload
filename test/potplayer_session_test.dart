import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/constants/media_extensions.dart';
import 'package:nipaplay/models/external_player_session/potplayer_session.dart';
import 'package:nipaplay/utils/external_player_utils.dart';

void main() {
  test('detects both 32-bit and 64-bit PotPlayer executables', () {
    expect(
      detectExternalPlayerType(
        r'C:\Program Files\DAUM\PotPlayer\PotPlayerMini64.exe',
      ),
      ExternalPlayerType.potPlayer,
    );
    expect(
      detectExternalPlayerType(r'D:\Apps\PotPlayerMini.exe'),
      ExternalPlayerType.potPlayer,
    );
  });

  test('formats PotPlayer seek positions', () {
    expect(
      PotPlayerSession.formatSeekPosition(
        const Duration(hours: 1, minutes: 2, seconds: 3, milliseconds: 45),
      ),
      '01:02:03.045',
    );
    expect(
      PotPlayerSession.formatSeekPosition(const Duration(seconds: -1)),
      '00:00:00.000',
    );
  });

  test('builds a new PotPlayer instance with resume and custom arguments', () {
    expect(
      PotPlayerSession.buildExtraArgs(
        const Duration(minutes: 12, seconds: 34, milliseconds: 567),
        const ['/user_agent=NipaPlay'],
        assFilePath: r'C:\Temp\nipaplay.ass',
      ),
      const [
        '/new',
        '/seek=00:12:34.567',
        r'/sub=C:\Temp\nipaplay.ass',
        '/user_agent=NipaPlay',
      ],
    );
  });

  test('PotPlayer session exposes its dedicated player type', () {
    final session = PotPlayerSession(
      playerPath: r'C:\Program Files\DAUM\PotPlayer\PotPlayerMini64.exe',
      mediaPath: r'D:\video.mkv',
      duration: const Duration(minutes: 24),
    );
    expect(session.type, ExternalPlayerType.potPlayer);
    session.dispose();
  });
}
