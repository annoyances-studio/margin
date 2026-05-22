// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:margin/margin.dart';
import 'package:margin/src/ui/app_controller.dart';
import 'package:margin/src/ui/repository_screen.dart';
import 'package:margin/src/ui/widgets/markdown_preview.dart';

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

  testWidgets('defaults to split: both editor and preview are shown',
      (tester) async {
    final controller = await openWithNote(tester);
    await tester.pumpWidget(
      MaterialApp(home: RepositoryScreen(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(MarkdownPreview), findsOneWidget);
  });

  testWidgets('Code mode shows only the editor', (tester) async {
    final controller = await openWithNote(tester);
    await tester.pumpWidget(
      MaterialApp(home: RepositoryScreen(controller: controller)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.code));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(MarkdownPreview), findsNothing);
  });

  testWidgets('Preview mode shows only the rendered preview', (tester) async {
    final controller = await openWithNote(tester);
    await tester.pumpWidget(
      MaterialApp(home: RepositoryScreen(controller: controller)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pumpAndSettle();

    expect(find.byType(MarkdownPreview), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });
}
