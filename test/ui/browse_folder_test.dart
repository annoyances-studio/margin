// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:margin/src/content/tree_node.dart';
import 'package:margin/src/storage/memory_backend.dart';
import 'package:margin/src/ui/app_controller.dart';
import 'package:margin/src/ui/editor_view_mode.dart';

/// Recursively lists every file under [dir], repo-relative with '/' separators.
Future<Set<String>> _files(Directory dir) async {
  final out = <String>{};
  await for (final e in dir.list(recursive: true)) {
    if (e is File) {
      out.add(e.path.substring(dir.path.length + 1).replaceAll(r'\', '/'));
    }
  }
  return out;
}

void main() {
  late Directory temp;
  late AppController controller;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('margin_browse_test');
    controller = AppController();
  });

  tearDown(() async {
    controller.dispose();
    await temp.delete(recursive: true);
  });

  Future<void> write(String relPath, String content) async {
    final file = File('${temp.path}/$relPath');
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
  }

  test('a plain folder (no properties.yaml) opens read-only in browse mode',
      () async {
    await write('overview.md', '# Overview');
    await write('Chapters/one.md', '# One');

    await controller.openPath(temp.path);

    expect(controller.hasFolio, isTrue);
    expect(controller.isBrowsing, isTrue);
    expect(controller.error, isNull);
    // Root note shows (browse relaxes the no-root-notes rule).
    expect(controller.tree!.notes.map((n) => n.name), contains('overview.md'));
  });

  test('a managed Folio still opens normally (not browsing)', () async {
    await controller.createPath(temp.path, 'My Notes');
    controller.closeFolio();

    await controller.openPath(temp.path);
    expect(controller.hasFolio, isTrue);
    expect(controller.isBrowsing, isFalse);
  });

  test('browse mode opens notes in preview by default', () async {
    await write('overview.md', '# Overview');
    await controller.openPath(temp.path);
    await controller.selectNote(
        controller.tree!.notes.firstWhere((n) => n.name == 'overview.md'));
    expect(controller.viewMode, EditorViewMode.preview);
  });

  test('opening a browsed folder lands on its overview (CLAUDE.md/README.md)',
      () async {
    await write('CLAUDE.md', '# Project');
    await write('README.md', '# Readme');
    await write('Chapters/one.md', '# One');
    await controller.openPath(temp.path);

    // CLAUDE.md wins over README.md as the overview.
    expect(controller.selectedNotePath, 'CLAUDE.md');
  });

  test('a relative .md link navigates to the sibling note in-app', () async {
    await write('Chapters/one.md', '# One\n\nSee [two](two.md) and [up](../top.md).');
    await write('Chapters/two.md', '# Two');
    await write('top.md', '# Top');
    await controller.openPath(temp.path);

    NoteNode find(String name) {
      NoteNode? hit;
      void walk(FolderNode f) {
        for (final n in f.notes) {
          if (n.name == name) hit = n;
        }
        f.folders.forEach(walk);
      }

      walk(controller.tree!);
      return hit!;
    }

    await controller.selectNote(find('one.md'));

    // Sibling link (same folder).
    await controller.openLink('two.md');
    expect(controller.selectedNotePath, 'Chapters/two.md');

    // Parent-relative link from two.md back up to the root note.
    await controller.openLink('../top.md');
    expect(controller.selectedNotePath, 'top.md');
  });

  test('backlinks lists the notes that link to the open note', () async {
    await write('Chapters/one.md', '# One\n\nSee [hero](../people/hero.md).');
    await write('Chapters/two.md', '# Two\n\nAlso [hero](../people/hero.md).');
    await write('people/hero.md', '# Hero');
    await write('people/other.md', '# Other'); // links to nothing
    await controller.openPath(temp.path);

    final back = await controller.backlinksFor('people/hero.md');
    expect(back.map((n) => n.path).toSet(),
        {'Chapters/one.md', 'Chapters/two.md'});

    // A note nobody references has no backlinks.
    expect(await controller.backlinksFor('people/other.md'), isEmpty);
  });

  test('deep (full-text) search matches note body content in browse mode',
      () async {
    await write('a.md', '# Alpha\n\nThe harbor city of Carsonne is busy.');
    await write('b.md', '# Beta\n\nMountains and rivers.');
    await controller.openPath(temp.path);

    await controller.setSearchQuery('harbor city');
    expect(controller.searchResults.map((n) => n.name), ['a.md']);
  });

  test('refreshTree picks up files added on disk after open', () async {
    await write('Chapters/one.md', '# One');
    await controller.openPath(temp.path);
    expect(controller.tree!.folders.expand((f) => f.notes).map((n) => n.name),
        ['one.md']);

    // Claude adds a file while the folder is open.
    await write('Chapters/two.md', '# Two');
    await controller.refreshTree();

    expect(
      controller.tree!.folders
          .expand((f) => f.notes)
          .map((n) => n.name)
          .toSet(),
      {'one.md', 'two.md'},
    );
  });

  test('refreshTree reloads the open note\'s body from disk', () async {
    await write('a.md', '# A\n\noriginal');
    await controller.openPath(temp.path);
    await controller.selectNote(
        controller.tree!.notes.firstWhere((n) => n.name == 'a.md'));
    expect(controller.workingBody, contains('original'));

    await write('a.md', '# A\n\nrewritten by Claude');
    await controller.refreshTree();
    expect(controller.workingBody, contains('rewritten by Claude'));
  });

  test('openRemoteBrowse opens a remote plain folder read-only', () async {
    // A remote backend (stand-in for WebDAV/OneDrive) with plain notes, no
    // properties.yaml — the "shared cloud folder" case.
    final remote = MemoryBackend();
    Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));
    await remote.write('README.md', b('# Shared Project'));
    await remote.write('Chapters/one.md', b('# One'));

    await controller.openRemoteBrowse(remote, name: 'Shared');

    expect(controller.isBrowsing, isTrue);
    expect(controller.canSync, isFalse); // direct read, no sync peer
    expect(controller.folioName, 'Shared');
    // Root README shows (browse) and the subfolder note is reachable.
    expect(controller.tree!.notes.map((n) => n.name), contains('README.md'));
    // Lands on the overview.
    expect(controller.selectedNotePath, 'README.md');
    // Read-only: save is a no-op.
    controller.updateBody('should not persist');
    await controller.save();
    expect(String.fromCharCodes(await remote.read('README.md')),
        '# Shared Project');
  });

  test('browse mode writes nothing to the folder (no sidecars/properties)',
      () async {
    await write('overview.md', '# Overview\n\nbody');
    final before = await _files(temp);

    await controller.openPath(temp.path);
    // Open a note and toggle its view — both no-ops on disk in browse mode.
    final note = controller.tree!.notes.firstWhere((n) => n.name == 'overview.md');
    await controller.selectNote(note);
    await controller.setViewMode(EditorViewMode.preview);
    await controller.save(); // guarded no-op

    final after = await _files(temp);
    expect(after, equals(before), reason: 'browse mode must not write anything');
  });
}
