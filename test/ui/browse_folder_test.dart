// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:margin/src/content/tree_node.dart';
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
