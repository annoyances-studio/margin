// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores secrets (e.g. a WebDAV password) in the platform's secure store —
/// never in the repository or in `properties.yaml` (DESIGN.md).
///
/// Generic on purpose: callers choose the key. How a backend derives its key
/// (from its endpoint URL, username, …) lives with that backend's wiring, not
/// here. Abstracted so the UI/controller can be unit-tested with an in-memory
/// store instead of the platform keystore.
abstract interface class CredentialStore {
  /// Returns the secret stored under [key], or null if there is none.
  Future<String?> read(String key);

  /// Stores [value] under [key], replacing any existing secret.
  Future<void> write(String key, String value);

  /// Removes the secret stored under [key] (no-op if absent).
  Future<void> delete(String key);
}

/// A non-persistent [CredentialStore] for tests and as a safe default.
class InMemoryCredentialStore implements CredentialStore {
  final Map<String, String> _secrets = {};

  @override
  Future<String?> read(String key) async => _secrets[key];

  @override
  Future<void> write(String key, String value) async => _secrets[key] = value;

  @override
  Future<void> delete(String key) async => _secrets.remove(key);
}

/// A [CredentialStore] backed by the OS keystore via `flutter_secure_storage`
/// (Keychain on Apple platforms, Keystore-backed encrypted prefs on Android,
/// libsecret on Linux, the credential locker on Windows).
class SecureCredentialStore implements CredentialStore {
  final FlutterSecureStorage _storage;

  SecureCredentialStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
