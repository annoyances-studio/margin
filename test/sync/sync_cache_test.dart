// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:margin/margin.dart';

/// Wraps a backend and counts [read] calls (per path), so tests can prove sync
/// does not re-read (for a remote: re-download) files it need not.
class _CountingBackend implements StorageBackend {
  final StorageBackend inner;
  final List<String> reads = [];

  _CountingBackend(this.inner);

  int get readCount => reads.length;
  void resetCounts() => reads.clear();

  @override
  Future<Uint8List> read(String path) {
    reads.add(path);
    return inner.read(path);
  }

  @override
  Future<List<StorageEntry>> list(String path) => inner.list(path);
  @override
  Future<bool> exists(String path) => inner.exists(path);
  @override
  Future<void> write(String path, Uint8List bytes) => inner.write(path, bytes);
  @override
  Future<void> delete(String path) => inner.delete(path);
}

void main() {
  late MemoryBackend localInner;
  late MemoryBackend remoteInner;
  late _CountingBackend local;
  late _CountingBackend remote;
  late SyncEngine engine;

  setUp(() {
    localInner = MemoryBackend();
    remoteInner = MemoryBackend();
    local = _CountingBackend(localInner);
    remote = _CountingBackend(remoteInner);
    engine = SyncEngine(local: local, remote: remote, deviceName: 'Phone');
  });

  Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));
  Future<String> readLocal(String p) async =>
      utf8.decode(await localInner.read(p));

  group('first-clone fast path', () {
    test('downloads each remote file exactly once (no double-download)',
        () async {
      await remoteInner.write('a.md', bytes('1'));
      await remoteInner.write('b.md', bytes('2'));
      await remoteInner.write('Work/c.md', bytes('3'));
      remote.resetCounts();

      final result = await engine.sync(const SyncState.empty());

      // Three files, three reads — not six (snapshot + apply).
      expect(remote.readCount, 3);
      expect(remote.reads.toSet(), {'a.md', 'b.md', 'Work/c.md'});
      expect(await readLocal('a.md'), '1');
      expect(await readLocal('Work/c.md'), '3');
      // State + remote cache are warmed for the next sync.
      expect(result.newState.hashes.keys,
          containsAll(<String>['a.md', 'b.md', 'Work/c.md']));
      expect(result.newState.remoteCache.length, 3);
    });

    test('pulls properties.yaml first so an interrupted clone reopens offline',
        () async {
      await remoteInner.write('z.md', bytes('z'));
      await remoteInner.write('properties.yaml', bytes('name: X'));
      await remoteInner.write('a.md', bytes('a'));
      remote.resetCounts();

      await engine.sync(const SyncState.empty());

      expect(remote.reads.first, 'properties.yaml');
    });
  });

  group('content-hash cache', () {
    test('a second sync re-reads nothing when nothing changed', () async {
      await remoteInner.write('a.md', bytes('1'));
      await remoteInner.write('Work/b.md', bytes('2'));
      final first = await engine.sync(const SyncState.empty());

      remote.resetCounts();
      local.resetCounts();
      final second = await engine.sync(first.newState);

      expect(second.madeChanges, isFalse);
      expect(remote.readCount, 0, reason: 'unchanged remote must not download');
      expect(local.readCount, 0, reason: 'unchanged local must not re-read');
      expect(second.newState.hashes, equals(first.newState.hashes));
    });

    test('re-reads only the file whose fingerprint changed', () async {
      await remoteInner.write('a.md', bytes('1'));
      await remoteInner.write('b.md', bytes('2'));
      final first = await engine.sync(const SyncState.empty());

      // Change b.md on the remote (new bytes -> new size/mtime -> new tag).
      await remoteInner.write('b.md', bytes('two-two'));
      remote.resetCounts();
      final second = await engine.sync(first.newState);

      // b.md read once to hash it in the snapshot, then pulled: a.md untouched.
      expect(remote.reads.where((p) => p == 'a.md'), isEmpty);
      expect(remote.reads.where((p) => p == 'b.md'), isNotEmpty);
      expect(await readLocal('b.md'), 'two-two');
      expect(second.madeChanges, isTrue);
    });
  });

  group('checkpoint + resume', () {
    test('checkpoints a partial, valid base during a large clone', () async {
      for (var i = 0; i < 60; i++) {
        await remoteInner.write('n$i.md', bytes('body $i'));
      }
      final checkpoints = <SyncState>[];

      await engine.sync(const SyncState.empty(),
          onCheckpoint: (s) async => checkpoints.add(s));

      // 60 files, checkpoint every 25 -> at 25 and 50 (not the final).
      expect(checkpoints.length, 2);
      expect(checkpoints[0].hashes.length, 25);
      expect(checkpoints[1].hashes.length, 50);
      // Every checkpointed path is genuinely pulled (present locally).
      for (final path in checkpoints[1].hashes.keys) {
        expect(await localInner.exists(path), isTrue);
      }
    });

    test('resuming from a checkpoint does not re-download pulled files',
        () async {
      await remoteInner.write('a.md', bytes('1'));
      await remoteInner.write('b.md', bytes('2'));
      await remoteInner.write('c.md', bytes('3'));

      // Reference clone (throwaway local, uncounted remote) gives the true
      // hash + remote fingerprint for a.md, matching what a real checkpoint
      // would have persisted mid-clone.
      final ref = await SyncEngine(
        local: MemoryBackend(),
        remote: remoteInner,
        deviceName: 'Phone',
      ).sync(const SyncState.empty());

      // Interrupted clone: only a.md made it to local + into the checkpoint.
      await localInner.write('a.md', bytes('1'));
      final partial = SyncState(
        {'a.md': ref.newState.hashes['a.md']!},
        remoteCache: {'a.md': ref.newState.remoteCache['a.md']!},
      );

      remote.resetCounts();
      final resumed = await engine.sync(partial);

      // a.md already synced + cached: never downloaded again.
      expect(resumed.madeChanges, isTrue);
      expect(remote.reads.where((p) => p == 'a.md'), isEmpty);
      // The remaining files are pulled.
      expect(await readLocal('b.md'), '2');
      expect(await readLocal('c.md'), '3');
    });
  });
}
