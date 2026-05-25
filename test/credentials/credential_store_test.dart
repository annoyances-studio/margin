// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:margin/src/credentials/credential_store.dart';

void main() {
  group('InMemoryCredentialStore', () {
    late CredentialStore store;

    setUp(() => store = InMemoryCredentialStore());

    test('reads back a written secret', () async {
      await store.write('webdav:https://host/me', 'hunter2');
      expect(await store.read('webdav:https://host/me'), 'hunter2');
    });

    test('returns null for an unknown key', () async {
      expect(await store.read('nope'), isNull);
    });

    test('write overwrites an existing secret', () async {
      await store.write('k', 'old');
      await store.write('k', 'new');
      expect(await store.read('k'), 'new');
    });

    test('delete removes the secret and is a no-op when absent', () async {
      await store.write('k', 'v');
      await store.delete('k');
      expect(await store.read('k'), isNull);
      await store.delete('k'); // must not throw
    });
  });
}
