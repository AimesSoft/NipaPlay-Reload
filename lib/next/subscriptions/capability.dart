import 'package:nipa_harness/nipa_harness.dart';
import '../capabilities/classic_action.dart';
import '../state/query.dart';
import 'store.dart';

const _id = StringSchema(minLength: 1, maxLength: 160);
const subscriptionStateSchema =
    StringSchema(values: ['active', 'paused', 'ended']);
const subscriptionReportSchema = ObjectSchema({
  'id': _id,
  'reportId': _id,
  'checkedAt': StringSchema(minLength: 1, maxLength: 64),
  'found': ArraySchema(
      ObjectSchema({
        'title': StringSchema(maxLength: 500),
        'key': _id,
        'episode': StringSchema(maxLength: 80, nullable: true),
      }, required: [
        'title'
      ]),
      maxItems: 100),
  'downloads': ArraySchema(
      ObjectSchema({
        'jobId': _id,
        'title': StringSchema(maxLength: 500),
        'episode': StringSchema(maxLength: 80, nullable: true),
      }, required: [
        'jobId',
        'title'
      ]),
      maxItems: 100),
  'errors': ArraySchema(StringSchema(maxLength: 1000), maxItems: 20),
}, required: [
  'id',
  'reportId',
  'checkedAt',
  'found',
  'downloads',
  'errors'
]);

const subscriptionFields = ObjectSchema({
  'id': _id,
  'title': StringSchema(minLength: 1, maxLength: 300),
  'kind': StringSchema(values: ['series', 'movie']),
  'workId': StringSchema(minLength: 1, nullable: true),
  'state': subscriptionStateSchema,
  'note': StringSchema(maxLength: 500),
  'program': StringSchema(minLength: 1, maxLength: 500),
  'facts': ObjectSchema({},
      additionalProperties: true,
      description:
          'Agent-owned JSON, at most 16384 UTF-8 bytes; store secret names, never values.'),
  'createdBy': StringSchema(minLength: 1, maxLength: 500),
  'createdAt': StringSchema(),
  'updatedAt': StringSchema(),
  'revision': IntegerSchema(),
  'latestReport': ObjectSchema({}, additionalProperties: true, nullable: true),
  'latestDownloads': ArraySchema(ObjectSchema({}, additionalProperties: true)),
  'reports': ArraySchema(ObjectSchema({}, additionalProperties: true)),
});

final class SubscriptionCapability implements Capability {
  SubscriptionCapability(this.store);
  final SubscriptionStore store;
  @override
  List<Action> get actions => [
        ClassicAction(
            ActionSpec(
                id: 'subscription.put',
                title: '保存订阅',
                description:
                    '保存梨花声明的订阅（完整替换可写字段）。不执行程序、不判断来源或下载。只在用户明确要求订阅后建立；每设备最多 500 条。',
                effect: Effect.write,
                input: ObjectSchema({
                  for (final key in [
                    'id',
                    'title',
                    'kind',
                    'workId',
                    'state',
                    'note',
                    'program',
                    'facts',
                    'createdBy'
                  ])
                    key: subscriptionFields.properties[key]!
                }, required: const [
                  'title',
                  'kind',
                  'note',
                  'program',
                  'createdBy'
                ]),
                output: subscriptionFields),
            (input, _) => store.put(input)),
        ClassicAction(
            const ActionSpec(
                id: 'subscription.list',
                title: '列出订阅',
                description: '本设备的订阅及最新检查，按创建时间与 ID 排序；offset 分页。不会启动巡查。',
                effect: Effect.read,
                input: ObjectSchema({
                  'state': subscriptionStateSchema,
                  'offset': IntegerSchema(minimum: 0),
                  'limit': IntegerSchema(minimum: 1, maximum: 500)
                }),
                output: ObjectSchema(
                    {'subscriptions': ArraySchema(subscriptionFields)},
                    required: ['subscriptions'])),
            (input, _) async => {
                  'subscriptions': await store.list(
                      state: input['state'] as String?,
                      offset: input['offset'] as int? ?? 0,
                      limit: input['limit'] as int? ?? 100)
                }),
        ClassicAction(
            const ActionSpec(
                id: 'subscription.get',
                title: '读取订阅',
                description: '本设备的订阅及最近 20 次脚本回报；回报是脚本提供的事实。',
                effect: Effect.read,
                input: ObjectSchema({'id': _id}, required: ['id']),
                output: subscriptionFields),
            (input, _) => store.get(input['id'] as String)),
        ClassicAction(
            const ActionSpec(
                id: 'subscription.remove',
                title: '删除订阅记录',
                description: '只删除订阅与检查记录，保留文件、下载任务和 harness 程序。',
                effect: Effect.write,
                input: ObjectSchema({'id': _id}, required: ['id']),
                output: ObjectSchema({'id': _id, 'removed': BooleanSchema()},
                    required: ['id', 'removed'])),
            (input, _) => store.remove(input['id'] as String)),
        ClassicAction(
            const ActionSpec(
                id: 'subscription.set_state',
                title: '修改订阅状态',
                description:
                    '设置 active、paused 或 ended；巡查脚本读取 active，已发起的下载不受影响。',
                effect: Effect.write,
                input: ObjectSchema(
                    {'id': _id, 'state': subscriptionStateSchema},
                    required: ['id', 'state']),
                output: subscriptionFields),
            (input, _) => store.setState(
                input['id'] as String, input['state'] as String)),
        ClassicAction(
            const ActionSpec(
                id: 'subscription.report',
                title: '记录一次订阅检查',
                description:
                    '保存时间、候选、下载和错误；最近 20 次，每次最多 32768 字节。同一 reportId 同内容可重试，不同内容冲突。不验证脚本判断，不自动绑定。',
                effect: Effect.write,
                input: subscriptionReportSchema,
                output: subscriptionFields),
            (input, _) => store.report(input)),
      ];
}

void registerSubscriptions(StateCapability state, SubscriptionStore store) {
  state.views['subscriptions'] = StateView(
      name: 'subscriptions',
      description: '本设备订阅和最新脚本检查；规则属于梨花，不含凭据值。',
      fields: subscriptionFields,
      read: (offset, limit) => store.list(offset: offset, limit: limit));
}
