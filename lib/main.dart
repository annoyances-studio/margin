// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import 'src/credentials/credential_store.dart';
import 'src/desktop/desktop_integration.dart';
import 'src/desktop/startup_service.dart';
import 'src/settings/settings_store.dart';
import 'src/sync/sync_state_store.dart';
import 'src/ui/margin_app.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // A run-at-login launch passes --minimized so the app starts in the tray.
  // The flag arrives as a process argument (forwarded by the Windows runner via
  // set_dart_entrypoint_arguments), i.e. through [args] — not through
  // Platform.executableArguments, which carries the (empty) Dart VM args in a
  // release build.
  final startMinimized = isDesktop && shouldStartMinimized(args);
  await initDesktopWindow(startMinimized: startMinimized);
  await DesktopTray.instance.setup();

  final startupService = LaunchAtStartupService()..configure();

  runApp(MarginApp(
    settings: SharedPreferencesSettingsStore(),
    credentials: SecureCredentialStore(),
    syncStates: FileSyncStateStore(),
    startupService: startupService,
  ));
}
