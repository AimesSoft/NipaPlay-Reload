import 'dart:async';
import '../../security/credential_vault.dart';

/// 只发布写入成功的引用，不携带凭据、令牌或摘要。
abstract final class CredentialChanges {
  static final _changes = StreamController<CredentialRef>.broadcast();
  static Stream<CredentialRef> get changes => _changes.stream;
  static void committed(CredentialRef ref) => _changes.add(ref);
}
