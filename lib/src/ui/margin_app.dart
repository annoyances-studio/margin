// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../credentials/credential_store.dart';
import '../desktop/desktop_integration.dart';
import '../desktop/startup_service.dart';
import '../mobile/app_background.dart';
import '../settings/settings_store.dart';
import '../sync/sync_state_store.dart';
import 'app_controller.dart';
import 'folio_screen.dart';
import 'open_folio_screen.dart';

/// Root widget: themes the app and shows either the open/create screen or the
/// repository screen depending on whether a repository is open.
class MarginApp extends StatefulWidget {
  /// Optional persistence; defaults to a non-persistent in-memory store (used
  /// by widget tests). The real app injects a shared_preferences store.
  final SettingsStore? settings;

  /// Optional secret store; defaults to in-memory (tests). The real app injects
  /// the OS keystore.
  final CredentialStore? credentials;

  /// Optional sync-state store; defaults to in-memory (tests). The real app
  /// injects the file-backed store.
  final SyncStateStore? syncStates;

  /// Run-at-login control; defaults to a no-op (used by widget tests).
  final StartupService startupService;

  /// Optional pre-built controller (tests). When null, one is created from the
  /// injected stores and started normally.
  final AppController? controller;

  const MarginApp({
    super.key,
    this.settings,
    this.credentials,
    this.syncStates,
    this.startupService = const NoopStartupService(),
    this.controller,
  });

  @override
  State<MarginApp> createState() => _MarginAppState();
}

class _MarginAppState extends State<MarginApp> with WidgetsBindingObserver {
  late final AppController _controller = widget.controller ??
      AppController(
        settings: widget.settings,
        credentials: widget.credentials,
        syncStates: widget.syncStates,
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Save the open note when the desktop window is closed to the tray (or the
    // app quits), so an unsaved buffer is never lost. Mobile backgrounding is
    // covered by didChangeAppLifecycleState below.
    DesktopTray.instance.beforeHide = _controller.save;
    // Load view settings and reopen the last Folio (falls back to landing).
    // A pre-built controller (tests) is left as-is.
    if (widget.controller == null) _controller.start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Only own the controller's lifecycle when we created it.
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  /// Flush the open note to disk whenever the app loses the foreground — app
  /// switch / background on mobile, focus loss / minimize on desktop — so edits
  /// survive the process being suspended or reclaimed. [AppController.save] is a
  /// no-op when nothing is dirty. On return to the foreground, retry a failed
  /// sync: the network blip that cut it (e.g. a WiFi handoff while walking) is
  /// usually over by the time the user looks at the app again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _controller.retrySyncOnResume();
    } else {
      _controller.save();
    }
  }

  /// Shared theme for both brightnesses. The text selection color is set
  /// explicitly and kept translucent so selected text (e.g. a block quote in
  /// the preview) stays readable instead of being washed out by an opaque
  /// highlight.
  ThemeData _theme(Brightness brightness) {
    final scheme =
        ColorScheme.fromSeed(seedColor: Colors.indigo, brightness: brightness);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      textSelectionTheme: TextSelectionThemeData(
        selectionColor: scheme.primary.withValues(alpha: 0.30),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appName,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // Follow the OS light/dark setting.
      themeMode: ThemeMode.system,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final Widget screen;
          if (_controller.hasFolio) {
            screen = FolioScreen(
              controller: _controller,
              startupService: widget.startupService,
            );
          } else if (_controller.isRestoring) {
            // While reconnecting a remembered Folio, show a splash rather than
            // the landing screen so a cold restart doesn't flash "open a Folio".
            screen = const _RestoringSplash();
          } else {
            screen = OpenFolioScreen(controller: _controller);
          }
          // On Android, intercept the root Back: first walk the note history
          // (browser-style — matters for companion reading, where you follow
          // links), and only when there's nowhere back to go, hide the app
          // (like Home) rather than finishing the activity, keeping state alive
          // for an instant resume. Elsewhere there's no system Back to intercept.
          if (!backMinimizesApp) return screen;
          return PopScope(
            key: const Key('rootBackGuard'),
            canPop: false,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) return;
              if (_controller.canGoBack) {
                _controller.goBack();
              } else {
                moveAppToBackground();
              }
            },
            child: screen,
          );
        },
      ),
    );
  }
}

/// A minimal splash shown while a remembered Folio is being reconnected at
/// startup (see [AppController.isRestoring]).
class _RestoringSplash extends StatelessWidget {
  const _RestoringSplash();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppLocalizations.of(context).appName,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 20),
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
          ],
        ),
      ),
    );
  }
}
