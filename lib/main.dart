// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import 'src/credentials/credential_store.dart';
import 'src/desktop/desktop_integration.dart';
import 'src/desktop/startup_service.dart';
import 'src/settings/settings_store.dart';
import 'src/ui/margin_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initDesktopWindow();
  await DesktopTray.instance.setup();

  final startupService = LaunchAtStartupService()..configure();

  runApp(MarginApp(
    settings: SharedPreferencesSettingsStore(),
    credentials: SecureCredentialStore(),
    startupService: startupService,
  ));
}
