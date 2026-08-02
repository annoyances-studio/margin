// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:margin/margin.dart';
import 'package:margin/src/settings/settings_store.dart';
import 'package:margin/src/ui/app_controller.dart';
import 'package:margin/src/ui/editor_view_mode.dart';

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

  test('back/forward navigate note history', () async {
    await controller.create(backend, 'My Notes');
    await controller.createFolder('F');
    await controller.createNote('a', folderPath: 'F');
    await controller.createNote('b', folderPath: 'F');
    await controller.createNote('c', folderPath: 'F');
    final a = findNote(controller.tree!, 'a')!;
    final b = findNote(controller.tree!, 'b')!;
    final c = findNote(controller.tree!, 'c')!;

    // Fresh Folio: nothing to go back to.
    expect(controller.canGoBack, isFalse);
    expect(controller.canGoForward, isFalse);

    await controller.selectNote(a);
    await controller.selectNote(b);
    await controller.selectNote(c);
    expect(controller.selectedNotePath, c.path);
    expect(controller.canGoBack, isTrue);
    expect(controller.canGoForward, isFalse);

    await controller.goBack(); // -> b
    expect(controller.selectedNotePath, b.path);
    expect(controller.canGoForward, isTrue);
    await controller.goBack(); // -> a
    expect(controller.selectedNotePath, a.path);

    await controller.goForward(); // -> b
    expect(controller.selectedNotePath, b.path);

    // Navigating fresh from here drops the forward history (c).
    await controller.selectNote(a);
    expect(controller.selectedNotePath, a.path);
    expect(controller.canGoForward, isFalse);
  });

  test('deleting a note drops it from history', () async {
    await controller.create(backend, 'My Notes');
    await controller.createFolder('F');
    await controller.createNote('a', folderPath: 'F');
    await controller.createNote('b', folderPath: 'F');
    final a = findNote(controller.tree!, 'a')!;
    final b = findNote(controller.tree!, 'b')!;

    await controller.selectNote(a);
    await controller.selectNote(b);
    await controller.deleteNote(a.path);

    // Walking all the way back must never land on the deleted note.
    while (controller.canGoBack) {
      await controller.goBack();
      expect(controller.selectedNotePath, isNot(a.path));
    }
  });

  test('create opens a repository and loads an (empty) tree', () async {
    await controller.create(backend, 'My Notes');
    expect(controller.hasFolio, isTrue);
    expect(controller.folioName, 'My Notes');
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
    expect(controller.isLocalFolio, isFalse);
    expect(controller.localAbsolutePath('Work'), isNull);
  });

  FolderNode folderNamed(FolderNode root, String name) =>
      root.folders.firstWhere((f) => f.name == name);

  test('openFolderNote creates README.md and opens it when absent', () async {
    await controller.create(backend, 'My Notes');
    await controller.createFolder('Lore');

    await controller.openFolderNote(folderNamed(controller.tree!, 'Lore'));

    expect(controller.selectedNotePath, 'Lore/README.md');
    expect(await backend.exists('Lore/README.md'), isTrue);
    // The folder is now flagged, and README isn't listed as a child note.
    final lore = folderNamed(controller.tree!, 'Lore');
    expect(lore.hasFolderNote, isTrue);
    expect(lore.notes.where((n) => n.name == 'README.md'), isEmpty);
  });

  test('openFolderNote opens an existing folder note without overwriting',
      () async {
    await controller.create(backend, 'My Notes');
    await controller.createFolder('Lore');
    await controller.createFolder('Work');
    await controller.createNote('other', folderPath: 'Work');

    await controller.openFolderNote(folderNamed(controller.tree!, 'Lore'));
    controller.updateBody('# Existing lore body');
    await controller.save();

    // Move to a different note, then re-open the (now existing) folder note:
    // its body is read from disk, not reset.
    await controller.selectNote(
        folderNamed(controller.tree!, 'Work').notes.single);
    await controller.openFolderNote(folderNamed(controller.tree!, 'Lore'));

    expect(controller.selectedNotePath, 'Lore/README.md');
    expect(controller.workingBody, contains('Existing lore body'));
  });

  test('word-wrap preference defaults on, persists, and reloads', () async {
    final settings = InMemorySettingsStore();
    final c1 = AppController(settings: settings);
    addTearDown(c1.dispose);
    expect(c1.wordWrap, isTrue); // default

    await c1.setWordWrap(false);
    expect(await settings.getWordWrap(), isFalse);

    final c2 = AppController(settings: settings);
    addTearDown(c2.dispose);
    await c2.start(); // _loadViewSettings reads it back
    expect(c2.wordWrap, isFalse);
  });

  test('attachToCurrentNote stores the file and inserts a link', () async {
    await controller.create(backend, 'My Notes');
    await controller.createFolder('Work');
    await controller.createNote('meeting', folderPath: 'Work');

    await controller.attachToCurrentNote(
      'pic.png',
      Uint8List.fromList(utf8.encode('imgdata')),
    );

    expect(controller.workingBody, contains('![](_attachments/pic.png)'));
    expect(await backend.exists('Work/_attachments/pic.png'), isTrue);
    expect(controller.isDirty, isFalse); // saved

    // The link was persisted to the note file.
    final reread = await ContentService(backend).readNote('Work/meeting.md');
    expect(reread.body, contains('_attachments/pic.png'));
  });

  test('attachToCurrentNote inserts a plain link for non-image files',
      () async {
    await controller.create(backend, 'My Notes');
    await controller.createFolder('Work');
    await controller.createNote('meeting', folderPath: 'Work');

    await controller.attachToCurrentNote(
      'report.pdf',
      Uint8List.fromList(utf8.encode('%PDF')),
    );

    // Non-image -> a labelled link, not an image embed.
    expect(controller.workingBody, contains('[report.pdf](_attachments/report.pdf)'));
    expect(controller.workingBody, isNot(contains('![]')));
  });

  group('view mode', () {
    Future<void> openNote() async {
      await controller.create(backend, 'My Notes');
      await controller.createFolder('Work');
      await controller.createNote('meeting', folderPath: 'Work');
    }

    test('note-specified policy remembers per-note view via the sidecar',
        () async {
      await openNote();
      // Default for new notes is editor.
      expect(controller.viewMode, EditorViewMode.edit);

      await controller.setViewMode(EditorViewMode.split);
      // Persisted to a sidecar (does not touch the note file).
      expect(await backend.exists('Work/meeting.md.yaml'), isTrue);

      // Reopen with a fresh controller -> the note reopens in split.
      final reopened = AppController();
      addTearDown(reopened.dispose);
      await reopened.open(backend);
      final node = findNote(reopened.tree!, 'meeting')!;
      await reopened.selectNote(node);
      expect(reopened.viewMode, EditorViewMode.split);
    });

    test('a fixed policy forces its mode regardless of the note', () async {
      await openNote();
      await controller.setViewMode(EditorViewMode.split); // sidecar says split

      await controller.setViewPolicy(DefaultViewPolicy.preview);
      expect(controller.viewMode, EditorViewMode.preview);
    });

    test('default-for-notes applies when a note has no stored view', () async {
      await controller.setDefaultNoteView(EditorViewMode.split);
      await openNote();
      expect(controller.viewMode, EditorViewMode.split);
    });
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
