// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:margin/margin.dart';
import 'package:margin/src/ui/app_controller.dart';
import 'package:margin/src/ui/margin_app.dart';
import 'package:margin/src/ui/folio_screen.dart';

import 'support/test_app.dart';

void main() {
  testWidgets('landing screen offers device notes and the Folio options',
      (tester) async {
    await tester.pumpWidget(const MarginApp());
    await tester.pumpAndSettle();

    expect(find.text('Margin•'), findsOneWidget);
    expect(find.text("Open this device's notes"), findsOneWidget);
    expect(find.text('Open a Folio'), findsOneWidget);

    // Unfolding "Open a Folio" reveals the open/create/connect choices.
    await tester.tap(find.text('Open a Folio'));
    await tester.pumpAndSettle();
    expect(find.text('Open an existing Folio'), findsOneWidget);
    expect(find.text('Create a Folio in the local file system'), findsOneWidget);
  });

  testWidgets('landing screen opens the WebDAV connect form', (tester) async {
    await tester.pumpWidget(const MarginApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open a Folio'));
    await tester.pumpAndSettle();

    expect(find.text('Connect to WebDAV'), findsOneWidget);
    await tester.tap(find.text('Connect to WebDAV'));
    await tester.pumpAndSettle();

    // The form prompts for the three connection fields.
    expect(find.text('Server URL'), findsOneWidget);
    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
  });

  testWidgets('repository screen renders the tree and a note', (tester) async {
    final backend = MemoryBackend();
    final controller = AppController();
    addTearDown(controller.dispose);

    await controller.create(backend, 'My Notes');
    await controller.createFolder('Work');
    await controller.createNote('meeting', folderPath: 'Work');

    await tester.pumpWidget(
      localizedApp(FolioScreen(controller: controller)),
    );
    await tester.pumpAndSettle();

    // The new note is auto-selected. The full literal path shows in the status
    // bar; the tree shows the folder and the note (the title-bar breadcrumb is a
    // Text.rich, which find.text does not match).
    expect(find.text('My Notes / Work / meeting.md'), findsOneWidget);
    expect(find.text('Work'), findsOneWidget); // folder in tree
    expect(find.text('meeting'), findsOneWidget); // note in tree
  });
}
