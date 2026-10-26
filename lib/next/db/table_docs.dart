/// What each table of `next.db` is, and who may change it through `db.write`.
///
/// This file is the contract that `db.describe` serves. A table without an
/// entry here is read-only (default deny), and a test fails until it has one.
enum DbAccess { write, read }

/// How a JSON text column must parse before a `db.write` is committed.
enum DbJson { object, array, any }

final class DbTableDoc {
  const DbTableDoc(this.access, this.summary,
      {this.reason, this.json = const {}, this.notes = const []});
  final DbAccess access;

  /// What a row is.
  final String summary;

  /// Why the table is read-only, or what to mind when writing it.
  final String? reason;

  /// JSON text columns and the shape their parsed value must have.
  final Map<String, DbJson> json;

  /// Facts about particular columns or about how other code reads the table.
  final List<String> notes;
}

const _classicAudit =
    '由 Classic 的观看历史同步（IdentityStore.importLegacy）写入；规则见 semantics.classic_match。';

const dbTableDocs = <String, DbTableDoc>{
  // ── 媒体身份与资料：可写 ──────────────────────────────────────────────
  'media_entities': DbTableDoc(
    DbAccess.write,
    '本机身份实体：作品 work → 版本 release → 剧集 episode，以及文件 file。parent_id 表示层级（file 没有 parent）；文件与剧集的对应在 media_file_episodes。',
    json: {'attributes': DbJson.object},
    notes: [
      'attributes 是 JSON 对象：title、type、number、season、order；localOnly=true 表示本机目录自建的作品；removed=true 是 remove 留下的墓碑（媒体库不显示，进度与来源保留）；file 的 probe、bindingRevision。',
      'revision 是专用原语做乐观并发（expectedRevision）和 Classic 投影的计数；db.write 不会自动递增它。想让专用原语察觉这次修改，自己把 revision 加一。',
      '删除实体前，引用它的行（绑定、位置、对应、覆盖、弹幕绑定、字幕等）必须先处理，否则外键检查会回滚整批。',
    ],
  ),
  'media_locations': DbTableDoc(
    DbAccess.write,
    '文件实体的位置：source（local、remote 或媒体源范围）、owner_device_id（所在设备）、locator（路径或 URL）、available。(source, owner_device_id, locator) 唯一。',
    notes: [
      'locator 指向别的设备或媒体服务器时，本机不能验证；本机路径需在媒体库根目录内才可访问。',
    ],
  ),
  'media_file_episodes': DbTableDoc(
    DbAccess.write,
    '文件 ↔ 剧集的对应，决定哪一集能播放。主键 (file_id, episode_id)；relation 为 exact 或 local_catalog；ordinal 是同一文件内的次序，start_ms/end_ms 是文件内的片段。',
    notes: [
      'relation=local_catalog 是本机目录手工对应（entities.put_batch 的 fileIds）。其他对应的来源由 media_bindings 推出：文件与剧集共同拥有同一个 accepted 的外部对象绑定时，source 取该文件绑定的 source（classic_match 或 explicit_binding）。',
      '同步 Classic 时，没有 accepted 绑定支撑、也不是 local_catalog 的对应会被清理（_pruneFileLinks）。',
    ],
  ),
  'media_external_objects': DbTableDoc(
    DbAccess.write,
    '外部来源对象的登记：provider（dandanplay、bangumi、tmdb…）、object_type、external_id、scope；(provider, object_type, external_id, scope) 唯一。绑定与快照用 id 引用它。',
    notes: [
      'id 必须等于由这四项算出的稳定哈希（专用原语靠它去重）。db.write 会校验新增行，不符时报告正确的 id。',
    ],
  ),
  'media_bindings': DbTableDoc(
    DbAccess.write,
    '实体 ↔ 外部对象的绑定。status 为 proposed、accepted、rejected、revoked，只有 accepted 才算身份；relation（exact、contains…）；scope 是 JSON（order、season、cour、numbers、startMs、endMs）；source 是 explicit_binding 或 classic_match；bound_by 是 user、agent、automatic，classic_match 为 NULL。',
    json: {'scope': DbJson.object},
    notes: [
      'source=classic_match 的绑定来自 Classic 观察，同步规则见 semantics.classic_match。',
      '撤销请把 status 改为 revoked 而不是删除：证据、活动与弹幕绑定通过 id 引用它；删除需先删 media_evidence、media_classic_observations.binding_id 与 supersedes 的引用。',
    ],
  ),
  'media_evidence': DbTableDoc(
    DbAccess.write,
    '绑定的证据与事件记录：payload JSON 含 event（bind、unbind、classic_match）、reason、origin、boundBy、invocationId、observationId。activity 的 identity.* 事件从这里读。',
    json: {'payload': DbJson.object},
    notes: [
      '直接修改绑定不会自动补证据；需要在活动里留下说明时，db.write 的 reason 会记入审计。',
    ],
  ),
  'media_snapshots': DbTableDoc(
    DbAccess.write,
    '外部对象的元数据快照：language、fetched_at、fields（JSON：ref、metadata{title、originalTitle、overview、imageUrl、year、rating…}、source、receivedAt、origin、artworkUrls 等）。',
    json: {'fields': DbJson.object},
    notes: [
      'source 取值：provider_snapshot（在线读取）、submitted_snapshot（Nipa 提交）、classic_match 与 classic_cache（Classic 同步）。合并资料时 classic_match 优先级最低，其余按 绑定在实体自己身上 → fetched_at 新者优先，标题与简介另外中文优先。',
      '快照在 media_overrides 之下：同一字段有覆盖时，快照不会显示。',
    ],
  ),
  'media_overrides': DbTableDoc(
    DbAccess.write,
    '用户或 Nipa 对资料字段的覆盖，主键 (entity_id, field)，value 是 JSON 值。mode 为 persistent 或 correction，actor、origin、changed_at 记录出处。',
    json: {'value': DbJson.any},
    notes: [
      '覆盖优先于所有快照；mode=correction 的覆盖，在出现 fetched_at 更晚的快照后让位。',
      'artwork 覆盖存在这里：field 为 artwork.poster、artwork.backdrop、artwork.logo、artwork.still，value 是 {"url":"https://…"} 或 {"file":"/绝对路径"}。图片缓存是 ui_cache 的 artwork:<实体 id>，随这些字段变化自动重取，不用清缓存。',
      'fieldSources 记录各字段的来源标签（media.metadata.put 维护）；titleLanguage、overviewLanguage 记录语言。',
      '作品级覆盖对作品及其所有版本生效；剧集的覆盖只对该剧集。',
      'media_metadata_edits 是编辑历史，只读；直接写本表不会补历史，审计在 db_commits。',
    ],
  ),
  'media_file_aliases': DbTableDoc(
    DbAccess.write,
    '合并过的文件的旧 ID → 现在的文件 ID（old_id 主键），archived 是合并前行的 JSON 存档。读取文件时旧 ID 按它解析。',
    json: {'archived': DbJson.any},
  ),
  'media_classic_observations': DbTableDoc(
    DbAccess.write,
    'Classic 观看历史对某个文件位置的一次观察：fingerprint（animeId、episodeId、animeName、episodeTitle、videoHash 的哈希）、payload（JSON 证据）、binding_id（这次观察产生的 classic_match 绑定，可空）、observed_at。',
    json: {'payload': DbJson.object},
    notes: ['规则见 semantics.classic_match。$_classicAudit'],
  ),
  'media_classic_current': DbTableDoc(
    DbAccess.write,
    '每个文件位置当前生效的 Classic 观察（location_id 主键 → observation_id）。',
    notes: ['规则见 semantics.classic_match。删除一行，下次同步会把该位置当作全新观察重新导入。'],
  ),
  'danmaku_bindings': DbTableDoc(
    DbAccess.write,
    '剧集 ↔ 弹幕来源视频的绑定：entity_id（剧集）、object_id（外部对象）、video（JSON）、status（accepted、revoked）、enabled、deduplicate、offset_ms、alignment（JSON）、evidence（JSON）、bound_by、revision。',
    json: {
      'video': DbJson.object,
      'alignment': DbJson.object,
      'evidence': DbJson.any,
      'provenance': DbJson.any
    },
    notes: [
      'cache_key、cache_revision、cache_job_id 指向弹幕缓存（danmaku_cache_chunks，只读）和下载任务；不要手改。',
      '修改历史在 danmaku_binding_events（只读），直接写本表不会补事件，也不会重建缓存；播放器下次载入时读取新值。',
      '撤销请改 status 为 revoked；删除会被 danmaku_binding_events 的外键拦住。',
    ],
  ),
  // ── 界面摆放：可写 ───────────────────────────────────────────────────
  'ui_shelves': DbTableDoc(
    DbAccess.write,
    'Nipa 摆在首页的书架：id、payload（JSON：title、note、items[{workId,note}]，hero 书架有专用形态）、updated_at。',
    json: {'payload': DbJson.object},
    notes: [
      'payload 里给观众看的文字（title、note）遵守 ui.shelves.put 的同一规则：一句自然的短话，不含 ID、URL、路径；db.write 会校验。',
      'items[].workId 必须是存在的作品实体。',
    ],
  ),
  'ui_presentations': DbTableDoc(
    DbAccess.write,
    'Nipa 在对话里摆出的卡片：thread_id、turn_id、cards（JSON 数组）、origin、invocation_id、created_at；id 自增。',
    json: {'cards': DbJson.array},
  ),

  // ── 只读：任务引擎及后续 ────────────────────────────────────────────
  'jobs': DbTableDoc(DbAccess.read, '后台任务的当前快照（任务引擎）。',
      reason: '任务引擎持有状态机和恢复逻辑，改它会弄坏正在跑的任务。用 task.* 操作。'),
  'job_events': DbTableDoc(DbAccess.read, '任务每次变化的追加式事件。',
      reason: '任务历史与 activity 的来源，属审计。'),
  'task_origins': DbTableDoc(DbAccess.read, '任务由谁（origin、invocation）提交。',
      reason: '任务归属与审计，随任务引擎写入。'),
  'followups': DbTableDoc(DbAccess.read, '后续（followup）的当前快照。',
      reason: '后续引擎持有状态机；用 followup.* 操作。'),
  'followup_events': DbTableDoc(DbAccess.read, '后续的追加式事件。',
      reason: '后续历史与 activity 的来源，属审计。'),
  'followup_objects': DbTableDoc(DbAccess.read,
      '每个自动回执已经报告过的东西：下载的对象（文件、停滞、任务结束）、媒体库批次的路径与文件 id，供后续去重查找。',
      reason: '由 followups 表上的触发器随快照写入；改它会让同一事实重复送达或被吞掉。'),
  'change_epochs': DbTableDoc(DbAccess.read,
      '媒体库与界面所依据的数据有没有变过的计数（name=catalogue）：相关表每改一行，触发器加一；第一次写入之前没有这一行。',
      reason: '由触发器维护。db.write 不拦它（拦了会连带拦住改媒体库表的语句），手写只会让媒体库和界面多刷新一次。'),
  'activity_invocations': DbTableDoc(DbAccess.read,
      '动态里显示的调用，随调用写入并只留动态读的字段：动作、来源、状态、起止、输入的相关字段与结果。',
      reason: '由调用记录的观察者写入，是动态的来源；改它会让动态与审计日志对不上。'),
  'invocation_origins': DbTableDoc(DbAccess.read,
      '每次写入类调用是谁发起的（invocationId 到 origin），供只记 invocationId 的领域行查来源。',
      reason: '审计；由调用记录的观察者写入。'),
  'activity_backfill': DbTableDoc(DbAccess.read,
      '有一行表示旧的 journal.jsonl 已经读进动态的表。',
      reason: '内部迁移标记。'),
  'followup_hook_events': DbTableDoc(DbAccess.read,
      '身体事件的持久日志，events.wait 的游标就是它的 sequence。',
      reason: '改动会让事件游标和 hook 重放不一致。'),
  'harness_sessions': DbTableDoc(DbAccess.read, '每个 harness 仓库当前的主对话与当前对话线程。',
      reason: '会话映射；改它会让对话断开或串线。用 chat.session.* 操作。'),
  'harness_discoveries': DbTableDoc(DbAccess.read, 'Nipa 报告的发现记录（activity 的来源）。',
      reason: '审计记录，用 followup.discover 追加。'),

  // ── 只读：审计与历史 ────────────────────────────────────────────────
  'body_changes': DbTableDoc(DbAccess.read,
      '各领域变更的公开事实（前后镜像），activity 的来源之一。db.write 的提交也在这里留一条摘要。',
      reason: '审计表。'),
  'db_commits': DbTableDoc(DbAccess.read,
      'db.write 与 db.undo 的审计：SQL、参数、改动计数、前后镜像、origin、invocationId、actor。db.undo 靠它撤回。',
      reason: '审计表本身；改它等于改写历史，也会让 undo 失效。'),
  'settings_changes': DbTableDoc(DbAccess.read, '设置修改的追加式历史。',
      reason: '审计；设置用 settings.set 修改。'),
  'media_metadata_edits': DbTableDoc(DbAccess.read,
      '资料覆盖的追加式编辑历史，activity 的 metadata.edited 来源。',
      reason: '历史记录，与 media_overrides 一起由编辑原语追加；直接写 media_overrides 的审计在 db_commits。'),
  'danmaku_binding_events': DbTableDoc(DbAccess.read, '弹幕绑定每次修订的追加式事件。',
      reason: '历史与 activity 的来源，属审计。'),
  'media_legacy_history': DbTableDoc(DbAccess.read,
      'Classic 旧版证据的原样存档，每个文件位置只保存最早的一份。',
      reason: '保留证据，只由同步以“先到先得”写入。'),

  // ── 只读：由别的模块维护的状态 ──────────────────────────────────────
  'media_binding_operations': DbTableDoc(DbAccess.read,
      '专用原语的幂等回执：requestId 的指纹与结果。',
      reason: '改了会让重放同一 requestId 的结果与现实不符。'),
  'media_projection_outbox': DbTableDoc(DbAccess.read,
      '写回 Classic 的投影队列（pending、delivered…）。',
      reason: '投递状态机，与 Classic 的数据库对账。db.write 不往 Classic 投影，因此也不写这个队列。'),
  'media_scan_items': DbTableDoc(DbAccess.read, '扫描任务处理过的文件条目。',
      reason: '属于任务引擎的扫描任务。'),
  'file_subtitles': DbTableDoc(DbAccess.read,
      '文件的字幕关联事实（JSON），由字幕模块对照磁盘文件核验。',
      reason: '事实须与磁盘上的字幕一致，并有自己的审计；用 subtitle.* 操作。'),
  'file_skip_segments': DbTableDoc(DbAccess.read,
      'Nipa 给某个文件写下的片头/片尾区间（毫秒），每个文件每种区间一行；同一文件再次打开时带上。',
      reason: '由 playback.set_skip_segment 写入并核对区间在片长之内；用该操作设置或清除。'),
  'danmaku_alignment_candidates': DbTableDoc(DbAccess.read,
      '弹幕对齐分析的候选结果，挂在分析任务（job_id）上。',
      reason: '随任务引擎的任务生命周期存在。'),
  'danmaku_cache_chunks': DbTableDoc(DbAccess.read,
      '弹幕缓存与已导入弹幕的分块，file_path 指向磁盘文件。',
      reason: '与磁盘文件和缓存回收（cache.plan/prune）对账。'),
  'danmaku_storage_state': DbTableDoc(DbAccess.read, '弹幕存储维护的内部标志。',
      reason: '内部状态。'),
  'next_library_index': DbTableDoc(DbAccess.read, '媒体库搜索与排序用的可丢弃投影。',
      reason: '由服务从其他表重建，写了也会被覆盖。'),
  'ui_cache': DbTableDoc(DbAccess.read,
      '界面缓存：封面（artwork:*）、媒体库来源目录、设备与进度（mesh:*）、媒体库布局（library:layout:*）、热度线、片头设置。',
      reason: '混有可丢弃缓存和用户整理的布局，由各自的服务按指纹维护；布局用 ui.library.*，封面随资料字段自动重取。'),
  'sqlite_sequence': DbTableDoc(DbAccess.read, 'SQLite 内部的 AUTOINCREMENT 计数。',
      reason: 'SQLite 内部表；写入由提交前后的对比拒绝。'),
};

/// Facts that cross tables. Served by `db.describe`.
const dbSemantics = <String, String>{
  'classic_match':
      '''source='classic_match' 的绑定、media_classic_observations 和 media_classic_current 来自 Classic 观看历史。同步（IdentityStore.importLegacy，随 Classic 历史同步、media.library.import_history、扫描触发）按文件位置逐条处理：
1. 用 animeId、episodeId、animeName、episodeTitle、videoHash 算 fingerprint；与 media_classic_current 当前观察的 fingerprint 相同则整条跳过——所以直接改写的绑定、对应、观察，在 Classic 对该文件的记录没变时保持原样。
2. fingerprint 不同（或没有当前观察）：把上一次观察的 binding_id 对应的绑定改为 revoked，并追加一条 unbind 证据；新建观察；匹配成立（animeId>0、episodeId>0、有 animeName 和 episodeTitle，并通过 Classic 历史资格检查）时，为作品、版本、剧集和文件各建 classic_match 绑定（该实体已有同一对象的 accepted 绑定则不重建）、写 source=classic_match 的快照、补 media_file_episodes（已存在则保留）；再替换 media_classic_current。
3. Classic 不再列出某文件时，按未匹配重新导入一次：旧绑定 revoked，新观察没有 binding_id。
4. 如果这个文件的对应是 Next 自己投影出去又被 Classic 读回的（回读），只记观察，不重建绑定。
结论：直接 revoke 或删除 classic_match 绑定，只在 Classic 对该文件的记录不变时有效；Classic 的记录一变，或你删掉 media_classic_current 的那一行，同步会按上面规则重新生成。要让某个文件长期不跟随 Classic，请给它显式的 accepted 绑定与对应（bind_batch），classic_match 与显式绑定可并存，identity.get 的 conflicts 会列出差异。''',
  'overrides_over_snapshots':
      '''资料合并顺序：先按快照（media_snapshots，经 accepted 绑定关联到实体）填字段——classic_match 来源最后，其余绑定在实体自己身上的优先，再按 fetched_at 新者优先，标题与简介另有中文优先；然后 media_overrides 逐字段覆盖，覆盖永远赢（mode=correction 的在更晚的快照出现后让位）。本地目录自建、没有快照的作品，标题取实体 attributes.title。''',
  'artwork':
      '''图片覆盖在 media_overrides：field=artwork.poster|backdrop|logo|still，value={"url":…} 或 {"file":…}；其余图片地址来自快照 fields.artworkUrls 和 metadata.imageUrl。封面缓存是 ui_cache 的 artwork:<实体 id>，指纹由这些字段和绑定算出，字段一变就重取，不需要清缓存。''',
  'identity_ids':
      '''media_external_objects.id 是 provider、object_type、external_id、scope 的稳定哈希，db.write 会拒绝不符的新行并给出正确值。其他表的 id 可以自取（唯一即可）。''',
  'no_classic_projection':
      '''db.write 和 db.undo 不往 Classic 投影：不写 media_projection_outbox，也不碰 Classic 的数据库。Classic 看到的匹配结果只在专用原语（bind_batch 等）或 Classic 自己的改动时变化。''',
  'no_receipts':
      '''直接写入不产生 media_binding_operations 回执，不写 media_metadata_edits 或 danmaku_binding_events 这类领域历史，也不自动递增 media_entities.revision；它的记录是 db_commits（审计与撤回依据）和 body_changes 里的一条摘要。''',
  'foreign_keys':
      '''外键在整批语句之后统一检查（批内顺序随意）；提交前新增的违例让整批回滚，并列出违例的行。提交前已存在的违例不算。''',
  'json_columns':
      '''标为 JSON 的文本列，改过的行必须是合法 JSON 且形状符合（对象、数组或任意值）；程序读取时直接解析，坏数据会让读取失败。''',
  'sql_dialect':
      '''db.write 的每条语句必须被 SQLite 当作触发器正文接受：单条 INSERT、UPDATE、DELETE（含 INSERT OR REPLACE、ON CONFLICT）。因此表名不带 main. 前缀、不能用 RETURNING；WITH 要放进子查询或 INSERT 的 SELECT 里（例如 DELETE FROM t WHERE id IN (WITH x AS (…) SELECT id FROM x)）。DDL、PRAGMA、ATTACH、事务控制和一条里放多条语句都会被拒绝。参数用 ? 按位置绑定。''',
  'preview_binding':
      '''previewId 绑定的是这批语句的“效果”：语句原文，加上每一行改动的前后镜像。提交时在新事务里重新执行，行级镜像与预演逐字节相同才提交；预演之后这些行被别人改过（或语句依赖的数据变了）就拒绝，重新预演即可。与这批改动无关的表的变化不影响提交。每次执行结果不同的表达式（datetime('now')、random()）会让提交被拒，请写具体的值。previewId 只存在于内存，约 10 分钟有效，用一次即失效。''',
  'undo':
      '''db.undo 恢复一次提交的前镜像：每一行当前内容必须仍等于那次提交的后镜像（插入的行必须还在且没变，删除的行位置必须仍然空着），否则整个撤回被拒绝并列出冲突的行。撤回本身也是一次提交，有自己的 commitId，可以再被撤回。''',
};
