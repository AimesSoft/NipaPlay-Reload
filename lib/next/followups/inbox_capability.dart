import 'package:nipa_harness/nipa_harness.dart';
import '../capabilities/classic_action.dart';
import '../settings/registry.dart';
import 'service.dart';

const _id = StringSchema(minLength: 1, maxLength: 200);
const _output = ObjectSchema({}, additionalProperties: true);

final class InboxCapability implements Capability {
  InboxCapability(Followups service)
      : actions = [
          ClassicAction(
              const ActionSpec(
                  id: 'ui.notify',
                  title: '提醒用户',
                  effect: Effect.write,
                  description:
                      'Publish a durable nonmodal reminder immediately. You decide whether and when to notify and write its title/body; no automatic completion summary. Same requestId and content returns the original reminder. Hiding or reading is not consent. severity error displays the error text supplied without replacing it with a generic message. UI popup preference does not delete the inbox entry.',
                  input: ObjectSchema({
                    'requestId': _id,
                    'title': StringSchema(minLength: 1, maxLength: 200),
                    'body': StringSchema(minLength: 1, maxLength: 16000),
                    'severity': StringSchema(values: ['info', 'error'])
                  }, required: [
                    'requestId',
                    'title',
                    'body'
                  ]),
                  output: _output),
              (input, invocation) =>
                  service.publishInbox(input, invocation, question: false)),
          ClassicAction(
              const ActionSpec(
                  id: 'ui.ask',
                  title: '异步询问用户',
                  effect: Effect.write,
                  description:
                      'Publish a persistent question immediately and return pending without blocking the Agent turn. Continue independent work; wait only for actions requiring this answer. Requires an originating embedded conversation. User may choose an option or type any answer; closing the popup is not consent. The answer is delivered to the originating device/conversation, via steer when supported or a later turn. Same requestId/content is idempotent. Never answer your own question through inbox.respond. Do not automatically treat any label as permission to change settings; interpret the actual user answer and scope.',
                  input: ObjectSchema({
                    'requestId': _id,
                    'title': StringSchema(minLength: 1, maxLength: 200),
                    'body': StringSchema(minLength: 1, maxLength: 16000),
                    'options': ArraySchema(
                        StringSchema(minLength: 1, maxLength: 200),
                        maxItems: 6)
                  }, required: [
                    'requestId',
                    'title',
                    'body'
                  ]),
                  output: _output),
              (input, invocation) =>
                  service.publishInbox(input, invocation, question: true)),
          ClassicAction(
              const ActionSpec(
                  id: 'ui.inbox.list',
                  title: '读取提醒与待答问题',
                  effect: Effect.read,
                  description:
                      'Read this device inbox, including hidden unanswered questions. Pagination is newest first. includeResolved also includes answered/cancelled questions and read notices. popupsEnabled controls presentation only. A published reminder does not prove its task succeeded.',
                  input: ObjectSchema({
                    'offset': IntegerSchema(minimum: 0),
                    'limit': IntegerSchema(minimum: 1, maximum: 50),
                    'includeResolved': BooleanSchema()
                  }),
                  output: _output),
              (input, _) => service.inboxList(
                  offset: input['offset'] as int? ?? 0,
                  limit: input['limit'] as int? ?? 30,
                  includeResolved: input['includeResolved'] == true)),
          ClassicAction(
              const ActionSpec(
                  id: 'ui.inbox.respond',
                  title: '回答提醒中的问题',
                  effect: Effect.write,
                  description:
                      'Viewer response transport, not an Agent decision tool. Records an explicit user answer and its durable delivery atomically. Repeating the same answer returns the same record; a different answer to a resolved question conflicts. Answer belongs to the saved target, never the currently selected chat.',
                  input: ObjectSchema({
                    'id': _id,
                    'answer': StringSchema(minLength: 1, maxLength: 16000)
                  }, required: [
                    'id',
                    'answer'
                  ]),
                  output: _output), (input, invocation) {
            if (invocation.origin != 'gui' &&
                !invocation.origin.startsWith('mesh:')) {
              throw const Failure(FailureCode.invalidInput,
                  'Only the viewer UI may submit an answer.');
            }
            return service.answerInbox(
                input['id'] as String, input['answer'] as String, invocation);
          }),
          ClassicAction(
              const ActionSpec(
                  id: 'ui.inbox.dismiss',
                  title: '收起或取消提醒',
                  effect: Effect.write,
                  description:
                      'Hide a popup. Questions remain pending unless cancel=true; no answer or permission is inferred. Notices become read. Does not cancel associated tasks or revoke existing settings.',
                  input: ObjectSchema({'id': _id, 'cancel': BooleanSchema()},
                      required: ['id']),
                  output: _output),
              (input, _) => service.dismissInbox(input['id'] as String,
                  cancel: input['cancel'] == true)),
        ];
  @override
  final List<Action> actions;
}

List<SettingEntry> inboxSettings(Followups service) {
  SettingEntry entry(String key, String title, String description,
          Schema schema, Object fallback) =>
      SettingEntry(
          key: key,
          title: title,
          description: description,
          schema: schema,
          defaultValue: fallback,
          storageKey: key,
          storageKind: 'database',
          reader: 'AgentInbox',
          writer: 'AgentInbox',
          read: () => service.inboxPreference(key, fallback),
          write: (v) => service.setInboxPreference(key, v),
          decodeStorage: (v) => v ?? fallback);
  return [
    entry(
        'notification.agentPopups',
        '梨花提醒浮窗',
        '显示梨花主动发出的提醒和问题。关闭后仍保留在提醒列表；失败错误仍显示。收起问题不等于同意。',
        const BooleanSchema(),
        true),
    entry(
        'library.organizeAddedFolders',
        '添加文件夹后交给梨花整理',
        '仅 GUI 明确添加文件夹后，扫描结束将结果交给梨花识别、补资料。后台新文件、启动扫描、手动重新扫描不触发。需要可运行的梨花；未运行时排队。关闭会取消尚未投递的整理请求，已经开始的任务需另外停止。',
        const BooleanSchema(),
        true),
    entry(
        'library.fileOrganization',
        '目录和文件名整理',
        '询问：梨花异步询问，继续整理资料；保持原样：不询问也不移动；自动：授权梨花按下方规则整理以后明确添加的文件夹。只适用于本次根目录，不授权删除、覆盖、移出根目录或破坏做种。规则冲突和无法保持身份进度关联的文件应跳过报告。',
        const StringSchema(values: ['ask', 'off', 'auto']),
        'ask'),
    entry(
        'library.fileOrganizationRules',
        '目录和文件名规则',
        '交给梨花的长期整理规则，可在这里或通过对话修改。只在已授权范围内生效；不隐含删除、覆盖或跨目录搬运权限。',
        const StringSchema(minLength: 1, maxLength: 4000),
        defaultFolderRules),
  ];
}
