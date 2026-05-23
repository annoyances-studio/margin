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
  Future<void> setEnabled(bool value);
}

/// A [StartupService] that does nothing; used on unsupported platforms and in
/// tests.
class NoopStartupService implements StartupService {
  const NoopStartupService();

  @override
  bool get isSupported => false;

  @override
  Future<bool> isEnabled() async => false;

  @override
  Future<void> setEnabled(bool value) async {}
}

/// A desktop [StartupService] backed by the launch_at_startup plugin.
///
/// Call [configure] once at startup (after the binding is initialized) before
/// using it.
class LaunchAtStartupService implements StartupService {
  bool _configured = false;

  @override
  bool get isSupported =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  void configure() {
    if (!isSupported || _configured) return;
    launchAtStartup.setup(
      appName: 'Margin',
      appPath: Platform.resolvedExecutable,
    );
    _configured = true;
  }

  @override
  Future<bool> isEnabled() async {
    if (!isSupported) return false;
    configure();
    return launchAtStartup.isEnabled();
  }

  @override
  Future<void> setEnabled(bool value) async {
    if (!isSupported) return;
    configure();
    if (value) {
      await launchAtStartup.enable();
    } else {
      await launchAtStartup.disable();
    }
  }
}
