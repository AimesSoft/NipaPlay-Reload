import 'package:nipa_harness/nipa_harness.dart';

import '../capabilities/classic_action.dart';
import 'service.dart';

/// Direct access to next.db beside the dedicated actions.
final class DbCapability implements Capability {
  DbCapability(DbService service)
      : actions = [
          ClassicAction(
            const ActionSpec(
              id: 'db.describe',
              title: 'Describe next.db',
              description:
                  'Every table of next.db with its columns, primary key, foreign keys, indexes and CREATE statement, what the table means, whether db.write may change it and why, and the cross-table rules (semantics): how classic_match bindings and media_classic_* are re-imported on sync, that media_overrides beat snapshots, where artwork overrides live, what is not projected to Classic. Pass tables to read only some. Credentials are not in this database.',
              effect: Effect.read,
              input: ObjectSchema({
                'tables': ArraySchema(StringSchema(minLength: 1), minItems: 1)
              }),
              output: ObjectSchema({}, additionalProperties: true),
            ),
            (input, invocation) => service.describe(input),
          ),
          ClassicAction(
            ActionSpec(
              id: 'db.query',
              title: 'Read next.db with SQL',
              description:
                  'Run one SELECT (WITH … SELECT, VALUES) against next.db. params (optional array of null, number, string, boolean or {"\$blob":base64}) bind to ? by position. SQLite refuses anything that is not a select and the connection is query_only, so nothing can change. Results are capped by limit (default ${dbQueryLimits.defaultRows}, max ${dbQueryLimits.maxRows}) and maxBytes (default ${dbQueryLimits.defaultBytes}, max ${dbQueryLimits.maxBytes}); when cut, truncated is true and nextOffset is where to continue (add ORDER BY so pages are stable). Long text cells are cut at ${dbQueryLimits.cellChars} characters. Secrets in values are masked. Use db.describe for tables and meanings.',
              effect: Effect.read,
              input: const ObjectSchema({
                'sql': StringSchema(minLength: 1, maxLength: 20000),
                'limit': IntegerSchema(minimum: 1, maximum: 1000),
                'offset': IntegerSchema(minimum: 0),
                'maxBytes': IntegerSchema(minimum: 1024, maximum: 1048576),
              }, required: [
                'sql'
              ], additionalProperties: true),
              output: const ObjectSchema({}, additionalProperties: true),
            ),
            (input, invocation) => service.query(input),
          ),
          ClassicAction(
            const ActionSpec(
              id: 'db.write',
              title: 'Write next.db with SQL',
              description:
                  'Change next.db with a batch of INSERT/UPDATE/DELETE (statements: [{sql, params?}], at most 100, one statement each, unqualified table names, no RETURNING; see db.describe semantics.sql_dialect). Without previewId it only previews: the batch runs in a transaction that is rolled back, and the result lists, per table, the rows inserted, updated and deleted with their before/after values, plus a previewId. With previewId it commits exactly what was previewed; if the rows it touches changed since, it refuses and writes nothing. Only tables db.describe marks writable can change (SQLite aborts the statement otherwise); DDL, PRAGMA, ATTACH and transaction control are refused by SQLite; foreign keys, JSON columns and a few invariants are checked and a violation rolls everything back. A commit is recorded in db_commits (SQL, parameters, counts, before/after images, origin, invocationId, actor) and activity, announces media.assets.changed for the affected entities and refreshes the views that read them. It is not projected to Classic (media_projection_outbox is untouched). Undo with db.undo.',
              effect: Effect.write,
              input: ObjectSchema({
                'statements': ArraySchema(
                    ObjectSchema({
                      'sql': StringSchema(minLength: 1, maxLength: 20000),
                    }, required: [
                      'sql'
                    ], additionalProperties: true),
                    minItems: 1,
                    maxItems: 100),
                'previewId': StringSchema(minLength: 1),
                'reason': StringSchema(minLength: 1, maxLength: 500),
              }),
              output: ObjectSchema({}, additionalProperties: true),
            ),
            (input, invocation) {
              if (!input.containsKey('statements') &&
                  !input.containsKey('previewId')) {
                throw const Failure(FailureCode.invalidInput,
                    'Supply statements to preview, or previewId to commit a preview.');
              }
              return service.write(input, invocation);
            },
          ),
          ClassicAction(
            const ActionSpec(
              id: 'db.undo',
              title: 'Undo a direct database write',
              description:
                  'Restore the before-images of commit commitId (from db.write or a previous db.undo). Every row the commit changed must still equal what the commit left; otherwise nothing is undone and the conflicting rows are listed. dryRun:true shows what would be restored without writing. The undo is itself a commit with its own commitId, audited and undoable, and refreshes the same views.',
              effect: Effect.write,
              input: ObjectSchema({
                'commitId': StringSchema(minLength: 1),
                'dryRun': BooleanSchema(),
                'reason': StringSchema(minLength: 1, maxLength: 500),
              }, required: [
                'commitId'
              ]),
              output: ObjectSchema({}, additionalProperties: true),
            ),
            (input, invocation) => service.undo(input, invocation),
          ),
        ];
  @override
  final List<Action> actions;
}
