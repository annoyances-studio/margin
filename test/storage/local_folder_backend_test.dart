// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:margin/src/storage/local_folder_backend.dart';
import 'package:margin/src/storage/storage_exception.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late LocalFolderBackend backend;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('margin_test_');
    backend = LocalFolderBackend(tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

  group('LocalFolderBackend', () {
    test('write then read round-trips bytes', () async {
      await backend.write('Work/note.md', bytes('# Hello'));
      final out = await backend.read('Work/note.md');
      expect(utf8.decode(out), '# Hello');
    });

    test('move renames a directory and its contents in one operation',
        () async {
      await backend.write('Work/note.md', bytes('hi'));
      await backend.write('Work/sub/deep.md', bytes('deep'));

      await backend.move('Work', 'Office');

      expect(await backend.exists('Work'), isFalse);
      expect(await backend.exists('Office/note.md'), isTrue);
      expect(utf8.decode(await backend.read('Office/sub/deep.md')), 'deep');
    });

    test('move on a missing source throws NotFoundException', () async {
      expect(backend.move('Nope', 'Other'),
          throwsA(isA<NotFoundException>()));
    });

    test('write creates parent directories', () async {
      await backend.write('a/b/c/deep.md', bytes('x'));
      expect(await backend.exists('a/b/c/deep.md'), isTrue);
      expect(await backend.exists('a/b'), isTrue);
    });

    test('overwrite replaces content', () async {
      await backend.write('f.md', bytes('old'));
      await backend.write('f.md', bytes('new'));
      expect(utf8.decode(await backend.read('f.md')), 'new');
    });

    test('list returns immediate children with types and size', () async {
      await backend.write('Work/note.md', bytes('n'));
      await backend.write('Work/sub/inner.md', bytes('i'));
      await backend.write('top.md', bytes('t'));

      final root = await backend.list('');
      expect(root.map((e) => e.name).toSet(), {'Work', 'top.md'});

      final work = root.firstWhere((e) => e.name == 'Work');
      expect(work.isDirectory, isTrue);
      expect(work.size, isNull);

      final top = root.firstWhere((e) => e.name == 'top.md');
      expect(top.isDirectory, isFalse);
      expect(top.size, 1);

      final workChildren = await backend.list('Work');
      expect(workChildren.map((e) => e.name).toSet(), {'note.md', 'sub'});
    });

    test('list reports posix-style relative paths', () async {
      await backend.write('Work/note.md', bytes('n'));
      final work = await backend.list('Work');
      expect(work.single.path, 'Work/note.md');
    });

    test('exists is false for missing, true for present', () async {
      expect(await backend.exists('nope.md'), isFalse);
      await backend.write('here.md', bytes('y'));
      expect(await backend.exists('here.md'), isTrue);
    });

    test('read missing throws NotFoundException', () {
      expect(() => backend.read('ghost.md'),
          throwsA(isA<NotFoundException>()));
    });

    test('read on a directory throws InvalidPathException', () async {
      await backend.write('dir/child.md', bytes('c'));
      expect(() => backend.read('dir'),
          throwsA(isA<InvalidPathException>()));
    });

    test('list on a missing directory throws NotFoundException', () {
      expect(() => backend.list('nodir'),
          throwsA(isA<NotFoundException>()));
    });

    test('delete removes a file', () async {
      await backend.write('x.md', bytes('x'));
      await backend.delete('x.md');
      expect(await backend.exists('x.md'), isFalse);
    });

    test('delete removes a directory recursively', () async {
      await backend.write('d/one.md', bytes('1'));
      await backend.write('d/two.md', bytes('2'));
      await backend.delete('d');
      expect(await backend.exists('d'), isFalse);
    });

    test('delete on a missing path is a no-op', () async {
      await backend.delete('not-there.md'); // must not throw
    });

    test('cannot delete the repository root', () {
      expect(() => backend.delete(''),
          throwsA(isA<InvalidPathException>()));
    });

    test('rejects parent-traversal paths', () {
      expect(() => backend.write('../escape.md', bytes('x')),
          throwsA(isA<InvalidPathException>()));
      expect(() => backend.read('../../etc/passwd'),
          throwsA(isA<InvalidPathException>()));
    });

    test('traversal attempt never writes outside the root', () async {
      try {
        await backend.write('../escape.md', bytes('x'));
      } catch (_) {
        // expected
      }
      final outside = File(p.join(tempDir.parent.path, 'escape.md'));
      expect(await outside.exists(), isFalse);
    });
  });
}
