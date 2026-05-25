// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:margin/margin.dart';
import 'package:margin/src/ui/app_controller.dart';

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
