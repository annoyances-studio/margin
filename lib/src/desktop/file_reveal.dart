// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

/// Whether the current platform is a desktop OS.
bool get _isDesktop =>
    !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

/// Whether revealing a path in the OS file manager is supported here.
/// Only the desktops have a "show in folder" concept.
bool get canRevealInFileManager => _isDesktop;

/// Whether opening a link/attachment target (URL or file) is supported here.
/// True on desktop and mobile; only web has no native handler we can reach.
bool get canOpenTargets => !kIsWeb;

/// Whether [target] is an external URL (http, mailto, …) rather than a local
/// filesystem path. A `file:` scheme is treated as local.
bool _isExternalUrl(String target) {
  final uri = Uri.tryParse(target);
  return uri != null && uri.hasScheme && uri.scheme != 'file';
}

/// Opens [absolutePath] in the platform's file manager (Explorer, Finder, or
/// the Linux default). No-op on unsupported platforms.
Future<void> revealInFileManager(String absolutePath) async {
  if (!canRevealInFileManager) return;
  final (command, args) = switch (Platform.operatingSystem) {
    'windows' => ('explorer', [absolutePath]),
    'macos' => ('open', [absolutePath]),
    _ => ('xdg-open', [absolutePath]),
  };
  // explorer.exe returns a non-zero exit code even on success, so ignore it.
  await Process.run(command, args);
}

/// Opens [target] (a file path or a URL) with the OS default handler — the
/// associated app for a file, the browser for an http(s) URL.
///
/// Desktop shells out to the OS opener. Mobile uses `url_launcher` for external
/// URLs and `open_filex` for local files (the latter routes through a content
/// URI on Android, avoiding `FileUriExposedException`). No-op on web.
Future<void> openWithDefaultApp(String target) async {
  if (kIsWeb) return;

  if (_isDesktop) {
    if (Platform.isWindows) {
      // `start` needs an empty title argument first.
      await Process.run('cmd', ['/c', 'start', '', target]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [target]);
    } else {
      await Process.run('xdg-open', [target]);
    }
    return;
  }

  // Mobile (Android, iOS).
  if (_isExternalUrl(target)) {
    final uri = Uri.tryParse(target);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  } else {
    await OpenFilex.open(target);
  }
}
