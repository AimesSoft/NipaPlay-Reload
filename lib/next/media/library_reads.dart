import 'package:nipa_harness/nipa_harness.dart';

import 'identity_store.dart';

/// What one pass over the catalogue has read so far, so that the several
/// parts of a pass that need the same thing about an entity (its merged
/// metadata, its danmaku tracks) read it once. A pass makes one of these
/// and drops it when it ends; what it holds is never used for anything
/// after that. Callers must not change what they are given.
final class LibraryReads {
  LibraryReads(this.store);
  final IdentityStore store;
  final _memo = <Object, Future<Object?>>{};

  /// [read]'s result for [key], read the first time it is asked for.
  Future<T> once<T>(Object key, Future<T> Function() read) =>
      (_memo[key] ??= read()) as Future<T>;

  Future<JsonMap> metadata(String id) =>
      once(('metadata', id), () => store.mergedMetadata(id));
}
