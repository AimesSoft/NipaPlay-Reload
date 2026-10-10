import 'package:nipa_harness/nipa_harness.dart';
import 'package:test/test.dart';

void main() {
  group('scalar validation', () {
    test('string type, enum and length', () {
      const schema = StringSchema(values: ['ok', 'yes'], minLength: 2);
      for (final value in ['ok', 'yes']) {
        expect(schema.validate(value), isEmpty);
      }
      for (final value in [1, true, <Object?>[], <String, Object?>{}, null]) {
        expect(schema.validate(value).single.path, '');
      }
      expect(schema.validate('x'), hasLength(2));
      expect(schema.validate('other'), hasLength(1));
      expect(const StringSchema(minLength: 2).validate('😀'), hasLength(1));
      expect(const StringSchema(minLength: 1).validate('😀'), isEmpty);
    });

    test('integer accepts integral double and enforces inclusive bounds', () {
      const schema = IntegerSchema(minimum: 1, maximum: 3);
      for (final value in [1, 2, 3, 1.0, 3.0]) {
        expect(schema.validate(value), isEmpty);
      }
      for (final value in [
        0,
        4,
        1.5,
        '2',
        true,
        <Object?>[],
        <String, Object?>{},
        null,
        double.nan,
        double.infinity
      ]) {
        expect(schema.validate(value).single.path, '');
      }
    });

    test('number accepts int and double and enforces bounds', () {
      const schema = NumberSchema(minimum: -1, maximum: 2.5);
      for (final value in [-1, 0, 1.5, 2.5]) {
        expect(schema.validate(value), isEmpty);
      }
      for (final value in [
        -2,
        3,
        '1',
        true,
        <Object?>[],
        <String, Object?>{},
        null
      ]) {
        expect(schema.validate(value).single.path, '');
      }
      expect(const NumberSchema().validate(double.infinity), isEmpty);
    });

    test('boolean accepts only booleans', () {
      const schema = BooleanSchema();
      expect(schema.validate(true), isEmpty);
      expect(schema.validate(false), isEmpty);
      for (final value in [
        0,
        1,
        'true',
        <Object?>[],
        <String, Object?>{},
        null
      ]) {
        expect(schema.validate(value).single.path, '');
      }
    });
  });

  test('all schema types enforce nullable', () {
    const schemas = <Schema>[
      StringSchema(),
      IntegerSchema(),
      NumberSchema(),
      BooleanSchema(),
      ArraySchema(StringSchema()),
      ObjectSchema({}),
    ];
    const nullable = <Schema>[
      StringSchema(nullable: true, values: ['yes'], minLength: 3),
      IntegerSchema(nullable: true, minimum: 1),
      NumberSchema(nullable: true, maximum: 2),
      BooleanSchema(nullable: true),
      ArraySchema(StringSchema(), nullable: true),
      ObjectSchema({'name': StringSchema()},
          required: ['name'], nullable: true),
    ];
    for (final schema in schemas) {
      expect(schema.validate(null).single.path, '');
    }
    for (final schema in nullable) {
      expect(schema.validate(null), isEmpty);
      expect(schema.toJsonSchema()['type'], isA<List<Object?>>());
      expect(schema.toJsonSchema()['type'], contains('null'));
    }
  });

  test('arrays validate every item', () {
    const schema = ArraySchema(IntegerSchema());
    expect(schema.validate([1, 2.0]), isEmpty);
    expect(schema.validate([1.2, 'bad']).map((v) => v.path), ['/0', '/1']);
    for (final value in [1, true, 'list', <String, Object?>{}, null]) {
      expect(schema.validate(value).single.path, '');
    }
  });

  group('objects', () {
    const schema = ObjectSchema({
      'name': StringSchema(minLength: 1),
      'count': IntegerSchema(),
    }, required: [
      'name'
    ]);

    test('required, unknown fields and all value violations', () {
      expect(schema.validate({'name': 'ok', 'count': 1.0}), isEmpty);
      expect(schema.validate({}).single.path, '/name');
      expect(
          schema.validate({'name': '', 'count': 'bad', 'extra': 1}).map(
              (v) => v.path),
          ['/extra', '/name', '/count']);
    });

    test('objects reject other types and non-string keys', () {
      for (final value in [1, true, 'object', <Object?>[], null]) {
        expect(schema.validate(value).single.path, '');
      }
      final violations = schema.validate({7: 'bad', 'name': ''});
      expect(violations.map((v) => v.path), ['', '/name']);
      expect(violations.first.message, contains('strings'));
    });

    test('nested paths and JSON Pointer escaping', () {
      const nested = ObjectSchema({
        'episodes': ArraySchema(ObjectSchema({
          'path': StringSchema(),
          'a~/b': IntegerSchema(),
        }, required: [
          'path'
        ])),
      });
      final violations = nested.validate({
        'episodes': [
          {'path': 1, 'a~/b': false},
          {'extra/key~': 1},
        ],
      });
      expect(violations.map((v) => v.path), [
        '/episodes/0/path',
        '/episodes/0/a~0~1b',
        '/episodes/1/extra~1key~0',
        '/episodes/1/path',
      ]);
    });

    test('oneOfRequired accepts exactly one complete and exclusive group', () {
      const exclusive = ObjectSchema({
        'path': StringSchema(),
        'animeId': IntegerSchema(),
        'episodeId': IntegerSchema(),
      }, oneOfRequired: [
        ['path'],
        ['animeId', 'episodeId']
      ]);
      for (final value in [
        {'path': 'file'},
        {'animeId': 1, 'episodeId': 2},
      ]) {
        expect(exclusive.validate(value), isEmpty);
      }
      for (final value in [
        <String, Object?>{},
        {'animeId': 1},
        {'path': 'file', 'animeId': 1, 'episodeId': 2},
        {'path': 'file', 'animeId': 1},
      ]) {
        final violation = exclusive.validate(value).single;
        expect(violation.path, '');
        expect(violation.message, contains('[path]'));
        expect(violation.message, contains('[animeId, episodeId]'));
      }
    });
  });

  group('JSON Schema serialization', () {
    test('exact scalar schemas and omission of unset constraints', () {
      expect(const StringSchema().toJsonSchema(), {'type': 'string'});
      expect(const IntegerSchema().toJsonSchema(), {'type': 'integer'});
      expect(const NumberSchema().toJsonSchema(), {'type': 'number'});
      expect(const BooleanSchema().toJsonSchema(), {'type': 'boolean'});
      expect(
          const StringSchema(
                  description: 'Name',
                  nullable: true,
                  values: ['one', 'two'],
                  minLength: 1)
              .toJsonSchema(),
          {
            'type': ['string', 'null'],
            'description': 'Name',
            'enum': ['one', 'two'],
            'minLength': 1,
          });
      expect(
          const IntegerSchema(
                  description: 'Count', nullable: true, minimum: 0, maximum: 3)
              .toJsonSchema(),
          {
            'type': ['integer', 'null'],
            'description': 'Count',
            'minimum': 0,
            'maximum': 3,
          });
      expect(const NumberSchema(minimum: 0.5, maximum: 2).toJsonSchema(), {
        'type': 'number',
        'minimum': 0.5,
        'maximum': 2,
      });
      expect(
          const BooleanSchema(nullable: true, description: 'Flag')
              .toJsonSchema(),
          {
            'type': ['boolean', 'null'],
            'description': 'Flag',
          });
    });

    test('exact array and object schemas', () {
      expect(
          const ArraySchema(StringSchema(),
                  description: 'Names', nullable: true)
              .toJsonSchema(),
          {
            'type': ['array', 'null'],
            'description': 'Names',
            'items': {'type': 'string'},
          });
      expect(const ObjectSchema({}).toJsonSchema(), {
        'type': 'object',
        'properties': <String, Object?>{},
        'additionalProperties': false,
      });
      expect(
          const ObjectSchema(
              {
                'path': StringSchema(minLength: 1),
                'ids': ArraySchema(IntegerSchema()),
              },
              description: 'Input',
              nullable: true,
              required: ['path'],
              oneOfRequired: [
                ['path'],
                ['ids']
              ]).toJsonSchema(),
          {
            'type': ['object', 'null'],
            'description': 'Input',
            'properties': {
              'path': {'type': 'string', 'minLength': 1},
              'ids': {
                'type': 'array',
                'items': {'type': 'integer'}
              },
            },
            'required': ['path'],
            'additionalProperties': false,
            'oneOf': [
              {
                'required': ['path']
              },
              {
                'required': ['ids']
              }
            ],
          });
    });

    test('SchemaViolation serializes its pointer and message', () {
      expect(const SchemaViolation('/path', 'Wrong type.').toJson(), {
        'path': '/path',
        'message': 'Wrong type.',
      });
    });
  });
}
