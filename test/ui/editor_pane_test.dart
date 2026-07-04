// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:margin/margin.dart';
import 'package:margin/src/ui/app_controller.dart';
import 'package:margin/src/ui/folio_screen.dart';
import 'package:margin/src/ui/widgets/markdown_preview.dart';
import 'package:margin/src/ui/widgets/note_editor.dart';
import 'package:margin/src/ui/widgets/note_editor_pane.dart';

import '../support/test_app.dart';

void main() {
  Future<AppController> openWithNote(WidgetTester tester) async {
    final controller = AppController();
    addTearDown(controller.dispose);
    await controller.create(MemoryBackend(), 'My Notes');
    await controller.createFolder('Work');
    await controller.createNote('meeting', folderPath: 'Work');
    controller.updateBody('# Hello world');
    return controller;
  }

  Widget app(AppController controller) =>
      localizedApp(FolioScreen(controller: controller));

  testWidgets('defaults to the inline editor (no preview)', (tester) async {
    final controller = await openWithNote(tester);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    expect(find.byType(NoteEditor), findsOneWidget);
    expect(find.byType(MarkdownPreview), findsNothing);
  });

  testWidgets('Split mode shows editor and preview', (tester) async {
    final controller = await openWithNote(tester);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.vertical_split_outlined));
    await tester.pumpAndSettle();

    expect(find.byType(NoteEditor), findsOneWidget);
    expect(find.byType(MarkdownPreview), findsOneWidget);
  });

  testWidgets('Preview mode shows only the rendered preview', (tester) async {
    final controller = await openWithNote(tester);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pumpAndSettle();

    expect(find.byType(MarkdownPreview), findsOneWidget);
    expect(find.byType(NoteEditor), findsNothing);
  });

  testWidgets('title shows the note breadcrumb whether the tree is shown or hidden',
      (tester) async {
    final controller = await openWithNote(tester);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    // Breadcrumb is present with the tree shown (so a note inside a collapsed
    // folder is still locatable)...
    expect(find.text('My Notes / Work / meeting.md'), findsOneWidget);

    // ...and remains when the tree is hidden.
    await tester.tap(find.byIcon(Icons.menu_open));
    await tester.pumpAndSettle();
    expect(find.text('My Notes / Work / meeting.md'), findsOneWidget);
  });

  testWidgets('preview is keyed by note (resets scroll) but not by body edits',
      (tester) async {
    Widget pane(String notePath, String body) => localizedApp(Scaffold(
          body: NoteEditorPane(
            notePath: notePath,
            body: body,
            onChanged: (_) {},
            mode: EditorViewMode.preview,
          ),
        ));

    await tester.pumpWidget(pane('a.md', 'one'));
    final keyA = tester.widget<MarkdownPreview>(find.byType(MarkdownPreview)).key;

    // Same note, edited body (e.g. split-view typing) -> same key (scroll kept).
    await tester.pumpWidget(pane('a.md', 'one edited'));
    final keyAEdited =
        tester.widget<MarkdownPreview>(find.byType(MarkdownPreview)).key;
    expect(keyAEdited, keyA);

    // Different note -> different key (fresh preview at the top).
    await tester.pumpWidget(pane('b.md', 'two'));
    final keyB = tester.widget<MarkdownPreview>(find.byType(MarkdownPreview)).key;
    expect(keyB, isNot(keyA));
  });

  testWidgets('overflow menu offers always-on-top, settings, and close',
      (tester) async {
    final controller = await openWithNote(tester);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();

    // On the desktop test host, the always-on-top toggle is offered.
    expect(find.text('Always on top'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Close Folio'), findsOneWidget);
    // Desktop-only: quit the whole app (vs. just closing the Folio).
    expect(find.text('Close Margin'), findsOneWidget);
    // Copy lives in the editor/preview context menu now, not the overflow.
    expect(find.text('Copy note'), findsNothing);
  });
}
