// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:shared_preferences/shared_preferences.dart';

/// Persists small bits of per-device app state (not repository content).
///
/// Abstracted so the UI controller can be unit-tested with an in-memory store
/// instead of the platform plugin.
abstract interface class SettingsStore {
  /// The last Folio's location: a local filesystem path, or (for WebDAV) the
  /// collection base URL. Paired with [getLastFolioType].
  Future<String?> getLastFolioPath();
  Future<void> setLastFolioPath(String? path);

  /// The last Folio's backend type id — `local` or `webdav`. Null/absent is
  /// treated as `local` (the historical default).
  Future<String?> getLastFolioType();
  Future<void> setLastFolioType(String? type);

  /// The username for the last WebDAV Folio (non-secret; the password lives in
  /// the OS keystore). Null when the last Folio is local.
  Future<String?> getLastWebDavUser();
  Future<void> setLastWebDavUser(String? user);

  /// The last remote Folio's id (UUID). Persisted so its on-device cache can be
  /// located and opened offline, without first reaching the remote to identify
  /// it. Null for a local Folio.
  Future<String?> getLastFolioId();
  Future<void> setLastFolioId(String? id);

  /// Repository-relative path of the last opened note (or null).
  Future<String?> getLastNotePath();
  Future<void> setLastNotePath(String? path);

  /// The recent-Folios list as a JSON string (see `recent_folios.dart` for the
  /// shape and codec). Unlike the last-Folio fields above, this survives an
  /// explicit close — it is what the landing screen's "Recent" entries read.
  Future<String?> getRecentFolios();
  Future<void> setRecentFolios(String? json);

  /// The default-view policy id (`note`/`editor`/`split`/`preview`).
  Future<String?> getViewPolicy();
  Future<void> setViewPolicy(String id);

  /// The default view id for notes without their own setting.
  Future<String?> getDefaultNoteView();
  Future<void> setDefaultNoteView(String id);

  /// Whether the desktop window should float above others.
  Future<bool> getAlwaysOnTop();
  Future<void> setAlwaysOnTop(bool value);

  /// Whether a run-at-login launch should start hidden in the tray.
  Future<bool> getStartMinimized();
  Future<void> setStartMinimized(bool value);

  /// Whether the editor soft-wraps long lines (default true). Off = lines run
  /// out horizontally with a scrollbar — handy for wide tables and code on
  /// desktop.
  Future<bool> getWordWrap();
  Future<void> setWordWrap(bool value);
}

/// A non-persistent [SettingsStore] for tests and as a safe default.
class InMemorySettingsStore implements SettingsStore {
  String? _lastRepositoryPath;
  String? _lastFolioType;
  String? _lastWebDavUser;
  String? _lastFolioId;
  String? _lastNotePath;

  @override
  Future<String?> getLastFolioPath() async => _lastRepositoryPath;

  @override
  Future<void> setLastFolioPath(String? path) async {
    _lastRepositoryPath = path;
  }

  @override
  Future<String?> getLastFolioType() async => _lastFolioType;

  @override
  Future<void> setLastFolioType(String? type) async {
    _lastFolioType = type;
  }

  @override
  Future<String?> getLastWebDavUser() async => _lastWebDavUser;

  @override
  Future<void> setLastWebDavUser(String? user) async {
    _lastWebDavUser = user;
  }

  @override
  Future<String?> getLastFolioId() async => _lastFolioId;

  @override
  Future<void> setLastFolioId(String? id) async {
    _lastFolioId = id;
  }

  @override
  Future<String?> getLastNotePath() async => _lastNotePath;

  @override
  Future<void> setLastNotePath(String? path) async {
    _lastNotePath = path;
  }

  String? _recentFolios;

  @override
  Future<String?> getRecentFolios() async => _recentFolios;

  @override
  Future<void> setRecentFolios(String? json) async {
    _recentFolios = json;
  }

  String? _viewPolicy;
  String? _defaultNoteView;

  @override
  Future<String?> getViewPolicy() async => _viewPolicy;

  @override
  Future<void> setViewPolicy(String id) async => _viewPolicy = id;

  @override
  Future<String?> getDefaultNoteView() async => _defaultNoteView;

  @override
  Future<void> setDefaultNoteView(String id) async => _defaultNoteView = id;

  bool _alwaysOnTop = false;

  @override
  Future<bool> getAlwaysOnTop() async => _alwaysOnTop;

  @override
  Future<void> setAlwaysOnTop(bool value) async => _alwaysOnTop = value;

  bool _startMinimized = false;

  @override
  Future<bool> getStartMinimized() async => _startMinimized;

  @override
  Future<void> setStartMinimized(bool value) async => _startMinimized = value;

  bool _wordWrap = true;

  @override
  Future<bool> getWordWrap() async => _wordWrap;

  @override
  Future<void> setWordWrap(bool value) async => _wordWrap = value;
}

/// A [SettingsStore] backed by `shared_preferences`.
class SharedPreferencesSettingsStore implements SettingsStore {
  static const String _lastRepoKey = 'lastRepositoryPath';
  static const String _lastFolioTypeKey = 'lastFolioType';
  static const String _lastWebDavUserKey = 'lastWebDavUser';
  static const String _lastFolioIdKey = 'lastFolioId';
  static const String _lastNoteKey = 'lastNotePath';
  static const String _recentFoliosKey = 'recentFolios';
  static const String _viewPolicyKey = 'viewPolicy';
  static const String _defaultNoteViewKey = 'defaultNoteView';
  static const String _alwaysOnTopKey = 'alwaysOnTop';
  static const String _startMinimizedKey = 'startMinimized';
  static const String _wordWrapKey = 'wordWrap';

  Future<String?> _getString(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  Future<void> _setString(String key, String? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, value);
    }
  }

  @override
  Future<String?> getLastFolioPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastRepoKey);
  }

  @override
  Future<void> setLastFolioPath(String? path) => _setString(_lastRepoKey, path);

  @override
  Future<String?> getLastFolioType() => _getString(_lastFolioTypeKey);

  @override
  Future<void> setLastFolioType(String? type) =>
      _setString(_lastFolioTypeKey, type);

  @override
  Future<String?> getLastWebDavUser() => _getString(_lastWebDavUserKey);

  @override
  Future<void> setLastWebDavUser(String? user) =>
      _setString(_lastWebDavUserKey, user);

  @override
  Future<String?> getLastFolioId() => _getString(_lastFolioIdKey);

  @override
  Future<void> setLastFolioId(String? id) => _setString(_lastFolioIdKey, id);

  @override
  Future<String?> getLastNotePath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastNoteKey);
  }

  @override
  Future<void> setLastNotePath(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path == null) {
      await prefs.remove(_lastNoteKey);
    } else {
      await prefs.setString(_lastNoteKey, path);
    }
  }

  @override
  Future<String?> getRecentFolios() => _getString(_recentFoliosKey);

  @override
  Future<void> setRecentFolios(String? json) =>
      _setString(_recentFoliosKey, json);

  @override
  Future<String?> getViewPolicy() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_viewPolicyKey);
  }

  @override
  Future<void> setViewPolicy(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_viewPolicyKey, id);
  }

  @override
  Future<String?> getDefaultNoteView() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_defaultNoteViewKey);
  }

  @override
  Future<void> setDefaultNoteView(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_defaultNoteViewKey, id);
  }

  @override
  Future<bool> getAlwaysOnTop() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_alwaysOnTopKey) ?? false;
  }

  @override
  Future<void> setAlwaysOnTop(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_alwaysOnTopKey, value);
  }

  @override
  Future<bool> getStartMinimized() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_startMinimizedKey) ?? false;
  }

  @override
  Future<void> setStartMinimized(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_startMinimizedKey, value);
  }

  @override
  Future<bool> getWordWrap() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_wordWrapKey) ?? true;
  }

  @override
  Future<void> setWordWrap(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_wordWrapKey, value);
  }
}
