import 'dart:typed_data';
import 'package:smb_connect/src/smb/authentication_type.dart';
import 'package:smb_connect/src/utils/base.dart';

import 'package:smb_connect/src/exceptions.dart';
import 'package:smb_connect/src/smb/ntlm_password_authenticator.dart';
import 'package:smb_connect/src/utils/strings.dart';

///
/// Authenticator directly specifing the user's NT hash
///
/// @author mbechler
///
class NtlmNtHashAuthenticator extends NtlmPasswordAuthenticator {
  static const int serialVersionUID = 4;
  final Uint8List _ntHash;

  /// Create username/password credentials with specified domain
  NtlmNtHashAuthenticator(
      String domain, String username, Uint8List passwordHash)
      : _ntHash = passwordHash,
        super(
            domain: domain, username: username, type: AuthenticationType.USER) {
    if (passwordHash.length != 16) {
      throw SmbIllegalArgumentException(
          "Password hash must be provided, expected length 16 byte");
    }
  }

  /// Create username/password credentials with specified domain
  NtlmNtHashAuthenticator.hex(
      String domain, String username, String passwordHashHex)
      : this(domain, username, Hexdump.decodeToBuff(passwordHashHex));

  @override
  @protected
  Uint8List getNTHash() {
    return _ntHash;
  }
}
