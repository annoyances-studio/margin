// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:margin/src/settings/settings_store.dart';
import 'package:margin/src/ui/app_controller.dart';

void main() {
  late Directory tempDir;
  late InMemorySettingsStore settings;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('margin_session_');
    settings = InMemorySettingsStore();
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('createPath remembers the repository path', () async {
    final controller = AppController(settings: settings);
    addTearDown(controller.dispose);

    await controller.createPath(tempDir.path, 'My Notes');
    expect(await settings.getLastFolioPath(), tempDir.path);
  });

  test('restoreLastFolio reopens the remembered repository', () async {
    final first = AppController(settings: settings);
    await first.createPath(tempDir.path, 'My Notes');
    first.dispose();

    final restored = AppController(settings: settings);
    addTearDown(restored.dispose);
    await restored.restoreLastFolio();

    expect(restored.hasFolio, isTrue);
    expect(restored.folioName, 'My Notes');
  });

  test('closing a repository forgets it', () async {
    final controller = AppController(settings: settings);
    addTearDown(controller.dispose);

    await controller.createPath(tempDir.path, 'My Notes');
    controller.closeFolio();
    // closeFolio persists asynchronously; allow the microtask to run.
    await Future<void>.delayed(Duration.zero);

    expect(await settings.getLastFolioPath(), isNull);
  });

  test('restore forgets a path that no longer exists', () async {
    await settings.setLastFolioPath('${tempDir.path}/gone'); // never created
    final controller = AppController(settings: settings);
    addTearDown(controller.dispose);

    await controller.restoreLastFolio();

    expect(controller.hasFolio, isFalse);
    expect(await settings.getLastFolioPath(), isNull);
  });

  test('restore reopens a remembered plain folder in browse mode', () async {
    // An existing folder with no properties.yaml is no longer discarded — it
    // reopens read-only in browse mode (same as the user opening it).
    await settings.setLastFolioPath(tempDir.path);
    final controller = AppController(settings: settings);
    addTearDown(controller.dispose);

    await controller.restoreLastFolio();

    expect(controller.hasFolio, isTrue);
    expect(controller.isBrowsing, isTrue);
    expect(await settings.getLastFolioPath(), tempDir.path);
  });

  test('reopens the last note when it still exists', () async {
    final first = AppController(settings: settings);
    await first.createPath(tempDir.path, 'My Notes');
    await first.createFolder('Work');
    await first.createNote('meeting', folderPath: 'Work');
    expect(await settings.getLastNotePath(), 'Work/meeting.md');
    first.dispose();

    final restored = AppController(settings: settings);
    addTearDown(restored.dispose);
    await restored.restoreLastFolio();

    expect(restored.selectedNotePath, 'Work/meeting.md');
  });

  test('always-on-top preference persists and reloads on start', () async {
    final first = AppController(settings: settings);
    await first.setAlwaysOnTop(true);
    expect(await settings.getAlwaysOnTop(), isTrue);
    first.dispose();

    final restored = AppController(settings: settings);
    addTearDown(restored.dispose);
    await restored.start();

    expect(restored.alwaysOnTop, isTrue);
  });

  test('signals isRestoring while reconnecting, then clears it', () async {
    final first = AppController(settings: settings);
    await first.createPath(tempDir.path, 'My Notes');
    first.dispose();

    final restored = AppController(settings: settings);
    addTearDown(restored.dispose);

    final seen = <bool>[];
    restored.addListener(() => seen.add(restored.isRestoring));

    expect(restored.isRestoring, isFalse); // idle before restore
    await restored.restoreLastFolio();

    expect(seen, contains(true)); // splash was signalled mid-restore
    expect(restored.isRestoring, isFalse); // cleared once done
    expect(restored.hasFolio, isTrue);
  });

  test('does not signal isRestoring when there is nothing to restore',
      () async {
    final controller = AppController(settings: settings); // no last Folio
    addTearDown(controller.dispose);

    final seen = <bool>[];
    controller.addListener(() => seen.add(controller.isRestoring));
    await controller.restoreLastFolio();

    expect(seen, isNot(contains(true)));
    expect(controller.isRestoring, isFalse);
  });

  test('shows no note when the last note is missing', () async {
    final first = AppController(settings: settings);
    await first.createPath(tempDir.path, 'My Notes');
    await first.createFolder('Work');
    await first.createNote('meeting', folderPath: 'Work');
    first.dispose();

    // Point lastNotePath at a note that does not exist.
    await settings.setLastNotePath('Work/ghost.md');

    final restored = AppController(settings: settings);
    addTearDown(restored.dispose);
    await restored.restoreLastFolio();

    expect(restored.hasFolio, isTrue);
    expect(restored.selectedNotePath, isNull);
  });
}
