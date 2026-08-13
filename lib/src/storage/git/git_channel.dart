// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/services.dart';

/// Bridge to native Git (JGit on Android): clone a repository read-only into
/// app-private storage, which Margin then browses with a `LocalFolderBackend`.
/// Kept as an interface so the controller stays testable with a fake (the real
/// one talks to native code, which unit tests can't).
abstract interface class GitChannel {
  /// Clones [url] over HTTPS (optionally with [user]/[password]; for GitHub the
  /// password is a Personal Access Token) into an app-private folder derived
  /// from [name]. Returns the absolute path of the checked-out working tree.
  /// Throws [GitException] on failure. Read-only — never pushes.
  Future<String> clone({
    required String url,
    String user,
    String password,
    required String name,
  });
}

/// The real [GitChannel], over the `margin/app` platform channel (Android).
class MethodChannelGit implements GitChannel {
  const MethodChannelGit();

  static const MethodChannel _channel = MethodChannel('margin/app');

  @override
  Future<String> clone({
    required String url,
    String user = '',
    String password = '',
    required String name,
  }) async {
    try {
      final path = await _channel.invokeMethod<String>('gitClone', {
        'url': url,
        'user': user,
        'pass': password,
        'name': name,
      });
      if (path == null || path.isEmpty) {
        throw const GitException('Clone returned no path');
      }
      return path;
    } on PlatformException catch (e) {
      throw GitException(e.message ?? e.code);
    }
  }
}

/// A clone/pull failure, carrying the native error message for display.
class GitException implements Exception {
  final String message;
  const GitException(this.message);
  @override
  String toString() => message;
}
