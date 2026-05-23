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
