// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:margin/src/credentials/credential_store.dart';
import 'package:margin/src/settings/settings_store.dart';
import 'package:margin/src/ui/app_controller.dart';

const _url = 'https://dav.example.com/dav/Notes/';
const _credKey = 'webdav|$_url|me';

const _propsYaml = '''
schemaVersion: 1
id: "remote-id"
name: "Remote Notes"
created: 2026-01-01T00:00:00.000Z
updated: 2026-01-01T00:00:00.000Z
appVersion: "test"
endpoints: []
''';

const _rootMultistatus = '''
<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/dav/Notes/</D:href>
    <D:propstat><D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat>
  </D:response>
</D:multistatus>''';

/// A WebDAV server that serves a valid, empty Folio.
http.Client _fakeServer() => MockClient((req) async {
      if (req.method == 'GET' && req.url.path.endsWith('/properties.yaml')) {
        return http.Response(_propsYaml, 200);
      }
      if (req.method == 'PROPFIND') return http.Response(_rootMultistatus, 207);
      return http.Response('', 404);
    });

void main() {
  test('openWebDav connects, persists the descriptor, and stores the password',
      () async {
    final settings = InMemorySettingsStore();
    final credentials = InMemoryCredentialStore();
    final controller = AppController(
      settings: settings,
      credentials: credentials,
      httpClientFactory: _fakeServer,
    );
    addTearDown(controller.dispose);

    await controller.openWebDav(_url, 'me', 'pw');

    expect(controller.hasFolio, isTrue);
    expect(controller.folioName, 'Remote Notes');
    expect(await settings.getLastFolioType(), 'webdav');
    expect(await settings.getLastFolioPath(), _url);
    expect(await settings.getLastWebDavUser(), 'me');
    // The password is in the keystore, never in settings.
    expect(await credentials.read(_credKey), 'pw');
  });

  test('restoreLastFolio reconnects to a remembered WebDAV Folio', () async {
    final settings = InMemorySettingsStore();
    final credentials = InMemoryCredentialStore();
    await settings.setLastFolioType('webdav');
    await settings.setLastFolioPath(_url);
    await settings.setLastWebDavUser('me');
    await credentials.write(_credKey, 'pw');

    final controller = AppController(
      settings: settings,
      credentials: credentials,
      httpClientFactory: _fakeServer,
    );
    addTearDown(controller.dispose);

    await controller.restoreLastFolio();

    expect(controller.hasFolio, isTrue);
    expect(controller.folioName, 'Remote Notes');
  });

  test('a bad URL surfaces an error instead of failing silently', () async {
    final controller = AppController(
      settings: InMemorySettingsStore(),
      credentials: InMemoryCredentialStore(),
      // Any reachable handler 404s; combined with a malformed URL this must
      // still end in a visible error, never a silent hang.
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
    // No credential stored.

    final controller = AppController(
      settings: settings,
      credentials: InMemoryCredentialStore(),
      httpClientFactory: _fakeServer,
    );
    addTearDown(controller.dispose);

    await controller.restoreLastFolio();

    expect(controller.hasFolio, isFalse);
  });
}
