// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:shared_preferences/shared_preferences.dart';

/// Persists small bits of per-device app state (not repository content).
///
/// Abstracted so the UI controller can be unit-tested with an in-memory store
/// instead of the platform plugin.
abstract interface class SettingsStore {
  Future<String?> getLastFolioPath();
  Future<void> setLastFolioPath(String? path);

  /// Repository-relative path of the last opened note (or null).
  Future<String?> getLastNotePath();
  Future<void> setLastNotePath(String? path);

  /// The default-view policy id (`note`/`editor`/`split`/`preview`).
  Future<String?> getViewPolicy();
  Future<void> setViewPolicy(String id);

  /// The default view id for notes without their own setting.
  Future<String?> getDefaultNoteView();
  Future<void> setDefaultNoteView(String id);

  /// Whether the desktop window should float above others.
  Future<bool> getAlwaysOnTop();
  Future<void> setAlwaysOnTop(bool value);
}

/// A non-persistent [SettingsStore] for tests and as a safe default.
class InMemorySettingsStore implements SettingsStore {
  String? _lastRepositoryPath;
  String? _lastNotePath;

  @override
  Future<String?> getLastFolioPath() async => _lastRepositoryPath;

  @override
  Future<void> setLastFolioPath(String? path) async {
    _lastRepositoryPath = path;
  }

  @override
  Future<String?> getLastNotePath() async => _lastNotePath;

  @override
  Future<void> setLastNotePath(String? path) async {
    _lastNotePath = path;
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
}

/// A [SettingsStore] backed by `shared_preferences`.
class SharedPreferencesSettingsStore implements SettingsStore {
  static const String _lastRepoKey = 'lastRepositoryPath';
  static const String _lastNoteKey = 'lastNotePath';
  static const String _viewPolicyKey = 'viewPolicy';
  static const String _defaultNoteViewKey = 'defaultNoteView';
  static const String _alwaysOnTopKey = 'alwaysOnTop';

  @override
  Future<String?> getLastFolioPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastRepoKey);
  }

  @override
  Future<void> setLastFolioPath(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path == null) {
      await prefs.remove(_lastRepoKey);
    } else {
      await prefs.setString(_lastRepoKey, path);
    }
  }

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
}
