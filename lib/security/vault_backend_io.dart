import 'dart:io';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'credential_vault.dart';
import 'desktop_credential_vault.dart';
import 'legacy_credential_vault.dart';

bool get usesSystemVault =>
    !globals.isHarmonyOS &&
    !globals.isTelevision &&
    (Platform.isMacOS || Platform.isWindows || Platform.isLinux);
CredentialVault createCredentialVault() =>
    usesSystemVault ? DesktopCredentialVault() : LegacyCredentialVault();
