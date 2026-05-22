// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/foundation.dart';

import '../content/content_service.dart';
import '../content/repository_node.dart';
import '../repository/note.dart';
import '../repository/repository.dart';
import '../storage/local_folder_backend.dart';
import '../storage/storage_backend.dart';

/// Drives the UI: owns the open repository, the folder tree, the selected note
/// and its editing buffer. Widget-independent so it can be unit-tested without
/// the OS folder picker.
///
/// Implements the save-before-switch rule from DESIGN.md: changing the selected
/// note flushes a dirty buffer to disk first.
class AppController extends ChangeNotifier {
  Repository? _repository;
  ContentService? _content;
  FolderNode? _tree;

  String? _selectedFolderPath; // target for new notes/folders ('' = root)
  String? _selectedNotePath;
  Note? _currentNote;
  String _workingBody = '';
  bool _dirty = false;

  bool _busy = false;
  String? _error;

  // --- read-only state ---
  bool get hasRepository => _repository != null;
  String get repositoryName => _repository?.name ?? 'Margin';
  FolderNode? get tree => _tree;
  String? get selectedFolderPath => _selectedFolderPath;
  String? get selectedNotePath => _selectedNotePath;
  Note? get currentNote => _currentNote;
  String get workingBody => _workingBody;
  bool get isDirty => _dirty;
  bool get isBusy => _busy;
  String? get error => _error;

  // --- opening / creating (path-based, used by the picker UI) ---

  Future<void> openPath(String path) => open(LocalFolderBackend(path));

  Future<void> createPath(String path, String name) =>
      create(LocalFolderBackend(path), name);

  /// Opens an existing repository on [backend]. Exposed for tests.
  Future<void> open(StorageBackend backend) async {
    await _run(() async {
      final repo = await Repository.open(backend);
      _adopt(repo, ContentService(backend));
      await _reloadTree();
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
    _selectedFolderPath = null;
    _selectedNotePath = null;
    _currentNote = null;
    _workingBody = '';
    _dirty = false;
    notifyListeners();
  }

  // --- navigation ---

  void selectFolder(String path) {
    _selectedFolderPath = path;
    notifyListeners();
  }

  Future<void> selectNote(NoteNode note) async {
    if (note.path == _selectedNotePath) return;
    await _run(() async {
      await _flushIfDirty();
      final loaded = await _content!.readNote(note.path);
      _selectedNotePath = note.path;
      _currentNote = loaded;
      _workingBody = loaded.body;
      _dirty = false;
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

  // --- mutations ---

  Future<void> createFolder(String name) async {
    await _run(() async {
      await _content!.createFolder(_selectedFolderPath ?? '', name);
      await _reloadTree();
    });
  }

  Future<void> createNote(String name) async {
    await _run(() async {
      final now = DateTime.now().toUtc();
      final node = await _content!.createNote(
        _selectedFolderPath ?? '',
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

  // --- internals ---

  void _adopt(Repository repo, ContentService content) {
    _repository = repo;
    _content = content;
    _selectedFolderPath = '';
    _selectedNotePath = null;
    _currentNote = null;
    _workingBody = '';
    _dirty = false;
  }

  Future<void> _reloadTree() async {
    _tree = await _content!.tree();
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
