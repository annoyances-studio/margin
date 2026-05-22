// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'sync_action.dart';

/// The brains of sync: a pure, side-effect-free three-way comparison.
///
/// Given the current local and remote snapshots (path -> content hash) and the
/// last-synced base, it decides what to push, pull, delete, or flag as a
/// conflict, and computes the resulting [SyncState] hashes. Being pure, it is
/// exhaustively unit-testable without any I/O.
class SyncPlanner {
  const SyncPlanner._();

  static SyncPlan plan({
    required Map<String, String> local,
    required Map<String, String> remote,
    required Map<String, String> base,
    required String conflictLabel,
  }) {
    final actions = <SyncAction>[];
    final resulting = <String, String>{};
    final paths = <String>{...local.keys, ...remote.keys, ...base.keys};

    for (final path in paths) {
      final l = local[path];
      final r = remote[path];
      final b = base[path];

      // Already identical on both sides (covers "both made the same change",
      // including both deleting the file).
      if (l == r) {
        if (l != null) resulting[path] = l;
        continue;
      }

      final localChanged = l != b;
      final remoteChanged = r != b;

      if (localChanged && !remoteChanged) {
        if (l == null) {
          actions.add(SyncAction(SyncActionType.deleteRemote, path));
        } else {
          actions.add(SyncAction(SyncActionType.pushToRemote, path));
          resulting[path] = l;
        }
      } else if (remoteChanged && !localChanged) {
        if (r == null) {
          actions.add(SyncAction(SyncActionType.deleteLocal, path));
        } else {
          actions.add(SyncAction(SyncActionType.pullToLocal, path));
          resulting[path] = r;
        }
      } else {
        // Both sides changed.
        if (l == null) {
          // Deleted locally but modified remotely: keep the edit (no data loss).
          actions.add(SyncAction(SyncActionType.pullToLocal, path));
          resulting[path] = r!;
        } else if (r == null) {
          // Deleted remotely but modified locally: keep the edit.
          actions.add(SyncAction(SyncActionType.pushToRemote, path));
          resulting[path] = l;
        } else {
          // Both hold differing content: a true conflict. The remote wins the
          // original path; the local version is preserved as a copy on both.
          final copy = conflictCopyName(path, conflictLabel);
          actions.add(SyncAction(
            SyncActionType.conflict,
            path,
            conflictCopyPath: copy,
          ));
          resulting[path] = r;
          resulting[copy] = l;
        }
      }
    }

    return SyncPlan(actions: actions, resultingState: resulting);
  }

  /// Builds a conflict copy path by inserting ` (conflict, <label>)` before the
  /// extension, e.g. `Work/note.md` -> `Work/note (conflict, Phone, 2026-05-22).md`.
  static String conflictCopyName(String path, String label) {
    final slash = path.lastIndexOf('/');
    final dir = slash >= 0 ? path.substring(0, slash + 1) : '';
    final file = slash >= 0 ? path.substring(slash + 1) : path;

    final dot = file.lastIndexOf('.');
    final hasExtension = dot > 0; // not a dotfile, has a real extension
    final stem = hasExtension ? file.substring(0, dot) : file;
    final ext = hasExtension ? file.substring(dot) : '';

    return '$dir$stem (conflict, $label)$ext';
  }
}
