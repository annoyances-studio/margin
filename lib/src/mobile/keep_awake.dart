// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter/services.dart';

/// Keeps the device awake (CPU + Wi-Fi) while a long sync/clone transfers bytes,
/// so the screen turning off does not suspend the process or idle the network
/// and drop the connection mid-transfer. Kept as an interface so the controller
/// stays unit-testable with a no-op fake.
abstract interface class KeepAwake {
  /// Acquires the wake locks. Safe to call again while held (a no-op).
  Future<void> acquire();

  /// Releases the wake locks. Safe to call when nothing is held.
  Future<void> release();

  /// Runs [action], holding the locks for its duration and always releasing
  /// afterwards — even on error.
  Future<T> guard<T>(Future<T> Function() action) async {
    await acquire();
    try {
      return await action();
    } finally {
      await release();
    }
  }
}

/// A [KeepAwake] that does nothing — the default on platforms without a native
/// implementation (desktop, tests), where the screen-off problem doesn't apply.
class NoopKeepAwake implements KeepAwake {
  const NoopKeepAwake();
  @override
  Future<void> acquire() async {}
  @override
  Future<void> release() async {}
  @override
  Future<T> guard<T>(Future<T> Function() action) => action();
}

/// The real [KeepAwake] on Android, over the `margin/app` platform channel.
/// A best-effort service: channel failures are swallowed so a sync still runs,
/// just without protection from the screen turning off.
class MethodChannelKeepAwake implements KeepAwake {
  const MethodChannelKeepAwake();

  static const MethodChannel _channel = MethodChannel('margin/app');

  /// Safety cap handed to the native CPU lock so a crash can never leak it: it
  /// auto-releases after this, and [release] is called normally on completion.
  static const int _timeoutMs = 30 * 60 * 1000;

  @override
  Future<void> acquire() async {
    try {
      await _channel
          .invokeMethod<void>('acquireSyncWakeLock', {'timeoutMs': _timeoutMs});
    } on PlatformException {
      // best-effort
    } on MissingPluginException {
      // best-effort
    }
  }

  @override
  Future<void> release() async {
    try {
      await _channel.invokeMethod<void>('releaseSyncWakeLock');
    } on PlatformException {
      // best-effort
    } on MissingPluginException {
      // best-effort
    }
  }

  @override
  Future<T> guard<T>(Future<T> Function() action) async {
    await acquire();
    try {
      return await action();
    } finally {
      await release();
    }
  }
}

/// The [KeepAwake] for the current platform: real on Android, no-op elsewhere.
KeepAwake createKeepAwake() =>
    Platform.isAndroid ? const MethodChannelKeepAwake() : const NoopKeepAwake();
