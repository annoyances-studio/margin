// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:convert';

import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:http/http.dart' as http;

import 'onedrive_auth.dart';

/// Production OAuth-authorize callback for [OneDriveAuth]: drives the
/// authorization-code-with-PKCE dance via the system browser using AppAuth.
///
/// Kept separate from [OneDriveAuth] so the pure-logic class stays free of
/// platform channels and can be unit-tested with a fake.
class FlutterAppAuthOneDriveAuthorize {
  final FlutterAppAuth _appAuth;

  FlutterAppAuthOneDriveAuthorize({FlutterAppAuth? appAuth})
      : _appAuth = appAuth ?? const FlutterAppAuth();

  Future<OneDriveTokens> call({
    required String clientId,
    required String redirectUri,
    required List<String> scopes,
  }) async {
    final response = await _appAuth.authorizeAndExchangeCode(
      AuthorizationTokenRequest(
        clientId,
        redirectUri,
        discoveryUrl: OneDriveAuth.discoveryUrl,
        scopes: scopes,
        // Always show the account picker so users can switch accounts (vs.
        // silently re-using the last one — surprising on a shared device).
        promptValues: const ['select_account'],
      ),
    );

    final access = response.accessToken;
    final expires = response.accessTokenExpirationDateTime;
    if (access == null) {
      throw const OneDriveAuthException(
        'OAuth response did not include an access token',
      );
    }
    return OneDriveTokens(
      accessToken: access,
      refreshToken: response.refreshToken,
      // If Microsoft skipped the expiry (very rare), assume an hour — the
      // standard OAuth default.
      accessTokenExpiresAt:
          expires?.toUtc() ?? DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
  }
}

/// Production refresh callback for [OneDriveAuth]: POSTs to Microsoft's token
/// endpoint with a `refresh_token` grant. We talk to the endpoint directly via
/// `package:http` rather than going through `flutter_appauth.token(...)` — it
/// is one fewer platform-channel hop, and (more importantly) lets us mock and
/// unit-test the refresh path with the same fake client used elsewhere.
class HttpOneDriveRefresh {
  final http.Client _client;

  HttpOneDriveRefresh({http.Client? client}) : _client = client ?? http.Client();

  Future<OneDriveTokens> call({
    required String clientId,
    required String refreshToken,
  }) async {
    final response = await _client.post(
      Uri.parse(OneDriveAuth.tokenEndpoint),
      headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': clientId,
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        // The scope we re-request on refresh — must be a subset of what was
        // originally granted; sending the same set is safest.
        'scope': OneDriveAuth.defaultScopes.join(' '),
      },
    );
    if (response.statusCode != 200) {
      throw OneDriveAuthException(
        'Refresh failed (HTTP ${response.statusCode}): ${response.body}',
      );
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return OneDriveTokens.fromExpiresIn(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String?, // may be omitted
      expiresIn: (json['expires_in'] as num).toInt(),
    );
  }
}
