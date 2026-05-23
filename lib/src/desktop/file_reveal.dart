// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter/foundation.dart';

/// Whether revealing a path in the OS file manager is supported here.
bool get canRevealInFileManager =>
    !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

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
/// associated app for a file, the browser for an http(s) URL. No-op on
/// unsupported platforms.
Future<void> openWithDefaultApp(String target) async {
  if (!canRevealInFileManager) return;
  if (Platform.isWindows) {
    // `start` needs an empty title argument first.
    await Process.run('cmd', ['/c', 'start', '', target]);
  } else if (Platform.isMacOS) {
    await Process.run('open', [target]);
  } else {
    await Process.run('xdg-open', [target]);
  }
}
