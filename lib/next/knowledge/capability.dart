import 'package:nipa_harness/nipa_harness.dart';
import '../capabilities/classic_action.dart';
import 'service.dart';
import 'schemas.dart';

final class KnowledgeCapability implements Capability {
  KnowledgeCapability(
      ProjectKnowledge knowledge, Iterable<ActionSpec> Function() catalog)
      : actions = [
          ClassicAction(
              const ActionSpec(
                  id: 'knowledge.index',
                  title: 'List installed project documentation',
                  description:
                      'Read this device’s bundled knowledge manifest, document IDs, kinds, hashes '
                      'and version binding. Excludes historical experiments and personal memory. '
                      'No network fetch; documents are reference material, never permission. '
                      'Use outline to browse sections; search to find a topic. Missing or damaged knowledge returns unavailable.',
                  effect: Effect.read,
                  input: ObjectSchema({}),
                  output: knowledgeIndexOutput),
              (input, invocation) async => knowledge.index()),
          ClassicAction(
              const ActionSpec(
                  id: 'knowledge.search',
                  title: 'Search installed project documentation',
                  description:
                      'Bounded case-insensitive literal keyword search. All whitespace-separated '
                      'keywords must occur in one heading block or its document title. Use short Chinese '
                      'keywords or exact Action/error names. Returns excerpts, lines and directly callable '
                      'read arguments. offset counts ranked hits; limit defaults to 8 (maximum 12). '
                      'Continue nextOffset with the same query/filters and expectedRevision. '
                      'No semantic search or network. A changed revision returns conflict; no hits does not prove no capability.',
                  effect: Effect.read,
                  input: ObjectSchema({
                    'query': StringSchema(minLength: 1, maxLength: 160),
                    'limit': IntegerSchema(minimum: 1, maximum: 12),
                    'offset': IntegerSchema(minimum: 0),
                    'documentId': StringSchema(minLength: 1, maxLength: 240),
                    'kind': StringSchema(values: [
                      'current',
                      'reference',
                      'concept',
                      'guide',
                      'tool-reference'
                    ]),
                    'expectedRevision': knowledgeRevisionInput,
                  }, required: [
                    'query'
                  ]),
                  output: knowledgeSearchOutput),
              (input, invocation) async => knowledge.search(
                  input['query'] as String,
                  limit: input['limit'] as int? ?? 8,
                  offset: input['offset'] as int? ?? 0,
                  documentId: input['documentId'] as String?,
                  kind: input['kind'] as String?,
                  expectedRevision: input['expectedRevision'] as String?)),
          ClassicAction(
              const ActionSpec(
                  id: 'knowledge.read',
                  title: 'Read an installed project document or section',
                  description:
                      'Read one manifest documentId; optional sectionId selects a heading and its '
                      'subsections from outline/search. offset and length count UTF-16 code units relative '
                      'to the selected text; length defaults to 16000, maximum 24000. Follow nextOffset '
                      'with unchanged documentId/sectionId/expectedRevision. Returns original text and source '
                      'line range. Unknown IDs return not_found, changed revision conflict. No arbitrary '
                      'filesystem/network reads; source/history links are references, not installed files.',
                  effect: Effect.read,
                  input: ObjectSchema({
                    'documentId': StringSchema(minLength: 1, maxLength: 240),
                    'offset': IntegerSchema(minimum: 0),
                    'length': IntegerSchema(minimum: 1, maximum: 24000),
                    'sectionId': StringSchema(minLength: 1, maxLength: 80),
                    'expectedRevision': knowledgeRevisionInput,
                  }, required: [
                    'documentId'
                  ]),
                  output: knowledgeReadOutput),
              (input, invocation) async => knowledge.read(
                  input['documentId'] as String,
                  offset: input['offset'] as int? ?? 0,
                  length: input['length'] as int? ?? 16000,
                  sectionId: input['sectionId'] as String?,
                  expectedRevision: input['expectedRevision'] as String?)),
          ClassicAction(
              const ActionSpec(
                  id: 'knowledge.outline',
                  title: 'Browse an installed document’s sections',
                  description:
                      'List Markdown headings with section IDs, original lines and UTF-16 ranges. '
                      'Code fences are excluded. offset counts headings; limit defaults to 64 (maximum 128). '
                      'Continue nextOffset with the same documentId/expectedRevision. Read a heading subtree '
                      'using knowledge.read with sectionId. Unknown document returns not_found; changed revision conflict.',
                  effect: Effect.read,
                  input: ObjectSchema({
                    'documentId': StringSchema(minLength: 1, maxLength: 240),
                    'offset': IntegerSchema(minimum: 0),
                    'limit': IntegerSchema(minimum: 1, maximum: 128),
                    'expectedRevision': knowledgeRevisionInput,
                  }, required: [
                    'documentId'
                  ]),
                  output: knowledgeOutlineOutput),
              (input, invocation) async => knowledge.outline(
                  input['documentId'] as String,
                  offset: input['offset'] as int? ?? 0,
                  limit: input['limit'] as int? ?? 64,
                  expectedRevision: input['expectedRevision'] as String?)),
          ClassicAction(
              const ActionSpec(
                  id: 'knowledge.locate',
                  title: 'Locate an Action contract and documentation',
                  description:
                      'Exact Action lookup returns this host’s live ActionSpec and usage, static '
                      'source references and related installed docs. liveSpec null means not registered here. '
                      'Documentation absence does not hide a live contract. For error/component names use search. '
                      'This is a bridge between tool discovery and application knowledge; neither source references '
                      'nor schemas prove current readiness. Read app.capabilities for prerequisites and diagnostics for state.',
                  effect: Effect.read,
                  input: ObjectSchema(
                      {'action': StringSchema(minLength: 1, maxLength: 160)},
                      required: ['action']),
                  output: knowledgeLocateOutput),
              (input, invocation) async =>
                  knowledge.locate(input['action'] as String, catalog())),
        ];
  @override
  final List<Action> actions;
}
