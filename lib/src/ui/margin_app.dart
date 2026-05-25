// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../desktop/startup_service.dart';
import '../settings/settings_store.dart';
import 'app_controller.dart';
import 'folio_screen.dart';
import 'open_folio_screen.dart';

/// Root widget: themes the app and shows either the open/create screen or the
/// repository screen depending on whether a repository is open.
class MarginApp extends StatefulWidget {
  /// Optional persistence; defaults to a non-persistent in-memory store (used
  /// by widget tests). The real app injects a shared_preferences store.
  final SettingsStore? settings;

  /// Run-at-login control; defaults to a no-op (used by widget tests).
  final StartupService startupService;

  const MarginApp({
    super.key,
    this.settings,
    this.startupService = const NoopStartupService(),
  });

  @override
  State<MarginApp> createState() => _MarginAppState();
}

class _MarginAppState extends State<MarginApp> {
  late final AppController _controller =
      AppController(settings: widget.settings);

  @override
  void initState() {
    super.initState();
    // Load view settings and reopen the last repository (falls back to landing).
    _controller.start();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appName,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // Follow the OS light/dark setting.
      themeMode: ThemeMode.system,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          return _controller.hasFolio
              ? FolioScreen(
                  controller: _controller,
                  startupService: widget.startupService,
                )
              : OpenFolioScreen(controller: _controller);
        },
      ),
    );
  }
}
