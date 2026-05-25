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

  const FolderNode({
    required super.path,
    required super.name,
    this.folders = const [],
    this.notes = const [],
    this.color,
  });

  /// Whether this folder has no child folders and no notes.
  bool get isEmpty => folders.isEmpty && notes.isEmpty;
}

/// A note file (`*.md`).
class NoteNode extends TreeNode {
  const NoteNode({required super.path, required super.name});

  /// The file name without its `.md` extension, for display.
  String get title {
    const ext = '.md';
    return name.toLowerCase().endsWith(ext)
        ? name.substring(0, name.length - ext.length)
        : name;
  }
}
