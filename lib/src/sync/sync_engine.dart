// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:typed_data';

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

  /// The repository-relative path this action touched — handy for showing the
  /// current file name in the UI.
  String get path => action.path;
}

/// The outcome of a sync run.
class SyncResult {
  final SyncPlan plan;

  /// The new last-synced state to persist for next time (carries the refreshed
  /// content-hash caches too).
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
///
/// ## Not re-downloading unchanged files
///
/// Hashing a file means reading its bytes — and for a remote that means
/// downloading them. Left naive, the initial clone of a large Folio would fetch
/// every file *twice* (once to hash it into a snapshot, once to actually pull
/// it). Two mechanisms avoid that:
///
///  * a **content-hash cache** (persisted in [SyncState]) memoises
///    `fingerprint → hash` per backend, so an unchanged file is not re-read on a
///    later sync; and
///  * a **first-clone fast path** (empty base, empty local) that lists the
///    remote by metadata only and hashes each file from the single copy it
///    downloads while pulling it.
///
/// Both are pure optimizations layered over the same canonical content hash, so
/// a cold or stale cache costs work, never correctness.
class SyncEngine {
  final StorageBackend local;
  final StorageBackend remote;

  /// Used to label conflict copies, e.g. "Phone" or "Desktop".
  final String deviceName;

  /// Injectable clock for deterministic conflict-copy names in tests.
  final DateTime Function() _clock;

  /// How many applied actions between [_checkpoint] saves during a long run, so
  /// an interrupted clone resumes near where it stopped instead of from zero.
  static const int _checkpointEvery = 25;

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
  /// [onCheckpoint] is invoked periodically with a *partial* [SyncState] that is
  /// safe to persist as the base: every path in it is genuinely in sync. If the
  /// run is later interrupted, the next run resumes from the last checkpoint
  /// rather than repeating all the transferred bytes.
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
    Future<void> Function(SyncState)? onCheckpoint,
    bool allowEmptying = false,
  }) async {
    final localSnap = await _snapshot(local, base.localCache);

    // First-clone fast path: nothing recorded and nothing local means every
    // remote file is a straight pull, with no pushes, deletes or conflicts
    // possible. Hash each file from the one copy we download, so the clone
    // transfers the Folio once instead of twice.
    if (base.hashes.isEmpty && localSnap.snapshot.isEmpty) {
      return _clone(
        base,
        localCache: localSnap.cache,
        onProgress: onProgress,
        onCheckpoint: onCheckpoint,
      );
    }

    final remoteSnap = await _snapshot(remote, base.remoteCache);

    final plan = SyncPlanner.plan(
      local: localSnap.snapshot,
      remote: remoteSnap.snapshot,
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

    SyncState newState() => SyncState(
          Map.of(plan.resultingState),
          localCache: localSnap.cache,
          remoteCache: remoteSnap.cache,
        );

    // A running "synced up to here" base for checkpoints: seed it with the
    // already-settled paths (no action needed) and mutate it as each action
    // completes, so an interrupted run resumes without repeating work.
    final actionPaths = <String>{};
    for (final a in plan.actions) {
      actionPaths.add(a.path);
      if (a.conflictCopyPath != null) actionPaths.add(a.conflictCopyPath!);
    }
    final live = Map.of(base.hashes)
      ..removeWhere((path, _) => actionPaths.contains(path));
    for (final entry in plan.resultingState.entries) {
      if (!actionPaths.contains(entry.key)) live[entry.key] = entry.value;
    }

    final total = plan.actions.length;
    for (var i = 0; i < total; i++) {
      final action = plan.actions[i];
      await _apply(action);
      _advance(live, action, plan.resultingState);
      onProgress?.call(SyncProgress(
        completed: i + 1,
        total: total,
        action: action,
      ));
      if (onCheckpoint != null &&
          i + 1 < total &&
          (i + 1) % _checkpointEvery == 0) {
        await onCheckpoint(SyncState(
          Map.of(live),
          localCache: localSnap.cache,
          remoteCache: remoteSnap.cache,
        ));
      }
    }

    return SyncResult(plan, newState());
  }

  /// The first-clone fast path (see [sync]): pulls every remote file, hashing it
  /// from the single copy it downloads. [localCache] is the (cheap) local
  /// snapshot's refreshed cache.
  Future<SyncResult> _clone(
    SyncState base, {
    required HashCache localCache,
    void Function(SyncProgress)? onProgress,
    Future<void> Function(SyncState)? onCheckpoint,
  }) async {
    final files = await _listFiles(remote);
    // Pull the Folio marker first so an interrupted clone can still be reopened
    // offline (the reopen path checks for properties.yaml).
    files.sort((a, b) {
      int rank(StorageEntry e) => e.path == 'properties.yaml' ? 0 : 1;
      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : a.path.compareTo(b.path);
    });

    final resulting = <String, String>{};
    final remoteCache = <String, FileHash>{};

    final total = files.length;
    for (var i = 0; i < total; i++) {
      final entry = files[i];
      final Uint8List bytes = await remote.read(entry.path);
      await local.write(entry.path, bytes);
      final hash = contentHash(bytes);
      resulting[entry.path] = hash;
      final fp = entry.fingerprint;
      if (fp != null) remoteCache[entry.path] = (fingerprint: fp, hash: hash);
      onProgress?.call(SyncProgress(
        completed: i + 1,
        total: total,
        action: SyncAction(SyncActionType.pullToLocal, entry.path),
      ));
      if (onCheckpoint != null &&
          i + 1 < total &&
          (i + 1) % _checkpointEvery == 0) {
        await onCheckpoint(SyncState(
          Map.of(resulting),
          localCache: localCache,
          remoteCache: Map.of(remoteCache),
        ));
      }
    }

    // Warm the local cache from the just-written files (metadata only, no byte
    // reads) so the first sync after the clone is a full cache hit on both
    // sides rather than re-hashing everything from local disk.
    final warmedLocal = <String, FileHash>{...localCache};
    for (final e in await _listFiles(local)) {
      final hash = resulting[e.path];
      final fp = e.fingerprint;
      if (hash != null && fp != null) {
        warmedLocal[e.path] = (fingerprint: fp, hash: hash);
      }
    }

    final actions = [
      for (final e in files) SyncAction(SyncActionType.pullToLocal, e.path),
    ];
    return SyncResult(
      SyncPlan(actions: actions, resultingState: resulting),
      SyncState(resulting, localCache: warmedLocal, remoteCache: remoteCache),
    );
  }

  /// Folds one applied [action] into the running checkpoint state [live].
  void _advance(
    Map<String, String> live,
    SyncAction action,
    Map<String, String> resulting,
  ) {
    switch (action.type) {
      case SyncActionType.pushToRemote:
      case SyncActionType.pullToLocal:
        final h = resulting[action.path];
        if (h != null) live[action.path] = h;
      case SyncActionType.deleteLocal:
      case SyncActionType.deleteRemote:
        live.remove(action.path);
      case SyncActionType.conflict:
        final h = resulting[action.path];
        if (h != null) live[action.path] = h;
        final copy = action.conflictCopyPath;
        final ch = copy == null ? null : resulting[copy];
        if (copy != null && ch != null) live[copy] = ch;
    }
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

  /// Walks [backend] recursively, returning path -> content hash for every file
  /// and a refreshed content-hash cache. A file whose backend [fingerprint]
  /// matches [priorCache] reuses its stored hash instead of being re-read.
  Future<({Map<String, String> snapshot, HashCache cache})> _snapshot(
    StorageBackend backend,
    HashCache priorCache, [
    String path = '',
  ]) async {
    final snapshot = <String, String>{};
    final cache = <String, FileHash>{};
    await _walk(backend, priorCache, snapshot, cache, path);
    return (snapshot: snapshot, cache: cache);
  }

  Future<void> _walk(
    StorageBackend backend,
    HashCache priorCache,
    Map<String, String> snapshot,
    HashCache cache,
    String path,
  ) async {
    final List<StorageEntry> entries;
    try {
      entries = await backend.list(path);
    } on NotFoundException {
      return; // missing directory => nothing here
    }

    for (final entry in entries) {
      if (entry.isDirectory) {
        await _walk(backend, priorCache, snapshot, cache, entry.path);
        continue;
      }
      final fp = entry.fingerprint;
      final cached = priorCache[entry.path];
      if (fp != null && cached != null && cached.fingerprint == fp) {
        snapshot[entry.path] = cached.hash; // unchanged — reuse, no read
        cache[entry.path] = cached;
      } else {
        final hash = contentHash(await backend.read(entry.path));
        snapshot[entry.path] = hash;
        if (fp != null) cache[entry.path] = (fingerprint: fp, hash: hash);
      }
    }
  }

  /// Lists every file (not directory) under [backend], recursively, by metadata
  /// only — no bytes are read. Used by the first-clone fast path.
  Future<List<StorageEntry>> _listFiles(StorageBackend backend,
      [String path = '']) async {
    final files = <StorageEntry>[];
    final List<StorageEntry> entries;
    try {
      entries = await backend.list(path);
    } on NotFoundException {
      return files;
    }
    for (final entry in entries) {
      if (entry.isDirectory) {
        files.addAll(await _listFiles(backend, entry.path));
      } else {
        files.add(entry);
      }
    }
    return files;
  }
}
