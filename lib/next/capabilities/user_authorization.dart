import 'package:nipa_harness/nipa_harness.dart';

/// The agent records the user's actual instruction, not a new permission token.
/// Existing conversational authorization is sufficient; never invent consent.
const userAuthorizationSchema = StringSchema(
  minLength: 1,
  description:
      'Record the explicit user instruction authorizing this operation, '
      'target device/server and use of credentials. Prior authorization in this '
      'conversation counts; do not ask again within its scope. Do not include '
      'secrets or substitute your own decision for user consent.',
);

void requireUserAuthorization(JsonMap input) {
  if ((input['userAuthorization'] as String? ?? '').trim().isEmpty) {
    throw const Failure(
        FailureCode.invalidInput,
        'Explicit user authorization is required. Record the user instruction '
        'in userAuthorization; ask only if it has not already been given.');
  }
}
