import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/remote_access_qr_service.dart';

void main() {
  group('RemoteAccessQrService', () {
    test('buildPayload includes all candidate urls in JSON payload', () {
      final payload = RemoteAccessQrService.buildPayload(
        baseUrl: 'http://192.168.1.10:1180',
        candidateBaseUrls: const [
          '192.168.1.11',
          'http://[2001:db8::1]:1180',
          'http://192.168.1.10:1180',
        ],
        displayName: 'Living Room PC',
      );

      final decoded = json.decode(payload) as Map<String, dynamic>;
      expect(decoded['type'], RemoteAccessQrService.payloadType);
      expect(decoded['baseUrl'], 'http://192.168.1.10:1180');
      expect(decoded['displayName'], 'Living Room PC');
      expect(
        decoded['urls'],
        <String>[
          'http://192.168.1.11:1180',
          'http://[2001:db8::1]:1180',
        ],
      );
    });

    test('parseScannedText reads candidate urls from JSON payload', () {
      const text =
          '{"type":"nipaplay_remote_access","baseUrl":"192.168.1.8","urls":["http://[2001:db8::2]:1180","192.168.1.9"],"displayName":"Home NAS"}';
      final payload = RemoteAccessQrService.parseScannedText(text);

      expect(payload.baseUrl, 'http://192.168.1.8:1180');
      expect(
        payload.allCandidateBaseUrls,
        <String>[
          'http://192.168.1.8:1180',
          'http://[2001:db8::2]:1180',
          'http://192.168.1.9:1180',
        ],
      );
      expect(payload.displayName, 'Home NAS');
    });

    test('allCandidateBaseUrls removes duplicates and keeps order', () {
      final payload = RemoteAccessQrPayload(
        baseUrl: 'http://192.168.1.7:1180',
        candidateBaseUrls: const [
          '192.168.1.7',
          'http://[2001:db8::7]:1180',
          'http://192.168.1.7:1180',
        ],
      );

      expect(
        payload.allCandidateBaseUrls,
        <String>[
          'http://192.168.1.7:1180',
          'http://[2001:db8::7]:1180',
        ],
      );
    });
  });
}
