import 'dart:typed_data';

import 'package:smb_connect/src/utils/extensions.dart';

///
/// SPNEGO Simple and Protected GSSAPI Negotiation Mechanism is a GSSAPI
/// "pseudo mechanism" that is used to negotiate one of a number of possible
/// real mechanisms.
///
/// SPNEGO's most visible use is in Microsoft's "HTTP Negotiate" authentication
/// extension. It was first implemented in Internet Explorer 5.01 and IIS 5.0
/// and provided single sign-on capability later marketed as Integrated Windows
/// Authentication. The negotiable sub-mechanisms included NTLM and Kerberos,
/// both used in Active Directory.
///
abstract class SpnegoToken {
  Uint8List? mechanismToken;

  Uint8List? mechanismListMIC;

  SpnegoToken({this.mechanismToken, this.mechanismListMIC});

  Uint8List toByteArray();

  @override
  String toString() =>
      'SpnegoToken(mechanismToken: ${mechanismToken?.toHexString()}, mechanismListMIC: ${mechanismListMIC?.toHexString()})';
}
