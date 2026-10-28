import 'package:nipa_harness/nipa_harness.dart';

const knowledgeRevisionInput = StringSchema(
    minLength: 1,
    maxLength: 64,
    description:
        'contentRevision from provenance. A changed snapshot returns conflict; restart navigation.');
const knowledgeProvenanceSchema = ObjectSchema({
  'appVersion': StringSchema(),
  'sourceCommit': StringSchema(nullable: true),
  'sourceDirty': BooleanSchema(nullable: true),
  'contentRevision': StringSchema(),
  'runtimeBuild': ObjectSchema({}, additionalProperties: true),
  'binding':
      StringSchema(values: ['matched', 'modified', 'mismatch', 'unverified']),
  'authority': StringSchema(),
}, required: [
  'contentRevision',
  'binding'
]);
const knowledgeReferenceProperties = <String, Schema>{
  'documentId': StringSchema(),
  'title': StringSchema(),
  'kind': StringSchema(),
  'sha256': StringSchema(),
  'sourceUrl': StringSchema(nullable: true),
};
const knowledgeReferenceSchema = ObjectSchema(knowledgeReferenceProperties,
    required: ['documentId', 'title', 'kind', 'sha256']);
const knowledgeSectionSchema = ObjectSchema({
  'sectionId': StringSchema(),
  'title': StringSchema(),
  'level': IntegerSchema(),
  'startOffset': IntegerSchema(),
  'endOffset': IntegerSchema(),
  'startLine': IntegerSchema(),
}, required: [
  'sectionId',
  'title',
  'startOffset',
  'endOffset',
  'startLine'
]);
const knowledgeSearchResultSchema = ObjectSchema({
  ...knowledgeReferenceProperties,
  'line': IntegerSchema(),
  'section': StringSchema(),
  'sectionId': StringSchema(),
  'excerpt': StringSchema(),
  'score': IntegerSchema(),
  'read': ObjectSchema({
    'documentId': StringSchema(),
    'sectionId': StringSchema(),
    'expectedRevision': StringSchema()
  }, required: [
    'documentId',
    'sectionId',
    'expectedRevision'
  ]),
}, required: [
  'documentId',
  'sectionId',
  'line',
  'excerpt',
  'read'
]);
const knowledgeIndexOutput = ObjectSchema({
  'provenance': knowledgeProvenanceSchema,
  'documents': ArraySchema(knowledgeReferenceSchema),
  'sourceActionCount': IntegerSchema(),
  'historyIncluded': BooleanSchema(),
  'next': StringSchema(),
}, required: [
  'provenance',
  'documents'
]);
const knowledgeOutlineOutput = ObjectSchema({
  ...knowledgeReferenceProperties,
  'provenance': knowledgeProvenanceSchema,
  'sections': ArraySchema(knowledgeSectionSchema),
  'sectionCount': IntegerSchema(),
  'offset': IntegerSchema(),
  'nextOffset': IntegerSchema(nullable: true),
}, required: [
  'provenance',
  'documentId',
  'sections',
  'nextOffset'
]);
const knowledgeReadOutput = ObjectSchema({
  ...knowledgeReferenceProperties,
  'provenance': knowledgeProvenanceSchema,
  'sectionId': StringSchema(nullable: true),
  'offset': IntegerSchema(),
  'documentOffset': IntegerSchema(),
  'nextOffset': IntegerSchema(nullable: true),
  'totalLength': IntegerSchema(),
  'startLine': IntegerSchema(),
  'endLine': IntegerSchema(),
  'content': StringSchema(),
  'links': StringSchema(),
}, required: [
  'provenance',
  'documentId',
  'content',
  'nextOffset'
]);
const knowledgeSearchOutput = ObjectSchema({
  'provenance': knowledgeProvenanceSchema,
  'query': StringSchema(),
  'matchCount': IntegerSchema(),
  'offset': IntegerSchema(),
  'nextOffset': IntegerSchema(nullable: true),
  'truncated': BooleanSchema(),
  'results': ArraySchema(knowledgeSearchResultSchema),
  'searchMode': StringSchema(),
}, required: [
  'provenance',
  'results',
  'nextOffset',
  'matchCount'
]);
const knowledgeLocateOutput = ObjectSchema({
  'action': StringSchema(),
  'registeredOnThisHost': BooleanSchema(),
  'liveSpec': ObjectSchema({}, additionalProperties: true, nullable: true),
  'provenance': ObjectSchema({}, additionalProperties: true, nullable: true),
  'knowledgeStatus': StringSchema(values: ['available', 'unavailable']),
  'sourceReferences': ArraySchema(ObjectSchema(
      {'path': StringSchema(), 'sourceUrl': StringSchema(nullable: true)},
      required: ['path', 'sourceUrl'])),
  'documents': ArraySchema(knowledgeSearchResultSchema),
  'next': StringSchema(),
}, required: [
  'action',
  'registeredOnThisHost',
  'liveSpec',
  'knowledgeStatus'
]);
