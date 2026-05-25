// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../content/content_service.dart';
import '../content/tree_node.dart';
import '../credentials/credential_store.dart';
import '../folio/note.dart';
import '../folio/folio.dart';
import '../settings/settings_store.dart';
import '../storage/local_folder_backend.dart';
import '../storage/storage_backend.dart';
import '../storage/webdav_backend.dart';
import '../sync/sync_engine.dart';
import '../sync/sync_state_store.dart';
import 'editor_view_mode.dart';

/// Drives the UI: owns the open repository, the folder tree, the selected note
/// and its editing buffer. Widget-independent so it can be unit-tested without
/// the OS folder picker.
///
/// Implements the save-before-switch rule from DESIGN.md: changing the selected
/// note flushes a dirty buffer to disk first.
class AppController extends ChangeNotifier {
  final SettingsStore _settings;
  final CredentialStore _credentials;
  final SyncStateStore _syncStates;

  /// Builds HTTP clients for WebDAV. Injectable so tests can supply a mock.
  final http.Client Function() _httpClientFactory;

  /// Resolves the parent directory for per-Folio caches (`<root>/<UUID>/`).
  /// Injectable so tests can use a temp dir instead of the OS documents dir.
  final Future<Directory> Function() _cacheRoot;

  AppController({
    SettingsStore? settings,
    CredentialStore? credentials,
    SyncStateStore? syncStates,
    http.Client Function()? httpClientFactory,
    Future<Directory> Function()? cacheRoot,
  })  : _settings = settings ?? InMemorySettingsStore(),
        _credentials = credentials ?? InMemoryCredentialStore(),
        _syncStates = syncStates ?? InMemorySyncStateStore(),
        _httpClientFactory = httpClientFactory ?? (() => http.Client()),
        _cacheRoot = cacheRoot ??
            (() async {
              final docs = await getApplicationDocumentsDirectory();
              return Directory(p.join(docs.path, 'Margin'));
            });

  /// The remote sync peer for the open cached Folio (null for purely local
  /// Folios), and that Folio's id — kept for later background/manual sync.
  StorageBackend? _syncPeer;
  String? _folioId;

  /// Progress of an in-flight cache/sync, or null when idle.
  ({int completed, int total})? _syncProgress;
  ({int completed, int total})? get syncProgress => _syncProgress;

  /// Whether the open Folio has a remote peer it can sync with.
  bool get canSync => _syncPeer != null;

  /// A label for conflict copies. Best-effort; falls back to a constant.
  String get _deviceName {
    try {
      return Platform.localHostname;
    } catch (_) {
      return 'Margin';
    }
  }

  /// Keystore key for a WebDAV password, derived from its (non-secret) URL and
  /// username — both known before we can connect.
  static String _webDavCredKey(String url, String username) =>
      'webdav|$url|$username';

  Folio? _folio;
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

  /// Whether the desktop window floats above others (device-local).
  bool _alwaysOnTop = false;

  bool _busy = false;
  String? _error;

  // --- read-only state ---
  bool get hasFolio => _folio != null;
  String get folioName => _folio?.name ?? 'Margin';
  FolderNode? get tree => _tree;
  String? get selectedNotePath => _selectedNotePath;

  /// Whether the open repository lives on the local filesystem (so its files
  /// can be revealed in the OS file manager).
  bool get isLocalFolio => _folio?.backend is LocalFolderBackend;

  /// The absolute on-disk path for a repository-relative [path], or null if the
  /// repository is not on the local filesystem.
  String? localAbsolutePath(String path) {
    final backend = _folio?.backend;
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
  bool get alwaysOnTop => _alwaysOnTop;
  bool get isBusy => _busy;
  String? get error => _error;

  // --- opening / creating (path-based, used by the picker UI) ---

  /// App startup: load view settings, then restore the last repository.
  Future<void> start() async {
    await _loadViewSettings();
    await restoreLastFolio();
  }

  Future<void> _loadViewSettings() async {
    try {
      _viewPolicy = defaultViewPolicyFromId(await _settings.getViewPolicy());
      _defaultNoteView =
          editorViewModeFromId(await _settings.getDefaultNoteView()) ??
              EditorViewMode.edit;
      _alwaysOnTop = await _settings.getAlwaysOnTop();
    } catch (_) {
      // Settings unavailable (e.g. tests): keep defaults.
    }
  }

  /// Persists and updates the always-on-top preference. Applying it to the OS
  /// window is the UI layer's job (desktop-only).
  Future<void> setAlwaysOnTop(bool value) async {
    _alwaysOnTop = value;
    await _settings.setAlwaysOnTop(value);
    notifyListeners();
  }

  /// Attempts to reopen the last-used Folio, if any — local or WebDAV. Silently
  /// falls back to the landing screen if it is missing or invalid (and forgets
  /// it).
  Future<void> restoreLastFolio() async {
    String? type;
    String? location;
    try {
      type = await _settings.getLastFolioType();
      location = await _settings.getLastFolioPath();
    } catch (_) {
      return; // settings unavailable (e.g. in tests) -> show landing
    }
    if (location == null) return;

    if (type == 'webdav') {
      final username = await _settings.getLastWebDavUser() ?? '';
      final password =
          await _credentials.read(_webDavCredKey(location, username));
      if (password == null) return; // can't reconnect without the secret
      await openWebDav(location, username, password);
      if (!hasFolio) await _settings.setLastFolioType(null);
    } else {
      await openPath(location);
      if (!hasFolio) await _settings.setLastFolioPath(null);
    }
  }

  Future<void> openPath(String path) async {
    await open(LocalFolderBackend(path));
    if (hasFolio) {
      await _settings.setLastFolioType('local');
      await _settings.setLastFolioPath(path);
    }
  }

  /// Connects to a WebDAV Folio at [url] with [username]/[password]. On success
  /// records it as the last Folio and stores the password in the OS keystore
  /// (the URL and username are non-secret and kept in settings).
  Future<void> openWebDav(String url, String username, String password) async {
    final StorageBackend backend;
    try {
      backend = WebDavBackend(
        baseUrl: Uri.parse(url),
        username: username,
        password: password,
        client: _httpClientFactory(),
      );
    } catch (e) {
      // A malformed URL throws synchronously, before the error handling below;
      // surface it so the landing screen can show it.
      _error = 'Invalid server URL: $e';
      notifyListeners();
      return;
    }
    await openThroughCache(backend);
    if (hasFolio) {
      await _settings.setLastFolioType('webdav');
      await _settings.setLastFolioPath(url);
      await _settings.setLastWebDavUser(username);
      await _credentials.write(_webDavCredKey(url, username), password);
    }
  }

  /// Opens a [remote] Folio through a local cache (clone-then-sync): identifies
  /// the remote Folio, syncs it into `<cacheRoot>/<id>/`, then adopts that local
  /// cache as the working backend with [remote] kept as the sync peer. This is
  /// what makes a remote Folio's notes and attachments work offline with real
  /// on-disk paths. Exposed for tests; [openWebDav] builds the WebDAV remote.
  Future<void> openThroughCache(StorageBackend remote) async {
    await _run(() async {
      // 1. Identify the remote Folio (its id keys the cache and sync state).
      final id = (await Folio.open(remote)).id;

      // 2. Prepare the local cache directory.
      final root = await _cacheRoot();
      final cacheDir = Directory(p.join(root.path, id));
      await cacheDir.create(recursive: true);
      final local = LocalFolderBackend(cacheDir.path);

      // 3. Clone/sync remote -> local cache, reporting progress.
      final engine = SyncEngine(
        local: local,
        remote: remote,
        deviceName: _deviceName,
      );
      final result = await engine.sync(
        await _syncStates.load(id),
        onProgress: (p) {
          _syncProgress = (completed: p.completed, total: p.total);
          notifyListeners();
        },
      );
      await _syncStates.save(id, result.newState);
      _syncProgress = null;

      // 4. Adopt the local cache as the working backend; keep the remote peer.
      _adopt(await Folio.open(local), ContentService(local));
      _syncPeer = remote;
      _folioId = id;
      await _reloadTree();
      await _restoreLastNote();
    });
  }

  /// Syncs the open cached Folio with its remote peer: flushes pending edits to
  /// the cache, reconciles cache ⇄ remote, and refreshes the tree. No-op for a
  /// purely local Folio.
  Future<void> syncNow() async {
    final peer = _syncPeer;
    final id = _folioId;
    final folio = _folio;
    if (peer == null || id == null || folio == null) return;
    await _run(() async {
      await _flushIfDirty();
      final engine = SyncEngine(
        local: folio.backend,
        remote: peer,
        deviceName: _deviceName,
      );
      final result = await engine.sync(
        await _syncStates.load(id),
        onProgress: (p) {
          _syncProgress = (completed: p.completed, total: p.total);
          notifyListeners();
        },
      );
      await _syncStates.save(id, result.newState);
      _syncProgress = null;
      await _reloadTree();
    });
  }

  /// Opens (or creates) a repository in this device's app documents directory —
  /// the portable, no-picker option that works on mobile, where arbitrary
  /// folders aren't reachable via `dart:io`.
  Future<void> openDeviceFolio({String name = 'My Notes'}) async {
    final docs = await getApplicationDocumentsDirectory();
    // The on-device Folio lives under Margin/DeviceNotes/, leaving Margin/ as
    // the parent for per-Folio remote caches (Margin/<UUID>/) added later.
    final repoPath = p.join(docs.path, 'Margin', 'DeviceNotes');
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
    if (hasFolio) {
      await _settings.setLastFolioType('local');
      await _settings.setLastFolioPath(path);
    }
  }

  /// Opens an existing repository on [backend]. Exposed for tests.
  Future<void> open(StorageBackend backend) async {
    await _run(() async {
      final repo = await Folio.open(backend);
      _adopt(repo, ContentService(backend));
      await _reloadTree();
      await _restoreLastNote();
    });
  }

  /// Creates a new repository on [backend]. Exposed for tests.
  Future<void> create(StorageBackend backend, String name) async {
    await _run(() async {
      final repo = await Folio.create(backend, name: name);
      _adopt(repo, ContentService(backend));
      await _reloadTree();
    });
  }

  void closeFolio() {
    _folio = null;
    _content = null;
    _tree = null;
    _selectedNotePath = null;
    _currentNote = null;
    _workingBody = '';
    _dirty = false;
    _syncPeer = null;
    _folioId = null;
    _syncProgress = null;
    // Explicit close: forget the Folio (and note) so the next launch shows
    // the landing screen rather than reopening it. (Any WebDAV password stays
    // in the keystore; re-adding the same URL reuses it.)
    unawaited(_settings.setLastFolioType(null));
    unawaited(_settings.setLastFolioPath(null));
    unawaited(_settings.setLastWebDavUser(null));
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

  void _adopt(Folio repo, ContentService content) {
    _folio = repo;
    _content = content;
    _selectedNotePath = null;
    _currentNote = null;
    _workingBody = '';
    _dirty = false;
    // Cleared here; openThroughCache sets them after adopting the cache.
    _syncPeer = null;
    _folioId = null;
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
      _syncProgress = null;
      notifyListeners();
    }
  }
}
