part of 'kernel.dart';

sealed class Schema {
  const Schema({this.description, this.nullable = false, this.secret = false});

  final String? description;
  final bool nullable;
  final bool secret;

  JsonMap toJsonSchema() {
    final type = switch (this) {
      StringSchema() => 'string',
      IntegerSchema() => 'integer',
      NumberSchema() => 'number',
      BooleanSchema() => 'boolean',
      ArraySchema() => 'array',
      ObjectSchema() => 'object',
      _TaskJsonSchema() => 'object',
    };
    return {
      'type': nullable ? [type, 'null'] : type,
      if (description != null) 'description': description,
      if (secret) 'writeOnly': true,
      if (secret) 'x-secret': true,
      ...switch (this) {
        StringSchema(:final values, :final minLength) => {
            if (values != null) 'enum': values,
            if (minLength != null) 'minLength': minLength,
          },
        IntegerSchema(:final minimum, :final maximum) => {
            if (minimum != null) 'minimum': minimum,
            if (maximum != null) 'maximum': maximum,
          },
        NumberSchema(:final minimum, :final maximum) => {
            if (minimum != null) 'minimum': minimum,
            if (maximum != null) 'maximum': maximum,
          },
        BooleanSchema() => <String, Object?>{},
        _TaskJsonSchema() => <String, Object?>{},
        ArraySchema(:final items) => {'items': items.toJsonSchema()},
        ObjectSchema(
          :final properties,
          :final required,
          :final additionalProperties,
          :final oneOfRequired
        ) =>
          {
            'properties': {
              for (final entry in properties.entries)
                entry.key: entry.value.toJsonSchema(),
            },
            if (required.isNotEmpty) 'required': required,
            'additionalProperties': additionalProperties,
            if (oneOfRequired.isNotEmpty)
              'oneOf': [
                for (final group in oneOfRequired) {'required': group},
              ],
          },
      },
    };
  }

  List<SchemaViolation> validate(Object? value) => _validate(value, '');

  List<SchemaViolation> _validate(Object? value, String path) {
    if (value == null && nullable) return [];
    final violations = <SchemaViolation>[];
    switch (this) {
      case _TaskJsonSchema():
        if (value is! JsonMap) {
          return [SchemaViolation(path, 'Expected an object.')];
        }
      case StringSchema(:final values, :final minLength):
        if (value is! String) {
          return [SchemaViolation(path, 'Expected a string.')];
        }
        if (values != null && !values.contains(value)) {
          violations.add(SchemaViolation(path, 'Expected one of $values.'));
        }
        if (minLength != null && value.runes.length < minLength) {
          violations.add(
            SchemaViolation(path, 'Expected at least $minLength characters.'),
          );
        }
      case IntegerSchema(:final minimum, :final maximum):
        if (value is! int &&
            !(value is double &&
                value.isFinite &&
                value == value.truncateToDouble())) {
          return [SchemaViolation(path, 'Expected an integer.')];
        }
        violations.addAll(_bounds(value as num, path, minimum, maximum));
      case NumberSchema(:final minimum, :final maximum):
        if (value is! num) {
          return [SchemaViolation(path, 'Expected a number.')];
        }
        violations.addAll(_bounds(value, path, minimum, maximum));
      case BooleanSchema():
        if (value is! bool) {
          return [SchemaViolation(path, 'Expected a boolean.')];
        }
      case ArraySchema(:final items):
        if (value is! List) {
          return [SchemaViolation(path, 'Expected an array.')];
        }
        for (var i = 0; i < value.length; i++) {
          violations.addAll(items._validate(value[i], '$path/$i'));
        }
      case ObjectSchema(
          :final properties,
          :final required,
          :final additionalProperties,
          :final oneOfRequired
        ):
        if (value is! Map) {
          return [SchemaViolation(path, 'Expected an object.')];
        }
        for (final key in value.keys) {
          if (key is! String) {
            violations
                .add(SchemaViolation(path, 'Object keys must be strings.'));
          } else if (!additionalProperties && !properties.containsKey(key)) {
            violations
                .add(SchemaViolation(_pointer(path, key), 'Unknown field.'));
          }
        }
        for (final key in required) {
          if (!value.containsKey(key)) {
            violations.add(
              SchemaViolation(
                  _pointer(path, key), 'Required field is missing.'),
            );
          }
        }
        for (final entry in properties.entries) {
          if (value.containsKey(entry.key)) {
            violations.addAll(
              entry.value
                  ._validate(value[entry.key], _pointer(path, entry.key)),
            );
          }
        }
        if (oneOfRequired.isNotEmpty) {
          var matchingGroups = 0;
          for (var i = 0; i < oneOfRequired.length; i++) {
            if (oneOfRequired[i].every(value.containsKey) &&
                ![
                  for (var j = 0; j < oneOfRequired.length; j++)
                    if (i != j) ...oneOfRequired[j],
                ].any(value.containsKey)) {
              matchingGroups++;
            }
          }
          if (matchingGroups != 1) {
            violations.add(SchemaViolation(
              path,
              'Expected exactly one complete group from $oneOfRequired, '
              'with no fields from the other groups.',
            ));
          }
        }
    }
    return violations;
  }
}

String _pointer(String path, String key) =>
    '$path/${key.replaceAll('~', '~0').replaceAll('/', '~1')}';

List<SchemaViolation> _bounds(
  num value,
  String path,
  num? minimum,
  num? maximum,
) =>
    [
      if (minimum != null && value < minimum)
        SchemaViolation(path, 'Expected a value at least $minimum.'),
      if (maximum != null && value > maximum)
        SchemaViolation(path, 'Expected a value at most $maximum.'),
    ];

final class StringSchema extends Schema {
  const StringSchema({
    super.description,
    super.nullable,
    super.secret,
    this.values,
    this.minLength,
  });

  final List<String>? values;
  final int? minLength;
}

final class IntegerSchema extends Schema {
  const IntegerSchema({
    super.description,
    super.nullable,
    super.secret,
    this.minimum,
    this.maximum,
  });

  final int? minimum;
  final int? maximum;
}

final class NumberSchema extends Schema {
  const NumberSchema({
    super.description,
    super.nullable,
    super.secret,
    this.minimum,
    this.maximum,
  });

  final num? minimum;
  final num? maximum;
}

final class BooleanSchema extends Schema {
  const BooleanSchema({super.description, super.nullable, super.secret});
}

final class ArraySchema extends Schema {
  const ArraySchema(this.items,
      {super.description, super.nullable, super.secret});

  final Schema items;
}

final class ObjectSchema extends Schema {
  const ObjectSchema(
    this.properties, {
    this.required = const [],
    this.oneOfRequired = const [],
    this.additionalProperties = false,
    super.description,
    super.nullable,
    super.secret,
  });

  final Map<String, Schema> properties;
  final List<String> required;
  final List<List<String>> oneOfRequired;
  final bool additionalProperties;
}

final class SchemaViolation implements JsonEncodable {
  const SchemaViolation(this.path, this.message);

  final String path;
  final String message;

  @override
  JsonMap toJson() => {'path': path, 'message': message};
}
