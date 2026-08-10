// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:margin/margin.dart';
import 'package:margin/src/storage/saf/saf_backend.dart';
import 'package:margin/src/storage/saf/saf_channel.dart';
import 'package:margin/src/ui/app_controller.dart';

/// A [SafChannel] backed by a [MemoryBackend], ignoring the tree URI — stands in
/// for the native SAF bridge so backend + controller logic is testable.
class _FakeSaf implements SafChannel {
  _FakeSaf(this.backend, {this.pick});

  final MemoryBackend backend;
  final ({String uri, String name})? pick;

  @override
  Future<({String uri, String name})?> pickFolder() async => pick;

  @override
  Future<List<StorageEntry>> list(String treeUri, String path) =>
      backend.list(path);

  @override
  Future<Uint8List> read(String treeUri, String path) => backend.read(path);

  @override
  Future<bool> exists(String treeUri, String path) => backend.exists(path);
}

void main() {
  Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

  group('SafBackend', () {
    test('delegates list/exists/read and normalises the root path', () async {
      final mem = MemoryBackend();
      await mem.write('Docs/a.md', bytes('hello'));
      final backend = SafBackend(_FakeSaf(mem), 'content://tree/x');

      // Root accepts '' and '/'.
      final rootNames = (await backend.list('')).map((e) => e.path).toList();
      expect(rootNames, contains('Docs'));
      expect((await backend.list('/')).map((e) => e.path), contains('Docs'));

      expect(await backend.exists('Docs/a.md'), isTrue);
      expect(utf8.decode(await backend.read('Docs/a.md')), 'hello');
    });

    test('is read-only: write and delete throw', () {
      final backend = SafBackend(_FakeSaf(MemoryBackend()), 'content://tree/x');
      expect(() => backend.write('x.md', bytes('x')), throwsUnsupportedError);
      expect(() => backend.delete('x.md'), throwsUnsupportedError);
    });
  });

  group('AppController.browseAndroidFolder', () {
    test('opens the picked folder read-only and records it', () async {
      final mem = MemoryBackend();
      await mem.write('README.md', bytes('# Overview'));
      final controller = AppController(
        saf: _FakeSaf(mem, pick: (uri: 'content://tree/docs', name: 'Docs')),
      );
      addTearDown(controller.dispose);

      await controller.browseAndroidFolder();

      expect(controller.hasFolio, isTrue);
      expect(controller.isBrowsing, isTrue);
      expect(controller.folioName, 'Docs');
      expect(
        controller.recentFolios.any(
          (r) => r.type == 'saf' && r.location == 'content://tree/docs' && r.browse,
        ),
        isTrue,
      );
    });

    test('no-ops when the picker is cancelled', () async {
      final controller = AppController(saf: _FakeSaf(MemoryBackend()));
      addTearDown(controller.dispose);

      await controller.browseAndroidFolder();

      expect(controller.hasFolio, isFalse);
      expect(controller.recentFolios, isEmpty);
    });
  });
}
