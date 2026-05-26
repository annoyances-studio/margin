// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const MethodChannel _channel = MethodChannel('margin/app');

/// True on Android, where the system Back gesture at the root would otherwise
/// finish the activity (closing the app) rather than backgrounding it.
bool get backMinimizesApp =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Sends the app to the background (like pressing Home) instead of letting Back
/// finish the activity. Keeps the Flutter engine and UI state alive so resuming
/// is instant and doesn't re-clone a remote Folio. No-op off Android.
Future<void> moveAppToBackground() async {
  if (!backMinimizesApp) return;
  try {
    await _channel.invokeMethod<void>('moveToBackground');
  } catch (e) {
    // A missing channel (e.g. older host) must not crash the Back gesture.
    debugPrint('moveToBackground failed: $e');
  }
}
