import 'package:nipa_harness/nipa_harness.dart';
import '../media/identity_store.dart';

Future<List<JsonMap>> todayUpdates(IdentityStore store, Set<String> following,
        List<JsonMap> cached) async =>
    throw const Failure(FailureCode.unavailable,
        'The headless host has no Classic account calendar.');
