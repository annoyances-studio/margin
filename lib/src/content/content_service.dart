// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:typed_data';

import '../repository/folder_properties.dart';
import '../repository/note.dart';
import '../storage/content_codec.dart';
import '../storage/storage_backend.dart';
import 'content_exception.dart';
import 'repository_node.dart';

/// Reads and edits the contents of a repository: the folder tree, notes, and
/// folder metadata. This is the layer the UI binds to (DESIGN.md).
///
/// Note bodies and folder properties are routed through the [ContentCodec]
/// seam, so encryption can later apply to them transparently. The root
/// `properties.yaml` is intentionally NOT handled here — it must stay plaintext
/// (it holds the encryption recipe) and is managed by [Repository].
class ContentService {
  final StorageBackend backend;
  final ContentCodec codec;

  const ContentService(this.backend, {this.codec = const IdentityCodec()});

  /// Extension that identifies note files.
  static const String noteExtension = '.md';

  /// Per-folder metadata file name (also the root properties name).
  static const String propertiesFileName = 'properties.yaml';

  /// Directory holding a folder's embedded attachments.
  static const String attachmentsDirName = '_attachments';

  /// Builds the repository tree, starting at the root.
  ///
  /// Excludes `properties.yaml` files and `_attachments` directories.
  /// Enforces the folder-only-root rule: any stray `.md` at the root is
  /// ignored rather than shown.
  Future<FolderNode> tree() => _buildFolder('', '');

  Future<FolderNode> _buildFolder(String path, String name) async {
    final entries = await backend.list(path);
    final folders = <FolderNode>[];
    final notes = <NoteNode>[];
    final isRoot = path.isEmpty;

    for (final entry in entries) {
      if (entry.isDirectory) {
        if (entry.name == attachmentsDirName) continue;
        folders.add(await _buildFolder(entry.path, entry.name));
      } else {
        if (entry.name == propertiesFileName) continue;
        if (!entry.name.toLowerCase().endsWith(noteExtension)) continue;
        if (isRoot) continue; // no notes at the root
        notes.add(NoteNode(path: entry.path, name: entry.name));
      }
    }

    int byName(RepositoryNode a, RepositoryNode b) =>
        a.name.toLowerCase().compareTo(b.name.toLowerCase());
    folders.sort(byName);
    notes.sort(byName);

    // Folders are few, so reading per-folder metadata here is cheap (DESIGN.md).
    // The root has no folder properties (its properties.yaml is the repo root).
    String? color;
    if (!isRoot) {
      color = (await _tryReadFolderProperties(path))?.color;
    }

    return FolderNode(
      path: path,
      name: name,
      folders: folders,
      notes: notes,
      color: color,
    );
  }

  Future<FolderProperties?> _tryReadFolderProperties(String folderPath) async {
    try {
      return await readFolderProperties(folderPath);
    } catch (_) {
      return null; // missing or unreadable properties -> no metadata
    }
  }

  /// Reads and parses the note at [path] (decoding through the codec).
  Future<Note> readNote(String path) async {
    final stored = await backend.read(path);
    return Note.parse(utf8.decode(codec.decode(stored)));
  }

  /// Serializes and writes [note] to [path] (encoding through the codec),
  /// overwriting any existing file.
  Future<void> saveNote(String path, Note note) async {
    final plain = Uint8List.fromList(utf8.encode(note.serialize()));
    await backend.write(path, codec.encode(plain));
  }

  /// Creates a new note named [fileName] inside [folderPath].
  ///
  /// A `.md` extension is added if missing. Throws [ContentException] if
  /// [folderPath] is the root (folder-enforced structure), the name is invalid,
  /// or a note already exists there. Returns the new [NoteNode].
  Future<NoteNode> createNote(
    String folderPath,
    String fileName, {
    Note? initial,
  }) async {
    if (_isRoot(folderPath)) {
      throw const ContentException(
        'Notes cannot be created at the repository root',
      );
    }
    final name = fileName.toLowerCase().endsWith(noteExtension)
        ? fileName
        : '$fileName$noteExtension';
    _validateSegment(name);
    if (name == propertiesFileName) {
      throw const ContentException('"$propertiesFileName" is a reserved name');
    }

    final path = _join(folderPath, name);
    if (await backend.exists(path)) {
      throw ContentException('A note already exists at "$path"');
    }

    final note = initial ??
        Note(
          frontmatter: NoteFrontmatter(title: _stripExtension(name)),
          body: '',
        );
    await saveNote(path, note);
    return NoteNode(path: path, name: name);
  }

  /// Creates a folder named [name] inside [parentPath] by writing its
  /// `properties.yaml`.
  ///
  /// Throws [ContentException] if the name is invalid or the folder already
  /// exists. Returns the new (empty) [FolderNode].
  Future<FolderNode> createFolder(String parentPath, String name) async {
    _validateSegment(name);
    if (name == attachmentsDirName) {
      throw const ContentException('"$attachmentsDirName" is a reserved name');
    }

    final path = _join(parentPath, name);
    final propsPath = _join(path, propertiesFileName);
    if (await backend.exists(propsPath)) {
      throw ContentException('A folder already exists at "$path"');
    }

    final props = FolderProperties(title: name, created: DateTime.now().toUtc());
    final plain = Uint8List.fromList(utf8.encode(props.toYaml()));
    await backend.write(propsPath, codec.encode(plain));
    return FolderNode(path: path, name: name);
  }

  /// Reads a folder's metadata (decoding through the codec).
  Future<FolderProperties> readFolderProperties(String folderPath) async {
    final stored = await backend.read(_join(folderPath, propertiesFileName));
    return FolderProperties.parse(utf8.decode(codec.decode(stored)));
  }

  /// Writes a folder's metadata (encoding through the codec).
  Future<void> writeFolderProperties(
    String folderPath,
    FolderProperties properties,
  ) async {
    final plain = Uint8List.fromList(utf8.encode(properties.toYaml()));
    await backend.write(_join(folderPath, propertiesFileName), codec.encode(plain));
  }

  /// Sets (or clears, with a null [colorHex]) a folder's accent color, creating
  /// its properties if they do not yet exist.
  Future<void> setFolderColor(String folderPath, String? colorHex) async {
    FolderProperties properties;
    try {
      properties = await readFolderProperties(folderPath);
    } catch (_) {
      final name = folderPath.split('/').where((s) => s.isNotEmpty).last;
      properties = FolderProperties(title: name, created: DateTime.now().toUtc());
    }
    await writeFolderProperties(
      folderPath,
      properties.copyWith(color: colorHex, clearColor: colorHex == null),
    );
  }

  /// Deletes the note at [path].
  Future<void> deleteNote(String path) => backend.delete(path);

  /// Deletes the folder at [path] and everything in it.
  Future<void> deleteFolder(String path) => backend.delete(path);

  // --- helpers ---

  bool _isRoot(String path) {
    final trimmed = path.trim();
    return trimmed.isEmpty || trimmed == '/';
  }

  String _join(String base, String segment) {
    final cleanBase = base.trim().replaceAll(RegExp(r'^/+|/+$'), '');
    return cleanBase.isEmpty ? segment : '$cleanBase/$segment';
  }

  void _validateSegment(String segment) {
    if (segment.isEmpty || segment == '.' || segment == '..') {
      throw ContentException('Invalid name: "$segment"');
    }
    if (segment.contains('/') || segment.contains('\\')) {
      throw ContentException('Name may not contain path separators: "$segment"');
    }
  }

  String _stripExtension(String fileName) {
    return fileName.toLowerCase().endsWith(noteExtension)
        ? fileName.substring(0, fileName.length - noteExtension.length)
        : fileName;
  }
}
