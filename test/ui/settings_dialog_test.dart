// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:margin/src/desktop/startup_service.dart';
import 'package:margin/src/ui/app_controller.dart';
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
  late AppController controller;

  setUp(() => controller = AppController());
  tearDown(() => controller.dispose());

  Widget host(StartupService service) => MaterialApp(
        home: SettingsDialog(startupService: service, controller: controller),
      );

  testWidgets('shows the two view dropdowns and the login switch', (tester) async {
    await tester.pumpWidget(host(_FakeStartupService()));
    await tester.pumpAndSettle();

    expect(find.byWidgetPredicate((w) => w is DropdownButton), findsNWidgets(2));
    expect(find.byType(SwitchListTile), findsOneWidget);
  });

  testWidgets('toggling the login switch calls the service', (tester) async {
    final service = _FakeStartupService(enabled: false);
    await tester.pumpWidget(host(service));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    expect(service.enabled, isTrue);
  });

  testWidgets('hides the login switch when unsupported', (tester) async {
    await tester.pumpWidget(host(_FakeStartupService(isSupported: false)));
    await tester.pumpAndSettle();

    expect(find.byType(SwitchListTile), findsNothing);
    // View dropdowns are still available.
    expect(find.byWidgetPredicate((w) => w is DropdownButton), findsNWidgets(2));
  });
}
