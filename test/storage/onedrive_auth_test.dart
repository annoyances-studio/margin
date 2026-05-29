// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:margin/src/credentials/credential_store.dart';
import 'package:margin/src/storage/onedrive_auth.dart';

OneDriveAuth _build({
  required CredentialStore credentials,
  required OneDriveAuthorize authorize,
  required OneDriveRefresh refresh,
  DateTime Function()? now,
}) {
  return OneDriveAuth(
    clientId: 'test-client',
    redirectUri: 'msauth://com.example/abc',
    credentials: credentials,
    authorize: authorize,
    refresh: refresh,
    now: now,
  );
}

void main() {
  group('OneDriveTokens', () {
    test('JSON round-trip preserves access, refresh, and expiry', () {
      final tokens = OneDriveTokens(
        accessToken: 'A',
        refreshToken: 'R',
        accessTokenExpiresAt: DateTime.utc(2026, 6, 1, 12),
      );
      final decoded = OneDriveTokens.fromJson(
        Map<String, dynamic>.from(tokens.toJson()),
      );
      expect(decoded.accessToken, 'A');
      expect(decoded.refreshToken, 'R');
      expect(decoded.accessTokenExpiresAt, DateTime.utc(2026, 6, 1, 12));
    });

    test('fromExpiresIn derives expiry from the issued-at instant', () {
      final issued = DateTime.utc(2026, 6, 1, 12);
      final tokens = OneDriveTokens.fromExpiresIn(
        accessToken: 'A',
        expiresIn: 3600,
        refreshToken: 'R',
        issuedAt: issued,
      );
      expect(tokens.accessTokenExpiresAt, DateTime.utc(2026, 6, 1, 13));
    });
  });

  group('OneDriveAuth', () {
    test('isSignedIn is false before sign-in, true after', () async {
      final credentials = InMemoryCredentialStore();
      final auth = _build(
        credentials: credentials,
        authorize: ({required clientId, required redirectUri, required scopes}) async =>
            OneDriveTokens(
          accessToken: 'A',
          refreshToken: 'R',
          accessTokenExpiresAt: DateTime.utc(2030, 1, 1),
        ),
        refresh: ({required clientId, required refreshToken}) async =>
            throw StateError('not called'),
      );

      expect(await auth.isSignedIn, isFalse);
      await auth.signIn();
      expect(await auth.isSignedIn, isTrue);
    });

    test('signIn persists tokens to the keystore', () async {
      final credentials = InMemoryCredentialStore();
      final auth = _build(
        credentials: credentials,
        authorize: ({required clientId, required redirectUri, required scopes}) async {
          expect(clientId, 'test-client');
          expect(scopes, contains('Files.ReadWrite'));
          return OneDriveTokens(
            accessToken: 'A',
            refreshToken: 'R',
            accessTokenExpiresAt: DateTime.utc(2030, 1, 1),
          );
        },
        refresh: ({required clientId, required refreshToken}) async =>
            throw StateError('not called'),
      );

      await auth.signIn();
      expect(await credentials.read('onedrive|tokens'), isNotNull);
    });

    test('signOut wipes the persisted tokens', () async {
      final credentials = InMemoryCredentialStore()
        ..write('onedrive|tokens', '{"access":"A","exp":"2030-01-01T00:00:00.000Z"}');
      final auth = _build(
        credentials: credentials,
        authorize: ({required clientId, required redirectUri, required scopes}) async =>
            throw StateError('not called'),
        refresh: ({required clientId, required refreshToken}) async =>
            throw StateError('not called'),
      );

      await auth.signOut();
      expect(await credentials.read('onedrive|tokens'), isNull);
      expect(await auth.isSignedIn, isFalse);
    });

    test('accessToken returns the current token while it is still valid',
        () async {
      final credentials = InMemoryCredentialStore();
      var now = DateTime.utc(2026, 6, 1, 12);
      final auth = _build(
        credentials: credentials,
        now: () => now,
        authorize: ({required clientId, required redirectUri, required scopes}) async =>
            OneDriveTokens(
          accessToken: 'A1',
          refreshToken: 'R',
          accessTokenExpiresAt: now.add(const Duration(hours: 1)),
        ),
        refresh: ({required clientId, required refreshToken}) async =>
            throw StateError('refresh should not be called when still valid'),
      );

      await auth.signIn();
      expect(await auth.accessToken(), 'A1');
    });

    test('accessToken refreshes when expired and persists the new token',
        () async {
      final credentials = InMemoryCredentialStore();
      var now = DateTime.utc(2026, 6, 1, 12);
      var refreshCalls = 0;
      final auth = _build(
        credentials: credentials,
        now: () => now,
        authorize: ({required clientId, required redirectUri, required scopes}) async =>
            OneDriveTokens(
          accessToken: 'A1',
          refreshToken: 'R1',
          accessTokenExpiresAt: now.add(const Duration(minutes: 1)),
        ),
        refresh: ({required clientId, required refreshToken}) async {
          refreshCalls++;
          expect(refreshToken, 'R1');
          return OneDriveTokens(
            accessToken: 'A2',
            refreshToken: 'R2',
            accessTokenExpiresAt: now
                .add(const Duration(hours: 1, minutes: 30)),
          );
        },
      );

      await auth.signIn();
      // Jump past the expiry to force a refresh.
      now = now.add(const Duration(minutes: 10));

      expect(await auth.accessToken(), 'A2');
      expect(refreshCalls, 1);

      // The new tokens are persisted: a second call uses the cached fresh one.
      expect(await auth.accessToken(), 'A2');
      expect(refreshCalls, 1, reason: 'no extra refresh needed');
    });

    test('accessToken keeps the previous refresh token if a rotation is omitted',
        () async {
      final credentials = InMemoryCredentialStore();
      var now = DateTime.utc(2026, 6, 1, 12);
      final auth = _build(
        credentials: credentials,
        now: () => now,
        authorize: ({required clientId, required redirectUri, required scopes}) async =>
            OneDriveTokens(
          accessToken: 'A1',
          refreshToken: 'R1',
          accessTokenExpiresAt: now.add(const Duration(minutes: 1)),
        ),
        refresh: ({required clientId, required refreshToken}) async =>
            OneDriveTokens(
          accessToken: 'A2',
          // Microsoft sometimes does not rotate refresh tokens — simulate that.
          accessTokenExpiresAt: now.add(const Duration(hours: 1)),
        ),
      );

      await auth.signIn();
      now = now.add(const Duration(minutes: 10));
      await auth.accessToken();

      // The stored refresh token must still be R1 so we can refresh again.
      var nextRefreshSeen = '';
      final auth2 = _build(
        credentials: credentials,
        now: () => now.add(const Duration(hours: 2)),
        authorize: ({required clientId, required redirectUri, required scopes}) async =>
            throw StateError('not called'),
        refresh: ({required clientId, required refreshToken}) async {
          nextRefreshSeen = refreshToken;
          return OneDriveTokens(
            accessToken: 'A3',
            accessTokenExpiresAt: now.add(const Duration(hours: 4)),
          );
        },
      );
      await auth2.accessToken();
      expect(nextRefreshSeen, 'R1');
    });

    test('accessToken throws when not signed in', () async {
      final auth = _build(
        credentials: InMemoryCredentialStore(),
        authorize: ({required clientId, required redirectUri, required scopes}) async =>
            throw StateError('not called'),
        refresh: ({required clientId, required refreshToken}) async =>
            throw StateError('not called'),
      );
      expect(auth.accessToken(), throwsA(isA<OneDriveAuthException>()));
    });

    test('a corrupt stored blob is treated as signed-out, not an error',
        () async {
      final credentials = InMemoryCredentialStore()
        ..write('onedrive|tokens', 'not-json');
      final auth = _build(
        credentials: credentials,
        authorize: ({required clientId, required redirectUri, required scopes}) async =>
            throw StateError('not called'),
        refresh: ({required clientId, required refreshToken}) async =>
            throw StateError('not called'),
      );

      expect(await auth.isSignedIn, isFalse);
      // The bad blob is also cleared so it can't keep failing.
      expect(await credentials.read('onedrive|tokens'), isNull);
    });
  });
}
