// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:margin/margin.dart';
import 'package:margin/src/sync/sync_state_store.dart';
import 'package:margin/src/ui/app_controller.dart';

/// A backend whose every operation fails — stands in for "no signal".
class _UnreachableBackend implements StorageBackend {
  Never _offline() => throw Exception('offline: no signal');

  @override
  Future<List<StorageEntry>> list(String path) async => _offline();
  @override
  Future<bool> exists(String path) async => _offline();
  @override
  Future<Uint8List> read(String path) async => _offline();
  @override
  Future<void> write(String path, Uint8List bytes) async => _offline();
  @override
  Future<void> delete(String path) async => _offline();
}

void main() {
  late Directory cacheDir;

  setUp(() async {
    cacheDir = await Directory.systemTemp.createTemp('margin_offline_');
  });
  tearDown(() async {
    if (await cacheDir.exists()) await cacheDir.delete(recursive: true);
  });

  test('opens the local cache when the remote is unreachable (offline)',
      () async {
    final states = InMemorySyncStateStore();

    // Online: the first open clones into the cache and records the Folio id.
    final remote = MemoryBackend();
    await Folio.create(remote, name: 'Remote Notes');
    final online =
        AppController(cacheRoot: () async => cacheDir, syncStates: states);
    addTearDown(online.dispose);
    await online.openThroughCache(remote);
    expect(online.hasFolio, isTrue);
    final id = online.folioId!;

    // Offline: the remote times out, but the cache exists -> open from cache.
    final offline =
        AppController(cacheRoot: () async => cacheDir, syncStates: states);
    addTearDown(offline.dispose);
    await offline.openThroughCache(_UnreachableBackend(), knownId: id);

    expect(offline.hasFolio, isTrue,
        reason: 'a dropped connection must not block opening cached notes');
    expect(offline.folioName, 'Remote Notes');
    expect(offline.canSync, isTrue);

    // The background refresh fails, but non-blockingly (recorded, not thrown).
    await offline.pendingSync;
    expect(offline.syncError, isNotNull);
  });

  test('without a cache, an unreachable remote surfaces an error', () async {
    final offline = AppController(cacheRoot: () async => cacheDir);
    addTearDown(offline.dispose);

    await offline.openThroughCache(_UnreachableBackend(), knownId: 'no-such-id');

    expect(offline.hasFolio, isFalse);
    expect(offline.error, isNotNull);
  });
}
