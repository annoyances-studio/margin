// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:path/path.dart' as p;

/// A single entry returned by [StorageBackend.list].
///
/// Paths are repository-relative and use forward slashes (`/`) on every
/// platform, so they are uniform across backends (local folder, WebDAV, ...).
class StorageEntry {
  /// Repository-relative path using forward slashes, e.g. `Work/note.md`.
  final String path;

  /// Whether this entry is a directory (otherwise it is a file).
  final bool isDirectory;

  /// Last modification time, if the backend can report it.
  final DateTime? modified;

  /// Size in bytes for files, if known. `null` for directories.
  final int? size;

  const StorageEntry({
    required this.path,
    required this.isDirectory,
    this.modified,
    this.size,
  });

  /// The final path segment (the file or directory name).
  String get name => p.posix.basename(path);

  @override
  String toString() =>
      'StorageEntry(${isDirectory ? 'dir' : 'file'}: $path, '
      'size: $size, modified: $modified)';

  @override
  bool operator ==(Object other) =>
      other is StorageEntry &&
      other.path == path &&
      other.isDirectory == isDirectory &&
      other.modified == modified &&
      other.size == size;

  @override
  int get hashCode => Object.hash(path, isDirectory, modified, size);
}
