// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

/// The kind of operation the sync engine will perform for a path.
enum SyncActionType {
  /// Copy the local file to the remote (local changed, remote did not).
  pushToRemote,

  /// Copy the remote file to the local (remote changed, local did not).
  pullToLocal,

  /// Delete the local file (it was removed remotely).
  deleteLocal,

  /// Delete the remote file (it was removed locally).
  deleteRemote,

  /// Both sides changed: keep the remote at the original path and preserve the
  /// local version as a conflict copy (DESIGN.md).
  conflict,
}

/// A single planned sync operation for one path.
class SyncAction {
  final SyncActionType type;
  final String path;

  /// For [SyncActionType.conflict], the path of the conflict copy that will
  /// hold the local version; `null` otherwise.
  final String? conflictCopyPath;

  const SyncAction(this.type, this.path, {this.conflictCopyPath});

  bool get isConflict => type == SyncActionType.conflict;

  @override
  String toString() => 'SyncAction(${type.name}, $path'
      '${conflictCopyPath != null ? ' -> $conflictCopyPath' : ''})';
}

/// The result of planning: the operations to perform and the sync state that
/// will hold once they are applied successfully.
class SyncPlan {
  final List<SyncAction> actions;

  /// path -> content hash expected after the plan is applied. Becomes the new
  /// [SyncState].
  final Map<String, String> resultingState;

  const SyncPlan({required this.actions, required this.resultingState});

  List<SyncAction> get conflicts =>
      actions.where((a) => a.isConflict).toList(growable: false);

  bool get isEmpty => actions.isEmpty;
}
