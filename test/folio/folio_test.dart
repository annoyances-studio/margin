// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:margin/margin.dart';
import 'package:uuid/uuid.dart';

void main() {
  late Directory tempDir;
  late LocalFolderBackend backend;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('margin_repo_test_');
    backend = LocalFolderBackend(tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Folio.create', () {
    test('writes properties.yaml and returns a repository', () async {
      final repo = await Folio.create(
        backend,
        name: 'My Notes',
        now: DateTime.utc(2026, 5, 22),
        uuid: const Uuid(),
      );

      expect(repo.name, 'My Notes');
      expect(repo.id, isNotEmpty);
      expect(await backend.exists('properties.yaml'), isTrue);
    });

    test('a created repository can be re-opened with matching identity', () async {
      final created = await Folio.create(backend, name: 'Reopen me');
      final opened = await Folio.open(backend);

      expect(opened.id, created.id);
      expect(opened.name, 'Reopen me');
      expect(opened.properties.schemaVersion,
          FolioProperties.currentSchemaVersion);
    });

    test('persists endpoints', () async {
      await Folio.create(
        backend,
        name: 'With routes',
        endpoints: const [
          Endpoint(type: 'webdav', properties: {'url': 'https://nas.local/dav'}),
        ],
      );
      final opened = await Folio.open(backend);
      expect(opened.endpoints.single.type, 'webdav');
      expect(opened.endpoints.single.properties['url'], 'https://nas.local/dav');
    });

    test('throws if a repository already exists', () async {
      await Folio.create(backend, name: 'First');
      expect(
        () => Folio.create(backend, name: 'Second'),
        throwsA(isA<FolioExistsException>()),
      );
    });
  });

  group('Folio.open', () {
    test('throws NotAMarginFolioException on an empty folder', () {
      expect(
        () => Folio.open(backend),
        throwsA(isA<NotAMarginFolioException>()),
      );
    });

    test('throws NotAMarginFolioException on malformed properties', () async {
      await backend.write('properties.yaml',
          Uint8List.fromList(utf8.encode('this: is: not valid: yaml: at all')));
      expect(
        () => Folio.open(backend),
        throwsA(isA<NotAMarginFolioException>()),
      );
    });

    test('throws IncompatibleSchemaException on a newer schema', () async {
      final future = FolioProperties(
        schemaVersion: FolioProperties.currentSchemaVersion + 1,
        id: 'future-id',
        name: 'From the future',
        created: DateTime.utc(2030),
        updated: DateTime.utc(2030),
        appVersion: '9.9.9',
      );
      await backend.write('properties.yaml',
          Uint8List.fromList(utf8.encode(future.toYaml())));

      expect(
        () => Folio.open(backend),
        throwsA(isA<IncompatibleSchemaException>()),
      );
    });
  });
}
