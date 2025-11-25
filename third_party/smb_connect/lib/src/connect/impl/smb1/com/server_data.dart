import 'dart:typed_data';

class ServerData {
  int sflags = 0;
  int sflags2 = 0;
  int smaxMpxCount = 0;
  int maxBufferSize = 0;
  int sessKey = 0;
  int scapabilities = 0;
  String? oemDomainName;
  int securityMode = 0;
  int security = 0;
  bool encryptedPasswords = false;
  bool signaturesEnabled = false;
  bool signaturesRequired = false;
  int maxNumberVcs = 0;
  int maxRawSize = 0;
  int serverTime = 0;
  int serverTimeZone = 0;
  int encryptionKeyLength = 0;
  Uint8List? encryptionKey;
  Uint8List? guid;
}
