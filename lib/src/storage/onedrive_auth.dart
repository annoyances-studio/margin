// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// The constructor takes public-named params (credentials/authorize/refresh)
// and stores them in private fields — the lint's suggested rewrite would
// push leading underscores into the named-argument call sites.
// ignore_for_file: prefer_initializing_formals

import 'dart:convert';

import '../credentials/credential_store.dart';

/// A snapshot of OneDrive OAuth tokens: an access token (short-lived) and the
/// refresh token (long-lived) we use to mint new access tokens silently.
class OneDriveTokens {
  /// Bearer token used for Microsoft Graph requests.
  final String accessToken;

  /// Refresh token returned by the authorization or refresh exchanges. May be
  /// null if Microsoft chose not to issue/rotate it.
  final String? refreshToken;

  /// Absolute UTC time at which [accessToken] expires.
  final DateTime accessTokenExpiresAt;

  const OneDriveTokens({
    required this.accessToken,
    required this.accessTokenExpiresAt,
    this.refreshToken,
  });

  /// Builds tokens from a delta `expires_in` (seconds), the form Microsoft uses
  /// in its token endpoint responses.
  factory OneDriveTokens.fromExpiresIn({
    required String accessToken,
    required int expiresIn,
    String? refreshToken,
    DateTime? issuedAt,
  }) {
    final at = issuedAt ?? DateTime.now().toUtc();
    return OneDriveTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      accessTokenExpiresAt: at.add(Duration(seconds: expiresIn)),
    );
  }

  Map<String, dynamic> toJson() => {
        'access': accessToken,
        if (refreshToken != null) 'refresh': refreshToken,
        'exp': accessTokenExpiresAt.toUtc().toIso8601String(),
      };

  factory OneDriveTokens.fromJson(Map<String, dynamic> json) => OneDriveTokens(
        accessToken: json['access'] as String,
        refreshToken: json['refresh'] as String?,
        accessTokenExpiresAt: DateTime.parse(json['exp'] as String),
      );
}

/// Raised when OneDrive auth is unavailable: not signed in, refresh failed
/// (e.g. consent revoked), or the configured client ID is missing.
class OneDriveAuthException implements Exception {
  final String message;
  const OneDriveAuthException(this.message);
  @override
  String toString() => 'OneDriveAuthException: $message';
}

/// Performs an OAuth authorization-code-with-PKCE flow via the system browser
/// and returns the resulting tokens. Real implementations use `flutter_appauth`
/// (see `onedrive_oauth.dart`); tests inject a fake.
typedef OneDriveAuthorize = Future<OneDriveTokens> Function({
  required String clientId,
  required String redirectUri,
  required List<String> scopes,
});

/// Exchanges a refresh token for a fresh access token at Microsoft's token
/// endpoint. Real implementations call the token endpoint over HTTP.
typedef OneDriveRefresh = Future<OneDriveTokens> Function({
  required String clientId,
  required String refreshToken,
});

/// Drives the OneDrive OAuth life-cycle: sign-in, refresh-on-demand, sign-out,
/// and token persistence.
///
/// The actual OAuth dance and refresh HTTP call are injected as callbacks
/// ([OneDriveAuthorize] / [OneDriveRefresh]) so this class is fully testable
/// without `flutter_appauth` or a real Microsoft endpoint. The production
/// factory in `onedrive_oauth.dart` wires the real implementations.
class OneDriveAuth {
  /// Microsoft's v2.0 OpenID Connect discovery document for the personal-
  /// account ("consumers") tenant. Matches the "Personal Microsoft accounts
  /// only" supported account types in the Entra registration.
  static const String discoveryUrl =
      'https://login.microsoftonline.com/consumers/v2.0/.well-known/openid-configuration';

  /// Token endpoint used by the refresh exchange.
  static const String tokenEndpoint =
      'https://login.microsoftonline.com/consumers/oauth2/v2.0/token';

  /// Scopes the user consents to: read/write OneDrive content, get a refresh
  /// token, and let us call `/me` for the smoke-test display name.
  static const List<String> defaultScopes = [
    'Files.ReadWrite',
    'offline_access',
    'User.Read',
  ];

  /// Build-time client ID, supplied via `--dart-define=ONEDRIVE_CLIENT_ID=...`.
  /// Empty when OneDrive integration is not configured for this build.
  static const String clientIdFromEnv =
      String.fromEnvironment('ONEDRIVE_CLIENT_ID');

  /// Build-time redirect URI, supplied via `--dart-define=ONEDRIVE_REDIRECT_URI=...`.
  /// Must match the URI registered in Entra for this app's Android platform —
  /// `msauth://<package>/<urlEncodedSignatureHash>`.
  static const String redirectUriFromEnv =
      String.fromEnvironment('ONEDRIVE_REDIRECT_URI');

  /// True when both ONEDRIVE_CLIENT_ID and ONEDRIVE_REDIRECT_URI are set, so
  /// the OneDrive sign-in path is available to the UI.
  static bool get isConfiguredFromEnv =>
      clientIdFromEnv.isNotEmpty && redirectUriFromEnv.isNotEmpty;

  static const String _tokenKey = 'onedrive|tokens';

  /// Refresh slightly before the actual expiry — small headroom covers clock
  /// skew and the latency of the request itself.
  static const Duration _expiryHeadroom = Duration(minutes: 1);

  final String clientId;
  final String redirectUri;
  final List<String> scopes;
  final CredentialStore _credentials;
  final OneDriveAuthorize _authorize;
  final OneDriveRefresh _refresh;
  final DateTime Function() _now;

  OneDriveAuth({
    required this.clientId,
    required this.redirectUri,
    required CredentialStore credentials,
    required OneDriveAuthorize authorize,
    required OneDriveRefresh refresh,
    List<String>? scopes,
    DateTime Function()? now,
  })  : scopes = scopes ?? defaultScopes,
        _credentials = credentials,
        _authorize = authorize,
        _refresh = refresh,
        _now = now ?? DateTime.now;

  /// Whether tokens are currently persisted (i.e. we've signed in at least
  /// once and not signed out since).
  Future<bool> get isSignedIn async => (await _readTokens()) != null;

  /// Triggers the OAuth sign-in dance via the system browser, persists the
  /// resulting tokens in the OS keystore, and returns them.
  Future<OneDriveTokens> signIn() async {
    final tokens = await _authorize(
      clientId: clientId,
      redirectUri: redirectUri,
      scopes: scopes,
    );
    await _writeTokens(tokens);
    return tokens;
  }

  /// Drops the persisted tokens. The user will be re-prompted next sign-in.
  Future<void> signOut() => _credentials.delete(_tokenKey);

  /// Returns a valid access token, transparently refreshing if expired (or
  /// near-expired). Throws [OneDriveAuthException] when not signed in or when
  /// refresh fails (e.g. consent revoked).
  Future<String> accessToken() async {
    final tokens = await _readTokens();
    if (tokens == null) {
      throw const OneDriveAuthException('Not signed in to OneDrive');
    }
    if (_now().toUtc().add(_expiryHeadroom).isBefore(tokens.accessTokenExpiresAt)) {
      return tokens.accessToken; // still valid
    }
    final refreshTokenValue = tokens.refreshToken;
    if (refreshTokenValue == null) {
      throw const OneDriveAuthException(
        'Access token expired and no refresh token is available',
      );
    }
    final refreshed = await _refresh(
      clientId: clientId,
      refreshToken: refreshTokenValue,
    );
    // Microsoft sometimes omits a rotated refresh token; if so, keep the
    // previous one so the next refresh still works.
    final merged = OneDriveTokens(
      accessToken: refreshed.accessToken,
      refreshToken: refreshed.refreshToken ?? refreshTokenValue,
      accessTokenExpiresAt: refreshed.accessTokenExpiresAt,
    );
    await _writeTokens(merged);
    return merged.accessToken;
  }

  Future<OneDriveTokens?> _readTokens() async {
    final raw = await _credentials.read(_tokenKey);
    if (raw == null) return null;
    try {
      return OneDriveTokens.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Corrupt/legacy blob — drop it; the user will be prompted to sign in.
      await _credentials.delete(_tokenKey);
      return null;
    }
  }

  Future<void> _writeTokens(OneDriveTokens tokens) =>
      _credentials.write(_tokenKey, jsonEncode(tokens.toJson()));
}
