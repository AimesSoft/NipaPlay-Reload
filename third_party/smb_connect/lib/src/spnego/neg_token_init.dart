import 'dart:typed_data';

import 'package:pointycastle/asn1.dart';
import 'package:smb_connect/src/exceptions.dart';
import 'package:smb_connect/src/spnego/spnego_constants.dart';
import 'package:smb_connect/src/utils/extensions/asn1/asn1_tagged_object.dart';

import 'spnego_token.dart';

///
/// The negTokenInit message is sent from the client to the server and is used
/// to begin the negotiation. The client uses that message to specify the set
/// of authentication mechanisms that are supported and an opportunistic
/// authentication message from the mechanism that the client believes will be
/// agreed upon with the server.
///
/// https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-spng/217c771b-7754-475a-a0d5-771ab4cac752
///
class NegTokenInit extends SpnegoToken {
  static const int DELEGATION = 0x80;
  static const int MUTUAL_AUTHENTICATION = 0x40;
  static const int REPLAY_DETECTION = 0x20;
  static const int SEQUENCE_CHECKING = 0x10;
  static const int ANONYMITY = 0x08;
  static const int CONFIDENTIALITY = 0x04;
  static const int INTEGRITY = 0x02;

  static final ASN1ObjectIdentifier SPNEGO_OID =
      ASN1ObjectIdentifier.fromIdentifierString(
          SpnegoConstants.SPNEGO_MECHANISM);

  List<ASN1ObjectIdentifier>? mechanisms;

  int contextFlags;

  NegTokenInit({
    this.mechanisms,
    this.contextFlags = 0,
    super.mechanismToken,
    super.mechanismListMIC,
  });

  void setContextFlags(int contextFlags) {
    this.contextFlags = contextFlags;
  }

  bool getContextFlag(int flag) => (contextFlags & flag) == flag;

  void setContextFlag(int flag, bool value) {
    setContextFlags(
        value ? (contextFlags | flag) : (contextFlags & (0xffffffff ^ flag)));
  }

  List<ASN1ObjectIdentifier>? getMechanisms() => mechanisms;

  void setMechanisms(List<ASN1ObjectIdentifier> mechanisms) {
    this.mechanisms = mechanisms;
  }

  @override
  String toString() {
    final mic = mechanismListMIC?.map((e) => e.toRadixString(16)).join("");
    return "NegTokenInit[flags=$contextFlags,mechs=${getMechanisms()},mic=$mic]";
  }

  @override
  Uint8List toByteArray() {
    ASN1Sequence fields = ASN1Sequence();
    List<ASN1ObjectIdentifier>? mechs = getMechanisms();
    if (mechs != null) {
      ASN1Sequence vector = ASN1Sequence();
      for (int i = 0; i < mechs.length; i++) {
        vector.add(mechs[i]);
      }
      fields.add(ASN1TaggedObject(tagNo: 0, vector));
    }
    int ctxFlags = contextFlags;
    if (ctxFlags != 0) {
      fields.add(
          ASN1TaggedObject(tagNo: 1, ASN1BitString(stringValues: [ctxFlags])));
    }
    Uint8List? mechanismToken = this.mechanismToken;
    if (mechanismToken != null) {
      fields.add(
          ASN1TaggedObject(tagNo: 2, ASN1OctetString(octets: mechanismToken)));
    }
    Uint8List? mechanismListMIC = this.mechanismListMIC;
    if (mechanismListMIC != null) {
      fields.add(ASN1TaggedObject(
          tagNo: 3, ASN1OctetString(octets: mechanismListMIC)));
    }

    ASN1Sequence ev =
        ASN1Sequence(tag: ASN1Tags.APPLICATION | ASN1Tags.CONSTRUCTED);
    ev.add(SPNEGO_OID);
    ev.add(ASN1TaggedObject(fields));
    return ev.encode(encodingRule: ASN1EncodingRule.ENCODING_DER);
  }

  @override
  factory NegTokenInit.parse(Uint8List token) {
    var root = ASN1Sequence.fromBytes(token);
    if (((root.tag ?? 0) & ASN1Tags.APPLICATION) != ASN1Tags.APPLICATION ||
        root.elements?.length != 2) {
      throw SmbIOException("Malformed SPNEGO token $root");
    }
    var spnego = root.elements![0] as ASN1ObjectIdentifier;
    if (SPNEGO_OID.objectIdentifierAsString !=
        spnego.objectIdentifierAsString) {
      throw SmbIOException(
          "Malformed SPNEGO token, OID ${spnego.objectIdentifierAsString}");
    }
    var fieldsObj = root.elements![1]; // as ASN1TaggedObject;
    var fields = ASN1Sequence.fromBytes(fieldsObj.valueBytes!);

    List<ASN1ObjectIdentifier>? mechs;
    int ctxFlags = 0; //1
    Uint8List? mechanismToken; //2
    Uint8List? mechanismListMIC; //3
    for (var field in fields.elements!) {
      var tagNo = (field.tag ?? 0) & 0xF;
      if (tagNo == 0) {
        var mechsSeq = ASN1Sequence.fromBytes(field.valueBytes!);
        mechs =
            mechsSeq.elements?.map((e) => e as ASN1ObjectIdentifier).toList();
      } else if (tagNo == 1) {
        ctxFlags = ASN1BitString.fromBytes(field.valueBytes!).stringValues![0];
      } else if (tagNo == 2) {
        mechanismToken = ASN1OctetString.fromBytes(field.valueBytes!).octets;
      } else if (tagNo == 3) {
        if ((field.valueBytes?.firstOrNull ?? 0) & ASN1Tags.OCTET_STRING ==
            ASN1Tags.OCTET_STRING) {
          mechanismListMIC =
              ASN1OctetString.fromBytes(field.valueBytes!).octets;
        }
      } else if (tagNo == 4) {
        mechanismListMIC = ASN1OctetString.fromBytes(field.valueBytes!).octets;
      } else {
        throw "Unsupported tagNo=$tagNo";
      }
    }
    return NegTokenInit(
      mechanisms: mechs,
      contextFlags: ctxFlags,
      mechanismToken: mechanismToken,
      mechanismListMIC: mechanismListMIC,
    );
  }
}
