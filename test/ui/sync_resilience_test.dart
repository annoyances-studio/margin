// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:margin/margin.dart';
import 'package:margin/src/mobile/keep_awake.dart';
import 'package:margin/src/settings/recent_folios.dart';
import 'package:margin/src/settings/settings_store.dart';
import 'package:margin/src/sync/sync_state_store.dart';
import 'package:margin/src/ui/app_controller.dart';

/// Fails `read` for one chosen path, so a test can interrupt a clone partway
/// (after the Folio marker, before another file).
class _ReadFailBackend implements StorageBackend {
  final StorageBackend _inner;
  final String failPath;
  _ReadFailBackend(this._inner, this.failPath);

  @override
  Future<Uint8List> read(String path) {
    if (path == failPath) {
      throw const StorageException('connection closed while receiving data');
    }
    return _inner.read(path);
  }

  @override
  Future<List<StorageEntry>> list(String path) => _inner.list(path);
  @override
  Future<bool> exists(String path) => _inner.exists(path);
  @override
  Future<void> write(String path, Uint8List bytes) => _inner.write(path, bytes);
  @override
  Future<void> delete(String path) => _inner.delete(path);
}

/// Records the acquire/release lifecycle so a test can prove a sync is guarded.
class _RecordingKeepAwake implements KeepAwake {
  int acquired = 0;
  int released = 0;
  bool heldDuringAction = false;

  @override
  Future<void> acquire() async => acquired++;
  @override
  Future<void> release() async => released++;

  @override
  Future<T> guard<T>(Future<T> Function() action) async {
    await acquire();
    heldDuringAction = acquired > released; // held while the action runs
    try {
      return await action();
    } finally {
      await release();
    }
  }
}

void main() {
  late Directory cacheDir;
  late MemoryBackend remote;

  setUp(() async {
    cacheDir = await Directory.systemTemp.createTemp('margin_resilience_');
    remote = MemoryBackend();
    await Folio.create(remote, name: 'Remote');
    await remote.write('a.md', Uint8List.fromList('alpha'.codeUnits));
    await remote.write('b.md', Uint8List.fromList('beta'.codeUnits));
  });
  tearDown(() async {
    if (await cacheDir.exists()) await cacheDir.delete(recursive: true);
  });

  test('a clone interrupted mid-pull still adopts the partial cache offline',
      () async {
    // properties.yaml pulls first, so the Folio is usable even though b.md
    // fails — the user lands on their notes, not a dead error screen.
    final flaky = _ReadFailBackend(remote, 'b.md');
    final c = AppController(cacheRoot: () async => cacheDir);
    addTearDown(c.dispose);

    await c.openThroughCache(flaky);

    expect(c.hasFolio, isTrue, reason: 'partial clone must be usable');
    expect(c.canSync, isTrue);
    expect(c.syncError, isNotNull, reason: 'the failure is surfaced to retry');
    // Idle-but-incomplete: the state the "Not fully synced — tap to resume"
    // banner keys on (syncError set, nothing running).
    expect(c.isSyncing, isFalse);

    final id = c.folioId!;
    expect(File('${cacheDir.path}/$id/properties.yaml').existsSync(), isTrue);
    expect(File('${cacheDir.path}/$id/a.md').existsSync(), isTrue);
    expect(File('${cacheDir.path}/$id/b.md').existsSync(), isFalse);
  });

  test('a resumed clone finishes and does not re-fetch the pulled files',
      () async {
    // First attempt fails on b.md.
    final c1 = AppController(cacheRoot: () async => cacheDir);
    await c1.openThroughCache(_ReadFailBackend(remote, 'b.md'));
    final id = c1.folioId!;
    expect(c1.syncError, isNotNull);
    c1.dispose();

    // Reopen against the healthy remote (same cache): the pulled files stay,
    // b.md is fetched, and the Folio ends fully synced with no error.
    final c2 = AppController(cacheRoot: () async => cacheDir);
    addTearDown(c2.dispose);
    await c2.openThroughCache(remote, knownId: id);
    await c2.pendingSync;

    expect(c2.syncError, isNull);
    expect(File('${cacheDir.path}/$id/b.md').existsSync(), isTrue);
    expect(c2.hasUnsyncedChanges, isFalse);
  });

  test('the clone is wrapped in a keep-awake guard', () async {
    final awake = _RecordingKeepAwake();
    final c = AppController(
      cacheRoot: () async => cacheDir,
      keepAwake: awake,
    );
    addTearDown(c.dispose);

    await c.openThroughCache(remote);

    expect(awake.acquired, greaterThanOrEqualTo(1));
    expect(awake.released, awake.acquired, reason: 'always released');
    expect(awake.heldDuringAction, isTrue);
  });

  group('removing a Folio clears its cache', () {
    late Directory stateDir;
    late FileSyncStateStore store;
    setUp(() async {
      stateDir = await Directory.systemTemp.createTemp('margin_state_');
      store = FileSyncStateStore(stateDir);
    });
    tearDown(() async {
      if (await stateDir.exists()) await stateDir.delete(recursive: true);
    });

    test('discards the on-device cache and sync state (clean re-add)',
        () async {
      final c = AppController(cacheRoot: () async => cacheDir, syncStates: store);
      addTearDown(c.dispose);
      await c.openThroughCache(remote);
      final id = c.folioId!;
      final cache = Directory('${cacheDir.path}/$id');
      final stateFile = File('${stateDir.path}/$id.json');
      expect(cache.existsSync(), isTrue);
      expect(stateFile.existsSync(), isTrue);

      c.closeFolio(); // not the open Folio anymore
      c.removeRecentFolio(
          RecentFolio(type: 'onedrive', location: 'x', name: 'n', id: id));
      await c.pendingCacheDiscard;

      // Clean slate: a later open would be a fresh clone, not a stale resume.
      expect(cache.existsSync(), isFalse);
      expect(stateFile.existsSync(), isFalse);
    });

    test('never touches the cache of the currently-open Folio', () async {
      final c = AppController(cacheRoot: () async => cacheDir, syncStates: store);
      addTearDown(c.dispose);
      await c.openThroughCache(remote);
      final id = c.folioId!;

      // Removing the recent while the Folio is still open must not delete it.
      c.removeRecentFolio(
          RecentFolio(type: 'onedrive', location: 'x', name: 'n', id: id));
      await c.pendingCacheDiscard;

      expect(Directory('${cacheDir.path}/$id').existsSync(), isTrue);
    });
  });

  test('folioCacheStats reports the cached size and file count', () async {
    final c = AppController(cacheRoot: () async => cacheDir);
    addTearDown(c.dispose);
    await c.openThroughCache(remote); // pulls properties.yaml + a.md + b.md

    final stats = await c.currentFolioCacheStats();
    expect(stats, isNotNull);
    expect(stats!.files, greaterThanOrEqualTo(3));
    expect(stats.bytes, greaterThan(0));
  });

  group('orphan-cache prune on startup', () {
    Directory dir(String name) => Directory('${cacheDir.path}/$name');
    Future<void> seedFolioCache(String name) async {
      await dir(name).create(recursive: true);
      await File('${dir(name).path}/properties.yaml')
          .writeAsString('name: $name');
    }

    test('deletes caches with no list entry, keeps listed/device/non-cache',
        () async {
      // A listed Folio (its cache must survive)...
      await seedFolioCache('keep-id');
      // ...an orphan cache from an older capped list (must be pruned)...
      await seedFolioCache('orphan-id');
      // ...the on-device Folio (never a cache, must survive)...
      await seedFolioCache('DeviceNotes');
      // ...and unrelated data with no Folio marker (must survive).
      final other = Directory('${cacheDir.path}/misc')..createSync();
      File('${other.path}/data.txt').writeAsStringSync('x');

      final settings = InMemorySettingsStore();
      await settings.setRecentFolios(encodeRecentFolios(const [
        RecentFolio(type: 'onedrive', location: 'x', name: 'Keep', id: 'keep-id'),
      ]));
      final c = AppController(
        cacheRoot: () async => cacheDir,
        settings: settings,
      );
      addTearDown(c.dispose);

      await c.start(); // auto-prune is skipped under flutter test
      await c.pruneOrphanCaches(); // …so exercise it directly

      expect(dir('orphan-id').existsSync(), isFalse, reason: 'orphan pruned');
      expect(dir('keep-id').existsSync(), isTrue, reason: 'listed survives');
      expect(dir('DeviceNotes').existsSync(), isTrue, reason: 'device survives');
      expect(other.existsSync(), isTrue, reason: 'non-cache data survives');
    });
  });
}
