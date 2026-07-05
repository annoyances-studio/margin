// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:margin/src/settings/recent_folios.dart';

void main() {
  test('encode/decode round-trips all fields', () {
    final folios = [
      const RecentFolio(
        type: 'webdav',
        location: 'https://dav.example.com/notes/',
        name: 'Work',
        user: 'dan',
        id: 'uuid-1',
      ),
    ];
    final decoded = decodeRecentFolios(encodeRecentFolios(folios));
    expect(decoded, hasLength(1));
    expect(decoded.single.type, 'webdav');
    expect(decoded.single.location, 'https://dav.example.com/notes/');
    expect(decoded.single.name, 'Work');
    expect(decoded.single.user, 'dan');
    expect(decoded.single.id, 'uuid-1');
  });

  test('optional fields stay null through the round-trip', () {
    final decoded = decodeRecentFolios(encodeRecentFolios([
      const RecentFolio(type: 'local', location: 'C:/notes', name: 'Notes'),
    ]));
    expect(decoded.single.user, isNull);
    expect(decoded.single.id, isNull);
    expect(decoded.single.browse, isFalse); // default
  });

  test('the browse flag round-trips', () {
    final decoded = decodeRecentFolios(encodeRecentFolios([
      const RecentFolio(
          type: 'onedrive', location: 'Shared/Notes', name: 'Notes', browse: true),
    ]));
    expect(decoded.single.browse, isTrue);
  });

  test('decode tolerates garbage and wrong shapes', () {
    expect(decodeRecentFolios(null), isEmpty);
    expect(decodeRecentFolios(''), isEmpty);
    expect(decodeRecentFolios('not json'), isEmpty);
    expect(decodeRecentFolios('{"a": 1}'), isEmpty);
    // Entries missing required fields are skipped, not fatal.
    expect(
      decodeRecentFolios(
          '[{"name": "no type or location"}, {"type": "local", "location": "/x"}]'),
      hasLength(1),
    );
  });

  test('upsert puts the entry first, dedupes by target, and caps', () {
    const a = RecentFolio(type: 'local', location: '/a', name: 'A');
    const b = RecentFolio(type: 'webdav', location: 'https://b', name: 'B');

    var list = upsertRecentFolio(const [], a, cap: 2);
    list = upsertRecentFolio(list, b, cap: 2);
    expect(list.map((f) => f.name), ['B', 'A']);

    // Re-opening A moves it to the front (no duplicate), with its new name.
    const a2 = RecentFolio(type: 'local', location: '/a', name: 'A renamed');
    list = upsertRecentFolio(list, a2, cap: 2);
    expect(list.map((f) => f.name), ['A renamed', 'B']);

    // The cap drops the oldest.
    const c = RecentFolio(type: 'onedrive', location: 'Apps/M', name: 'C');
    list = upsertRecentFolio(list, c, cap: 2);
    expect(list.map((f) => f.name), ['C', 'A renamed']);
  });

  test('default cap is the configured maximum', () {
    var list = const <RecentFolio>[];
    for (var i = 0; i < kMaxRecentFolios + 3; i++) {
      list = upsertRecentFolio(
          list, RecentFolio(type: 'local', location: '/$i', name: '$i'));
    }
    expect(list, hasLength(kMaxRecentFolios));
  });
}
