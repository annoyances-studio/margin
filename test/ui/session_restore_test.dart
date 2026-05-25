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
    expect(await settings.getLastRepositoryPath(), tempDir.path);
  });

  test('restoreLastRepository reopens the remembered repository', () async {
    final first = AppController(settings: settings);
    await first.createPath(tempDir.path, 'My Notes');
    first.dispose();

    final restored = AppController(settings: settings);
    addTearDown(restored.dispose);
    await restored.restoreLastRepository();

    expect(restored.hasRepository, isTrue);
    expect(restored.repositoryName, 'My Notes');
  });

  test('closing a repository forgets it', () async {
    final controller = AppController(settings: settings);
    addTearDown(controller.dispose);

    await controller.createPath(tempDir.path, 'My Notes');
    controller.closeRepository();
    // closeRepository persists asynchronously; allow the microtask to run.
    await Future<void>.delayed(Duration.zero);

    expect(await settings.getLastRepositoryPath(), isNull);
  });

  test('restore forgets a path that is no longer a valid repository', () async {
    await settings.setLastRepositoryPath(tempDir.path); // empty dir, no repo
    final controller = AppController(settings: settings);
    addTearDown(controller.dispose);

    await controller.restoreLastRepository();

    expect(controller.hasRepository, isFalse);
    expect(await settings.getLastRepositoryPath(), isNull);
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
    await restored.restoreLastRepository();

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
    await restored.restoreLastRepository();

    expect(restored.hasRepository, isTrue);
    expect(restored.selectedNotePath, isNull);
  });
}
