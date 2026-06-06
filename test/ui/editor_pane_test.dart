// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:margin/margin.dart';
import 'package:margin/src/ui/app_controller.dart';
import 'package:margin/src/ui/folio_screen.dart';
import 'package:margin/src/ui/widgets/markdown_preview.dart';

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

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(MarkdownPreview), findsNothing);
  });

  testWidgets('Split mode shows editor and preview', (tester) async {
    final controller = await openWithNote(tester);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.vertical_split_outlined));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(MarkdownPreview), findsOneWidget);
  });

  testWidgets('Preview mode shows only the rendered preview', (tester) async {
    final controller = await openWithNote(tester);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pumpAndSettle();

    expect(find.byType(MarkdownPreview), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('title shows the repo name with tree shown, note path when hidden',
      (tester) async {
    final controller = await openWithNote(tester);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    expect(find.text('My Notes'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.menu_open));
    await tester.pumpAndSettle();
    expect(find.text('My Notes / Work / meeting.md'), findsOneWidget);
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
    // Copy is offered when a note is open.
    expect(find.text('Copy note'), findsOneWidget);
  });

  testWidgets('Copy note opens a sheet with the three formats', (tester) async {
    final controller = await openWithNote(tester);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy note'));
    await tester.pumpAndSettle();

    expect(find.text('Formatted (for Word, web)'), findsOneWidget);
    expect(find.text('Markdown source'), findsOneWidget);
    expect(find.text('Plain text'), findsOneWidget);
  });
}
