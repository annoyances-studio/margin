// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:margin/margin.dart';
import 'package:margin/src/ui/app_controller.dart';

void main() {
  late MemoryBackend backend;
  late AppController controller;

  setUp(() {
    backend = MemoryBackend();
    controller = AppController();
  });

  tearDown(() => controller.dispose());

  NoteNode? findNote(FolderNode root, String title) {
    for (final folder in root.folders) {
      for (final note in folder.notes) {
        if (note.title == title) return note;
      }
      final nested = findNote(folder, title);
      if (nested != null) return nested;
    }
    return null;
  }

  test('create opens a repository and loads an (empty) tree', () async {
    await controller.create(backend, 'My Notes');
    expect(controller.hasRepository, isTrue);
    expect(controller.repositoryName, 'My Notes');
    expect(controller.tree, isNotNull);
    expect(controller.tree!.isEmpty, isTrue);
  });

  test('create folder and note, then edit and save', () async {
    await controller.create(backend, 'My Notes');
    await controller.createFolder('Work');
    await controller.createNote('meeting', folderPath: 'Work');

    expect(controller.selectedNotePath, 'Work/meeting.md');
    expect(controller.currentNote!.frontmatter.title, 'meeting');

    controller.updateBody('# Hello\n\nbody');
    expect(controller.isDirty, isTrue);
    await controller.save();
    expect(controller.isDirty, isFalse);

    // Re-open with a fresh controller against the same in-memory backend.
    final reopened = AppController();
    addTearDown(reopened.dispose);
    await reopened.open(backend);
    final note = findNote(reopened.tree!, 'meeting')!;
    await reopened.selectNote(note);
    expect(reopened.currentNote!.body, '# Hello\n\nbody');
  });

  test('refuses to create a note at the root', () async {
    await controller.create(backend, 'My Notes');
    await controller.createNote('orphan', folderPath: '');
    expect(controller.error, isNotNull);
    expect(controller.selectedNotePath, isNull);
  });

  test('deleting the open note clears the selection', () async {
    await controller.create(backend, 'My Notes');
    await controller.createFolder('Work');
    await controller.createNote('temp', folderPath: 'Work');
    expect(controller.selectedNotePath, 'Work/temp.md');

    await controller.deleteNote('Work/temp.md');
    expect(controller.selectedNotePath, isNull);
    expect(await backend.exists('Work/temp.md'), isFalse);
  });

  test('deleting a folder removes it and clears a note open inside it',
      () async {
    await controller.create(backend, 'My Notes');
    await controller.createFolder('Work');
    await controller.createNote('inside', folderPath: 'Work');

    await controller.deleteFolder('Work');
    expect(controller.selectedNotePath, isNull);
    expect(await backend.exists('Work'), isFalse);
    expect(findNote(controller.tree!, 'inside'), isNull);
  });

  test('selectedNoteFolderColor reflects the open note\'s folder', () async {
    await controller.create(backend, 'My Notes');
    await controller.createFolder('Work');
    await controller.setFolderColor('Work', '#64B5F6');
    await controller.createNote('meeting', folderPath: 'Work');

    expect(controller.selectedNoteFolderColor, '#64B5F6');
  });

  test('memory-backed repository is not local and has no absolute path',
      () async {
    await controller.create(backend, 'My Notes');
    expect(controller.isLocalRepository, isFalse);
    expect(controller.localAbsolutePath('Work'), isNull);
  });

  test('renameFolder keeps the open note selected under its new path',
      () async {
    await controller.create(backend, 'My Notes');
    await controller.createFolder('Work');
    await controller.createNote('meeting', folderPath: 'Work');
    expect(controller.selectedNotePath, 'Work/meeting.md');

    await controller.renameFolder('Work', 'Job');

    expect(controller.selectedNotePath, 'Job/meeting.md');
    expect(findNote(controller.tree!, 'meeting')!.path, 'Job/meeting.md');
  });

  test('switching notes flushes a dirty buffer first (save-before-switch)',
      () async {
    await controller.create(backend, 'My Notes');
    await controller.createFolder('Work');
    await controller.createNote('first', folderPath: 'Work');
    await controller.createNote('second', folderPath: 'Work');

    // Select 'first', edit it, then switch to 'second' without saving.
    final first = findNote(controller.tree!, 'first')!;
    final second = findNote(controller.tree!, 'second')!;
    await controller.selectNote(first);
    controller.updateBody('edited first');
    await controller.selectNote(second);

    // The edit to 'first' must have been persisted by the switch.
    final content = ContentService(backend);
    final reloaded = await content.readNote('Work/first.md');
    expect(reloaded.body, 'edited first');
  });
}
