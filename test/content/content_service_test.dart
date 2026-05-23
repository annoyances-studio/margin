// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:margin/margin.dart';

/// A non-trivial codec used to prove the [ContentCodec] seam is actually
/// applied: stored bytes are XOR-masked, so on-disk content differs from the
/// plaintext while reads still return the original.
class _XorCodec implements ContentCodec {
  final int mask;
  const _XorCodec(this.mask);

  Uint8List _xor(Uint8List input) =>
      Uint8List.fromList([for (final b in input) b ^ mask]);

  @override
  Uint8List encode(Uint8List plain) => _xor(plain);

  @override
  Uint8List decode(Uint8List stored) => _xor(stored);
}

void main() {
  late Directory tempDir;
  late LocalFolderBackend backend;
  late ContentService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('margin_content_test_');
    backend = LocalFolderBackend(tempDir.path);
    service = ContentService(backend);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

  group('tree', () {
    test('builds folders and notes, excluding special entries', () async {
      // Folders (each marked by a properties.yaml), notes, and entries that
      // must be excluded from the tree.
      await backend.write('Work/properties.yaml', bytes('title: "Work"'));
      await backend.write('Work/meeting.md', bytes('m'));
      await backend.write('Work/q2.md', bytes('q'));
      await backend.write('Work/_attachments/diagram.png', bytes('img'));
      await backend.write('Personal/properties.yaml', bytes('title: "Personal"'));
      await backend.write('Personal/ideas.md', bytes('i'));
      await backend.write('properties.yaml', bytes('root props'));
      await backend.write('stray-at-root.md', bytes('should be ignored'));
      await backend.write('Work/notes.txt', bytes('not a markdown note'));

      final root = await service.tree();

      // Root shows only folders (no stray .md, no properties.yaml).
      expect(root.path, '');
      expect(root.notes, isEmpty);
      expect(root.folders.map((f) => f.name), ['Personal', 'Work']);

      final work = root.folders.firstWhere((f) => f.name == 'Work');
      // _attachments and the .txt are excluded; notes sorted by name.
      expect(work.folders, isEmpty);
      expect(work.notes.map((n) => n.name), ['meeting.md', 'q2.md']);
      expect(work.notes.first.path, 'Work/meeting.md');
      expect(work.notes.first.title, 'meeting');
    });

    test('nests subfolders', () async {
      await backend.write('A/properties.yaml', bytes('title: "A"'));
      await backend.write('A/B/properties.yaml', bytes('title: "B"'));
      await backend.write('A/B/deep.md', bytes('d'));

      final root = await service.tree();
      final a = root.folders.single;
      expect(a.name, 'A');
      final b = a.folders.single;
      expect(b.name, 'B');
      expect(b.notes.single.name, 'deep.md');
    });
  });

  group('notes', () {
    test('createNote writes a note with a default title from the file name',
        () async {
      final node = await service.createNote('Work', 'meeting');
      expect(node.path, 'Work/meeting.md');
      expect(node.name, 'meeting.md');

      final note = await service.readNote('Work/meeting.md');
      expect(note.frontmatter.title, 'meeting');
    });

    test('createNote refuses the repository root', () {
      expect(
        () => service.createNote('', 'orphan'),
        throwsA(isA<ContentException>()),
      );
    });

    test('createNote refuses a duplicate', () async {
      await service.createNote('Work', 'dup');
      expect(
        () => service.createNote('Work', 'dup'),
        throwsA(isA<ContentException>()),
      );
    });

    test('save then read round-trips a note', () async {
      final note = Note(
        frontmatter: const NoteFrontmatter(title: 'Hello', tags: ['x']),
        body: '# Hi\n\nbody',
      );
      await service.saveNote('Folder/note.md', note);

      final read = await service.readNote('Folder/note.md');
      expect(read.frontmatter.title, 'Hello');
      expect(read.frontmatter.tags, ['x']);
      expect(read.body, '# Hi\n\nbody');
    });

    test('deleteNote removes the file', () async {
      await service.createNote('Work', 'temp');
      await service.deleteNote('Work/temp.md');
      expect(await backend.exists('Work/temp.md'), isFalse);
    });
  });

  group('folders', () {
    test('createFolder writes properties and is readable', () async {
      await service.createFolder('', 'Project X');
      final props = await service.readFolderProperties('Project X');
      expect(props.title, 'Project X');
    });

    test('createFolder refuses a duplicate', () async {
      await service.createFolder('', 'Dup');
      expect(
        () => service.createFolder('', 'Dup'),
        throwsA(isA<ContentException>()),
      );
    });

    test('setFolderColor persists and surfaces in the tree', () async {
      await service.createFolder('', 'Work');
      await service.setFolderColor('Work', '#64B5F6');

      expect((await service.readFolderProperties('Work')).color, '#64B5F6');

      final root = await service.tree();
      expect(root.folders.single.color, '#64B5F6');
    });

    test('setFolderColor with null clears the color', () async {
      await service.createFolder('', 'Work');
      await service.setFolderColor('Work', '#64B5F6');
      await service.setFolderColor('Work', null);

      expect((await service.readFolderProperties('Work')).color, isNull);
    });

    test('renameFolder moves contents and updates the title', () async {
      await service.createFolder('', 'Work');
      await service.createNote('Work', 'meeting');
      await service.createFolder('Work', 'Sub');
      await service.createNote('Work/Sub', 'deep');

      final newPath = await service.renameFolder('Work', 'Job');
      expect(newPath, 'Job');

      expect(await backend.exists('Work'), isFalse);
      expect(await backend.exists('Job/meeting.md'), isTrue);
      expect(await backend.exists('Job/Sub/deep.md'), isTrue);
      expect((await service.readFolderProperties('Job')).title, 'Job');
    });

    test('renameFolder refuses an existing sibling name', () async {
      await service.createFolder('', 'A');
      await service.createFolder('', 'B');
      expect(
        () => service.renameFolder('A', 'B'),
        throwsA(isA<ContentException>()),
      );
    });

    test('renameFolder supports a case-only change', () async {
      await service.createFolder('', 'LEvel');
      await service.createNote('LEvel', 'note');

      final newPath = await service.renameFolder('LEvel', 'Level');
      expect(newPath, 'Level');
      expect(await backend.exists('Level/note.md'), isTrue);

      // The on-disk casing actually changed.
      final root = await service.tree();
      expect(root.folders.single.name, 'Level');
    });
  });

  group('attachments', () {
    test('addAttachment stores under _attachments and returns a link',
        () async {
      await service.createFolder('', 'Work');
      final link = await service.addAttachment('Work', 'pic.png', bytes('img'));

      expect(link, '_attachments/pic.png');
      expect(await backend.exists('Work/_attachments/pic.png'), isTrue);
    });

    test('addAttachment de-duplicates a repeated name', () async {
      await service.createFolder('', 'Work');
      await service.addAttachment('Work', 'pic.png', bytes('a'));
      final second = await service.addAttachment('Work', 'pic.png', bytes('b'));

      expect(second, isNot('_attachments/pic.png'));
      expect(second, startsWith('_attachments/pic-'));
    });

    test('addAttachment replaces spaces but keeps the extension', () async {
      await service.createFolder('', 'Work');
      final link =
          await service.addAttachment('Work', 'my photo.png', bytes('x'));
      expect(link, '_attachments/my_photo.png');
    });

    test('addAttachment preserves non-ASCII (e.g. Japanese) names', () async {
      await service.createFolder('', 'Work');
      final link =
          await service.addAttachment('Work', 'スクリーンショット.png', bytes('x'));
      expect(link, '_attachments/スクリーンショット.png');
      expect(await backend.exists('Work/_attachments/スクリーンショット.png'), isTrue);
    });

    test('_attachments is excluded from the tree', () async {
      await service.createFolder('', 'Work');
      await service.addAttachment('Work', 'pic.png', bytes('img'));

      final root = await service.tree();
      final work = root.folders.single;
      expect(work.folders, isEmpty); // _attachments not shown as a folder
    });
  });

  group('codec seam', () {
    test('note content is encoded on disk and decoded on read', () async {
      final encrypted = ContentService(backend, codec: const _XorCodec(0x5a));
      final note = Note(
        frontmatter: const NoteFrontmatter(title: 'Secret'),
        body: 'classified',
      );
      await encrypted.saveNote('Vault/secret.md', note);

      // Raw bytes on disk must NOT contain the plaintext.
      final raw = utf8.decode(await backend.read('Vault/secret.md'),
          allowMalformed: true);
      expect(raw.contains('classified'), isFalse);

      // Reading back through the same codec restores the plaintext.
      final read = await encrypted.readNote('Vault/secret.md');
      expect(read.frontmatter.title, 'Secret');
      expect(read.body, 'classified');
    });
  });
}
