// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:margin/src/ui/margin_app.dart';

void main() {
  const channel = MethodChannel('margin/app');

  testWidgets('Android: root Back backgrounds the app instead of closing it',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async {
          calls.add(call.method);
          return null;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));

      await tester.pumpWidget(const MarginApp());
      await tester.pumpAndSettle();

      // The root is guarded by a PopScope that prevents the
      // activity-finishing pop.
      final guard = find.byKey(const Key('rootBackGuard'));
      expect(tester.widget<PopScope>(guard).canPop, isFalse);

      // Simulate the Android system Back (a 'popRoute' platform message).
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'flutter/navigation',
        const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')),
        (_) {},
      );
      await tester.pump();

      // Back was routed to "move to background", not a route pop / app close.
      expect(calls, contains('moveToBackground'));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('desktop: no Back interception (no root guard)', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await tester.pumpWidget(const MarginApp());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('rootBackGuard')), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
