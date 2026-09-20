// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:margin/margin.dart';

void main() {
  group('SyncState', () {
    test('encodes and decodes round-trip', () {
      const state = SyncState({'Work/note.md': 'abc123', 'a/b.md': 'def456'});
      final restored = SyncState.decode(state.encode());
      expect(restored.hashes, equals(state.hashes));
    });

    test('empty state round-trips', () {
      final restored = SyncState.decode(const SyncState.empty().encode());
      expect(restored.hashes, isEmpty);
    });

    test('decoding malformed input yields an empty state', () {
      expect(SyncState.decode('"not an object"').hashes, isEmpty);
    });

    test('content-hash caches round-trip', () {
      const state = SyncState(
        {'a.md': 'h1'},
        localCache: {'a.md': (fingerprint: 's:5:100', hash: 'h1')},
        remoteCache: {'a.md': (fingerprint: 't:quickxor==', hash: 'h1')},
      );
      final restored = SyncState.decode(state.encode());
      expect(restored.localCache['a.md']?.fingerprint, 's:5:100');
      expect(restored.remoteCache['a.md']?.hash, 'h1');
    });

    test('reads a v1 state (no caches) as empty caches', () {
      // A state written before caches existed must still load.
      final restored =
          SyncState.decode('{"version":1,"hashes":{"a.md":"h1"}}');
      expect(restored.hashes, {'a.md': 'h1'});
      expect(restored.localCache, isEmpty);
      expect(restored.remoteCache, isEmpty);
    });

    test('drops malformed cache entries but keeps the state', () {
      final restored = SyncState.decode(
          '{"hashes":{"a.md":"h1"},"remoteCache":{"a.md":{"f":42}}}');
      expect(restored.hashes, {'a.md': 'h1'});
      expect(restored.remoteCache, isEmpty); // bad entry dropped
    });
  });
}
