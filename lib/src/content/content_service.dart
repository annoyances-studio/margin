// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:typed_data';

import '../folio/folder_properties.dart';
import '../folio/note.dart';
import '../folio/note_properties.dart';
import '../storage/content_codec.dart';
import '../storage/storage_backend.dart';
import 'content_exception.dart';
import 'tree_node.dart';

/// Reads and edits the contents of a Folio: the folder tree, notes, and
/// folder metadata. This is the layer the UI binds to (DESIGN.md).
///
/// Note bodies and folder properties are routed through the [ContentCodec]
/// seam, so encryption can later apply to them transparently. The root
/// `properties.yaml` is intentionally NOT handled here — it must stay plaintext
/// (it holds the encryption recipe) and is managed by [Folio].
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

    int byName(TreeNode a, TreeNode b) =>
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
  /// overwriting any existing file, then refreshes its sidecar index so the two
  /// never drift.
  Future<void> saveNote(String path, Note note) async {
    final plain = Uint8List.fromList(utf8.encode(note.serialize()));
    await backend.write(path, codec.encode(plain));
    await _writeNoteIndex(path, note);
  }

  /// Rewrites a note's sidecar so its search-index fields (title/tags/updated)
  /// mirror [note], while preserving the device/UI [NoteProperties.view]. This
  /// keeps `<note>.md.yaml` a faithful, openable-without-the-body index of the
  /// note — the small file search scans instead of every `.md`.
  Future<void> _writeNoteIndex(String notePath, Note note) async {
    final existing = await readNoteProperties(notePath); // keep view
    final indexed = NoteProperties(
      title: note.frontmatter.title,
      tags: note.frontmatter.tags,
      updated: note.frontmatter.updated,
      view: existing.view,
    );
    await writeNoteProperties(notePath, indexed);
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

  /// Stores [bytes] as an attachment inside [folderPath]'s `_attachments/`
  /// directory and returns a note-relative link (e.g. `_attachments/pic.png`).
  ///
  /// The name is sanitized and de-duplicated. Attachment bytes go through the
  /// codec like note content (so encryption, when enabled, covers them too).
  Future<String> addAttachment(
    String folderPath,
    String fileName,
    Uint8List bytes,
  ) async {
    final dir = _join(folderPath, attachmentsDirName);
    var name = _sanitizeFileName(fileName);
    if (await backend.exists(_join(dir, name))) {
      final dot = name.lastIndexOf('.');
      final stem = dot > 0 ? name.substring(0, dot) : name;
      final ext = dot > 0 ? name.substring(dot) : '';
      name = '$stem-${DateTime.now().millisecondsSinceEpoch}$ext';
    }
    await backend.write(_join(dir, name), codec.encode(bytes));
    return '$attachmentsDirName/$name';
  }

  String _sanitizeFileName(String fileName) {
    final base = fileName.split(RegExp(r'[\\/]')).last.trim();
    // Replace only characters that are illegal on common filesystems, plus
    // spaces (to keep Markdown links simple). Unicode letters — Japanese,
    // accented, etc. — are preserved.
    var cleaned = base
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .replaceAll(' ', '_');
    // Windows disallows trailing dots/spaces.
    cleaned = cleaned.replaceAll(RegExp(r'[. ]+$'), '');
    return cleaned.isEmpty ? 'attachment' : cleaned;
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

  /// Deletes the note at [path] and its sidecar properties, if any.
  Future<void> deleteNote(String path) async {
    await backend.delete(path);
    await backend.delete(_notePropertiesPath(path));
  }

  String _notePropertiesPath(String notePath) => '$notePath.yaml';

  /// Reads a note's sidecar properties — its search-index record (title, tags,
  /// updated) plus UI prefs (view) — decoding through the codec. Returns empty
  /// properties if there is no sidecar. This is the small file search scans
  /// instead of opening the note body.
  Future<NoteProperties> readNoteProperties(String notePath) async {
    try {
      final stored = await backend.read(_notePropertiesPath(notePath));
      return NoteProperties.parse(utf8.decode(codec.decode(stored)));
    } catch (_) {
      return const NoteProperties();
    }
  }

  /// Writes a note's sidecar properties, deleting the sidecar if empty.
  Future<void> writeNoteProperties(
    String notePath,
    NoteProperties properties,
  ) async {
    final path = _notePropertiesPath(notePath);
    if (properties.isEmpty) {
      await backend.delete(path);
      return;
    }
    final plain = Uint8List.fromList(utf8.encode(properties.toYaml()));
    await backend.write(path, codec.encode(plain));
  }

  /// The stored view id for a note (`editor`/`split`/`preview`), or null.
  Future<String?> readNoteViewId(String notePath) async =>
      (await readNoteProperties(notePath)).view;

  /// Records the view id for a note in its sidecar.
  Future<void> setNoteView(String notePath, String viewId) async {
    final props = await readNoteProperties(notePath);
    await writeNoteProperties(notePath, props.copyWith(view: viewId));
  }

  /// Deletes the folder at [path] and everything in it.
  Future<void> deleteFolder(String path) => backend.delete(path);

  /// Renames the folder at [folderPath] to [newName] within the same parent,
  /// moving all of its contents. Returns the new folder path.
  ///
  /// Throws [ContentException] if the name is invalid, the folder is the root,
  /// or a sibling with that name already exists.
  Future<String> renameFolder(String folderPath, String newName) async {
    if (_isRoot(folderPath)) {
      throw const ContentException('The repository root cannot be renamed');
    }
    _validateSegment(newName);
    if (newName == attachmentsDirName) {
      throw const ContentException('"$attachmentsDirName" is a reserved name');
    }

    final parent = _parentOf(folderPath);
    final newPath = _join(parent, newName);
    if (newPath == folderPath) return folderPath;

    // A case-only rename (e.g. "LEvel" -> "Level") collides with itself on
    // case-insensitive filesystems (Windows, default macOS): the target
    // "exists" because it is the same directory. Detect it and route through a
    // temporary name so the copy/delete don't operate on the same path.
    final caseOnly = newPath.toLowerCase() == folderPath.toLowerCase();
    if (!caseOnly && await backend.exists(newPath)) {
      throw ContentException('A folder named "$newName" already exists');
    }

    // Move raw bytes (no codec) so any encryption is preserved as-is.
    if (caseOnly) {
      final temp = _join(
        parent,
        '.margin-rename-${DateTime.now().microsecondsSinceEpoch}',
      );
      await _copyDirectoryRaw(folderPath, temp);
      await backend.delete(folderPath);
      await _copyDirectoryRaw(temp, newPath);
      await backend.delete(temp);
    } else {
      await _copyDirectoryRaw(folderPath, newPath);
      await backend.delete(folderPath);
    }

    // Keep the folder's own title in sync with its new name (best effort).
    try {
      final props = await readFolderProperties(newPath);
      await writeFolderProperties(newPath, props.copyWith(title: newName));
    } catch (_) {
      // No/unreadable properties: nothing to update.
    }
    return newPath;
  }

  Future<void> _copyDirectoryRaw(String from, String to) async {
    for (final entry in await backend.list(from)) {
      final target = _join(to, entry.name);
      if (entry.isDirectory) {
        await _copyDirectoryRaw(entry.path, target);
      } else {
        await backend.write(target, await backend.read(entry.path));
      }
    }
  }

  String _parentOf(String path) {
    final clean = path.trim().replaceAll(RegExp(r'^/+|/+$'), '');
    final slash = clean.lastIndexOf('/');
    return slash < 0 ? '' : clean.substring(0, slash);
  }

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
