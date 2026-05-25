// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'sync_state.dart';

/// Persists the per-device sync base state, keyed by Folio id (DESIGN.md: this
/// is device-local and must NOT live inside the Folio). Abstracted so the
/// controller can be unit-tested with an in-memory store.
abstract interface class SyncStateStore {
  /// Loads the last-synced state for [folioId] (empty if there is none).
  Future<SyncState> load(String folioId);

  /// Saves the latest synced [state] for [folioId].
  Future<void> save(String folioId, SyncState state);
}

/// A non-persistent [SyncStateStore] for tests and as a safe default.
class InMemorySyncStateStore implements SyncStateStore {
  final Map<String, SyncState> _states = {};

  @override
  Future<SyncState> load(String folioId) async =>
      _states[folioId] ?? const SyncState.empty();

  @override
  Future<void> save(String folioId, SyncState state) async =>
      _states[folioId] = state;
}

/// A [SyncStateStore] that writes one JSON file per Folio under the app support
/// directory (`<support>/Margin/sync/<id>.json`). Pass an explicit [directory]
/// in tests; production resolves the support directory lazily.
class FileSyncStateStore implements SyncStateStore {
  final Directory? _explicitDirectory;

  FileSyncStateStore([this._explicitDirectory]);

  Future<Directory> _directory() async {
    final explicit = _explicitDirectory;
    if (explicit != null) return explicit;
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'Margin', 'sync'));
  }

  Future<File> _file(String folioId) async =>
      File(p.join((await _directory()).path, '$folioId.json'));

  @override
  Future<SyncState> load(String folioId) async {
    final file = await _file(folioId);
    if (!await file.exists()) return const SyncState.empty();
    try {
      return SyncState.decode(await file.readAsString());
    } catch (_) {
      return const SyncState.empty(); // corrupt -> resync from scratch
    }
  }

  @override
  Future<void> save(String folioId, SyncState state) async {
    final file = await _file(folioId);
    await file.parent.create(recursive: true);
    await file.writeAsString(state.encode());
  }
}
