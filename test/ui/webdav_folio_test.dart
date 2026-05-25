// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:margin/src/credentials/credential_store.dart';
import 'package:margin/src/settings/settings_store.dart';
import 'package:margin/src/ui/app_controller.dart';

const _url = 'https://dav.example.com/dav/Notes/';
const _credKey = 'webdav|$_url|me';
const _folioId = 'remote-id';

const _propsYaml = '''
schemaVersion: 1
id: "$_folioId"
name: "Remote Notes"
created: 2026-01-01T00:00:00.000Z
updated: 2026-01-01T00:00:00.000Z
appVersion: "test"
endpoints: []
''';

// A PROPFIND listing must include properties.yaml so the clone copies it into
// the cache (the new flow syncs, rather than reading the remote live).
const _multistatus = '''
<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/dav/Notes/</D:href>
    <D:propstat><D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat>
  </D:response>
  <D:response>
    <D:href>/dav/Notes/properties.yaml</D:href>
    <D:propstat><D:prop><D:resourcetype/><D:getcontentlength>120</D:getcontentlength></D:prop></D:propstat>
  </D:response>
</D:multistatus>''';

http.Client _fakeServer() => MockClient((req) async {
      if (req.method == 'GET' && req.url.path.endsWith('/properties.yaml')) {
        return http.Response(_propsYaml, 200);
      }
      if (req.method == 'PROPFIND') return http.Response(_multistatus, 207);
      return http.Response('', 404);
    });

void main() {
  late Directory cacheDir;
  setUp(() async {
    cacheDir = await Directory.systemTemp.createTemp('margin_cache_');
  });
  tearDown(() async {
    if (await cacheDir.exists()) await cacheDir.delete(recursive: true);
  });

  AppController controllerWith({
    required SettingsStore settings,
    required CredentialStore credentials,
    http.Client Function()? httpClientFactory,
  }) =>
      AppController(
        settings: settings,
        credentials: credentials,
        httpClientFactory: httpClientFactory ?? _fakeServer,
        cacheRoot: () async => cacheDir,
      );

  test('openWebDav clones into the cache and adopts it as a local Folio',
      () async {
    final settings = InMemorySettingsStore();
    final credentials = InMemoryCredentialStore();
    final controller =
        controllerWith(settings: settings, credentials: credentials);
    addTearDown(controller.dispose);

    await controller.openWebDav(_url, 'me', 'pw');

    expect(controller.hasFolio, isTrue);
    expect(controller.folioName, 'Remote Notes');
    // Adopted the local cache (so attachments/notes have real paths), with a
    // remote peer available to sync back.
    expect(controller.isLocalFolio, isTrue);
    expect(controller.canSync, isTrue);
    // The cache was populated under <cacheRoot>/<id>/.
    expect(
      await File('${cacheDir.path}/$_folioId/properties.yaml').exists(),
      isTrue,
    );
    // Descriptor persisted; password in the keystore, not in settings.
    expect(await settings.getLastFolioType(), 'webdav');
    expect(await settings.getLastFolioPath(), _url);
    expect(await settings.getLastWebDavUser(), 'me');
    expect(await credentials.read(_credKey), 'pw');
  });

  test('restoreLastFolio reconnects and re-clones a remembered WebDAV Folio',
      () async {
    final settings = InMemorySettingsStore();
    final credentials = InMemoryCredentialStore();
    await settings.setLastFolioType('webdav');
    await settings.setLastFolioPath(_url);
    await settings.setLastWebDavUser('me');
    await credentials.write(_credKey, 'pw');

    final controller =
        controllerWith(settings: settings, credentials: credentials);
    addTearDown(controller.dispose);

    await controller.restoreLastFolio();

    expect(controller.hasFolio, isTrue);
    expect(controller.folioName, 'Remote Notes');
    expect(controller.canSync, isTrue);
  });

  test('a bad URL surfaces an error instead of failing silently', () async {
    final controller = controllerWith(
      settings: InMemorySettingsStore(),
      credentials: InMemoryCredentialStore(),
      httpClientFactory: () => MockClient((_) async => http.Response('', 404)),
    );
    addTearDown(controller.dispose);

    await controller.openWebDav('http://exa mple/bad', 'me', 'pw');

    expect(controller.hasFolio, isFalse);
    expect(controller.error, isNotNull);
  });

  test('restore does not reconnect when the password is missing', () async {
    final settings = InMemorySettingsStore();
    await settings.setLastFolioType('webdav');
    await settings.setLastFolioPath(_url);
    await settings.setLastWebDavUser('me');

    final controller = controllerWith(
      settings: settings,
      credentials: InMemoryCredentialStore(),
    );
    addTearDown(controller.dispose);

    await controller.restoreLastFolio();

    expect(controller.hasFolio, isFalse);
  });
}
