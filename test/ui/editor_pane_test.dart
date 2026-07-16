// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:margin/margin.dart';
import 'package:margin/src/ui/app_controller.dart';
import 'package:margin/src/ui/folio_screen.dart';
import 'package:margin/src/ui/widgets/find_bar.dart';
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

  testWidgets('Ctrl+F opens find, counts matches, and navigates', (tester) async {
    await tester.pumpWidget(localizedApp(Scaffold(
      body: NoteEditorPane(
        notePath: 'a.md',
        body: 'alpha beta alpha gamma alpha',
        onChanged: (_) {},
        mode: EditorViewMode.edit,
      ),
    )));
    await tester.pumpAndSettle();

    // The bar is hidden until invoked.
    expect(find.byType(FindBar), findsNothing);

    // Ctrl+F fires from a cold open (the pane autofocuses, so no click needed).
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(find.byType(FindBar), findsOneWidget);

    // Typing a query counts the hits and marks the first active.
    await tester.enterText(find.byKey(const Key('findField')), 'alpha');
    await tester.pumpAndSettle();
    expect(find.text('1 of 3'), findsOneWidget);

    // Next advances (and wraps at the end).
    await tester.tap(find.byTooltip('Next match (Enter)'));
    await tester.pumpAndSettle();
    expect(find.text('2 of 3'), findsOneWidget);

    // Close hides the bar again.
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(FindBar), findsNothing);
  });

  testWidgets('search keeps correct results across a view-mode change',
      (tester) async {
    final controller = await openWithNote(tester);
    controller.updateBody('alpha beta alpha');
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('findField')), 'alpha');
    await tester.pumpAndSettle();
    expect(find.text('1 of 2'), findsOneWidget);

    // Flip to Preview and back to Edit: the bar stays and the count stays
    // correct (no stale "No results" needing a re-type).
    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pumpAndSettle();
    expect(find.text('1 of 2'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.edit_note));
    await tester.pumpAndSettle();
    expect(find.byType(FindBar), findsOneWidget);
    expect(find.text('1 of 2'), findsOneWidget);
    expect(find.text('No results'), findsNothing);
  });

  testWidgets('find highlights the active match in the preview', (tester) async {
    final controller = await openWithNote(tester);
    controller.updateBody('alpha beta alpha gamma');
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    // Search from Preview mode.
    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('findField')), 'alpha');
    await tester.pumpAndSettle();

    // The active match renders as a highlighted Text with a background, and the
    // sentinel codepoints never leak into the rendered output.
    final highlighted = tester
        .widgetList<Text>(find.byType(Text))
        .where((t) => t.style?.backgroundColor != null && t.data == 'alpha');
    expect(highlighted, isNotEmpty);
    expect(find.textContaining('\u{E000}'), findsNothing);
    expect(find.text('1 of 2'), findsOneWidget);
  });

  testWidgets('find highlights a match inside an inline code span',
      (tester) async {
    final controller = await openWithNote(tester);
    controller.updateBody('see `the-gemma-file.md` for names');
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('findField')), 'gemma');
    await tester.pumpAndSettle();

    expect(find.text('1 of 1'), findsOneWidget);
    // The matched run inside the code span is painted with a background, and no
    // sentinel leaks into the rendered code.
    final rich = tester.widgetList<RichText>(find.byType(RichText));
    bool hasHighlightedGemma = false;
    for (final r in rich) {
      r.text.visitChildren((span) {
        if (span is TextSpan &&
            span.text == 'gemma' &&
            span.style?.backgroundColor != null) {
          hasHighlightedGemma = true;
        }
        return true;
      });
    }
    expect(hasHighlightedGemma, isTrue);
    expect(find.textContaining('\u{E000}'), findsNothing);
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
