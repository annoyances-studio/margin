// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:margin/src/desktop/startup_service.dart';
import 'package:margin/src/ui/settings_dialog.dart';

class _FakeStartupService implements StartupService {
  @override
  final bool isSupported;
  bool enabled;

  _FakeStartupService({this.isSupported = true, this.enabled = false});

  @override
  Future<bool> isEnabled() async => enabled;

  @override
  Future<void> setEnabled(bool value) async => enabled = value;
}

void main() {
  testWidgets('shows the run-at-login switch when supported', (tester) async {
    final service = _FakeStartupService(enabled: false);
    await tester.pumpWidget(
      MaterialApp(home: SettingsDialog(startupService: service)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SwitchListTile), findsOneWidget);

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    expect(service.enabled, isTrue);
  });

  testWidgets('hides the switch when unsupported', (tester) async {
    final service = _FakeStartupService(isSupported: false);
    await tester.pumpWidget(
      MaterialApp(home: SettingsDialog(startupService: service)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.textContaining('No settings available'), findsOneWidget);
  });
}
