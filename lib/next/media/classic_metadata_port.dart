import 'package:nipa_harness/nipa_harness.dart';

abstract interface class ClassicMetadataPort {
  Future<List<JsonMap>> history();
  Future<void> apply(String locator, JsonMap fields);
  Future<bool> verify(String locator, JsonMap fields);
}

abstract interface class ReversibleClassicMetadataPort
    implements ClassicMetadataPort {
  Future<JsonMap> projectionOutcome(String locator, JsonMap fields);
}
