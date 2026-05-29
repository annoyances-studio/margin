// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:typed_data';

import 'storage_entry.dart';

/// A "dumb folder": the minimal storage primitives Margin needs.
///
/// Paths are repository-relative and use forward slashes (`/`) regardless of
/// platform. The repository root is the empty string (`''`) or `/`.
///
/// Implementations only store and retrieve bytes. History, sync, conflict
/// handling and any encryption all live in higher layers — see DESIGN.md.
/// Adding a new backend (WebDAV, SMB, cloud, ...) means implementing just
/// these methods.
abstract interface class StorageBackend {
  /// Lists the immediate children of the directory at [path] (non-recursive).
  ///
  /// Listing the root uses `''` or `/`. Higher layers recurse using the
  /// [StorageEntry.isDirectory] flag. Throws [NotFoundException] if the
  /// directory does not exist.
  Future<List<StorageEntry>> list(String path);

  /// Whether a file or directory exists at [path].
  Future<bool> exists(String path);

  /// Reads the file at [path].
  ///
  /// Throws [NotFoundException] if it is missing, or [InvalidPathException] if
  /// the path refers to a directory.
  Future<Uint8List> read(String path);

  /// Writes [bytes] to [path], creating parent directories as needed and
  /// overwriting any existing file.
  Future<void> write(String path, Uint8List bytes);

  /// Deletes the file or directory at [path] (directories recursively).
  ///
  /// Deleting a path that does not exist is a no-op.
  Future<void> delete(String path);
}

/// Optional capability for backends that can move/rename a path within
/// themselves far more cheaply than a copy-then-delete — e.g. an atomic
/// filesystem rename. Higher layers (folder rename) use this when available and
/// fall back to copy+delete otherwise.
///
/// Avoiding copy+delete matters on OS-synced folders (OneDrive, Dropbox, …): a
/// folder rename done as "copy every file, then delete the old tree" creates a
/// burst of sync churn that can briefly lock files; an atomic move sidesteps it.
abstract interface class MovableBackend {
  /// Moves [from] to [to] within the same backend. The parent of [to] is
  /// created as needed; [to] must not already exist. Throws [NotFoundException]
  /// if [from] does not exist.
  Future<void> move(String from, String to);
}
