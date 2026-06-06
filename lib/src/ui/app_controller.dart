// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../content/content_service.dart';
import '../content/markdown_convert.dart';
import '../content/tree_node.dart';
import '../credentials/credential_store.dart';
import '../folio/note.dart';
import '../folio/note_properties.dart';
import '../folio/folio.dart';
import '../folio/folio_exception.dart';
import '../settings/settings_store.dart';
import '../storage/local_folder_backend.dart';
import '../storage/onedrive_auth.dart';
import '../storage/onedrive_backend.dart';
import '../storage/onedrive_oauth.dart';
import '../storage/storage_backend.dart';
import '../storage/storage_exception.dart';
import '../storage/webdav_backend.dart';
import '../sync/sync_engine.dart';
import '../sync/sync_state_store.dart';
import 'clipboard_service.dart';
import 'editor_view_mode.dart';
import 'link_target.dart';

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

  /// Clipboard access (incl. rich HTML). Injectable so tests use a fake.
  final ClipboardService _clipboard;

  AppController({
    SettingsStore? settings,
    CredentialStore? credentials,
    SyncStateStore? syncStates,
    http.Client Function()? httpClientFactory,
    Future<Directory> Function()? cacheRoot,
    ClipboardService? clipboard,
  })  : _settings = settings ?? InMemorySettingsStore(),
        _credentials = credentials ?? InMemoryCredentialStore(),
        _syncStates = syncStates ?? InMemorySyncStateStore(),
        _httpClientFactory = httpClientFactory ?? (() => http.Client()),
        _clipboard = clipboard ?? createClipboardService(),
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

  /// The open Folio's id (the cache key). Exposed for tests.
  @visibleForTesting
  String? get folioId => _folioId;

  /// Local changes saved to the cache but not yet pushed to the remote.
  bool _hasUnsyncedChanges = false;
  bool get hasUnsyncedChanges => _hasUnsyncedChanges;

  /// The last background-sync error (non-blocking; cleared on a successful
  /// sync). Manual sync reports failures through [error] instead.
  String? _syncError;
  String? get syncError => _syncError;

  /// True when a sync was withheld because a side that previously had content
  /// now reads as empty (likely a flaky connection, possibly a real delete).
  /// The UI prompts the user; [confirmEmptyingSync] proceeds, [dismissEmptyingSync]
  /// leaves everything untouched. Guards against a dropped connection wiping data.
  bool _syncNeedsEmptyConfirm = false;
  bool get syncNeedsEmptyConfirm => _syncNeedsEmptyConfirm;

  bool _autoSyncing = false;
  bool _pendingSync = false;

  bool _disposed = false;

  /// Tail of the serialized operation chain (see [_serialize]).
  Future<void> _opChain = Future<void>.value();

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

  /// Whether a run-at-login launch should start hidden in the tray (device-local).
  bool _startMinimized = false;

  bool _busy = false;
  String? _error;

  /// True only while reconnecting a remembered Folio at startup. Lets the UI
  /// show a splash instead of the open/landing screen during the reconnect, so
  /// a cold restart (e.g. Android reclaimed the process) doesn't flash the
  /// landing screen before the Folio reappears.
  bool _restoring = false;
  bool get isRestoring => _restoring;

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
  bool get startMinimized => _startMinimized;
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
      _startMinimized = await _settings.getStartMinimized();
    } catch (_) {
      // Settings unavailable (e.g. tests): keep defaults.
    }
  }

  /// Persists and updates the "start minimized at login" preference. Registering
  /// the launch flag is the UI/startup layer's job (desktop-only).
  Future<void> setStartMinimized(bool value) async {
    _startMinimized = value;
    await _settings.setStartMinimized(value);
    notifyListeners();
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

    // We have a Folio to reconnect: signal the UI to show a splash instead of
    // the landing screen while we do (the reconnect can hit the network).
    _restoring = true;
    _notify();
    try {
      // Pass the cached Folio id so an offline reopen adopts the cache instead
      // of waiting on (and failing) a remote identify.
      final knownId = await _settings.getLastFolioId();
      if (type == 'webdav') {
        final username = await _settings.getLastWebDavUser() ?? '';
        final password =
            await _credentials.read(_webDavCredKey(location, username));
        if (password == null) return; // can't reconnect without the secret
        await openWebDav(location, username, password, knownId: knownId);
        if (!hasFolio) await _settings.setLastFolioType(null);
      } else if (type == 'onedrive') {
        // Tokens live in the keystore; if sign-in lapsed, openOneDrive surfaces
        // the error and we fall back to the landing screen.
        await openOneDrive(location, knownId: knownId);
        if (!hasFolio) await _settings.setLastFolioType(null);
      } else {
        await openPath(location);
        if (!hasFolio) await _settings.setLastFolioPath(null);
      }
    } finally {
      _restoring = false;
      _notify();
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
  Future<void> openWebDav(
    String url,
    String username,
    String password, {
    String? knownId,
  }) async {
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
    await openThroughCache(backend, knownId: knownId);
    if (hasFolio) {
      await _settings.setLastFolioType('webdav');
      await _settings.setLastFolioPath(url);
      await _settings.setLastWebDavUser(username);
      await _credentials.write(_webDavCredKey(url, username), password);
    }
  }

  /// Builds the OneDrive auth helper, reading the build-time client id/redirect
  /// URI and persisting tokens in the same keystore as other credentials.
  OneDriveAuth _buildOneDriveAuth() => OneDriveAuth(
        clientId: OneDriveAuth.clientIdFromEnv,
        redirectUri: OneDriveAuth.redirectUriFromEnv,
        credentials: _credentials,
        authorize: FlutterAppAuthOneDriveAuthorize().call,
        refresh: HttpOneDriveRefresh(client: _httpClientFactory()).call,
      );

  /// Whether a OneDrive sign-in is already on file (so the connect flow can skip
  /// the browser and go straight to choosing a folder).
  Future<bool> get isOneDriveSignedIn => _buildOneDriveAuth().isSignedIn;

  /// Drives the OneDrive OAuth sign-in (system browser). Returns true on
  /// success. Failures are surfaced via [error]. Safe to call when already
  /// signed in (it will simply re-confirm).
  Future<bool> signInOneDrive() async {
    _error = null;
    try {
      final auth = _buildOneDriveAuth();
      if (!await auth.isSignedIn) await auth.signIn();
      // Confirm we can actually mint a token (catches a revoked consent early).
      await auth.accessToken();
      return true;
    } catch (e) {
      _error = 'OneDrive sign-in failed: $e';
      notifyListeners();
      return false;
    }
  }

  /// Opens (or creates) a Folio in the user's OneDrive at [rootPath], through
  /// the local cache. Assumes [signInOneDrive] already succeeded. On first use
  /// of a folder, the folder and a new Folio are created there; otherwise the
  /// existing Folio is opened. [knownId] (on restore) takes the offline-first
  /// path.
  Future<void> openOneDrive(
    String rootPath, {
    String name = 'My Notes',
    String? knownId,
  }) async {
    final auth = _buildOneDriveAuth();
    final backend = OneDriveBackend(
      rootPath: rootPath,
      accessToken: auth.accessToken,
      client: _httpClientFactory(),
    );
    // First-time open of a (possibly new) folder: make sure the folder exists
    // before we try to write a Folio into it. Errors surface via [error].
    if (knownId == null) {
      try {
        await backend.ensureRoot();
      } catch (e) {
        _error = 'Could not open the OneDrive folder: $e';
        notifyListeners();
        return;
      }
    }
    await openThroughCache(
      backend,
      knownId: knownId,
      createName: knownId == null ? name : null,
    );
    if (hasFolio) {
      await _settings.setLastFolioType('onedrive');
      await _settings.setLastFolioPath(rootPath);
    }
  }

  /// Opens a [remote] Folio through a local cache (clone-then-sync): adopts the
  /// on-device cache as the working backend and keeps [remote] as the sync peer.
  /// This is what makes a remote Folio's notes and attachments work offline with
  /// real on-disk paths. Exposed for tests; [openWebDav] builds the WebDAV peer.
  ///
  /// Offline-first: when [knownId] names a Folio we have already cached, the
  /// cache is adopted immediately (no network needed) and the remote is synced
  /// in the background. Only the very first open of a never-cached Folio needs a
  /// connection — there is nothing local to fall back to.
  ///
  /// When [createName] is given and the remote holds no Folio yet, a new one is
  /// created there (used when opening a fresh cloud folder as a Folio).
  Future<void> openThroughCache(
    StorageBackend remote, {
    String? knownId,
    String? createName,
  }) async {
    await _run(() async {
      final root = await _cacheRoot();

      // Offline-first path: a dropped connection must never block opening notes
      // we already hold. Adopt the cache, then refresh from the remote in the
      // background (failures just set syncError and keep the local copy usable).
      if (knownId != null) {
        final cacheDir = Directory(p.join(root.path, knownId));
        final props = File(p.join(cacheDir.path, 'properties.yaml'));
        if (await props.exists()) {
          final local = LocalFolderBackend(cacheDir.path);
          _adopt(await Folio.open(local), ContentService(local));
          _syncPeer = remote;
          _folioId = knownId;
          await _pruneEmptyFolders();
          await _reloadTree();
          await _restoreLastNote();
          unawaited(_settings.setLastFolioId(knownId));
          _autoSyncFuture = _autoSync(); // best-effort background pull
          return;
        }
      }

      // First open (no cache yet): identify the remote Folio, creating one when
      // asked to and none exists there yet.
      final id = (await _openOrCreateRemote(remote, createName)).id;
      final cacheDir = Directory(p.join(root.path, id));
      await cacheDir.create(recursive: true);
      final local = LocalFolderBackend(cacheDir.path);

      final engine = SyncEngine(
        local: local,
        remote: remote,
        deviceName: _deviceName,
      );
      final result = await engine.sync(
        await _syncStates.load(id),
        onProgress: (progress) {
          _syncProgress = (completed: progress.completed, total: progress.total);
          _notify();
        },
      );
      await _syncStates.save(id, result.newState);
      _syncProgress = null;

      // Adopt the local cache as the working backend; keep the remote peer.
      _adopt(await Folio.open(local), ContentService(local));
      _syncPeer = remote;
      _folioId = id;
      await _pruneEmptyFolders();
      await _reloadTree();
      await _restoreLastNote();
      unawaited(_settings.setLastFolioId(id));
    });
  }

  /// Opens the remote Folio, or creates one named [createName] when none exists
  /// there yet (and creating is requested).
  Future<Folio> _openOrCreateRemote(
    StorageBackend remote,
    String? createName,
  ) async {
    if (createName == null) return Folio.open(remote);
    try {
      return await Folio.open(remote);
    } on NotAMarginFolioException {
      return Folio.create(remote, name: createName);
    }
  }

  /// Reconciles the cache with the remote peer: flushes pending edits, syncs
  /// both ways, and refreshes the tree. The shared body of manual and auto
  /// sync. Assumes a remote peer exists.
  Future<void> _syncWithPeer({bool allowEmptying = false}) async {
    final peer = _syncPeer;
    final id = _folioId;
    final folio = _folio;
    if (peer == null || id == null || folio == null) return;
    await _flushIfDirty();
    final engine = SyncEngine(
      local: folio.backend,
      remote: peer,
      deviceName: _deviceName,
    );
    final result = await engine.sync(
      await _syncStates.load(id),
      allowEmptying: allowEmptying,
      onProgress: (progress) {
        _syncProgress = (completed: progress.completed, total: progress.total);
        notifyListeners();
      },
    );
    _syncProgress = null;
    if (result.withheld) {
      // A side looks empty — don't touch anything; ask the user to confirm.
      _syncNeedsEmptyConfirm = true;
      return;
    }
    _syncNeedsEmptyConfirm = false;
    await _syncStates.save(id, result.newState);
    _hasUnsyncedChanges = false;
    await _pruneEmptyFolders();
    await _reloadTree();
  }

  /// Manual sync (the always-available "Sync now"): shows the busy/progress UI
  /// and reports failures via [error]. No-op for a purely local Folio.
  Future<void> syncNow() async {
    if (!canSync) return;
    await _run(() => _syncWithPeer());
    if (_error == null) _syncError = null;
  }

  /// Proceeds with a sync the emptying guard withheld (the user confirmed the
  /// Folio really is empty). Applies the pending deletions.
  Future<void> confirmEmptyingSync() async {
    if (!canSync) return;
    await _run(() => _syncWithPeer(allowEmptying: true));
    if (_error == null) _syncError = null;
  }

  /// Dismisses the emptying prompt without syncing — leaves both sides as-is.
  void dismissEmptyingSync() {
    _syncNeedsEmptyConfirm = false;
    notifyListeners();
  }

  /// Best-effort cleanup of recursively-empty directories in the working
  /// backend (e.g. folders left behind after notes were deleted outside the
  /// app). Folders marked by a `properties.yaml` are preserved. Never fails a
  /// sync.
  Future<void> _pruneEmptyFolders() async {
    try {
      await _content?.pruneEmptyFolders();
    } catch (_) {
      // Cleanup is best-effort.
    }
  }

  /// Marks the Folio unsynced and kicks off a best-effort background sync after
  /// a local change. Never throws into the caller.
  void _scheduleSync() {
    if (!canSync) return;
    _hasUnsyncedChanges = true;
    _notify();
    // If a sync loop is already running, it will pick up this change via
    // _pendingSync; don't overwrite the tracked future with a no-op.
    if (_autoSyncing) {
      _pendingSync = true;
    } else {
      _autoSyncFuture = _autoSync();
    }
  }

  /// The in-flight background sync, if any (exposed for deterministic tests).
  @visibleForTesting
  Future<void> get pendingSync => _autoSyncFuture ?? Future<void>.value();
  Future<void>? _autoSyncFuture;

  /// Background sync: single-flight, failure-tolerant (offline/server-down keeps
  /// the unsynced flag and records [syncError] without blocking editing). Picks
  /// up changes that arrive mid-sync via [_pendingSync].
  Future<void> _autoSync() async {
    if (!canSync || _autoSyncing) {
      if (_autoSyncing) _pendingSync = true;
      return;
    }
    _autoSyncing = true;
    try {
      do {
        _pendingSync = false;
        try {
          await _serialize(() => _syncWithPeer()); // serialized: never overlaps an edit
          _syncError = null;
        } catch (e) {
          _syncError = e.toString(); // keep _hasUnsyncedChanges; retry later
          break;
        }
      } while (_pendingSync && canSync);
    } finally {
      _autoSyncing = false;
      _notify();
    }
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
    _hasUnsyncedChanges = false;
    _syncError = null;
    _searchQuery = '';
    _searchResults = const [];
    _searchIndex = null;
    // Explicit close: forget the Folio (and note) so the next launch shows
    // the landing screen rather than reopening it. (Any WebDAV password stays
    // in the keystore; re-adding the same URL reuses it.)
    unawaited(_settings.setLastFolioType(null));
    unawaited(_settings.setLastFolioPath(null));
    unawaited(_settings.setLastWebDavUser(null));
    unawaited(_settings.setLastFolioId(null));
    unawaited(_settings.setLastNotePath(null));
    notifyListeners();
  }

  // --- navigation ---

  Future<void> selectNote(NoteNode note) async {
    if (note.path == _selectedNotePath) return;
    final hadUnsavedEdits = _dirty;
    try {
      // A pending edit is a write — flush it through the op-queue so it stays
      // correctly ordered with a background sync. (Skipped when nothing is
      // dirty, which is the common "just browsing" case.)
      if (hadUnsavedEdits) await _serialize(_flushIfDirty);
      // Opening a note is a read: run it OUTSIDE the op-queue so switching notes
      // stays responsive even while a sync holds the queue (the original
      // "can't change the note while it's refreshing" freeze). Dart is
      // single-threaded, so the worst case is briefly stale content that the
      // next sync reconciles — never corruption.
      await _openNote(note);
    } catch (e) {
      _error = e.toString();
    }
    notifyListeners();
    if (hadUnsavedEdits) _scheduleSync();
    // Bring the latest version of this note from the remote in the background,
    // so you edit fresh content rather than a stale cache (conflict avoidance).
    if (canSync) _noteRefreshFuture = _refreshOpenNoteFromPeer(note.path);
  }

  /// The in-flight per-note freshness pull, if any (exposed for tests).
  @visibleForTesting
  Future<void> get pendingNoteRefresh =>
      _noteRefreshFuture ?? Future<void>.value();
  Future<void>? _noteRefreshFuture;

  /// True while checking the remote for a newer version of the open note, so the
  /// UI can show a "checking for the latest" cue.
  bool _noteRefreshing = false;
  bool get noteRefreshing => _noteRefreshing;

  /// Best-effort: if the remote has a newer version of [notePath] (by its
  /// sidecar's `updated`), pull it into the cache and — only if the user is
  /// still on that note and hasn't started editing — reload the editor with it.
  /// Never blocks note-switching (it runs unawaited) and tolerates offline.
  Future<void> _refreshOpenNoteFromPeer(String notePath) async {
    final peer = _syncPeer;
    final folio = _folio;
    final content = _content;
    if (peer == null || folio == null || content == null) return;
    _noteRefreshing = true;
    _notify();
    try {
      final pulled = await _pullNoteIfRemoteNewer(peer, folio, content, notePath)
          .timeout(const Duration(seconds: 10));
      if (!pulled) return;
      // Don't clobber: only refresh when still viewing this note, unedited.
      if (_selectedNotePath != notePath || _dirty) return;
      final loaded = await content.readNote(notePath);
      _currentNote = loaded;
      _workingBody = loaded.body;
      _editorRevision++; // force the editor widget to reload the fresh body
      _notify();
    } catch (_) {
      // Offline / missing / parse error -> keep the cached copy.
    } finally {
      _noteRefreshing = false;
      _notify();
    }
  }

  /// Pulls [notePath] (and its sidecar) from [peer] into the cache when the
  /// remote sidecar's `updated` is newer than the local one. Returns whether a
  /// pull happened. Reads are remote (not serialized); the cache writes are
  /// serialized so they can't race a running sync.
  Future<bool> _pullNoteIfRemoteNewer(
    StorageBackend peer,
    Folio folio,
    ContentService content,
    String notePath,
  ) async {
    final sidecarPath = '$notePath.yaml';
    final Uint8List remoteSidecarRaw;
    try {
      remoteSidecarRaw = await peer.read(sidecarPath);
    } on NotFoundException {
      return false; // no remote sidecar to compare against
    }
    final remoteUpdated =
        NoteProperties.parse(utf8.decode(content.codec.decode(remoteSidecarRaw)))
            .updated;
    if (remoteUpdated == null) return false;

    DateTime? localUpdated;
    try {
      localUpdated = (await content.readNoteProperties(notePath)).updated;
    } catch (_) {
      localUpdated = null;
    }
    if (localUpdated != null && !remoteUpdated.isAfter(localUpdated)) {
      return false; // cache is already current
    }

    final remoteNoteRaw = await peer.read(notePath);
    await _serialize(() async {
      await folio.backend.write(notePath, remoteNoteRaw);
      await folio.backend.write(sidecarPath, remoteSidecarRaw);
    });
    return true;
  }

  /// Loads [note] as the current note. No save-before-switch and no [_run], so
  /// it can be reused inside another operation (e.g. createNote) without
  /// nesting the serialized queue.
  Future<void> _openNote(NoteNode note) async {
    final loaded = await _content!.readNote(note.path);
    _selectedNotePath = note.path;
    _currentNote = loaded;
    _workingBody = loaded.body;
    _dirty = false;
    _viewMode = await _resolveViewMode();
    unawaited(_settings.setLastNotePath(note.path));
  }

  // --- search (over the lightweight sidecar index) ---

  String _searchQuery = '';
  String get searchQuery => _searchQuery;
  bool get isSearching => _searchQuery.trim().isNotEmpty;

  List<NoteNode> _searchResults = const [];
  List<NoteNode> get searchResults => _searchResults;

  /// Cached note index (path -> searchable text), built from sidecars. Null when
  /// it needs rebuilding (after a tree change).
  List<_NoteIndexEntry>? _searchIndex;

  /// Sets the note-search query and recomputes results. Matching is a
  /// case-insensitive substring over each note's title, tags and file name —
  /// read from the tiny `.md.yaml` sidecars, not the note bodies.
  Future<void> setSearchQuery(String query) async {
    _searchQuery = query;
    if (query.trim().isEmpty) {
      _searchResults = const [];
      notifyListeners();
      return;
    }
    await _ensureSearchIndex();
    if (_searchQuery != query) return; // superseded by a newer keystroke
    final q = query.trim().toLowerCase();
    _searchResults = [
      for (final e in _searchIndex!)
        if (e.haystack.contains(q)) e.note,
    ]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    notifyListeners();
  }

  /// Clears the active search.
  void clearSearch() {
    if (_searchQuery.isEmpty) return;
    _searchQuery = '';
    _searchResults = const [];
    notifyListeners();
  }

  /// Builds the in-memory search index from the sidecars, once, until the tree
  /// changes (which nulls it). Tolerates unreadable sidecars (uses the filename).
  Future<void> _ensureSearchIndex() async {
    if (_searchIndex != null) return;
    final tree = _tree;
    final content = _content;
    if (tree == null || content == null) {
      _searchIndex = const [];
      return;
    }
    final entries = <_NoteIndexEntry>[];
    Future<void> walk(FolderNode folder) async {
      for (final note in folder.notes) {
        var title = note.title;
        var tags = const <String>[];
        try {
          final props = await content.readNoteProperties(note.path);
          if (props.title != null && props.title!.isNotEmpty) {
            title = props.title!;
          }
          tags = props.tags;
        } catch (_) {
          // Unreadable sidecar -> fall back to the file-name title.
        }
        entries.add(_NoteIndexEntry(
          note: note,
          haystack: '$title ${tags.join(' ')} ${note.name}'.toLowerCase(),
        ));
      }
      for (final sub in folder.folders) {
        await walk(sub);
      }
    }

    await walk(tree);
    _searchIndex = entries;
  }

  // --- editing ---

  void updateBody(String body) {
    if (body == _workingBody) return;
    _workingBody = body;
    _dirty = true;
    notifyListeners();
  }

  // --- copy the open note (uses the current editing buffer) ---

  /// Whether there is an open note to copy.
  bool get canCopyNote => _selectedNotePath != null;

  /// Copies the open note as **rich text** (HTML) so it pastes into Word/web
  /// with formatting, with a plain-text fallback for plain targets. Local
  /// attachment images are inlined as base64 so the HTML is self-contained.
  Future<void> copyNoteFormatted() async {
    if (_selectedNotePath == null) return;
    final html = await embedHtmlImages(
      markdownToHtml(_workingBody),
      _readLocalImage,
    );
    await _clipboard.copyRich(
      html: html,
      text: markdownToPlainText(_workingBody),
    );
  }

  /// Downloads a remote image and saves it as an attachment of the open note,
  /// returning its note-relative link — used to localize hotlinked images on
  /// paste so they don't rot. Times out per image so a slow/dead URL can't hang
  /// the app; returns null on any failure (caller keeps the original link).
  Future<String?> downloadImageAsAttachment(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return null;
    }
    final client = _httpClientFactory();
    try {
      final res =
          await client.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;
      final ext = _imageExtension(res.headers['content-type'], uri.path);
      return saveAttachmentForCurrentNote(res.bodyBytes, ext);
    } catch (_) {
      return null; // timeout, network error, etc. -> keep the hotlink
    } finally {
      client.close();
    }
  }

  /// Best-effort image extension from a content-type or URL path; defaults png.
  String _imageExtension(String? contentType, String urlPath) {
    final type = (contentType ?? '').split(';').first.trim().toLowerCase();
    switch (type) {
      case 'image/jpeg':
        return 'jpg';
      case 'image/png':
        return 'png';
      case 'image/gif':
        return 'gif';
      case 'image/webp':
        return 'webp';
      case 'image/bmp':
        return 'bmp';
      case 'image/svg+xml':
        return 'svg';
    }
    final dot = urlPath.lastIndexOf('.');
    final fromPath = dot < 0 ? '' : urlPath.substring(dot + 1).toLowerCase();
    const known = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'svg'};
    if (known.contains(fromPath)) return fromPath == 'jpeg' ? 'jpg' : fromPath;
    return 'png';
  }

  /// Saves [bytes] as an attachment of the open note (e.g. a pasted image) and
  /// returns its note-relative link, without inserting or saving the note.
  Future<String?> saveAttachmentForCurrentNote(
    Uint8List bytes,
    String extension,
  ) async {
    final folder = _currentNoteFolder();
    if (folder == null || _content == null) return null;
    final name = 'pasted-${DateTime.now().millisecondsSinceEpoch}.$extension';
    try {
      String? link;
      await _serialize(() async {
        link = await _content!.addAttachment(folder, name, bytes);
      });
      return link;
    } catch (_) {
      return null;
    }
  }

  /// Repo-relative folder of the open note (or null if none open).
  String? _currentNoteFolder() {
    final notePath = _selectedNotePath;
    if (notePath == null) return null;
    final slash = notePath.lastIndexOf('/');
    return slash < 0 ? '' : notePath.substring(0, slash);
  }

  /// Reads a note-relative image source from disk (for HTML embedding); null for
  /// external/unresolvable sources.
  Future<Uint8List?> _readLocalImage(String src) async {
    final folder = _currentNoteFolder();
    final baseDir = folder == null ? null : localAbsolutePath(folder);
    final path = resolveLinkTarget(src, baseDir);
    if (path == null) return null;
    try {
      return await File(path).readAsBytes();
    } catch (_) {
      return null;
    }
  }

  /// Copies the open note's raw **Markdown** source.
  Future<void> copyNoteMarkdown() async {
    if (_selectedNotePath == null) return;
    await _clipboard.copyText(_workingBody);
  }

  /// Copies the open note as **plain text** (markup stripped).
  Future<void> copyNotePlain() async {
    if (_selectedNotePath == null) return;
    await _clipboard.copyText(markdownToPlainText(_workingBody));
  }

  Future<void> save() async {
    if (!_dirty || _currentNote == null || _selectedNotePath == null) return;
    await _run(_flushIfDirty);
    _scheduleSync();
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
    _scheduleSync();
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
    _scheduleSync();
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
      await _openNote(node);
    });
    _scheduleSync();
  }

  /// Sets (or clears, with null) a folder's accent color.
  Future<void> setFolderColor(String path, String? colorHex) async {
    await _run(() async {
      await _content!.setFolderColor(path, colorHex);
      await _reloadTree();
    });
    _scheduleSync();
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
    _scheduleSync();
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
    _scheduleSync();
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
    _scheduleSync();
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
    _hasUnsyncedChanges = false;
    _syncError = null;
  }

  Future<void> _reloadTree() async {
    _tree = await _content!.tree();
    _searchIndex = null; // notes changed -> rebuild the search index on demand
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
  /// Serializes async operations so a background sync never overlaps a mutation
  /// (which would race on the cache and the tree). Errors are swallowed for the
  /// chain only; the caller still sees them.
  Future<void> _serialize(Future<void> Function() action) {
    final result = _opChain.then((_) => action());
    _opChain = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Notifies listeners unless the controller has been disposed (a background
  /// sync may complete after disposal).
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) {
    return _serialize(() async {
      _busy = true;
      _error = null;
      _notify();
      try {
        await action();
      } catch (e) {
        _error = e.toString();
      } finally {
        _busy = false;
        _syncProgress = null;
        _notify();
      }
    });
  }
}

/// One entry in the in-memory note search index: the note plus its precomputed
/// lowercase searchable text (title + tags + file name).
class _NoteIndexEntry {
  final NoteNode note;
  final String haystack;
  const _NoteIndexEntry({required this.note, required this.haystack});
}
