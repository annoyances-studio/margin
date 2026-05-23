// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:shared_preferences/shared_preferences.dart';

/// Persists small bits of per-device app state (not repository content).
///
/// Abstracted so the UI controller can be unit-tested with an in-memory store
/// instead of the platform plugin.
abstract interface class SettingsStore {
  Future<String?> getLastRepositoryPath();
  Future<void> setLastRepositoryPath(String? path);

  /// Repository-relative path of the last opened note (or null).
  Future<String?> getLastNotePath();
  Future<void> setLastNotePath(String? path);
}

/// A non-persistent [SettingsStore] for tests and as a safe default.
class InMemorySettingsStore implements SettingsStore {
  String? _lastRepositoryPath;
  String? _lastNotePath;

  @override
  Future<String?> getLastRepositoryPath() async => _lastRepositoryPath;

  @override
  Future<void> setLastRepositoryPath(String? path) async {
    _lastRepositoryPath = path;
  }

  @override
  Future<String?> getLastNotePath() async => _lastNotePath;

  @override
  Future<void> setLastNotePath(String? path) async {
    _lastNotePath = path;
  }
}

/// A [SettingsStore] backed by `shared_preferences`.
class SharedPreferencesSettingsStore implements SettingsStore {
  static const String _lastRepoKey = 'lastRepositoryPath';
  static const String _lastNoteKey = 'lastNotePath';

  @override
  Future<String?> getLastRepositoryPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastRepoKey);
  }

  @override
  Future<void> setLastRepositoryPath(String? path) async {
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
}
