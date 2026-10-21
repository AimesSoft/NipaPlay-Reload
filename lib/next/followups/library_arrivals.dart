part of 'service.dart';

/// Files that enter the library are reported to Nipa as facts, in batches.
///
/// - Caused from a conversation of hers (her call, or a task her call
///   started): the batch goes back to that conversation as an automatic
///   followup, like a download's.
/// - Anything else (the user adding a folder, Classic's scan, a media source
///   syncing, the app itself): one background helper per batch, with no
///   return to any conversation. Its end is an entry in activity, as any
///   task's is.
///
/// Nothing here looks at what a file is. The only filter is that a file
/// already reported by a download return is not reported twice.
extension LibraryArrivals on Followups {
  bool get _libraryOn => libraryEnabled?.call() ?? true;

  static const _conversational = [
    'harness_cli:chat:',
    'harness_cli:helper:',
    'codex_native:'
  ];

  /// A file entered the library: [file] is `library.file_added`'s data
  /// (`path`, `fileId`, `via`, `cause`).
  Future<void> libraryFileAdded(JsonMap file) => _serial(() async {
        if (!_libraryOn) return;
        await location.ready;
        final path = file['path'] as String;
        final fileId = file['fileId'] as String?;
        final rows = await _rows();
        final seen = {
          for (final row in rows.where((r) => r['automatic'] == 'library'))
            ...(row['libraryObjects'] as List).cast<String>()
        };
        if (seen.contains(path) || fileId != null && seen.contains(fileId)) {
          return;
        }
        JsonMap? target;
        final cause = file['cause'] as Map?;
        final origin = cause?['origin'] as String?;
        if (origin != null && _conversational.any(origin.startsWith)) {
          target = await downloadReturnTarget(
              Invocation(origin: origin, id: cause!['invocationId'] as String?));
        }
        final batch =
            target == null ? 'background' : 'thread:${target['threadId']}';
        final now = DateTime.now().toUtc();
        final entry = {
          'event': 'library.file_added',
          'objectId': fileId ?? path,
          'occurredAt': now.toIso8601String(),
          'data': {
            'path': path,
            if (fileId != null) 'fileId': fileId,
            'via': file['via'],
            'enteredAt': now.toIso8601String(),
          }
        };
        final open = rows
            .where((r) =>
                r['automatic'] == 'library' &&
                r['state'] == 'ready' &&
                r['frozen'] != true &&
                r['batchKey'] == batch)
            .lastOrNull;
        if (open != null &&
            ((open['trigger'] as Map)['facts'] as List).length <
                libraryBatchLimit) {
          ((open['trigger'] as Map)['facts'] as List).add(entry);
          (open['libraryObjects'] as List)
              .addAll([path, if (fileId != null) fileId]);
          _libraryDue(open, now);
          open['updatedAt'] = now.toIso8601String();
          // Coalescing is silent: a scan would otherwise write one event per file.
          await database.update(
              'followups', {'snapshot': jsonEncode(redactHarnessJson(open))},
              where: 'id=?', whereArgs: [open['id']]);
        } else {
          final stamp = now.microsecondsSinceEpoch;
          final row = <String, Object?>{
            'id': 'followup-library-$stamp-'
                '${Random.secure().nextInt(1 << 32).toRadixString(16)}',
            'automatic': 'library',
            'batchKey': batch,
            'state': 'ready',
            'title': '新进片库的文件',
            'instruction': target == null
                ? '这些文件进了片库，不是由你在对话里发起的。事实见下。下一步由你决定。'
                : '你发起的操作让这些文件进了片库。事实见下。下一步由你决定。',
            'condition': {'kind': 'library.facts'},
            'libraryObjects': [path, if (fileId != null) fileId],
            'firstAt': now.toIso8601String(),
            'repository': target?['repository'] ?? location.path,
            'threadId': target?['threadId'],
            'turnId': null,
            'origin': target?['origin'] ?? 'application',
            'invocationId': target?['invocationId'] ?? 'library',
            'createdAt': now.toIso8601String(),
            'updatedAt': now.toIso8601String(),
            'reason': null,
            'turnStatus': null,
            'waitingFor': 'Waiting for the library batch to settle.',
            if (target?['deviceId'] != null)
              'remoteDeviceId': target!['deviceId'],
            if (target?['returnTicket'] != null)
              'returnTicket': target!['returnTicket'],
            'trigger': {
              'kind': 'library.facts',
              'facts': [entry]
            }
          };
          _libraryDue(row, now);
          final safe = redactHarnessJson(row) as JsonMap;
          await database.transaction((tx) async {
            await tx.insert('followups', {
              'id': safe['id'],
              'state': 'ready',
              'snapshot': jsonEncode(safe)
            });
            await _event(tx, safe, 'registered', safe['origin'] as String,
                safe['invocationId'] as String);
          });
        }
        _schedule();
      });

  /// The batch is due once files stop arriving for [libraryQuiet], and never
  /// later than [libraryMaxWait] after its first file.
  void _libraryDue(JsonMap row, DateTime now) {
    final quiet = now.add(libraryQuiet);
    final cap = DateTime.parse(row['firstAt'] as String).add(libraryMaxWait);
    final batchFull =
        ((row['trigger'] as Map)['facts'] as List).length >= libraryBatchLimit;
    row['deliverAfter'] =
        (batchFull ? now : quiet.isBefore(cap) ? quiet : cap).toIso8601String();
  }

  /// A scan or sync ended: whatever it brought is delivered now.
  Future<void> libraryBatchEnded() => _serial(() async {
        for (final row in await _rows()) {
          if (row['automatic'] != 'library' ||
              row['state'] != 'ready' ||
              row['frozen'] == true) {
            continue;
          }
          row['deliverAfter'] = DateTime.now().toUtc().toIso8601String();
          await database.update(
              'followups', {'snapshot': jsonEncode(row)},
              where: 'id=?', whereArgs: [row['id']]);
        }
        _schedule();
      });

  Future<void> _libraryPending(JsonMap row, String reason) async {
    if (row['reason'] != reason) await _save(row, 'ready', 'pending', reason: reason);
  }

  /// Whether a ready library batch goes on to be delivered. A batch for a
  /// conversation is described and then continues into the usual delivery
  /// (waiting there while the conversation is busy); a background batch is
  /// dispatched here.
  Future<bool> _libraryGate(JsonMap row) async {
    if (row['frozen'] != true) {
      if (!_libraryOn) {
        await _save(row, 'cancelled', 'cancelled',
            reason: 'Library notifications are off.');
        return false;
      }
      final due = DateTime.parse(row['deliverAfter'] as String);
      if (DateTime.now().toUtc().isBefore(due)) {
        if (row['batchKey'] == 'background') _libraryHeld = true;
        await _libraryPending(
            row, 'Waiting for library files to stop arriving until $due.');
        return false;
      }
    }
    if (row['batchKey'] != 'background') return _freezeLibrary(row);
    if (row['frozen'] != true) {
      if (_libraryHeld) {
        await _libraryPending(row, 'Waiting for the previous library batch.');
        return false;
      }
      for (final other in await _rows()) {
        final id = other['helperJobId'] as String?;
        if (other['automatic'] != 'library' || id == null) continue;
        final job = await engine.get(id).then<Job?>((j) => j, onError: (_) => null);
        if (job != null && !job.state.isTerminal) {
          _libraryHeld = true;
          await _libraryPending(row,
              'A background helper is still handling the previous library batch; these files wait for the next one.');
          return false;
        }
      }
    }
    final dispatch = backgroundDispatch ?? helpers?.dispatchBackground;
    if (dispatch == null) {
      _libraryHeld = true;
      await _libraryPending(row, _unavailable);
      return false;
    }
    if (!await _freezeLibrary(row)) return false;
    final facts = (row['trigger'] as Map)['facts'] as List;
    final jobId = 'library-${row['id']}';
    try {
      await dispatch(
          jobId: jobId,
          title: '新进片库的 ${facts.length} 个文件',
          instruction:
              '${row['instruction']}\n触发事实：${jsonEncode(row['trigger'])}');
    } on Failure catch (error) {
      _libraryHeld = true;
      await _libraryPending(row, error.message);
      return false;
    }
    row['helperJobId'] = jobId;
    row['dispatchedAt'] = DateTime.now().toUtc().toIso8601String();
    await _save(row, 'completed', 'dispatched',
        reason: 'Handed to a background helper; its end is recorded in activity.');
    _libraryHeld = true;
    return false;
  }

  /// Describes the files as the library holds them now, and drops those a
  /// download return already reported. Returns false when nothing is left.
  Future<bool> _freezeLibrary(JsonMap row) async {
    if (row['frozen'] == true) return true;
    final trigger = row['trigger'] as Map;
    final entries = [
      for (final fact in (trigger['facts'] as List).cast<Map>())
        Map<String, Object?>.from(fact['data'] as Map)
    ];
    final described = describeLibraryFiles == null
        ? entries
        : await describeLibraryFiles!(entries);
    final reported = await _libraryReported(row, row['threadId'] as String?);
    final left = [
      for (final fact in described)
        if (fact['fileId'] == null || !reported.contains(fact['fileId'])) fact
    ];
    if (left.isEmpty) {
      await _save(row, 'cancelled', 'deduplicated',
          reason: 'A download return already reported every one of these files.');
      return false;
    }
    trigger['facts'] = redactHarnessJson([
      for (final fact in left)
        {
          'event': 'library.file_added',
          'objectId': fact['fileId'] ?? fact['path'],
          'occurredAt': fact['enteredAt'],
          'data': fact
        }
    ]);
    (row['libraryObjects'] as List).addAll([
      for (final fact in left)
        if (fact['fileId'] != null) fact['fileId'] as String
    ]);
    row['title'] = '新进片库的 ${left.length} 个文件';
    row['frozen'] = true;
    await _save(row, 'ready', 'frozen');
    return true;
  }

  /// fileIds already on their way to [thread] (any conversation when null)
  /// through a download return, or in another frozen library batch.
  Future<Set<String>> _libraryReported(JsonMap row, String? thread) async {
    final ids = <String>{};
    for (final other in await _rows()) {
      if (other['id'] == row['id'] || other['state'] == 'cancelled') continue;
      final facts = ((other['trigger'] as Map?)?['facts'] as List? ?? const [])
          .whereType<Map>();
      if (other['automatic'] == 'library' && other['frozen'] == true) {
        for (final fact in facts) {
          if ((fact['data'] as Map)['fileId'] case final String id) ids.add(id);
        }
      } else if (other['automatic'] == 'download' &&
          other['state'] != 'execution_failed' &&
          (thread == null || other['threadId'] == thread)) {
        for (final fact in facts) {
          final media = ((fact['data'] as Map)['file'] as Map?)?['media'];
          if (media is Map && media['fileId'] is String) {
            ids.add(media['fileId'] as String);
          }
        }
      }
    }
    // A completed file the download return has not been built for yet.
    for (final job in await engine.list(type: 'download')) {
      final target = job.input['returnTo'] as Map?;
      if (target == null || thread != null && target['threadId'] != thread) {
        continue;
      }
      for (final file
          in (job.checkpoint['completedFiles'] as List? ?? []).cast<Map>()) {
        final media = file['media'];
        if (file['isVideo'] == true &&
            file['imported'] == true &&
            file['verification'] == 'verified' &&
            media is Map &&
            media['fileId'] is String) {
          ids.add(media['fileId'] as String);
        }
      }
    }
    return ids;
  }
}
