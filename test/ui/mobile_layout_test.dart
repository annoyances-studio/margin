// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:margin/margin.dart';
import 'package:margin/src/ui/app_controller.dart';
import 'package:margin/src/ui/editor_view_mode.dart';
import 'package:margin/src/ui/folio_screen.dart';
import 'package:margin/src/ui/widgets/markdown_preview.dart';

import '../support/test_app.dart';

void main() {
  Future<AppController> openWithNote() async {
    final controller = AppController();
    addTearDown(controller.dispose);
    await controller.create(MemoryBackend(), 'My Notes');
    await controller.createFolder('Work');
    await controller.createNote('meeting', folderPath: 'Work');
    return controller;
  }

  /// A controller backed by a remote peer (clone-then-sync), so it [canSync].
  Future<AppController> openSyncedWithNote() async {
    final cacheDir = await Directory.systemTemp.createTemp('margin_mobsync_');
    addTearDown(() async {
      if (await cacheDir.exists()) await cacheDir.delete(recursive: true);
    });
    final remote = MemoryBackend();
    await Folio.create(remote, name: 'Remote');
    final controller = AppController(cacheRoot: () async => cacheDir);
    addTearDown(controller.dispose);
    await controller.openThroughCache(remote);
    await controller.createFolder('Work');
    await controller.createNote('meeting', folderPath: 'Work');
    await controller.pendingSync;
    return controller;
  }

  void useNarrowScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('phone layout: swipeable pages + bottom nav, no view control',
      (tester) async {
    useNarrowScreen(tester);
    final controller = await openWithNote();
    await tester.pumpWidget(
      localizedApp(FolioScreen(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PageView), findsOneWidget);
    // The desktop segmented view control is not used on phones.
    expect(find.byType(SegmentedButton<EditorViewMode>), findsNothing);
    // Bottom navigation for the three pages.
    expect(find.byTooltip('Folders'), findsOneWidget);
    expect(find.byTooltip('Editor'), findsOneWidget);
    expect(find.byTooltip('Preview'), findsOneWidget);
    // The editor page is shown initially.
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('Folders page: searching filters to matching notes',
      (tester) async {
    useNarrowScreen(tester);
    final controller = await openWithNote(); // Work/meeting.md
    await controller.createFolder('Personal');
    await controller.createNote('groceries', folderPath: 'Personal');
    await tester.pumpWidget(
      localizedApp(FolioScreen(controller: controller)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Folders'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('noteSearchField')), 'groc');
    await tester.pumpAndSettle();

    // The matching note appears as a result tile; the non-match is filtered out.
    expect(find.widgetWithText(ListTile, 'groceries'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'meeting'), findsNothing);
  });

  testWidgets('phone layout: the Folders page shows the tree', (tester) async {
    useNarrowScreen(tester);
    final controller = await openWithNote();
    await tester.pumpWidget(
      localizedApp(FolioScreen(controller: controller)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Folders'));
    await tester.pumpAndSettle();

    expect(find.text('Work'), findsOneWidget);
  });

  testWidgets('phone "+" creates a note in the current folder', (tester) async {
    useNarrowScreen(tester);
    final controller = await openWithNote(); // selects Work/meeting.md
    await tester.pumpWidget(
      localizedApp(FolioScreen(controller: controller)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('New note'));
    await tester.pumpAndSettle();

    // The note-name field is the dialog's (last) text field.
    await tester.enterText(find.byType(TextField).last, 'groceries');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(controller.selectedNotePath, 'Work/groceries.md');
  });

  testWidgets('phone layout: the Preview page renders Markdown', (tester) async {
    useNarrowScreen(tester);
    final controller = await openWithNote();
    controller.updateBody('# Hello world');
    await tester.pumpWidget(
      localizedApp(FolioScreen(controller: controller)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Preview'));
    await tester.pumpAndSettle();

    expect(find.byType(MarkdownPreview), findsOneWidget);
  });

  testWidgets('phone: a remote-backed Folio offers pull-to-refresh',
      (tester) async {
    useNarrowScreen(tester);
    // The clone-then-sync setup does real filesystem IO (temp-dir cache), which
    // only progresses under the test binding inside runAsync.
    late AppController controller;
    await tester.runAsync(() async {
      controller = await openSyncedWithNote();
    });

    await tester.pumpWidget(
      localizedApp(FolioScreen(controller: controller)),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Folders'));
    await tester.pump(const Duration(milliseconds: 300)); // page transition
    await tester.pump(const Duration(milliseconds: 300));

    // The Folders page is wrapped in a RefreshIndicator (pull down = Sync).
    // The pull actually triggering syncNow is covered at the controller level
    // in sync_ux_test; here we only assert the gesture surface is wired up.
    expect(find.byType(RefreshIndicator), findsWidgets);
  });

  testWidgets('phone: no pull-to-refresh for a local-only Folio',
      (tester) async {
    useNarrowScreen(tester);
    final controller = await openWithNote(); // local, cannot sync
    await tester.pumpWidget(
      localizedApp(FolioScreen(controller: controller)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Folders'));
    await tester.pumpAndSettle();

    expect(find.byType(RefreshIndicator), findsNothing);
  });
}
