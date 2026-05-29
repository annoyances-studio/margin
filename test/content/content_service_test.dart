// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:margin/margin.dart';

/// A backend that injects a phantom self-referential "." child into one folder
/// (as OneDrive placeholders did transiently), to prove the tree builder won't
/// recurse back into the root.
class _PhantomDotBackend implements StorageBackend {
  final MemoryBackend _inner;
  _PhantomDotBackend(this._inner);

  @override
  Future<List<StorageEntry>> list(String path) async {
    final entries = await _inner.list(path);
    if (path == 'Trap') {
      // A bogus entry whose path resolves to the root — the dangerous case.
      entries.add(const StorageEntry(path: '.', isDirectory: true));
    }
    return entries;
  }

  @override
  Future<bool> exists(String path) => _inner.exists(path);
  @override
  Future<Uint8List> read(String path) => _inner.read(path);
  @override
  Future<void> write(String path, Uint8List bytes) => _inner.write(path, bytes);
  @override
  Future<void> delete(String path) => _inner.delete(path);
}

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

  group('sidecar index', () {
    test('createNote writes a sidecar index mirroring the note', () async {
      await service.createNote('Work', 'meeting');

      expect(await backend.exists('Work/meeting.md.yaml'), isTrue);
      final index = await service.readNoteProperties('Work/meeting.md');
      expect(index.title, 'meeting');
    });

    test('saveNote keeps the index title/tags/updated in step', () async {
      final updated = DateTime.utc(2026, 5, 1, 12);
      await service.saveNote(
        'Work/note.md',
        Note(
          frontmatter: NoteFrontmatter(
            title: 'Edited',
            tags: const ['x', 'y'],
            updated: updated,
          ),
          body: 'body',
        ),
      );

      final index = await service.readNoteProperties('Work/note.md');
      expect(index.title, 'Edited');
      expect(index.tags, ['x', 'y']);
      expect(index.updated, updated);
    });

    test('saving a note preserves the device-local view in the sidecar',
        () async {
      await service.createNote('Work', 'meeting');
      await service.setNoteView('Work/meeting.md', 'preview');

      // A later content save must not clobber the view.
      await service.saveNote(
        'Work/meeting.md',
        Note(
          frontmatter: const NoteFrontmatter(title: 'meeting'),
          body: 'new body',
        ),
      );

      final index = await service.readNoteProperties('Work/meeting.md');
      expect(index.view, 'preview');
      expect(index.title, 'meeting');
    });

    test('setNoteView preserves the index fields', () async {
      await service.saveNote(
        'Work/n.md',
        Note(
          frontmatter: const NoteFrontmatter(title: 'Keep', tags: ['t']),
          body: 'b',
        ),
      );
      await service.setNoteView('Work/n.md', 'split');

      final index = await service.readNoteProperties('Work/n.md');
      expect(index.title, 'Keep');
      expect(index.tags, ['t']);
      expect(index.view, 'split');
    });

    test('deleteNote also removes the sidecar (no orphan)', () async {
      await service.createNote('Work', 'temp');
      expect(await backend.exists('Work/temp.md.yaml'), isTrue);

      await service.deleteNote('Work/temp.md');
      expect(await backend.exists('Work/temp.md.yaml'), isFalse);
    });

    test('renameFolder moves notes and their sidecars together', () async {
      await service.createNote('Work', 'meeting');
      await service.setNoteView('Work/meeting.md', 'preview');

      final newPath = await service.renameFolder('Work', 'Office');

      expect(await backend.exists('$newPath/meeting.md'), isTrue);
      expect(await backend.exists('$newPath/meeting.md.yaml'), isTrue);
      expect(await backend.exists('Work/meeting.md.yaml'), isFalse);
      // The moved sidecar still carries its index + view.
      final index = await service.readNoteProperties('$newPath/meeting.md');
      expect(index.title, 'meeting');
      expect(index.view, 'preview');
    });
  });

  test('a phantom "." child does not recurse into the root', () async {
    final inner = MemoryBackend();
    final svc = ContentService(_PhantomDotBackend(inner));
    await inner.write('Trap/properties.yaml', bytes('title: "Trap"'));
    await inner.write('Trap/note.md', bytes('n'));
    await inner.write('Other/properties.yaml', bytes('title: "Other"'));

    final root = await svc.tree(); // must terminate, not blow the stack
    final trap = root.folders.firstWhere((f) => f.name == 'Trap');
    // The phantom "." child is ignored: Trap shows its note, no sub-folders,
    // and certainly not a copy of the root.
    expect(trap.folders, isEmpty);
    expect(trap.notes.map((n) => n.name), ['note.md']);
    expect(root.folders.map((f) => f.name), ['Other', 'Trap']);
  });

  group('empty folders', () {
    // Creates a real empty directory (write a file, then delete it).
    Future<void> makeEmptyDir(String name) async {
      await backend.write('$name/_tmp', bytes('x'));
      await backend.delete('$name/_tmp');
    }

    test('tree hides an empty, unmarked leftover directory', () async {
      await backend.write('Work/properties.yaml', bytes('title: "Work"'));
      await backend.write('Work/note.md', bytes('n'));
      await makeEmptyDir('Leftover'); // no properties.yaml, no notes

      final root = await service.tree();
      expect(root.folders.map((f) => f.name), ['Work']); // Leftover hidden
    });

    test('tree keeps an empty folder that has properties.yaml', () async {
      await backend.write('Empty/properties.yaml', bytes('title: "Empty"'));
      final root = await service.tree();
      expect(root.folders.map((f) => f.name), ['Empty']);
    });

    test('tree keeps a foreign markdown folder without properties.yaml',
        () async {
      await backend.write('Foreign/note.md', bytes('n'));
      final root = await service.tree();
      expect(root.folders.single.name, 'Foreign');
      expect(root.folders.single.notes.single.name, 'note.md');
    });

    test('pruneEmptyFolders removes empty dirs, keeps marked and populated',
        () async {
      await backend.write('Work/properties.yaml', bytes('title: "Work"'));
      await backend.write('Work/note.md', bytes('n'));
      await backend.write('Marked/properties.yaml', bytes('title: "Marked"'));
      await makeEmptyDir('Leftover');
      await makeEmptyDir('Nested/Inner');

      final removed = await service.pruneEmptyFolders();

      expect(await backend.exists('Leftover'), isFalse);
      expect(await backend.exists('Nested'), isFalse); // whole empty subtree
      expect(await backend.exists('Marked/properties.yaml'), isTrue); // kept
      expect(await backend.exists('Work/note.md'), isTrue);
      expect(removed, greaterThanOrEqualTo(2));
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
