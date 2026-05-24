// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../content/content_service.dart';
import '../content/repository_node.dart';
import '../repository/note.dart';
import '../repository/repository.dart';
import '../settings/settings_store.dart';
import '../storage/local_folder_backend.dart';
import '../storage/storage_backend.dart';
import 'editor_view_mode.dart';

/// Drives the UI: owns the open repository, the folder tree, the selected note
/// and its editing buffer. Widget-independent so it can be unit-tested without
/// the OS folder picker.
///
/// Implements the save-before-switch rule from DESIGN.md: changing the selected
/// note flushes a dirty buffer to disk first.
class AppController extends ChangeNotifier {
  final SettingsStore _settings;

  AppController({SettingsStore? settings})
      : _settings = settings ?? InMemorySettingsStore();

  Repository? _repository;
  ContentService? _content;
  FolderNode? _tree;

  String? _selectedNotePath;
  Note? _currentNote;
  String _workingBody = '';
  bool _dirty = false;

  /// Bumped when the working body is changed programmatically (e.g. inserting
  /// an attachment) so the editor widget reloads from it.
  int _editorRevision = 0;

  // View settings (device-local) and the current note's resolved view.
  DefaultViewPolicy _viewPolicy = DefaultViewPolicy.noteSpecified;
  EditorViewMode _defaultNoteView = EditorViewMode.edit;
  EditorViewMode _viewMode = EditorViewMode.edit;

  bool _busy = false;
  String? _error;

  // --- read-only state ---
  bool get hasRepository => _repository != null;
  String get repositoryName => _repository?.name ?? 'Margin';
  FolderNode? get tree => _tree;
  String? get selectedNotePath => _selectedNotePath;

  /// Whether the open repository lives on the local filesystem (so its files
  /// can be revealed in the OS file manager).
  bool get isLocalRepository => _repository?.backend is LocalFolderBackend;

  /// The absolute on-disk path for a repository-relative [path], or null if the
  /// repository is not on the local filesystem.
  String? localAbsolutePath(String path) {
    final backend = _repository?.backend;
    return backend is LocalFolderBackend ? backend.absolutePathOf(path) : null;
  }

  /// The accent color (`#RRGGBB`) of the folder containing the selected note,
  /// or null. Used as a per-note visual cue.
  String? get selectedNoteFolderColor {
    final notePath = _selectedNotePath;
    final tree = _tree;
    if (notePath == null || tree == null) return null;
    final slash = notePath.lastIndexOf('/');
    final folderPath = slash < 0 ? '' : notePath.substring(0, slash);
    return _findFolder(tree, folderPath)?.color;
  }
  Note? get currentNote => _currentNote;
  String get workingBody => _workingBody;
  int get editorRevision => _editorRevision;
  bool get isDirty => _dirty;

  DefaultViewPolicy get viewPolicy => _viewPolicy;
  EditorViewMode get defaultNoteView => _defaultNoteView;
  EditorViewMode get viewMode => _viewMode;
  bool get isBusy => _busy;
  String? get error => _error;

  // --- opening / creating (path-based, used by the picker UI) ---

  /// App startup: load view settings, then restore the last repository.
  Future<void> start() async {
    await _loadViewSettings();
    await restoreLastRepository();
  }

  Future<void> _loadViewSettings() async {
    try {
      _viewPolicy = defaultViewPolicyFromId(await _settings.getViewPolicy());
      _defaultNoteView =
          editorViewModeFromId(await _settings.getDefaultNoteView()) ??
              EditorViewMode.edit;
    } catch (_) {
      // Settings unavailable (e.g. tests): keep defaults.
    }
  }

  /// Attempts to reopen the last-used repository, if any. Silently falls back
  /// to the landing screen if it is missing or invalid (and forgets it).
  Future<void> restoreLastRepository() async {
    String? path;
    try {
      path = await _settings.getLastRepositoryPath();
    } catch (_) {
      return; // settings unavailable (e.g. in tests) -> show landing
    }
    if (path == null) return;
    await openPath(path);
    if (!hasRepository) {
      await _settings.setLastRepositoryPath(null);
    }
  }

  Future<void> openPath(String path) async {
    await open(LocalFolderBackend(path));
    if (hasRepository) {
      await _settings.setLastRepositoryPath(path);
    }
  }

  /// Opens (or creates) a repository in this device's app documents directory —
  /// the portable, no-picker option that works on mobile, where arbitrary
  /// folders aren't reachable via `dart:io`.
  Future<void> openDeviceRepository({String name = 'My Notes'}) async {
    final docs = await getApplicationDocumentsDirectory();
    final repoPath = p.join(docs.path, 'Margin');
    await Directory(repoPath).create(recursive: true);
    final backend = LocalFolderBackend(repoPath);
    if (await backend.exists('properties.yaml')) {
      await openPath(repoPath);
    } else {
      await createPath(repoPath, name);
    }
  }

  Future<void> createPath(String path, String name) async {
    await create(LocalFolderBackend(path), name);
    if (hasRepository) {
      await _settings.setLastRepositoryPath(path);
    }
  }

  /// Opens an existing repository on [backend]. Exposed for tests.
  Future<void> open(StorageBackend backend) async {
    await _run(() async {
      final repo = await Repository.open(backend);
      _adopt(repo, ContentService(backend));
      await _reloadTree();
      await _restoreLastNote();
    });
  }

  /// Creates a new repository on [backend]. Exposed for tests.
  Future<void> create(StorageBackend backend, String name) async {
    await _run(() async {
      final repo = await Repository.create(backend, name: name);
      _adopt(repo, ContentService(backend));
      await _reloadTree();
    });
  }

  void closeRepository() {
    _repository = null;
    _content = null;
    _tree = null;
    _selectedNotePath = null;
    _currentNote = null;
    _workingBody = '';
    _dirty = false;
    // Explicit close: forget the repository (and note) so the next launch shows
    // the landing screen rather than reopening it.
    unawaited(_settings.setLastRepositoryPath(null));
    unawaited(_settings.setLastNotePath(null));
    notifyListeners();
  }

  // --- navigation ---

  Future<void> selectNote(NoteNode note) async {
    if (note.path == _selectedNotePath) return;
    await _run(() async {
      await _flushIfDirty();
      final loaded = await _content!.readNote(note.path);
      _selectedNotePath = note.path;
      _currentNote = loaded;
      _workingBody = loaded.body;
      _dirty = false;
      _viewMode = await _resolveViewMode();
      unawaited(_settings.setLastNotePath(note.path));
    });
  }

  // --- editing ---

  void updateBody(String body) {
    if (body == _workingBody) return;
    _workingBody = body;
    _dirty = true;
    notifyListeners();
  }

  Future<void> save() async {
    if (!_dirty || _currentNote == null || _selectedNotePath == null) return;
    await _run(_flushIfDirty);
  }

  /// Stores [bytes] as an attachment of the open note, inserts a Markdown link
  /// (an image embed for image types), and saves. Does nothing if no note is
  /// open.
  Future<void> attachToCurrentNote(String fileName, Uint8List bytes) async {
    final notePath = _selectedNotePath;
    if (notePath == null) return;
    await _run(() async {
      final slash = notePath.lastIndexOf('/');
      final folderPath = slash < 0 ? '' : notePath.substring(0, slash);
      final link = await _content!.addAttachment(folderPath, fileName, bytes);

      final snippet =
          _looksLikeImage(fileName) ? '![]($link)' : '[$fileName]($link)';
      final needsNewline = _workingBody.isNotEmpty && !_workingBody.endsWith('\n');
      _workingBody = '$_workingBody${needsNewline ? '\n' : ''}$snippet\n';
      _dirty = true;
      _editorRevision++;
      await _flushIfDirty();
    });
  }

  bool _looksLikeImage(String fileName) {
    final lower = fileName.toLowerCase();
    return const ['.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.svg']
        .any(lower.endsWith);
  }

  // --- view mode ---

  /// Sets the current note's view. Under the "note specified" policy this is
  /// remembered in the note's sidecar so it reopens the same way.
  Future<void> setViewMode(EditorViewMode mode) async {
    _viewMode = mode;
    notifyListeners();
    if (_viewPolicy == DefaultViewPolicy.noteSpecified &&
        _selectedNotePath != null) {
      try {
        await _content!.setNoteView(_selectedNotePath!, mode.id);
      } catch (_) {
        // Persisting the view is best-effort.
      }
    }
  }

  Future<void> setViewPolicy(DefaultViewPolicy policy) async {
    _viewPolicy = policy;
    await _settings.setViewPolicy(policy.id);
    _viewMode = await _resolveViewMode();
    notifyListeners();
  }

  Future<void> setDefaultNoteView(EditorViewMode mode) async {
    _defaultNoteView = mode;
    await _settings.setDefaultNoteView(mode.id);
    _viewMode = await _resolveViewMode();
    notifyListeners();
  }

  /// Resolves which view the open note should use, per the policy.
  Future<EditorViewMode> _resolveViewMode() async {
    final forced = _viewPolicy.forcedMode;
    if (forced != null) return forced;
    final notePath = _selectedNotePath;
    if (notePath == null) return _defaultNoteView;
    final stored = editorViewModeFromId(await _content?.readNoteViewId(notePath));
    return stored ?? _defaultNoteView;
  }

  // --- mutations ---

  /// Creates a folder named [name] under [parentPath] (default: the root).
  Future<void> createFolder(String name, {String parentPath = ''}) async {
    await _run(() async {
      await _content!.createFolder(parentPath, name);
      await _reloadTree();
    });
  }

  /// Creates a note named [name] inside [folderPath] and selects it.
  Future<void> createNote(String name, {required String folderPath}) async {
    await _run(() async {
      final now = DateTime.now().toUtc();
      final node = await _content!.createNote(
        folderPath,
        name,
        initial: Note(
          frontmatter: NoteFrontmatter(title: name, created: now, updated: now),
          body: '',
        ),
      );
      await _reloadTree();
      await selectNote(node);
    });
  }

  /// Sets (or clears, with null) a folder's accent color.
  Future<void> setFolderColor(String path, String? colorHex) async {
    await _run(() async {
      await _content!.setFolderColor(path, colorHex);
      await _reloadTree();
    });
  }

  /// Renames the folder at [path] to [newName], keeping the open note selected
  /// if it lived inside the renamed folder.
  Future<void> renameFolder(String path, String newName) async {
    await _run(() async {
      final newPath = await _content!.renameFolder(path, newName);
      final selected = _selectedNotePath;
      if (selected != null &&
          (selected == path || selected.startsWith('$path/'))) {
        final updated = selected.replaceFirst(path, newPath);
        _selectedNotePath = updated;
        unawaited(_settings.setLastNotePath(updated));
      }
      await _reloadTree();
    });
  }

  Future<void> deleteNote(String path) async {
    await _run(() async {
      await _content!.deleteNote(path);
      if (_selectedNotePath == path) {
        _selectedNotePath = null;
        _currentNote = null;
        _workingBody = '';
        _dirty = false;
      }
      await _reloadTree();
    });
  }

  Future<void> deleteFolder(String path) async {
    await _run(() async {
      await _content!.deleteFolder(path);
      // If the open note lived inside the deleted folder, clear it.
      final selected = _selectedNotePath;
      if (selected != null &&
          (selected == path || selected.startsWith('$path/'))) {
        _selectedNotePath = null;
        _currentNote = null;
        _workingBody = '';
        _dirty = false;
      }
      await _reloadTree();
    });
  }

  // --- internals ---

  void _adopt(Repository repo, ContentService content) {
    _repository = repo;
    _content = content;
    _selectedNotePath = null;
    _currentNote = null;
    _workingBody = '';
    _dirty = false;
  }

  Future<void> _reloadTree() async {
    _tree = await _content!.tree();
  }

  /// Reselects the last opened note if it still exists; otherwise leaves no
  /// selection (the editor shows its "select a note" message).
  Future<void> _restoreLastNote() async {
    final notePath = await _settings.getLastNotePath();
    if (notePath == null || _tree == null) return;
    final node = _findNote(_tree!, notePath);
    if (node == null) return;
    try {
      final loaded = await _content!.readNote(node.path);
      _selectedNotePath = node.path;
      _currentNote = loaded;
      _workingBody = loaded.body;
      _dirty = false;
      _viewMode = await _resolveViewMode();
    } catch (_) {
      // File vanished between listing and reading: leave unselected.
    }
  }

  NoteNode? _findNote(FolderNode folder, String path) {
    for (final note in folder.notes) {
      if (note.path == path) return note;
    }
    for (final child in folder.folders) {
      final found = _findNote(child, path);
      if (found != null) return found;
    }
    return null;
  }

  FolderNode? _findFolder(FolderNode folder, String path) {
    if (folder.path == path) return folder;
    for (final child in folder.folders) {
      final found = _findFolder(child, path);
      if (found != null) return found;
    }
    return null;
  }

  Future<void> _flushIfDirty() async {
    if (!_dirty || _currentNote == null || _selectedNotePath == null) return;
    final previous = _currentNote!.frontmatter;
    final updated = Note(
      frontmatter: NoteFrontmatter(
        title: previous.title,
        created: previous.created,
        updated: DateTime.now().toUtc(),
        tags: previous.tags,
      ),
      body: _workingBody,
    );
    await _content!.saveNote(_selectedNotePath!, updated);
    _currentNote = updated;
    _dirty = false;
  }

  /// Runs [action] with busy/error bookkeeping and a single notification.
  Future<void> _run(Future<void> Function() action) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await action();
    } catch (e) {
      _error = e.toString();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
