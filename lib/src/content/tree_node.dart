// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

/// A node in the Folio's navigable tree (DESIGN.md). The UI binds to this.
///
/// Nodes describe structure only; note bodies and folder metadata are loaded on
/// demand through the content service. Display names here are derived from path
/// segments so building the tree does not require reading every file.
sealed class TreeNode {
  /// Folio-relative path using forward slashes. The root folder is `''`.
  final String path;

  /// The final path segment.
  final String name;

  const TreeNode({required this.path, required this.name});
}

/// A directory: zero or more child folders and notes.
class FolderNode extends TreeNode {
  final List<FolderNode> folders;
  final List<NoteNode> notes;

  /// Optional accent color as a `#RRGGBB` hex string (from the folder's
  /// properties), for a visual cue in the tree.
  final String? color;

  /// Whether this folder has a folder-level note (a `README.md`), surfaced by
  /// tapping the folder name rather than listed among [notes].
  final bool hasFolderNote;

  /// The folder note's last-modified time and size (when [hasFolderNote]), from
  /// the directory listing — for the folder-note tooltip.
  final DateTime? folderNoteModified;
  final int? folderNoteSize;

  const FolderNode({
    required super.path,
    required super.name,
    this.folders = const [],
    this.notes = const [],
    this.color,
    this.hasFolderNote = false,
    this.folderNoteModified,
    this.folderNoteSize,
  });

  /// Whether this folder has no child folders and no notes.
  bool get isEmpty => folders.isEmpty && notes.isEmpty;
}

/// A note file (`*.md`).
class NoteNode extends TreeNode {
  /// Last-modified time, if the backend reports it (from the directory listing,
  /// so it costs no extra reads and works for browsed folders too).
  final DateTime? modified;

  /// File size in bytes, if known.
  final int? size;

  const NoteNode({
    required super.path,
    required super.name,
    this.modified,
    this.size,
  });

  /// The file name without its `.md` extension, for display.
  String get title {
    const ext = '.md';
    return name.toLowerCase().endsWith(ext)
        ? name.substring(0, name.length - ext.length)
        : name;
  }
}
