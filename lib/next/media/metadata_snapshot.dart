import 'package:nipa_harness/nipa_harness.dart';

const metadataFieldsSchema = ObjectSchema({
  'title': StringSchema(nullable: true),
  'originalTitle': StringSchema(nullable: true),
  'overview': StringSchema(nullable: true),
  'imageUrl': StringSchema(nullable: true),
  'year': IntegerSchema(nullable: true),
  'rating': ObjectSchema({
    'value': NumberSchema(minimum: 0),
    'max': NumberSchema(minimum: 0),
    'count': IntegerSchema(minimum: 0, nullable: true),
    'label': StringSchema(minLength: 1),
  }, required: [
    'value',
    'max'
  ], nullable: true),
  'directors': ArraySchema(StringSchema()),
  'actors': ArraySchema(StringSchema()),
  'genres': ArraySchema(StringSchema()),
},
    additionalProperties: true,
    description:
        'JSON facts. Common fields are validated; all other fields are retained verbatim. rating source is assigned by the host from ref.provider.');

const metadataViewSchema = ObjectSchema({
  'fields': ObjectSchema({}, additionalProperties: true),
  'provenance': ObjectSchema({}, additionalProperties: true),
  'ratings': ArraySchema(ObjectSchema({}, additionalProperties: true)),
  'sources': ArraySchema(ObjectSchema({}, additionalProperties: true)),
  // The page's rule this view was merged by (ui.detail.layout).
  'presentation': ObjectSchema({}, additionalProperties: true),
}, required: [
  'fields',
  'provenance',
  'ratings'
]);

void validateMetadataFields(JsonMap fields) {
  final violations = metadataFieldsSchema.validate(fields);
  if (violations.isNotEmpty) {
    throw Failure(FailureCode.invalidInput, 'Invalid metadata fields.',
        violations: violations);
  }
  if (fields['rating'] case final Map rating) {
    final value = rating['value'] as num, max = rating['max'] as num;
    if (!value.isFinite || !max.isFinite || max <= 0 || value > max) {
      throw const Failure(FailureCode.invalidInput,
          'rating must have finite 0 <= value <= max and max > 0.');
    }
  }
}
