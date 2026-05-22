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
  });
}
