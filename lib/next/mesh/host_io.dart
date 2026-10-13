import 'package:nipa_harness/nipa_harness.dart';

const meshDevelopmentHost = true;
Future<Failure?> authorizeMeshPeer(String deviceId, String name) async =>
    const Failure(FailureCode.unavailable, 'Host authorization is required.');
