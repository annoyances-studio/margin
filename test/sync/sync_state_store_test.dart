// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:margin/src/sync/sync_state.dart';
import 'package:margin/src/sync/sync_state_store.dart';

void main() {
  group('InMemorySyncStateStore', () {
    test('returns empty for an unknown Folio, round-trips a saved state',
        () async {
      final store = InMemorySyncStateStore();
      expect((await store.load('id1')).hashes, isEmpty);

      await store.save('id1', const SyncState({'a.md': 'h1'}));
      expect((await store.load('id1')).hashes, {'a.md': 'h1'});
      // Keyed by Folio id — another id is independent.
      expect((await store.load('id2')).hashes, isEmpty);
    });
  });

  group('FileSyncStateStore', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('margin_sync_');
    });
    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('persists per-Folio state to its own JSON file', () async {
      final store = FileSyncStateStore(dir);
      expect((await store.load('abc')).hashes, isEmpty);

      await store.save('abc', const SyncState({'Work/n.md': 'hash'}));
      expect(await File('${dir.path}/abc.json').exists(), isTrue);

      // A fresh store instance reads the persisted state back.
      final reopened = FileSyncStateStore(dir);
      expect((await reopened.load('abc')).hashes, {'Work/n.md': 'hash'});
    });

    test('treats a corrupt file as empty', () async {
      await File('${dir.path}/bad.json').writeAsString('{not json');
      final store = FileSyncStateStore(dir);
      expect((await store.load('bad')).hashes, isEmpty);
    });
  });
}
