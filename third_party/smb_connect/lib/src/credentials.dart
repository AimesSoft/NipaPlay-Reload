import 'dart:typed_data';

import 'package:smb_connect/src/configuration.dart';
import 'package:smb_connect/src/smb/ssp_context.dart';

/// Interface for opaque credential data
/// @author mbechler
abstract class Credentials {
  /// the domain the user account is in
  String getUserDomain();

  /// whether these are anonymous credentials
  bool isAnonymous();

  /// whether these are guest credentials
  bool isGuest();

  SSPContext createContext(Configuration config, String? targetDomain,
      String host, Uint8List initialToken, bool doSigning);
}
