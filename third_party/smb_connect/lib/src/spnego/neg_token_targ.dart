import 'dart:typed_data';

import 'package:pointycastle/pointycastle.dart';
import 'package:smb_connect/src/spnego/spnego_token.dart';
import 'package:smb_connect/src/utils/extensions.dart';
import 'package:smb_connect/src/utils/extensions/asn1/asn1_tagged_object.dart';

class NegTokenTarg extends SpnegoToken {
  static const int UNSPECIFIED_RESULT = -1;
  static const int ACCEPT_COMPLETED = 0;
  static const int ACCEPT_INCOMPLETE = 1;
  static const int REJECTED = 2;
  static const int REQUEST_MIC = 3;

  ASN1ObjectIdentifier? mechanism;

  int result = UNSPECIFIED_RESULT;

  NegTokenTarg(
    this.result,
    this.mechanism,
    Uint8List? mechanismToken,
    Uint8List? mechanismListMIC,
  ) : super(
          mechanismToken: mechanismToken,
          mechanismListMIC: mechanismListMIC,
        );
  @override
  String toString() =>
      'NegTokenTarg(mechanism: $mechanism, mechanismToken: ${mechanismToken?.toHexString()}, mechanismListMIC: ${mechanismListMIC?.toHexString()})';

  @override
  Uint8List toByteArray() {
    ASN1Sequence fields = ASN1Sequence();
    int res = result;
    if (res != UNSPECIFIED_RESULT) {
      fields.add(ASN1TaggedObject(tagNo: 0, ASN1Enumerated(res)));
    }
    final mech = mechanism;
    if (mech != null) {
      fields.add(ASN1TaggedObject(tagNo: 1, mech));
    }
    final mechanismToken = this.mechanismToken;
    if (mechanismToken != null) {
      fields.add(
          ASN1TaggedObject(tagNo: 2, ASN1OctetString(octets: mechanismToken)));
    }
    final mechanismListMIC = this.mechanismListMIC;
    if (mechanismListMIC != null) {
      fields.add(ASN1TaggedObject(
          tagNo: 3, ASN1OctetString(octets: mechanismListMIC)));
    }
    return ASN1TaggedObject(fields, tagNo: 1).encode();
  }

  @override
  factory NegTokenTarg.parse(Uint8List token) {
    token.toHexString();
    var root = ASN1Object.fromBytes(token);
    var fields = ASN1Sequence.fromBytes(root.valueBytes!);
    int result = UNSPECIFIED_RESULT;
    ASN1ObjectIdentifier? mechanism;
    Uint8List? mechanismToken, mechanismListMIC;
    for (var field in fields.elements!) {
      var tagNo = (field.tag ?? 0) & 0xF;
      if (tagNo == 0) {
        result = ASN1Enumerated.fromBytes(field.valueBytes!).integer!.toInt();
      } else if (tagNo == 1) {
        mechanism = ASN1ObjectIdentifier.fromBytes(field.valueBytes!);
      } else if (tagNo == 2) {
        mechanismToken = ASN1OctetString.fromBytes(field.valueBytes!).octets;
      } else if (tagNo == 3) {
        mechanismListMIC = ASN1OctetString.fromBytes(field.valueBytes!).octets;
      } else {
        throw "Malformed NegTokenTarg";
      }
    }
    return NegTokenTarg(result, mechanism, mechanismToken, mechanismListMIC);
  }
}
