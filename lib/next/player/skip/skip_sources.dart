import '../../media/identity_store.dart';
import 'aniskip_lookup.dart';
import 'skip_store.dart';

export 'aniskip_lookup.dart' show AniSkipOutcome, anilistProvider, malProvider;

/// Where a session's skip segments come from besides the kernel and the
/// danmaku: what Nipa set and the file remembers, and AniSkip for an anime
/// whose MAL (or AniList) ID she wrote down.
final class SessionSkipSources {
  SessionSkipSources(IdentityStore Function() identities,
      {AniSkipFetch? fetch, MalOfAniList? malOf})
      : store = SkipSegmentStore(identities),
        aniskip = AniSkipLookup(identities, fetch: fetch, malOf: malOf);
  final SkipSegmentStore store;
  final AniSkipLookup aniskip;
}
