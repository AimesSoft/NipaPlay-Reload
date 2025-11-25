import 'package:smb_connect/src/exceptions.dart';
import 'package:smb_connect/src/smb/ntlm_password_authenticator.dart';

///
/// This class can be extended by applications that wish to trap authentication related exceptions and automatically
/// retry the exceptional operation with different credentials.
///
abstract class NtlmAuthenticator {
  static NtlmAuthenticator? auth;

  String? url;
  SmbAuthException? sae;

  /// Set the default NtlmAuthenticator. Once the default authenticator is set it cannot be changed. Calling
  /// this metho again will have no effect.
  static void setDefault(NtlmAuthenticator a) {
    if (auth != null) {
      return;
    }
    auth = a;
  }

  static NtlmAuthenticator? getDefault() {
    return auth;
  }

  String? getRequestingURL() => url;

  SmbAuthException? getRequestingException() => sae;

  /// credentials returned by prompt
  static NtlmPasswordAuthenticator? requestNtlmPasswordAuthentication(
      NtlmAuthenticator? a, String url, SmbAuthException? sae) {
    if (a == null) {
      return null;
    }
    a.url = url;
    a.sae = sae;
    return a.getNtlmPasswordAuthentication();
  }

  /// An application extending this class must provide an implementation for this method that returns new user
  /// credentials try try when accessing SMB resources described by the getRequestingURL and
  /// getRequestingException methods.
  /// If this method returns null the SmbAuthException that triggered the authenticator check will
  /// simply be rethrown. The default implementation returns null.
  NtlmPasswordAuthenticator? getNtlmPasswordAuthentication() {
    return null;
  }
}
