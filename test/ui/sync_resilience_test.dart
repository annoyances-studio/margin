// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:margin/margin.dart';
import 'package:margin/src/mobile/keep_awake.dart';
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
}
