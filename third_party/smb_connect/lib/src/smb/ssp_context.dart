import 'dart:typed_data';

import 'package:pointycastle/asn1/primitives/asn1_object_identifier.dart';

abstract class SSPContext {
  Uint8List? getSigningKey();

  bool isEstablished();

  Uint8List? initSecContext(Uint8List token, int off, int len);

  void dispose();

  bool isSupported(ASN1ObjectIdentifier mechanism);

  bool isPreferredMech(ASN1ObjectIdentifier? selectedMech);

  int getFlags();

  List<ASN1ObjectIdentifier> getSupportedMechs();

  bool supportsIntegrity();

  Uint8List calculateMIC(Uint8List data);

  void verifyMIC(Uint8List data, Uint8List mic);

  bool isMICAvailable();
}
