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

  /// An opaque, backend-supplied version token for a file — e.g. an HTTP ETag
  /// or OneDrive's `quickXorHash`. When two listings report the same [tag] for
  /// a path, its bytes are unchanged. Content-addressed tags (a server-side
  /// hash) are collision-free; weaker ones (an ETag) may change without the
  /// content changing, which only costs a redundant re-hash, never correctness.
  /// `null` when the backend has nothing to offer.
  final String? tag;

  const StorageEntry({
    required this.path,
    required this.isDirectory,
    this.modified,
    this.size,
    this.tag,
  });

  /// A cheap fingerprint used by sync's content-hash cache to decide whether a
  /// file must be re-read and re-hashed, or its last-known hash can be reused.
  ///
  /// Prefers a backend [tag]; otherwise falls back to size + modification time.
  /// `null` when neither is available (the file is then always re-read — the
  /// safe default). This is never compared across backends: each side's
  /// fingerprint is only ever matched against that same backend's own prior
  /// record, so a local `size:mtime` and a remote `tag` never meet.
  String? get fingerprint {
    if (isDirectory) return null;
    if (tag != null && tag!.isNotEmpty) return 't:$tag';
    if (size != null && modified != null) {
      return 's:$size:${modified!.microsecondsSinceEpoch}';
    }
    return null;
  }

  /// The final path segment (the file or directory name).
  String get name => p.posix.basename(path);

  @override
  String toString() =>
      'StorageEntry(${isDirectory ? 'dir' : 'file'}: $path, '
      'size: $size, modified: $modified, tag: $tag)';

  @override
  bool operator ==(Object other) =>
      other is StorageEntry &&
      other.path == path &&
      other.isDirectory == isDirectory &&
      other.modified == modified &&
      other.size == size &&
      other.tag == tag;

  @override
  int get hashCode => Object.hash(path, isDirectory, modified, size, tag);
}
