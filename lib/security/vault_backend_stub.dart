import 'credential_vault.dart';
import 'legacy_credential_vault.dart';

bool get usesSystemVault => false;
CredentialVault createCredentialVault() => LegacyCredentialVault();
