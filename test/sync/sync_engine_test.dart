// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:margin/margin.dart';

void main() {
  late MemoryBackend local;
  late MemoryBackend remote;
  late SyncEngine engine;

  setUp(() {
    local = MemoryBackend();
    remote = MemoryBackend();
    engine = SyncEngine(
      local: local,
      remote: remote,
      deviceName: 'Phone',
      clock: () => DateTime.utc(2026, 5, 22),
    );
  });

  Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));
  Future<String> readLocal(String p) async => utf8.decode(await local.read(p));
  Future<String> readRemote(String p) async => utf8.decode(await remote.read(p));

  test('pushes a new local file to the remote', () async {
    await local.write('Work/note.md', bytes('hello'));

    final result = await engine.sync(const SyncState.empty());

    expect(result.madeChanges, isTrue);
    expect(await readRemote('Work/note.md'), 'hello');
    expect(result.newState.hashes.containsKey('Work/note.md'), isTrue);
  });

  test('pulls a new remote file to the local', () async {
    await remote.write('Work/note.md', bytes('world'));

    await engine.sync(const SyncState.empty());

    expect(await readLocal('Work/note.md'), 'world');
  });

  test('a second sync with no changes is a no-op', () async {
    await local.write('Work/note.md', bytes('hello'));
    final first = await engine.sync(const SyncState.empty());

    final second = await engine.sync(first.newState);

    expect(second.madeChanges, isFalse);
    expect(second.newState.hashes, equals(first.newState.hashes));
  });

  test('propagates a local deletion to the remote', () async {
    // Two files so deleting one is a normal deletion, not a full emptying
    // (which the guard would withhold — covered separately below).
    await local.write('Work/note.md', bytes('hello'));
    await local.write('Work/keep.md', bytes('stay'));
    final synced = await engine.sync(const SyncState.empty());

    await local.delete('Work/note.md');
    final result = await engine.sync(synced.newState);

    expect(await remote.exists('Work/note.md'), isFalse);
    expect(await remote.exists('Work/keep.md'), isTrue);
    expect(result.newState.hashes.containsKey('Work/note.md'), isFalse);
  });

  group('emptying guard', () {
    test('withholds a plan that would wipe everything (e.g. empty listing)',
        () async {
      await remote.write('a.md', bytes('1'));
      await remote.write('b.md', bytes('2'));
      final synced = await engine.sync(const SyncState.empty()); // clone both

      // Simulate a flaky/incomplete remote that now lists as empty.
      await remote.delete('a.md');
      await remote.delete('b.md');
      final result = await engine.sync(synced.newState);

      expect(result.withheld, isTrue);
      // Nothing applied: the local copy is untouched, state unchanged.
      expect(await local.exists('a.md'), isTrue);
      expect(await local.exists('b.md'), isTrue);
      expect(result.newState.hashes, equals(synced.newState.hashes));
    });

    test('allowEmptying lets the wipe through after confirmation', () async {
      await local.write('a.md', bytes('1'));
      final synced = await engine.sync(const SyncState.empty());

      await local.delete('a.md'); // empties the only file
      final result = await engine.sync(synced.newState, allowEmptying: true);

      expect(result.withheld, isFalse);
      expect(await remote.exists('a.md'), isFalse);
      expect(result.newState.hashes, isEmpty);
    });

    test('the first clone (empty base) is never withheld', () async {
      await remote.write('a.md', bytes('1'));
      final result = await engine.sync(const SyncState.empty());
      expect(result.withheld, isFalse);
      expect(await local.exists('a.md'), isTrue);
    });

    test('a delete that leaves content is not withheld', () async {
      await local.write('a.md', bytes('1'));
      await local.write('b.md', bytes('2'));
      final synced = await engine.sync(const SyncState.empty());

      await local.delete('a.md'); // b.md remains
      final result = await engine.sync(synced.newState);

      expect(result.withheld, isFalse);
      expect(await remote.exists('a.md'), isFalse);
      expect(await remote.exists('b.md'), isTrue);
    });
  });

  test('keeps the edit when one side deletes and the other edits', () async {
    await local.write('Work/note.md', bytes('v1'));
    final synced = await engine.sync(const SyncState.empty());

    // Delete locally, edit remotely.
    await local.delete('Work/note.md');
    await remote.write('Work/note.md', bytes('v2'));

    await engine.sync(synced.newState);

    expect(await readLocal('Work/note.md'), 'v2');
    expect(await readRemote('Work/note.md'), 'v2');
  });

  group('conflict', () {
    test('both edited: remote wins original, local kept as a conflict copy',
        () async {
      await local.write('Work/note.md', bytes('base'));
      final synced = await engine.sync(const SyncState.empty());

      await local.write('Work/note.md', bytes('local version'));
      await remote.write('Work/note.md', bytes('remote version'));

      final result = await engine.sync(synced.newState);

      expect(result.hadConflicts, isTrue);
      const copy = 'Work/note (conflict, Phone, 2026-05-22).md';

      // Original converges to the remote version on both sides.
      expect(await readLocal('Work/note.md'), 'remote version');
      expect(await readRemote('Work/note.md'), 'remote version');

      // Local version preserved as the conflict copy on both sides.
      expect(await readLocal(copy), 'local version');
      expect(await readRemote(copy), 'local version');

      // New state tracks both files; a follow-up sync is a no-op.
      expect(result.newState.hashes.keys,
          containsAll(<String>['Work/note.md', copy]));
      final after = await engine.sync(result.newState);
      expect(after.madeChanges, isFalse);
    });
  });

  test('reports progress per applied action (e.g. initial download)', () async {
    await remote.write('a.md', bytes('1'));
    await remote.write('b.md', bytes('2'));
    await remote.write('Work/c.md', bytes('3'));

    final updates = <SyncProgress>[];
    // Empty base + populated remote = the initial clone/download.
    await engine.sync(const SyncState.empty(), onProgress: updates.add);

    expect(updates.length, 3);
    expect(updates.map((p) => p.completed), [1, 2, 3]);
    expect(updates.every((p) => p.total == 3), isTrue);
    expect(updates.last.fraction, 1.0);
  });

  test('no progress callbacks when there is nothing to sync', () async {
    final updates = <SyncProgress>[];
    await engine.sync(const SyncState.empty(), onProgress: updates.add);
    expect(updates, isEmpty);
  });
}
