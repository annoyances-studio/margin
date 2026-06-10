// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:launch_at_startup/launch_at_startup.dart';

/// Controls whether the app launches automatically when the user logs in.
///
/// Abstracted so the Settings UI can be built and tested without the platform
/// plugin (which is desktop-only and uses platform channels).
abstract interface class StartupService {
  /// Whether run-at-login is available on this platform.
  bool get isSupported;

  Future<bool> isEnabled();

  /// Enables/disables run-at-login. When [minimized] is true, the login entry is
  /// registered to launch with the `--minimized` flag so the app starts hidden
  /// in the tray. (Re-call with the new [minimized] value to update it.)
  Future<void> setEnabled(bool value, {bool minimized = false});
}

/// The launch argument added to the run-at-login entry to start hidden in the
/// tray. Detected at startup (see main.dart).
const String kStartMinimizedArg = '--minimized';

/// Whether the app should start hidden in the tray, given the process launch
/// [args] (`main`'s parameter — forwarded by the desktop runner). NOTE: this is
/// *not* `Platform.executableArguments`, which carries the Dart VM args (empty
/// in a release build) and so never sees the run-at-login flag.
bool shouldStartMinimized(List<String> args) =>
    args.contains(kStartMinimizedArg);

/// A [StartupService] that does nothing; used on unsupported platforms and in
/// tests.
class NoopStartupService implements StartupService {
  const NoopStartupService();

  @override
  bool get isSupported => false;

  @override
  Future<bool> isEnabled() async => false;

  @override
  Future<void> setEnabled(bool value, {bool minimized = false}) async {}
}

/// A desktop [StartupService] backed by the launch_at_startup plugin.
///
/// Call [configure] once at startup (after the binding is initialized) before
/// using it.
class LaunchAtStartupService implements StartupService {
  @override
  bool get isSupported =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  /// (Re)registers the app with the given launch [args]. Cheap to call again
  /// to change the args before enabling.
  void _setup({List<String> args = const []}) {
    if (!isSupported) return;
    launchAtStartup.setup(
      appName: 'Margin',
      appPath: Platform.resolvedExecutable,
      args: args,
    );
  }

  void configure() => _setup();

  @override
  Future<bool> isEnabled() async {
    if (!isSupported) return false;
    // The plugin's isEnabled() returns true only when the stored Run entry
    // matches the *exact* command line it was set up with, args included. Since
    // a run-at-login entry may or may not carry the --minimized flag, checking a
    // single arg variant would misreport the other as "disabled" — which pins
    // the Settings switch and makes run-at-login impossible to turn off. Treat
    // the entry as enabled if either variant is registered.
    _setup(args: const [kStartMinimizedArg]);
    if (await launchAtStartup.isEnabled()) return true;
    _setup(args: const []);
    return launchAtStartup.isEnabled();
  }

  @override
  Future<void> setEnabled(bool value, {bool minimized = false}) async {
    if (!isSupported) return;
    // Register with the right launch args, then (re)write the login entry.
    _setup(args: minimized ? const [kStartMinimizedArg] : const []);
    if (value) {
      await launchAtStartup.enable();
    } else {
      await launchAtStartup.disable();
    }
  }
}
