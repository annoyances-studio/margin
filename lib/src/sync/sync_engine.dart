// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import '../storage/storage_backend.dart';
import '../storage/storage_entry.dart';
import '../storage/storage_exception.dart';
import 'content_hash.dart';
import 'sync_action.dart';
import 'sync_planner.dart';
import 'sync_state.dart';

/// Progress of a sync run, reported once per applied action so the UI can
/// show caching/sync status (a determinate bar, or at least "syncing N of M").
class SyncProgress {
  /// Actions applied so far (1-based as each completes).
  final int completed;

  /// Total actions planned for this run.
  final int total;

  /// The action just applied.
  final SyncAction action;

  const SyncProgress({
    required this.completed,
    required this.total,
    required this.action,
  });

  /// Fraction complete in `[0, 1]` (1 when there is nothing to do).
  double get fraction => total == 0 ? 1 : completed / total;
}

/// The outcome of a sync run.
class SyncResult {
  final SyncPlan plan;

  /// The new last-synced state to persist for next time.
  final SyncState newState;

  /// True when a destructive "one side is now empty" plan was withheld pending
  /// explicit confirmation (see [SyncEngine.sync]'s emptying guard). Nothing was
  /// applied; [newState] equals the unchanged base.
  final bool withheld;

  const SyncResult(this.plan, this.newState, {this.withheld = false});

  List<SyncAction> get conflicts => plan.conflicts;
  bool get hadConflicts => conflicts.isNotEmpty;
  bool get madeChanges => plan.actions.isNotEmpty;
}

/// Reconciles a [local] working copy with a [remote] backend, moving raw bytes
/// in both directions (DESIGN.md).
///
/// Sync operates below the content layer: it moves the at-rest bytes as-is and
/// never applies the [ContentCodec]. The conflict policy is "keep both" via a
/// conflict copy; delete-vs-edit keeps the edit to avoid data loss.
class SyncEngine {
  final StorageBackend local;
  final StorageBackend remote;

  /// Used to label conflict copies, e.g. "Phone" or "Desktop".
  final String deviceName;

  /// Injectable clock for deterministic conflict-copy names in tests.
  final DateTime Function() _clock;

  SyncEngine({
    required this.local,
    required this.remote,
    this.deviceName = 'device',
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Runs one synchronization against the last-synced [base] state and returns
  /// the actions taken plus the new state to persist.
  ///
  /// [onProgress] is invoked after each action is applied — useful for showing
  /// caching/sync status (the initial download of a remote Folio is just a sync
  /// from an empty [base], so this reports download progress too).
  ///
  /// Emptying guard: if a side that held content in [base] now reads as *empty*,
  /// that is far more likely a failed/incomplete listing than a real "delete
  /// everything", so the destructive plan is withheld (nothing applied,
  /// [SyncResult.withheld] = true) unless [allowEmptying] is set — the caller is
  /// expected to confirm with the user first. The first clone (empty base) is
  /// never affected.
  Future<SyncResult> sync(
    SyncState base, {
    void Function(SyncProgress)? onProgress,
    bool allowEmptying = false,
  }) async {
    final localSnapshot = await _snapshot(local);
    final remoteSnapshot = await _snapshot(remote);

    final plan = SyncPlanner.plan(
      local: localSnapshot,
      remote: remoteSnapshot,
      base: base.hashes,
      conflictLabel: _conflictLabel(),
    );

    // Emptying guard: a plan that would wipe everything we had (the result is
    // empty, reached via deletions) is far more likely a failed/incomplete
    // listing than a deliberate "delete all". Withhold it for explicit
    // confirmation. The first clone (empty base) and partial changes (the
    // result still holds files) are unaffected.
    if (base.hashes.isNotEmpty &&
        plan.actions.isNotEmpty &&
        plan.resultingState.isEmpty &&
        !allowEmptying) {
      return SyncResult(plan, base, withheld: true);
    }

    final total = plan.actions.length;
    for (var i = 0; i < total; i++) {
      await _apply(plan.actions[i]);
      onProgress?.call(SyncProgress(
        completed: i + 1,
        total: total,
        action: plan.actions[i],
      ));
    }

    return SyncResult(plan, SyncState(plan.resultingState));
  }

  String _conflictLabel() {
    final now = _clock();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$deviceName, $y-$m-$d';
  }

  Future<void> _apply(SyncAction action) async {
    switch (action.type) {
      case SyncActionType.pushToRemote:
        await remote.write(action.path, await local.read(action.path));
      case SyncActionType.pullToLocal:
        await local.write(action.path, await remote.read(action.path));
      case SyncActionType.deleteLocal:
        await local.delete(action.path);
      case SyncActionType.deleteRemote:
        await remote.delete(action.path);
      case SyncActionType.conflict:
        // Read the local divergent version BEFORE overwriting it.
        final localContent = await local.read(action.path);
        final remoteContent = await remote.read(action.path);
        final copyPath = action.conflictCopyPath!;
        // Preserve the local version as a copy on both sides.
        await local.write(copyPath, localContent);
        await remote.write(copyPath, localContent);
        // Converge the original path to the remote version locally.
        await local.write(action.path, remoteContent);
    }
  }

  /// Walks [backend] recursively, returning path -> content hash for every
  /// file. A missing root is treated as empty.
  Future<Map<String, String>> _snapshot(StorageBackend backend,
      [String path = '']) async {
    final result = <String, String>{};
    final List<StorageEntry> entries;
    try {
      entries = await backend.list(path);
    } on NotFoundException {
      return result; // missing directory => nothing here
    }

    for (final entry in entries) {
      if (entry.isDirectory) {
        result.addAll(await _snapshot(backend, entry.path));
      } else {
        result[entry.path] = contentHash(await backend.read(entry.path));
      }
    }
    return result;
  }
}
