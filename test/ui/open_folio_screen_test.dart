// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:margin/src/settings/recent_folios.dart';
import 'package:margin/src/settings/settings_store.dart';
import 'package:margin/src/ui/app_controller.dart';
import 'package:margin/src/ui/open_folio_screen.dart';

import '../support/test_app.dart';

void main() {
  late InMemorySettingsStore settings;
  late AppController controller;

  setUp(() {
    settings = InMemorySettingsStore();
    controller = AppController(settings: settings);
  });

  tearDown(() => controller.dispose());

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(localizedApp(OpenFolioScreen(controller: controller)));
    await tester.pumpAndSettle();
  }

  testWidgets('device-notes button is primary; options start folded',
      (tester) async {
    await pumpScreen(tester);

    expect(find.text("Open this device's notes"), findsOneWidget);
    expect(find.text('Open a Folio'), findsOneWidget);
    // Folded: no backend choices visible yet.
    expect(find.text('Connect to WebDAV'), findsNothing);
    expect(find.text('Open an existing Folio'), findsNothing);
  });

  testWidgets('tapping "Open a Folio" unfolds and refolds the options',
      (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Open a Folio'));
    await tester.pumpAndSettle();
    expect(find.text('Connect to WebDAV'), findsOneWidget);
    expect(find.text('Open an existing Folio'), findsOneWidget);
    expect(find.text('Create a Folio in the local file system'), findsOneWidget);

    await tester.tap(find.text('Open a Folio'));
    await tester.pumpAndSettle();
    expect(find.text('Connect to WebDAV'), findsNothing);
  });

  testWidgets('shows a recent Folio with name and location', (tester) async {
    await settings.setRecentFolios(encodeRecentFolios([
      const RecentFolio(
        type: 'webdav',
        location: 'https://dav.example.com/notes/',
        name: 'Work',
        user: 'dan',
      ),
    ]));
    await controller.start();
    await pumpScreen(tester);

    expect(find.text('Recent'), findsOneWidget);
    expect(find.text('Work'), findsOneWidget);
    expect(find.text('https://dav.example.com/notes/'), findsOneWidget);
  });

  testWidgets('the X removes a recent entry', (tester) async {
    await settings.setRecentFolios(encodeRecentFolios([
      const RecentFolio(type: 'local', location: 'C:/notes', name: 'Notes'),
    ]));
    await controller.start();
    await pumpScreen(tester);
    expect(find.text('Notes'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('Notes'), findsNothing);
    expect(find.text('Recent'), findsNothing);
  });

  testWidgets('no Recent section when there are no recents', (tester) async {
    await pumpScreen(tester);
    expect(find.text('Recent'), findsNothing);
  });
}
