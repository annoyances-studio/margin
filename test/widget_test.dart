// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:margin/margin.dart';
import 'package:margin/src/ui/app_controller.dart';
import 'package:margin/src/ui/margin_app.dart';
import 'package:margin/src/ui/repository_screen.dart';

void main() {
  testWidgets('landing screen offers open and create', (tester) async {
    await tester.pumpWidget(const MarginApp());
    await tester.pumpAndSettle();

    expect(find.text('Margin'), findsOneWidget);
    expect(find.text('Open a notes folder'), findsOneWidget);
    expect(find.text('Create a new notes folder'), findsOneWidget);
  });

  testWidgets('repository screen renders the tree and a note', (tester) async {
    final backend = MemoryBackend();
    final controller = AppController();
    addTearDown(controller.dispose);

    await controller.create(backend, 'My Notes');
    await controller.createFolder('Work');
    await controller.createNote('meeting', folderPath: 'Work');

    await tester.pumpWidget(
      MaterialApp(home: RepositoryScreen(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('My Notes'), findsOneWidget); // app bar title
    expect(find.text('Work'), findsOneWidget); // folder in tree
    expect(find.text('meeting'), findsOneWidget); // note in tree
  });
}
