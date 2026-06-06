// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:margin/margin.dart';
import 'package:margin/src/ui/app_controller.dart';

/// Wraps a backend so a test can stall its `list` mid-sync (the sync snapshots
/// via list), to prove note navigation doesn't block behind a running sync.
class _GatedBackend implements StorageBackend {
  final MemoryBackend _inner;
  Completer<void>? gate; // when non-null, list() awaits it
  _GatedBackend(this._inner);

  @override
  Future<List<StorageEntry>> list(String path) async {
    if (gate != null) await gate!.future;
    return _inner.list(path);
  }

  @override
  Future<bool> exists(String path) => _inner.exists(path);
  @override
  Future<Uint8List> read(String path) => _inner.read(path);
  @override
  Future<void> write(String path, Uint8List bytes) => _inner.write(path, bytes);
  @override
  Future<void> delete(String path) => _inner.delete(path);
}

NoteNode? _findNote(FolderNode folder, String name) {
  for (final n in folder.notes) {
    if (n.name == name) return n;
  }
  for (final f in folder.folders) {
    final found = _findNote(f, name);
    if (found != null) return found;
  }
  return null;
}

void main() {
  late Directory cacheDir;
  late MemoryBackend remote;

  setUp(() async {
    cacheDir = await Directory.systemTemp.createTemp('margin_syncux_');
    remote = MemoryBackend();
    await Folio.create(remote, name: 'Remote');
  });
  tearDown(() async {
    if (await cacheDir.exists()) await cacheDir.delete(recursive: true);
  });

  AppController controller() =>
      AppController(cacheRoot: () async => cacheDir);

  test('a freshly cloned Folio starts fully synced', () async {
    final c = controller();
    addTearDown(c.dispose);
    await c.openThroughCache(remote);

    expect(c.canSync, isTrue);
    expect(c.hasUnsyncedChanges, isFalse);
  });

  test('a local change marks the Folio unsynced, then auto-syncs to the remote',
      () async {
    final c = controller();
    addTearDown(c.dispose);
    await c.openThroughCache(remote);

    await c.createFolder('Work');
    await c.createNote('note', folderPath: 'Work');

    // The marker turns on synchronously when a change is made.
    expect(c.hasUnsyncedChanges, isTrue);

    // Let the background auto-sync run to completion.
    await c.pendingSync;

    expect(c.hasUnsyncedChanges, isFalse);
    expect(c.syncError, isNull);
    // The new note reached the remote without a manual Sync now.
    expect(await remote.exists('Work/note.md'), isTrue);
  });

  test('a remote that comes back empty is withheld, not propagated as a wipe',
      () async {
    final c = controller();
    addTearDown(c.dispose);
    await c.openThroughCache(remote);
    await c.createFolder('Work');
    await c.createNote('note', folderPath: 'Work');
    await c.pendingSync;
    expect(await remote.exists('Work/note.md'), isTrue);

    final id = c.folioId!;
    final cachedNote = File('${cacheDir.path}/$id/Work/note.md');
    expect(cachedNote.existsSync(), isTrue);

    // Wipe the remote out-of-band (simulating a flaky/empty listing).
    Future<void> wipe([String path = '']) async {
      for (final e in await remote.list(path)) {
        if (e.isDirectory) {
          await wipe(e.path);
        } else {
          await remote.delete(e.path);
        }
      }
    }

    await wipe();
    await c.syncNow();

    // The local cache is preserved; the user is asked before any deletion.
    expect(c.syncNeedsEmptyConfirm, isTrue);
    expect(cachedNote.existsSync(), isTrue);
    expect(c.syncError, isNull);

    // After confirmation, the wipe is applied.
    await c.confirmEmptyingSync();
    expect(c.syncNeedsEmptyConfirm, isFalse);
    expect(cachedNote.existsSync(), isFalse);
  });

  test('openThroughCache with createName initializes a Folio on an empty remote',
      () async {
    final empty = MemoryBackend(); // no Folio yet
    final c = controller();
    addTearDown(c.dispose);

    await c.openThroughCache(empty, createName: 'Fresh Notes');

    expect(c.hasFolio, isTrue);
    expect(c.folioName, 'Fresh Notes');
    expect(c.canSync, isTrue);
    // The new Folio was written through to the remote.
    expect(await empty.exists('properties.yaml'), isTrue);
  });

  test('switching notes stays responsive while a sync is in flight', () async {
    final gated = _GatedBackend(MemoryBackend());
    await Folio.create(gated._inner, name: 'Remote');
    final c = AppController(cacheRoot: () async => cacheDir);
    addTearDown(c.dispose);

    await c.openThroughCache(gated); // initial clone (gate open)
    await c.createFolder('Work');
    await c.createNote('a', folderPath: 'Work');
    await c.createNote('b', folderPath: 'Work');
    await c.pendingSync;

    // Stall the next sync mid-flight, then trigger one.
    gated.gate = Completer<void>();
    c.updateBody('# edit'); // dirty the selected note (b)
    await c.save(); // flushes, then schedules a sync that blocks on the gate

    // Switching to another note must NOT wait for the stalled sync.
    final a = _findNote(c.tree!, 'a.md')!;
    await c.selectNote(a).timeout(
          const Duration(seconds: 2),
          onTimeout: () =>
              fail('selectNote blocked behind the in-flight sync'),
        );
    expect(c.selectedNotePath, 'Work/a.md');

    // Release the sync and let it finish cleanly.
    gated.gate!.complete();
    gated.gate = null;
    await c.pendingSync;
    expect(c.syncError, isNull);
  });

  test('manual syncNow pushes a local edit to the remote', () async {
    final c = controller();
    addTearDown(c.dispose);
    await c.openThroughCache(remote);
    await c.createFolder('Work');
    await c.createNote('note', folderPath: 'Work');
    await c.pendingSync;

    c.updateBody('# Edited body');
    await c.save();
    await c.syncNow();

    expect(c.hasUnsyncedChanges, isFalse);
    final remoteBody = await remote.read('Work/note.md');
    expect(String.fromCharCodes(remoteBody), contains('Edited body'));
  });
}
