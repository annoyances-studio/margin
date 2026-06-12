// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:margin/src/settings/recent_folios.dart';
import 'package:margin/src/settings/settings_store.dart';
import 'package:margin/src/ui/app_controller.dart';

void main() {
  late Directory temp;
  late InMemorySettingsStore settings;
  late AppController controller;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('margin_recent_test');
    settings = InMemorySettingsStore();
    controller = AppController(settings: settings);
  });

  tearDown(() async {
    controller.dispose();
    await temp.delete(recursive: true);
  });

  test('creating and opening a local Folio records a recent entry', () async {
    await controller.createPath(temp.path, 'My Notes');
    expect(controller.hasFolio, isTrue);
    expect(controller.recentFolios, hasLength(1));
    final recent = controller.recentFolios.single;
    expect(recent.type, 'local');
    expect(recent.location, temp.path);
    expect(recent.name, 'My Notes');
    // Persisted, not just in memory.
    expect(decodeRecentFolios(await settings.getRecentFolios()), hasLength(1));
  });

  test('record: false keeps the Folio out of the recents (device notes)',
      () async {
    await controller.createPath(temp.path, 'Device Notes', record: false);
    expect(controller.hasFolio, isTrue);
    expect(controller.recentFolios, isEmpty);
  });

  test('recents survive an explicit close (unlike the last-Folio fields)',
      () async {
    await controller.createPath(temp.path, 'My Notes');
    controller.closeFolio();
    expect(controller.hasFolio, isFalse);
    expect(await settings.getLastFolioPath(), isNull);
    expect(controller.recentFolios, hasLength(1));
  });

  test('removeRecentFolio forgets the entry and persists that', () async {
    await controller.createPath(temp.path, 'My Notes');
    controller.removeRecentFolio(controller.recentFolios.single);
    expect(controller.recentFolios, isEmpty);
    expect(decodeRecentFolios(await settings.getRecentFolios()), isEmpty);
  });

  test('opening a recent whose folder is gone reports it and keeps the entry',
      () async {
    await controller.createPath(temp.path, 'My Notes');
    controller.closeFolio();
    final missing = Directory('${temp.path}_gone');
    final entry = RecentFolio(
        type: 'local', location: missing.path, name: 'Gone');
    await controller.openRecentFolio(entry);
    expect(controller.hasFolio, isFalse);
    expect(controller.error, contains('missing'));
  });

  test('a recent webdav entry without a saved password asks to reconnect',
      () async {
    const entry = RecentFolio(
      type: 'webdav',
      location: 'https://dav.example.com/notes/',
      name: 'Work',
      user: 'dan',
    );
    await controller.openRecentFolio(entry);
    expect(controller.hasFolio, isFalse);
    expect(controller.error, contains('connect to WebDAV again'));
  });

  test('opening a recent local Folio reopens it and refreshes the entry',
      () async {
    await controller.createPath(temp.path, 'My Notes');
    controller.closeFolio();
    await controller.openRecentFolio(controller.recentFolios.single);
    expect(controller.hasFolio, isTrue);
    expect(controller.folioName, 'My Notes');
    expect(controller.recentFolios, hasLength(1));
  });

  test('opening a recent shows the restoring splash while it works', () async {
    await controller.createPath(temp.path, 'My Notes');
    controller.closeFolio();

    final seen = <bool>[];
    controller.addListener(() => seen.add(controller.isRestoring));
    await controller.openRecentFolio(controller.recentFolios.single);

    expect(seen, contains(true)); // the splash was up during the open...
    expect(controller.isRestoring, isFalse); // ...and cleared after
    expect(controller.hasFolio, isTrue);
  });

  test('a fresh controller sees the persisted recents after start()', () async {
    await controller.createPath(temp.path, 'My Notes');
    controller.closeFolio();

    final fresh = AppController(settings: settings);
    addTearDown(fresh.dispose);
    await fresh.start();
    expect(fresh.recentFolios, hasLength(1));
    expect(fresh.recentFolios.single.name, 'My Notes');
  });
}
