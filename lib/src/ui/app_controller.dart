// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show PaintingBinding;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../content/content_exception.dart';
import '../content/content_service.dart';
import '../content/markdown_convert.dart';
import '../content/tree_node.dart';
import '../credentials/credential_store.dart';
import '../desktop/file_reveal.dart';
import '../folio/note.dart';
import '../folio/note_properties.dart';
import '../folio/folio.dart';
import '../folio/folio_exception.dart';
import '../mobile/keep_awake.dart';
import '../settings/recent_folios.dart';
import '../settings/settings_store.dart';
import '../storage/local_folder_backend.dart';
import '../storage/onedrive_auth.dart';
import '../storage/onedrive_backend.dart';
import '../storage/onedrive_oauth.dart';
import '../storage/git/git_channel.dart';
import '../storage/saf/saf_backend.dart';
import '../storage/saf/saf_channel.dart';
import '../storage/storage_backend.dart';
import '../storage/storage_exception.dart';
import '../storage/webdav_backend.dart';
import '../sync/sync_engine.dart';
import '../sync/sync_state_store.dart';
import '../sync/transient_error.dart';
import 'clipboard_service.dart';
import 'editor_view_mode.dart';
import 'widgets/markdown_editing_controller.dart' show findMarkdownLinks;
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
  final SafChannel _saf;
  final GitChannel _git;

  /// Keeps the device awake during a long sync/clone. Injectable so tests use a
  /// no-op fake.
  final KeepAwake _keepAwake;

  AppController({
    SettingsStore? settings,
    CredentialStore? credentials,
    SyncStateStore? syncStates,
    http.Client Function()? httpClientFactory,
    Future<Directory> Function()? cacheRoot,
    ClipboardService? clipboard,
    SafChannel? saf,
    GitChannel? git,
    KeepAwake? keepAwake,
  })  : _settings = settings ?? InMemorySettingsStore(),
        _credentials = credentials ?? InMemoryCredentialStore(),
        _syncStates = syncStates ?? InMemorySyncStateStore(),
        _httpClientFactory = httpClientFactory ?? (() => http.Client()),
        _clipboard = clipboard ?? createClipboardService(),
        _saf = saf ?? const MethodChannelSaf(),
        _git = git ?? const MethodChannelGit(),
        _keepAwake = keepAwake ?? createKeepAwake(),
        _cacheRoot = cacheRoot ??
            (() async {
              final docs = await getApplicationDocumentsDirectory();
              return Directory(p.join(docs.path, 'Margin'));
            });

  /// The remote sync peer for the open cached Folio (null for purely local
  /// Folios), and that Folio's id — kept for later background/manual sync.
  StorageBackend? _syncPeer;
  String? _folioId;

  /// When the open Folio is a git clone (browse mode), the clone URL, its local
  /// path, and the username — so Refresh can `git pull` the folder up to date.
  /// All null for non-git Folios; set after opening a git clone, cleared on
  /// adopting/closing any other Folio.
  String? _gitUrl;
  String? _gitPath;
  String? _gitUser;

  /// Whether the open Folio is a git clone that Refresh can pull.
  bool get isGitFolio => _gitUrl != null;

  /// Progress of an in-flight cache/sync, or null when idle. [path] is the file
  /// currently being transferred, shown so a long clone/sync is legible.
  ({int completed, int total, String? path})? _syncProgress;
  ({int completed, int total, String? path})? get syncProgress => _syncProgress;

  /// Whether the open Folio has a remote peer it can sync with.
  bool get canSync => _syncPeer != null;

  /// True while a background clone/sync is actively running — so the UI can show
  /// an honest "Syncing…/resuming" cue instead of a bare spinner.
  bool get isSyncing => _autoSyncing || _syncProgress != null;

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

  /// Keystore key for a git password/PAT, derived from its (non-secret) clone
  /// URL and username — both known before we can clone.
  static String _gitCredKey(String url, String username) =>
      'git|$url|$username';

  Folio? _folio;
  ContentService? _content;
  FolderNode? _tree;

  String? _selectedNotePath;
  Note? _currentNote;
  String _workingBody = '';
  bool _dirty = false;

  /// Browser-style navigation history over opened notes (paths). [selectNote]
  /// pushes the current note onto [_backStack] and clears [_forwardStack];
  /// [goBack]/[goForward] move between them without recording. Cleared when a
  /// Folio is adopted or closed.
  final List<String> _backStack = [];
  final List<String> _forwardStack = [];

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

  /// Whether the editor soft-wraps long lines (device-local; default true).
  bool _wordWrap = true;

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

  /// Whether the open folder is a read-only **browsed** plain folder (no
  /// managed `properties.yaml`). The UI suppresses every mutation in this mode
  /// so a folder Margin didn't create is never written to.
  bool get isBrowsing => _content?.browse ?? false;

  /// The absolute on-disk path for a repository-relative [path], or null if the
  /// repository is not on the local filesystem.
  String? localAbsolutePath(String path) {
    final backend = _folio?.backend;
    return backend is LocalFolderBackend ? backend.absolutePathOf(path) : null;
  }

  /// Reads the bytes of an image referenced from the open note ([src] is note-
  /// relative, e.g. `_attachments/pic.png`) **through the backend** — so images
  /// render when browsing a remote/SAF folder that has no local file on disk.
  /// Returns null for absolute/remote srcs (the preview handles http(s) itself)
  /// or on any failure. Used by the preview only when there's no local path.
  Future<Uint8List?> readNoteImage(String src) async {
    final content = _content;
    final notePath = _selectedNotePath;
    if (content == null || notePath == null || src.isEmpty) return null;
    // Skip anything with a scheme (http/https/data) — not a backend path.
    if (Uri.tryParse(src)?.hasScheme ?? false) return null;
    final slash = notePath.lastIndexOf('/');
    final folder = slash < 0 ? '' : notePath.substring(0, slash);
    final resolved =
        p.posix.normalize(folder.isEmpty ? src : '$folder/$src');
    // Never read outside the Folio root.
    if (resolved.startsWith('..') || resolved.startsWith('/')) return null;
    try {
      return await content.backend.read(resolved);
    } catch (_) {
      return null;
    }
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
  bool get wordWrap => _wordWrap;
  bool get isBusy => _busy;
  String? get error => _error;

  // --- opening / creating (path-based, used by the picker UI) ---

  /// App startup: load view settings, kick off orphan-cache cleanup in the
  /// background (best-effort; must never block or delay showing the UI), then
  /// restore the last repository.
  ///
  /// The auto-prune is skipped under `flutter test`: it walks the real app
  /// documents dir, which would give unit tests a filesystem side effect (and
  /// resolving that dir can hang the test process). Tests that exercise pruning
  /// call [pruneOrphanCaches] directly with an injected cache root.
  Future<void> start() async {
    await _loadViewSettings();
    if (Platform.environment['FLUTTER_TEST'] != 'true') {
      unawaited(pruneOrphanCaches());
    }
    await restoreLastFolio();
  }

  /// Deletes on-device Folio caches that no list entry points at, so nothing is
  /// cached invisibly (the list now keeps every Folio, so an orphan means data
  /// the user can neither see nor manage — e.g. left by an older capped list).
  /// Best-effort; only touches directories that are actually a Folio cache
  /// (hold a `properties.yaml`), never `DeviceNotes/` or the active Folio.
  Future<void> pruneOrphanCaches() async {
    try {
      final root = await _cacheRoot();
      if (!await root.exists()) return;
      final keep = <String>{
        for (final r in _recentFolios)
          if (r.id != null) r.id!,
      };
      final last = await _settings.getLastFolioId();
      if (last != null) keep.add(last);

      await for (final entity in root.list(followLinks: false)) {
        if (entity is! Directory) continue;
        final name = p.basename(entity.path);
        if (name == 'DeviceNotes' || keep.contains(name)) continue;
        // Only prune what is unmistakably a Folio cache, so unrelated data that
        // happens to sit under Margin/ is never deleted.
        final marker = File(p.join(entity.path, 'properties.yaml'));
        if (!await marker.exists()) continue;
        await entity.delete(recursive: true);
        await _syncStates.delete(name);
      }
    } catch (_) {
      // best-effort cleanup — a leftover cache only costs disk
    }
  }

  Future<void> _loadViewSettings() async {
    try {
      _viewPolicy = defaultViewPolicyFromId(await _settings.getViewPolicy());
      _defaultNoteView =
          editorViewModeFromId(await _settings.getDefaultNoteView()) ??
              EditorViewMode.edit;
      _alwaysOnTop = await _settings.getAlwaysOnTop();
      _startMinimized = await _settings.getStartMinimized();
      _wordWrap = await _settings.getWordWrap();
      _recentFolios = decodeRecentFolios(await _settings.getRecentFolios());
    } catch (_) {
      // Settings unavailable (e.g. tests): keep defaults.
    }
  }

  // --- recent Folios ---

  /// Recently opened Folios (most recent first; device notes excluded — it has
  /// its own permanent landing button). Survives an explicit close, unlike the
  /// last-Folio auto-restore fields. No secrets: reconnect reads the keystore.
  List<RecentFolio> _recentFolios = const [];
  List<RecentFolio> get recentFolios => _recentFolios;

  void _recordRecent(RecentFolio entry) {
    _recentFolios = upsertRecentFolio(_recentFolios, entry);
    unawaited(_settings.setRecentFolios(encodeRecentFolios(_recentFolios)));
    notifyListeners();
  }

  void removeRecentFolio(RecentFolio entry) {
    _recentFolios =
        _recentFolios.where((f) => !f.sameTarget(entry)).toList(growable: false);
    unawaited(_settings.setRecentFolios(encodeRecentFolios(_recentFolios)));
    notifyListeners();
    // Removing a Folio also discards its disposable on-device cache and sync
    // record, so re-adding it later is a clean start — not a silent resume
    // against stale data (which shows a confusing partial file count). Only for
    // remote Folios, whose local copy is a rebuildable cache keyed by the
    // remote id; a `local` Folio's "cache" IS the user's own folder and is
    // never touched, and the currently-open Folio is left intact.
    final id = entry.id;
    if (id != null && entry.type != 'local' && id != _folioId) {
      _cacheDiscardFuture = _discardFolioCache(id);
    }
  }

  /// The in-flight cache discard from [removeRecentFolio], if any (for tests).
  @visibleForTesting
  Future<void> get pendingCacheDiscard =>
      _cacheDiscardFuture ?? Future<void>.value();
  Future<void>? _cacheDiscardFuture;

  /// Memoised cache-stats *futures* per Folio id. Memoising the future (not just
  /// its result) is deliberate: a `FutureBuilder` fed a fresh future on every
  /// rebuild never settles, so a stable future per id keeps the list from
  /// re-walking a big cache each frame. Cleared when the cache is discarded.
  final Map<String, Future<({int bytes, int files})?>> _cacheStatsFutures = {};

  /// Total size and file count of a Folio's on-device cache
  /// (`<cacheRoot>/<id>`), or null when there is no cache (e.g. a local Folio,
  /// or one whose cache was pruned). A metadata-only walk — no file contents are
  /// read. Pass [refresh] to recompute after the cache changes.
  Future<({int bytes, int files})?> folioCacheStats(
    String id, {
    bool refresh = false,
  }) {
    if (!refresh) {
      final cached = _cacheStatsFutures[id];
      if (cached != null) return cached;
    }
    final future = _computeCacheStats(id);
    _cacheStatsFutures[id] = future;
    return future;
  }

  Future<({int bytes, int files})?> _computeCacheStats(String id) async {
    try {
      final dir = Directory(p.join((await _cacheRoot()).path, id));
      if (!await dir.exists()) return null;
      var bytes = 0;
      var files = 0;
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (e is File) {
          bytes += await e.length();
          files++;
        }
      }
      return (bytes: bytes, files: files);
    } catch (_) {
      return null; // unreadable cache → treat as unknown
    }
  }

  /// Whether the open Folio is a remote Folio with an on-device cache (as
  /// opposed to a local folder, which lives in the user's own directory).
  bool get isCloudFolio => canSync && _folioId != null;

  /// Cache stats for the currently open Folio (size + file count), or null when
  /// it has no on-device cache. See [folioCacheStats].
  Future<({int bytes, int files})?> currentFolioCacheStats(
      {bool refresh = true}) {
    final id = _folioId;
    if (id == null) return Future<({int bytes, int files})?>.value(null);
    return folioCacheStats(id, refresh: refresh);
  }

  /// Deletes a remote Folio's on-device cache directory (`<cacheRoot>/<id>`) and
  /// its persisted sync state. Best-effort: a leftover only costs disk space.
  Future<void> _discardFolioCache(String id) async {
    _cacheStatsFutures.remove(id);
    try {
      final dir = Directory(p.join((await _cacheRoot()).path, id));
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // ignore — reclaiming the cache is best-effort
    }
    try {
      await _syncStates.delete(id);
    } catch (_) {
      // ignore
    }
  }

  /// Reopens a remembered Folio, dispatching on its backend type — the same
  /// reconnect paths as [restoreLastFolio], including the offline-first cache
  /// adoption for remote Folios. Failures keep the entry (it may just be
  /// offline) and surface through [error]; a *missing* local folder gets a
  /// distinct message so the user knows the Folio itself is gone, not the
  /// connection.
  ///
  /// Shown behind the restoring splash: reconnecting a remote can take a few
  /// seconds (token refresh, identify, first sync), and a landing screen that
  /// just sits there reads as "the app hung".
  Future<void> openRecentFolio(RecentFolio recent) async {
    _restoring = true;
    _notify();
    try {
      await _openRecentFolio(recent);
    } finally {
      _restoring = false;
      _notify();
    }
  }

  Future<void> _openRecentFolio(RecentFolio recent) async {
    _error = null;
    switch (recent.type) {
      case 'webdav':
        final password = await _credentials
            .read(_webDavCredKey(recent.location, recent.user ?? ''));
        if (password == null) {
          // The keystore lost the secret (or it was never this device's):
          // reconnecting needs credentials again.
          _error = 'No saved password for ${recent.location} — '
              'connect to WebDAV again.';
          notifyListeners();
          return;
        }
        if (recent.browse) {
          await browseWebDav(recent.location, recent.user ?? '', password);
        } else {
          await openWebDav(recent.location, recent.user ?? '', password,
              knownId: recent.id);
        }
      case 'onedrive':
        if (recent.browse) {
          if (!await signInOneDrive()) return; // error already surfaced
          await browseOneDrive(recent.location);
        } else {
          await openOneDrive(recent.location, knownId: recent.id);
        }
      case 'saf':
        // Reopen a granted Android folder (permission persisted natively).
        // A revoked/missing grant surfaces as an [error] via openRemoteBrowse.
        await openRemoteBrowse(
          SafBackend(_saf, recent.location),
          name: recent.name,
        );
      case 'git':
        // Offline-first: if the clone is still on disk, open it instantly (no
        // network, no credentials). Otherwise re-clone with the saved PAT.
        final name = _gitRepoName(recent.location);
        final cached = await _git.localPath(name);
        if (cached != null) {
          await open(LocalFolderBackend(cached), browseName: name);
          if (hasFolio) {
            _gitUrl = recent.location;
            _gitPath = cached;
            _gitUser = recent.user ?? '';
          }
          return;
        }
        final password =
            await _credentials.read(_gitCredKey(recent.location, recent.user ?? '')) ??
                '';
        await browseGitRepo(
          url: recent.location,
          user: recent.user ?? '',
          password: password,
        );
      default:
        if (!await Directory(recent.location).exists()) {
          _error = 'This Folio\'s folder is missing: ${recent.location}';
          notifyListeners();
          return;
        }
        // A local browsed folder (no properties.yaml) is auto-detected by open().
        await openPath(recent.location);
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

  /// Persists and updates the editor word-wrap preference.
  Future<void> setWordWrap(bool value) async {
    _wordWrap = value;
    await _settings.setWordWrap(value);
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
        // Restoring the device-notes Folio must not seed the recent list (it
        // has its own landing button); any other local Folio may (this also
        // seeds recents for users upgrading from the single last-Folio era).
        var record = true;
        try {
          record = location != await _deviceNotesPath();
        } catch (_) {
          // Docs dir unavailable: then device notes can't be at [location].
        }
        await openPath(location, record: record);
        if (!hasFolio) await _settings.setLastFolioPath(null);
      }
    } finally {
      _restoring = false;
      _notify();
    }
  }

  /// [record] adds the Folio to the recent list; the device-notes Folio passes
  /// false (it has its own permanent landing button).
  Future<void> openPath(String path, {bool record = true}) async {
    await open(LocalFolderBackend(path), browseName: p.basename(path));
    if (hasFolio) {
      await _settings.setLastFolioType('local');
      await _settings.setLastFolioPath(path);
      if (record) {
        _recordRecent(
            RecentFolio(type: 'local', location: path, name: folioName));
      }
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
      _recordRecent(RecentFolio(
        type: 'webdav',
        location: url,
        name: folioName,
        user: username,
        id: _folioId,
      ));
    }
  }

  /// Opens a plain **remote** folder (WebDAV/OneDrive) read-only in browse mode
  /// — reads directly over the network, no clone/sync, writes nothing. This is
  /// companion mode for a shared cloud folder, and the only way to browse a
  /// folder on mobile (no local folder picker there). Works over any backend.
  Future<void> openRemoteBrowse(
    StorageBackend remote, {
    required String name,
  }) async {
    await _run(() async {
      await remote.list(''); // reachable? (throws -> surfaced as [error])
      _adopt(
        Folio.browse(remote, name: name),
        ContentService(remote, browse: true),
      );
      await _reloadTree();
      if (_selectedNotePath == null) await _selectOverviewNote();
    });
  }

  /// The last path segment of a remote [location] (URL or Graph path), for the
  /// browsed folder's display name.
  String _remoteBasename(String location) {
    final trimmed = location.replaceAll(RegExp(r'/+$'), '');
    final slash = trimmed.lastIndexOf('/');
    final name = slash >= 0 ? trimmed.substring(slash + 1) : trimmed;
    return name.isEmpty ? 'Notes' : name;
  }

  /// Companion mode on Android: the user picks a folder via the system picker
  /// (SAF), and it's browsed read-only over the granted `content://` tree URI.
  /// The permission is persisted natively, and a recent-Folios entry stores the
  /// URI so it reopens with one tap. No-op if the user cancels the picker.
  Future<void> browseAndroidFolder() async {
    final ({String uri, String name})? picked;
    try {
      picked = await _saf.pickFolder();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return;
    }
    if (picked == null) return; // cancelled
    await openRemoteBrowse(SafBackend(_saf, picked.uri), name: picked.name);
    if (hasFolio) {
      _recordRecent(RecentFolio(
        type: 'saf',
        location: picked.uri,
        name: folioName,
        browse: true,
      ));
    }
  }

  /// Git-read spike (Android): clone [url] read-only (optional HTTPS
  /// [user]/[password] — for GitHub the password is a PAT) into app-private
  /// storage, then browse the checked-out working tree like any local folder.
  /// LFS pointers smudge to real bytes during checkout (native side). No push,
  /// no keystore/recents yet — this validates JGit + LFS on-device before the
  /// full backend (shared-storage destination, auth-once, pull, recents) lands.
  Future<void> browseGitRepo({
    required String url,
    String user = '',
    String password = '',
  }) async {
    final name = _gitRepoName(url);
    final String path;
    // Clone can take many seconds (fetch + LFS); show the busy indicator the
    // whole time so the landing screen doesn't look frozen. open() below keeps
    // its own busy state up (via _run), so we don't clear it on success.
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      path = await _git.clone(
        url: url,
        user: user,
        password: password,
        name: name,
      );
    } catch (e) {
      _error = 'Clone failed: $e';
      _busy = false;
      notifyListeners();
      return;
    }
    await open(LocalFolderBackend(path), browseName: name);
    if (hasFolio) {
      // Auth-once: keep the PAT in the OS keystore (never in the recent entry),
      // and record a git recent so reopening is one tap.
      if (user.isNotEmpty || password.isNotEmpty) {
        await _credentials.write(_gitCredKey(url, user), password);
      }
      _recordRecent(RecentFolio(
        type: 'git',
        location: url,
        name: folioName,
        user: user,
        browse: true,
      ));
      _gitUrl = url;
      _gitPath = path;
      _gitUser = user;
    }
  }

  /// A repo's display name from its clone URL: the last path segment without a
  /// trailing `.git` (e.g. `https://host/org/notes.git` -> `notes`).
  String _gitRepoName(String url) {
    final base = _remoteBasename(url);
    return base.endsWith('.git') ? base.substring(0, base.length - 4) : base;
  }

  /// Browses a WebDAV folder read-only (companion mode). Stores the password in
  /// the keystore so the recent entry can reconnect.
  Future<void> browseWebDav(String url, String username, String password) async {
    final StorageBackend backend;
    try {
      backend = WebDavBackend(
        baseUrl: Uri.parse(url),
        username: username,
        password: password,
        client: _httpClientFactory(),
      );
    } catch (e) {
      _error = 'Invalid server URL: $e';
      notifyListeners();
      return;
    }
    await openRemoteBrowse(backend, name: _remoteBasename(url));
    if (hasFolio) {
      await _credentials.write(_webDavCredKey(url, username), password);
      _recordRecent(RecentFolio(
        type: 'webdav',
        location: url,
        name: folioName,
        user: username,
        browse: true,
      ));
    }
  }

  /// Browses a OneDrive folder read-only (companion mode). Assumes
  /// [signInOneDrive] already succeeded.
  Future<void> browseOneDrive(String rootPath) async {
    final auth = _buildOneDriveAuth();
    final backend = OneDriveBackend(
      rootPath: rootPath,
      accessToken: auth.accessToken,
      client: _httpClientFactory(),
    );
    await openRemoteBrowse(backend, name: _remoteBasename(rootPath));
    if (hasFolio) {
      _recordRecent(RecentFolio(
        type: 'onedrive',
        location: rootPath,
        name: folioName,
        browse: true,
      ));
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
      _recordRecent(RecentFolio(
        type: 'onedrive',
        location: rootPath,
        name: folioName,
        id: _folioId,
      ));
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
      SyncResult? result;
      try {
        final base = await _syncStates.load(id);
        result = await _keepAwake.guard<SyncResult>(() => engine.sync(
          base,
          onProgress: (progress) {
            _syncProgress = (
              completed: progress.completed,
              total: progress.total,
              path: progress.path,
            );
            _notify();
          },
          // Persist progress mid-clone so an interrupted first sync (dropped
          // connection, screen off) resumes near where it stopped, never from
          // zero — and the bytes already pulled are not fetched again.
          onCheckpoint: (partial) => _syncStates.save(id, partial),
        ));
        await _syncStates.save(id, result.newState);
      } catch (e) {
        // Offline-first: a failed/partial clone must not strand the user on the
        // landing screen. Adopt whatever reached the cache so the pulled notes
        // are usable, and surface the failure as a sync error to retry later.
        _syncProgress = null;
        if (await File(p.join(cacheDir.path, 'properties.yaml')).exists()) {
          _adopt(await Folio.open(local), ContentService(local));
          _syncPeer = remote;
          _folioId = id;
          await _pruneEmptyFolders();
          await _reloadTree();
          await _restoreLastNote();
          unawaited(_settings.setLastFolioId(id));
          _syncError = e.toString();
          return;
        }
        rethrow; // nothing usable landed — let the caller report the error
      }
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
    final base = await _syncStates.load(id);
    final result = await _keepAwake.guard<SyncResult>(() => engine.sync(
      base,
      allowEmptying: allowEmptying,
      onProgress: (progress) {
        _syncProgress = (
          completed: progress.completed,
          total: progress.total,
          path: progress.path,
        );
        notifyListeners();
      },
      onCheckpoint: (partial) => _syncStates.save(id, partial),
    ));
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

  /// Rebuilds the tree from disk to pick up changes made outside the app (e.g.
  /// Claude adding or editing files in the folder while it's open). The open
  /// note is reloaded too — unless it has unsaved edits, which are never
  /// clobbered — and cleared if it vanished on disk. (A stop-gap until live
  /// file-watching; for remote Folios, "Sync now" remains the way to pull.)
  /// Bumped by [refreshTree]; the preview watches it to drop memoised image
  /// futures and re-resolve file images. On-disk image bytes can change under a
  /// stable path (an updated attachment, a git pull), which Flutter's image
  /// cache would otherwise keep showing stale until an app restart.
  int get imageEpoch => _imageEpoch;
  int _imageEpoch = 0;

  /// Forgets every cached/decoded image so the next paint re-reads from disk.
  void _invalidateImages() {
    _imageEpoch++;
    try {
      PaintingBinding.instance.imageCache
        ..clear()
        ..clearLiveImages();
    } catch (_) {
      // No painting binding (e.g. a pure unit test) — the epoch bump suffices.
    }
  }

  Future<void> refreshTree() async {
    if (!hasFolio) return;
    // Refresh means "show me what's on disk now", so stale images must not
    // survive it (Flutter caches decoded images by path, ignoring new bytes).
    _invalidateImages();
    await _run(() async {
      // A git Folio refreshes by pulling the remote into the local clone first
      // (fetch + reset + re-smudge LFS). Best-effort: on failure keep showing
      // the last-good clone and warn it may be stale (never blank the reader).
      if (_gitUrl != null && _gitPath != null) {
        try {
          final password =
              await _credentials.read(_gitCredKey(_gitUrl!, _gitUser ?? '')) ?? '';
          await _git.pull(
            path: _gitPath!,
            url: _gitUrl!,
            user: _gitUser ?? '',
            password: password,
          );
        } catch (e) {
          _error = 'Couldn\'t pull the latest — showing the last synced copy. ($e)';
        }
      }
      await _reloadTree();
      final notePath = _selectedNotePath;
      if (notePath == null || _dirty) return;
      if (await _folio!.backend.exists(notePath)) {
        await _openNote(
            NoteNode(path: notePath, name: notePath.split('/').last));
        _editorRevision++; // force the editor to reload the fresh body
      } else {
        _selectedNotePath = null;
        _currentNote = null;
        _workingBody = '';
      }
    });
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
          await _syncWithTransientRetry();
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

  /// Delays between silent retries of a background sync cut by a transient
  /// network failure. Mutable so tests can zero them out.
  @visibleForTesting
  List<Duration> syncRetryDelays = const [
    Duration(seconds: 3),
    Duration(seconds: 10),
    Duration(seconds: 30),
  ];

  /// Runs one serialized sync, silently retrying transient network failures
  /// (a mobile cellular→WiFi handoff cuts in-flight requests all the time).
  /// Rerunning a cut sync is safe: the planner recomputes from fresh snapshots
  /// and [SyncState] is only saved after a successful run, so a half-applied
  /// sync simply continues. Non-network errors surface immediately.
  Future<void> _syncWithTransientRetry() async {
    for (var attempt = 0;; attempt++) {
      try {
        // Serialized: never overlaps an edit.
        await _serialize(() => _syncWithPeer());
        return;
      } catch (e) {
        if (attempt >= syncRetryDelays.length || !isTransientNetworkError(e)) {
          rethrow;
        }
        await Future<void>.delayed(syncRetryDelays[attempt]);
        // The Folio may have been closed (or the app disposed) while waiting.
        if (!canSync || _disposed) rethrow;
      }
    }
  }

  /// Kicks one background sync when the app returns to the foreground and the
  /// last sync failed (or changes are still unsynced) — e.g. the connection
  /// changed while walking and the cut sync flagged offline; by the time the
  /// user looks at the app, the network is back. No-op when idle or in-flight.
  void retrySyncOnResume() {
    if (!canSync || _autoSyncing) return;
    if (_syncError == null && !_hasUnsyncedChanges) return;
    _autoSyncFuture = _autoSync();
  }

  /// Where the on-device Folio lives: under `Margin/DeviceNotes/`, leaving
  /// `Margin/` as the parent for per-Folio remote caches (`Margin/<UUID>/`).
  Future<String> _deviceNotesPath() async {
    final docs = await getApplicationDocumentsDirectory();
    return p.join(docs.path, 'Margin', 'DeviceNotes');
  }

  /// Opens (or creates) a repository in this device's app documents directory —
  /// the portable, no-picker option that works on mobile, where arbitrary
  /// folders aren't reachable via `dart:io`.
  Future<void> openDeviceFolio({String name = 'My Notes'}) async {
    final repoPath = await _deviceNotesPath();
    await Directory(repoPath).create(recursive: true);
    final backend = LocalFolderBackend(repoPath);
    if (await backend.exists('properties.yaml')) {
      await openPath(repoPath, record: false);
    } else {
      await createPath(repoPath, name, record: false);
    }
  }

  /// [record] adds the Folio to the recent list; the device-notes Folio passes
  /// false (it has its own permanent landing button).
  Future<void> createPath(String path, String name,
      {bool record = true}) async {
    await create(LocalFolderBackend(path), name);
    if (hasFolio) {
      await _settings.setLastFolioType('local');
      await _settings.setLastFolioPath(path);
      if (record) {
        _recordRecent(
            RecentFolio(type: 'local', location: path, name: folioName));
      }
    }
  }

  /// Opens an existing repository on [backend]. Exposed for tests.
  ///
  /// A folder with no `properties.yaml` is not a managed Folio — it's opened in
  /// read-only **browse** mode (a plain folder of Markdown, e.g. one Claude
  /// generated). [browseName] names it for the title bar.
  Future<void> open(StorageBackend backend, {String? browseName}) async {
    await _run(() async {
      late final Folio repo;
      late final ContentService content;
      var browse = false;
      try {
        repo = await Folio.open(backend);
        content = ContentService(backend);
      } on NotAMarginFolioException {
        // Plain folder: validate it's actually there/readable before adopting
        // browse mode, so a missing path errors cleanly instead of leaving a
        // half-open Folio. Synthesize properties, write nothing, prune nothing.
        await backend.list(''); // throws if the folder is gone/unreadable
        repo = Folio.browse(backend, name: browseName ?? 'Notes');
        content = ContentService(backend, browse: true);
        browse = true;
      }
      _adopt(repo, content);
      if (!browse) {
        // Clean up empty folders left behind by deletions made outside the app
        // (e.g. a sync from another device that removed files but left the
        // directory). Best-effort, and never in read-only browse mode.
        await _pruneEmptyFolders();
      }
      await _reloadTree();
      await _restoreLastNote();
      // A freshly opened browsed folder lands on its overview (CLAUDE.md /
      // README.md at the root) so the reader gets oriented.
      if (browse && _selectedNotePath == null) await _selectOverviewNote();
    });
  }

  /// Selects a browsed folder's overview note — root `CLAUDE.md`, else root
  /// `README.md` — when one exists. Best-effort.
  Future<void> _selectOverviewNote() async {
    final tree = _tree;
    if (tree == null) return;
    for (final wanted in const ['claude.md', 'readme.md']) {
      for (final note in tree.notes) {
        if (note.name.toLowerCase() == wanted) {
          await selectNote(note);
          return;
        }
      }
    }
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
    _backStack.clear();
    _forwardStack.clear();
    _currentNote = null;
    _workingBody = '';
    _dirty = false;
    _syncPeer = null;
    _folioId = null;
    _syncProgress = null;
    _hasUnsyncedChanges = false;
    _syncError = null;
    _gitUrl = null;
    _gitPath = null;
    _gitUser = null;
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

  /// True when there's a previous/next note to return to via [goBack]/[goForward].
  bool get canGoBack => _backStack.isNotEmpty;
  bool get canGoForward => _forwardStack.isNotEmpty;

  /// Returns to the previously opened note (browser-style). No-op if the history
  /// is empty.
  Future<void> goBack() async {
    if (_backStack.isEmpty) return;
    final target = _backStack.removeLast();
    if (_selectedNotePath != null) _forwardStack.add(_selectedNotePath!);
    await selectNote(
      NoteNode(path: target, name: target.split('/').last),
      record: false,
    );
  }

  /// Re-opens the note stepped back from. No-op if there's nothing ahead.
  Future<void> goForward() async {
    if (_forwardStack.isEmpty) return;
    final target = _forwardStack.removeLast();
    if (_selectedNotePath != null) _backStack.add(_selectedNotePath!);
    await selectNote(
      NoteNode(path: target, name: target.split('/').last),
      record: false,
    );
  }

  /// Opens [note]. Normal navigation ([record] true) pushes the current note
  /// onto the back history and drops the forward history; [goBack]/[goForward]
  /// pass [record] false so they don't rewrite the history they're walking.
  Future<void> selectNote(NoteNode note, {bool record = true}) async {
    if (note.path == _selectedNotePath) return;
    if (record && _selectedNotePath != null) {
      _backStack.add(_selectedNotePath!);
      _forwardStack.clear();
    }
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

  /// Builds the in-memory search index once, until the tree changes (which
  /// nulls it).
  ///
  /// Managed Folios index the tiny sidecars (title/tags/file name) — fast, no
  /// note bodies read. Browsed plain folders have no sidecars, so they index
  /// the **full text** of each note (the "deep search" you need to find a note
  /// by its content). Tolerates unreadable files (falls back to the file name).
  Future<void> _ensureSearchIndex() async {
    if (_searchIndex != null) return;
    final tree = _tree;
    final content = _content;
    if (tree == null || content == null) {
      _searchIndex = const [];
      return;
    }
    final deep = content.browse;
    final entries = <_NoteIndexEntry>[];
    Future<void> walk(FolderNode folder) async {
      for (final note in folder.notes) {
        var title = note.title;
        var tags = const <String>[];
        var body = '';
        if (deep) {
          try {
            body = (await content.readNote(note.path)).body;
          } catch (_) {
            // Unreadable note -> file name only.
          }
        } else {
          try {
            final props = await content.readNoteProperties(note.path);
            if (props.title != null && props.title!.isNotEmpty) {
              title = props.title!;
            }
            tags = props.tags;
          } catch (_) {
            // Unreadable sidecar -> fall back to the file-name title.
          }
        }
        entries.add(_NoteIndexEntry(
          note: note,
          haystack: '$title ${tags.join(' ')} ${note.name} $body'.toLowerCase(),
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

  /// Follows a Markdown link [target] from the open note. A relative link to a
  /// sibling `.md` note in the same Folio opens that note **in-app** (so a
  /// worldbuilding/doc graph is navigable); an external URL or any other local
  /// file opens with the OS default handler.
  Future<void> openLink(String target) async {
    final raw = target.trim();
    if (raw.isEmpty) return;
    if (isExternalUrl(raw)) {
      await openWithDefaultApp(raw);
      return;
    }

    final folder = _currentNoteFolder();
    final rel = folder == null ? null : _resolveNoteLink(folder, raw);
    if (rel != null) {
      // A sibling note we can open in-app (stays inside the Folio).
      try {
        if (await _folio!.backend.exists(rel)) {
          await selectNote(NoteNode(path: rel, name: rel.split('/').last));
          return;
        }
      } catch (_) {
        // Fall through to opening with the OS.
      }
    }

    // Not an in-Folio note: hand the local file to the OS.
    final resolved = resolveLinkTarget(raw, localAbsolutePath(folder ?? ''));
    if (resolved != null) await openWithDefaultApp(resolved);
  }

  /// Resolves a Markdown link [target] from a note in [fromFolder] (repo-
  /// relative folder) to the repo-relative path of an in-Folio `.md` note, or
  /// null if it isn't one (external URL, a non-`.md` file, or it escapes the
  /// Folio root). Used by both link-following and backlink building.
  String? _resolveNoteLink(String fromFolder, String target) {
    final raw = target.trim();
    if (raw.isEmpty || isExternalUrl(raw)) return null;
    String decoded;
    try {
      decoded = Uri.decodeFull(raw); // %20 → space
    } catch (_) {
      decoded = raw;
    }
    final hash = decoded.indexOf('#'); // drop any #anchor
    final pathPart = hash >= 0 ? decoded.substring(0, hash) : decoded;
    if (pathPart.isEmpty) return null;
    final rel = p.posix
        .normalize(fromFolder.isEmpty ? pathPart : p.posix.join(fromFolder, pathPart));
    if (rel.startsWith('..') ||
        !rel.toLowerCase().endsWith(ContentService.noteExtension)) {
      return null;
    }
    return rel;
  }

  /// Reverse link graph (target note path -> notes that link to it), built lazily
  /// and invalidated on tree change. Null until first built.
  Map<String, List<NoteNode>>? _backlinks;

  /// The notes that link to [notePath] (a relative `.md` link resolving to it).
  /// Builds the graph on first use; cached until the tree changes.
  Future<List<NoteNode>> backlinksFor(String notePath) async {
    await _ensureBacklinks();
    return _backlinks?[notePath] ?? const [];
  }

  Future<void> _ensureBacklinks() async {
    if (_backlinks != null) return;
    final tree = _tree;
    final content = _content;
    if (tree == null || content == null) {
      _backlinks = const {};
      return;
    }
    final map = <String, List<NoteNode>>{};
    Future<void> walk(FolderNode folder) async {
      for (final note in folder.notes) {
        final String body;
        try {
          body = (await content.readNote(note.path)).body;
        } catch (_) {
          continue; // unreadable -> contributes no links
        }
        final from = note.path.contains('/')
            ? note.path.substring(0, note.path.lastIndexOf('/'))
            : '';
        final seen = <String>{};
        for (final link in findMarkdownLinks(body)) {
          final target = _resolveNoteLink(from, link.target);
          // De-dupe repeated links to the same note; skip self-links.
          if (target != null && target != note.path && seen.add(target)) {
            (map[target] ??= <NoteNode>[]).add(note);
          }
        }
      }
      for (final sub in folder.folders) {
        await walk(sub);
      }
    }

    await walk(tree);
    _backlinks = map;
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
    if (isBrowsing) return; // browsed folders are read-only
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
    // Don't persist the view in browse mode — it would write a sidecar into a
    // folder Margin doesn't own.
    if (_viewPolicy == DefaultViewPolicy.noteSpecified &&
        _selectedNotePath != null &&
        !isBrowsing) {
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
    // Browsed (read-only) folders open in Preview — rendered reading makes more
    // sense than a read-only source view. The user can still switch.
    if (isBrowsing) return EditorViewMode.preview;
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

  /// Opens a folder's folder-level note (`README.md`), creating an empty one if
  /// the folder doesn't have it yet. The root has no folder note (no `.md` at
  /// the root), so this is a no-op there.
  Future<void> openFolderNote(FolderNode folder) async {
    if (folder.path.isEmpty) return;
    final content = _content;
    if (content == null) return;
    final notePath = '${folder.path}/${ContentService.folderNoteName}';

    // Trust the filesystem, not the (possibly stale) tree flag: the file may
    // already exist when hasFolderNote is false — a double-click firing this
    // twice, or the tree not yet refreshed. Relying on the flag made the second
    // call re-create it and throw "already exists".
    var exists = folder.hasFolderNote;
    if (!exists) {
      try {
        exists = await content.backend.exists(notePath);
      } catch (_) {
        exists = false;
      }
    }

    if (!exists) {
      if (isBrowsing) return; // read-only: open an existing note, never create
      await _run(() async {
        final now = DateTime.now().toUtc();
        try {
          await content.createNote(
            folder.path,
            ContentService.folderNoteName,
            initial: Note(
              frontmatter: NoteFrontmatter(
                  title: folder.name, created: now, updated: now),
              body: '',
            ),
          );
        } on ContentException {
          // Already there (a racing double-click, or a stale flag): not an
          // error — fall through and just open it.
        }
        await _reloadTree();
      });
      if (_error != null) return; // a real creation failure surfaced
      _scheduleSync();
    }
    await selectNote(
        NoteNode(path: notePath, name: ContentService.folderNoteName));
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
      // Drop the gone note from history so Back/Forward never land on it.
      _backStack.removeWhere((p) => p == path);
      _forwardStack.removeWhere((p) => p == path);
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
      // Drop any history entries that lived under the deleted folder.
      bool underFolder(String p) => p == path || p.startsWith('$path/');
      _backStack.removeWhere(underFolder);
      _forwardStack.removeWhere(underFolder);
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
    _backStack.clear();
    _forwardStack.clear();
    _currentNote = null;
    _workingBody = '';
    _dirty = false;
    // Cleared here; openThroughCache sets them after adopting the cache.
    _syncPeer = null;
    _folioId = null;
    _hasUnsyncedChanges = false;
    _syncError = null;
    // Git context is set by the git flows after this returns; default to none.
    _gitUrl = null;
    _gitPath = null;
    _gitUser = null;
  }

  Future<void> _reloadTree() async {
    _tree = await _content!.tree();
    _searchIndex = null; // notes changed -> rebuild the search index on demand
    _backlinks = null; // and the backlink graph
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
