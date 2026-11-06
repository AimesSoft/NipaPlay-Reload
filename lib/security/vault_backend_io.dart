import 'dart:io';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'credential_vault.dart';
import 'desktop_credential_vault.dart';
import 'keychain_credential_vault.dart';
import 'legacy_credential_vault.dart';

bool get usesSystemVault =>
    !globals.isHarmonyOS &&
    !globals.isTelevision &&
    (Platform.isMacOS || Platform.isWindows || Platform.isLinux);
/// Apple mobile devices and televisions keep secrets in their own Keychain.
bool get usesKeychainVault => globals.isTvOS ||
    (Platform.isIOS && !globals.isTelevision);
CredentialVault createCredentialVault() => usesSystemVault
    ? DesktopCredentialVault()
    : usesKeychainVault
        ? KeychainCredentialVault()
        : LegacyCredentialVault();
