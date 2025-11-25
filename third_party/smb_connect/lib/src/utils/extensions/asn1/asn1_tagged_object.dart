import 'package:pointycastle/asn1.dart';

class ASN1TaggedObject extends ASN1Sequence {
  // static int tagClassFrom(ASN1Object obj) {
  //   return //obj is ASN1Sequence && obj.elements?.isNotEmpty == true
  //       // ? ASN1Tags.SEQUENCE :
  //       ASN1Tags.TAGGED | ASN1Tags.CONSTRUCTED;
  // }

  ASN1TaggedObject(ASN1Object obj, {int? tag, int tagNo = 0})
      : super(
            tag: (tag ?? ASN1Tags.TAGGED | ASN1Tags.CONSTRUCTED) | tagNo,
            elements: [obj]);

  ///
  /// Creates an [ASN1TaggedObject] entity from the given [encodedBytes].
  ///
  ASN1TaggedObject.fromBytes(super.encodedBytes) : super.fromBytes() {
    elements = [];
    var parser = ASN1Parser(valueBytes);
    if (parser.hasNext()) {
      elements!.add(parser.nextObject());
    }
  }

  ASN1Object? get obj => elements?.firstOrNull;
}
