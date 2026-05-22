// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:margin/margin.dart';

void main() {
  group('RepositoryProperties', () {
    final created = DateTime.utc(2026, 5, 22, 10);
    final updated = DateTime.utc(2026, 5, 22, 14, 30);

    RepositoryProperties sample({List<Endpoint> endpoints = const []}) {
      return RepositoryProperties(
        schemaVersion: 1,
        id: '7f3c9a1e-0000-4000-8000-000000000000',
        name: 'My Notes',
        created: created,
        updated: updated,
        appVersion: '0.1.0',
        endpoints: endpoints,
      );
    }

    test('round-trips through YAML (no endpoints)', () {
      final props = sample();
      final parsed = RepositoryProperties.parse(props.toYaml());

      expect(parsed.schemaVersion, 1);
      expect(parsed.id, props.id);
      expect(parsed.name, 'My Notes');
      expect(parsed.created, created);
      expect(parsed.updated, updated);
      expect(parsed.appVersion, '0.1.0');
      expect(parsed.endpoints, isEmpty);
    });

    test('round-trips endpoints with type-specific properties', () {
      final props = sample(endpoints: const [
        Endpoint(type: 'webdav', properties: {'url': 'https://nas.local/dav'}),
        Endpoint(type: 'smb', properties: {'path': r'\\nas\notes'}),
      ]);
      final parsed = RepositoryProperties.parse(props.toYaml());

      expect(parsed.endpoints, hasLength(2));
      expect(parsed.endpoints[0],
          const Endpoint(type: 'webdav', properties: {'url': 'https://nas.local/dav'}));
      expect(parsed.endpoints[1],
          const Endpoint(type: 'smb', properties: {'path': r'\\nas\notes'}));
    });

    test('safely round-trips names with YAML-hostile characters', () {
      final tricky = sample().copyWith(
        name: 'Quotes "x", colon: y, backslash \\ and emoji 🗒️',
      );
      final parsed = RepositoryProperties.parse(tricky.toYaml());
      expect(parsed.name, tricky.name);
    });

    test('parse rejects a missing id', () {
      expect(
        () => RepositoryProperties.parse('schemaVersion: 1\nname: "x"\n'),
        throwsA(isA<FormatException>()),
      );
    });

    test('parse rejects a non-integer schemaVersion', () {
      expect(
        () => RepositoryProperties.parse('schemaVersion: "one"\nid: "abc"\n'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
